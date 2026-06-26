import Foundation
import SwiftData
import os

// MARK: - CloudSyncService
//
// Bridges on-device health data to the PulseLoop web app so it's viewable on
// any platform (web / Windows / Android). The iPhone remains the only place
// that can read the BLE ring + HealthKit; this service uploads what it
// collects to the cloud backend.
//
// Flow:
//   1. User signs in on the web dashboard and generates a 6-char pairing code.
//   2. User enters that code here → `pair(code:)` exchanges it for a long-lived
//      device token (stored in the Keychain).
//   3. `sync(context:)` reads recent `Measurement`s and POSTs them to the
//      ingest endpoint. Idempotent: the server upserts on the sample's id.

@MainActor
@Observable
final class CloudSyncService {
    static let shared = CloudSyncService()

    private let tokenStore = CloudSyncKeychainStore()
    private let session: URLSession

    /// Last sync result for surfacing in the UI.
    var lastSyncAt: Date?
    var lastError: String?
    var isSyncing = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    var isPaired: Bool { tokenStore.hasKey }

    /// Whether cloud sync is configured (a non-local backend URL is present). When
    /// false, sync/pair are no-ops with a logged warning rather than hitting localhost.
    var isConfigured: Bool { resolvedBaseURL != nil }

    // MARK: - Consent
    //
    // No health data leaves the device until the user has explicitly consented to
    // cloud sync. The consent is persisted and required by both `pair` and `sync`,
    // so it can't be bypassed by calling the service directly (roadmap E1).

    private static let consentKey = "pulseloop.cloudsync.consent.v1"

    /// Whether the user has granted explicit consent to upload health data to the cloud.
    var hasCloudConsent: Bool {
        get { UserDefaults.standard.bool(forKey: Self.consentKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.consentKey) }
    }

    /// Public, hosted privacy policy. Surfaced at the consent point and in Settings.
    static let privacyPolicyURL = URL(string: "https://pulseloop.app/privacy")!

    // MARK: - Configuration

    /// Base URL of the web backend, from the `PULSELOOP_WEB_URL` Info.plist entry.
    ///
    /// In DEBUG a `localhost`/local URL is allowed for development. In release builds a
    /// local or missing URL disables cloud sync (returns `nil`) instead of silently
    /// pointing at `localhost:3000`, which would never reach a real backend on-device.
    private var resolvedBaseURL: URL? {
        guard let override = Bundle.main.object(forInfoDictionaryKey: "PULSELOOP_WEB_URL") as? String else {
            AppLog.network.warning("Cloud sync disabled: PULSELOOP_WEB_URL is not set.")
            return nil
        }
        let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let host = url.host else {
            AppLog.network.warning("Cloud sync disabled: PULSELOOP_WEB_URL is invalid (\(trimmed, privacy: .public)).")
            return nil
        }
        let isLocal = host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local")
        #if DEBUG
        return url
        #else
        if isLocal {
            AppLog.network.warning("Cloud sync disabled in release: PULSELOOP_WEB_URL points at a local host (\(host, privacy: .public)).")
            return nil
        }
        return url
        #endif
    }

    // MARK: - Errors

    enum SyncError: LocalizedError {
        case notConfigured
        case invalidCode
        case notPaired
        case consentRequired
        case server(Int)
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Cloud sync isn't configured for this build."
            case .invalidCode: return "That pairing code is invalid or expired."
            case .notPaired: return "This device isn't connected to the web app yet."
            case .consentRequired: return "Turn on cloud sync consent before connecting."
            case .server(let code): return "Server error (\(code)). Please try again."
            case .transport(let msg): return msg
            }
        }
    }

    // MARK: - Pairing

    /// Redeems a pairing code from the web dashboard for a device token.
    func pair(code: String, deviceName: String? = nil) async throws {
        guard hasCloudConsent else { throw SyncError.consentRequired }
        let name = deviceName ?? Self.deviceDisplayName()
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { throw SyncError.invalidCode }
        guard let baseURL = resolvedBaseURL else { throw SyncError.notConfigured }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/pair/redeem"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": trimmed,
            "deviceName": name,
        ])

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.transport("No response from server.")
        }
        if http.statusCode == 404 { throw SyncError.invalidCode }
        guard (200...299).contains(http.statusCode) else { throw SyncError.server(http.statusCode) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String, !token.isEmpty else {
            throw SyncError.transport("Pairing response was malformed.")
        }
        try tokenStore.saveKey(token)
    }

    /// Forgets the device token (disconnects from web) and revokes consent so a
    /// future reconnection must opt in again.
    func unpair() {
        try? tokenStore.deleteKey()
        hasCloudConsent = false
        lastSyncAt = nil
        linkedAccount = nil
    }

    // MARK: - Linked account (roadmap E3)

    /// The Clerk-backed account this device is paired to, as reported by the
    /// server. Refreshed lazily; surfaced in Settings so the user can confirm the
    /// device is linked to the right account.
    struct LinkedAccount: Equatable {
        let email: String?
        let creditBalance: Int
        let deviceName: String
        let pairedAt: Date?
    }

    /// Last fetched linked-account info (nil until `refreshLinkedAccount` succeeds).
    var linkedAccount: LinkedAccount?

    /// Asks the server which account this device token belongs to. Returns nil
    /// (and clears `linkedAccount`) when not paired/configured or on failure.
    @discardableResult
    func refreshLinkedAccount() async -> LinkedAccount? {
        guard let baseURL = resolvedBaseURL,
              let token = (try? tokenStore.readKey()) ?? nil else {
            linkedAccount = nil
            return nil
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/account/me"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await send(request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return linkedAccount // keep prior value on transient failure
        }

        let accountJSON = json["account"] as? [String: Any]
        let deviceJSON = json["device"] as? [String: Any]
        let account = LinkedAccount(
            email: accountJSON?["email"] as? String,
            creditBalance: accountJSON?["creditBalance"] as? Int ?? 0,
            deviceName: deviceJSON?["name"] as? String ?? Self.deviceDisplayName(),
            pairedAt: (deviceJSON?["pairedAt"] as? String).flatMap { ISO8601DateFormatter.shared.date(from: $0) }
        )
        linkedAccount = account
        return account
    }

    // MARK: - Data export / deletion (roadmap E2)

    /// Scope of a server-side deletion request.
    enum DeleteScope: String {
        /// Revoke just this device's token (other devices + data untouched).
        case device
        /// Erase all server-held data for the account.
        case account
    }

    /// Downloads everything the server holds for this account as raw JSON bytes.
    /// Returns the response body so the caller can save / share it.
    func exportServerData() async throws -> Data {
        guard let baseURL = resolvedBaseURL else { throw SyncError.notConfigured }
        guard let token = (try? tokenStore.readKey()) ?? nil else { throw SyncError.notPaired }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/account/export"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.transport("No response from server.")
        }
        if http.statusCode == 401 { throw SyncError.notPaired }
        guard (200...299).contains(http.statusCode) else { throw SyncError.server(http.statusCode) }
        return data
    }

    /// Deletes server-side data. For `.account` this erases everything; for
    /// `.device` it only revokes this device. After a successful `.account` or
    /// `.device` delete we also unpair locally so the app reflects the new state.
    func deleteServerData(scope: DeleteScope) async throws {
        guard let baseURL = resolvedBaseURL else { throw SyncError.notConfigured }
        guard let token = (try? tokenStore.readKey()) ?? nil else { throw SyncError.notPaired }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/account/delete"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["scope": scope.rawValue])

        let (_, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.transport("No response from server.")
        }
        if http.statusCode == 401 { throw SyncError.notPaired }
        guard (200...299).contains(http.statusCode) else { throw SyncError.server(http.statusCode) }

        // The token is now invalid (device scope) or all data is gone (account
        // scope); either way this device is no longer connected.
        unpair()
    }

    // MARK: - Sync

    /// Uploads measurements recorded in the last `days` days. Safe to call
    /// repeatedly — the server upserts on each sample's stable id.
    @discardableResult
    func sync(context: ModelContext, days: Int = 30) async -> Bool {
        guard hasCloudConsent else {
            lastError = SyncError.consentRequired.errorDescription
            return false
        }
        guard resolvedBaseURL != nil else {
            lastError = SyncError.notConfigured.errorDescription
            return false
        }
        guard let token = (try? tokenStore.readKey()) ?? nil else {
            lastError = SyncError.notPaired.errorDescription
            return false
        }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let descriptor = FetchDescriptor<Measurement>(
            predicate: #Predicate { $0.timestamp >= since },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        guard let measurements = try? context.fetch(descriptor), !measurements.isEmpty else {
            lastSyncAt = Date()
            return true // nothing to upload is still a success
        }

        let payload = measurements.map { m -> [String: Any] in
            [
                "clientId": m.id.uuidString,
                "kind": Self.webKind(for: m.kind),
                "value": m.value,
                "unit": m.unit,
                "recordedAt": ISO8601DateFormatter.shared.string(from: m.timestamp),
            ]
        }

        do {
            let accepted = try await upload(samples: payload, token: token)
            lastSyncAt = Date()
            return accepted >= 0
        } catch let error as SyncError {
            lastError = error.errorDescription
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// POSTs samples in batches and returns the total accepted count.
    private func upload(samples: [[String: Any]], token: String) async throws -> Int {
        guard let baseURL = resolvedBaseURL else { throw SyncError.notConfigured }
        let batchSize = 500
        var totalAccepted = 0

        for start in stride(from: 0, to: samples.count, by: batchSize) {
            let batch = Array(samples[start..<min(start + batchSize, samples.count)])
            var request = URLRequest(url: baseURL.appendingPathComponent("api/ingest/metrics"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["samples": batch])

            let (data, response) = try await send(request)
            guard let http = response as? HTTPURLResponse else {
                throw SyncError.transport("No response from server.")
            }
            if http.statusCode == 401 { throw SyncError.notPaired }
            guard (200...299).contains(http.statusCode) else { throw SyncError.server(http.statusCode) }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accepted = json["accepted"] as? Int {
                totalAccepted += accepted
            }
        }
        return totalAccepted
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw SyncError.transport(error.localizedDescription)
        }
    }

    // MARK: - Generic record sync (roadmap W3)
    //
    // Shared plumbing so `DataSyncService` can upload arbitrary module records
    // (Tasks, Notes, …) through the same configuration, consent, token, and
    // transport as health metrics — without re-implementing any of it.

    /// Whether generic record sync may run: configured, consented, and paired.
    /// Returns the device token when ready, or throws the precise reason.
    func requireSyncToken() throws -> String {
        guard hasCloudConsent else { throw SyncError.consentRequired }
        guard resolvedBaseURL != nil else { throw SyncError.notConfigured }
        guard let token = (try? tokenStore.readKey()) ?? nil else { throw SyncError.notPaired }
        return token
    }

    /// POSTs a batch of generic records to `/api/v1/sync/records` and returns the
    /// accepted count. Idempotent + last-writer-wins server-side.
    func uploadRecords(_ records: [[String: Any]], token: String) async throws -> Int {
        guard let baseURL = resolvedBaseURL else { throw SyncError.notConfigured }
        let batchSize = 500
        var totalAccepted = 0

        for start in stride(from: 0, to: records.count, by: batchSize) {
            let batch = Array(records[start..<min(start + batchSize, records.count)])
            var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/sync/records"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["records": batch])

            let (data, response) = try await send(request)
            guard let http = response as? HTTPURLResponse else {
                throw SyncError.transport("No response from server.")
            }
            if http.statusCode == 401 { throw SyncError.notPaired }
            guard (200...299).contains(http.statusCode) else { throw SyncError.server(http.statusCode) }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accepted = json["accepted"] as? Int {
                totalAccepted += accepted
            }
        }
        return totalAccepted
    }

    // MARK: - Mapping

    /// Maps the app's `MeasurementKind` to the web schema's `kind` string.
    static func webKind(for kind: MeasurementKind) -> String {
        switch kind {
        case .heartRate: return "heart_rate"
        case .spo2: return "spo2"
        }
    }

    static func deviceDisplayName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iPhone"
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif

private extension ISO8601DateFormatter {
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
