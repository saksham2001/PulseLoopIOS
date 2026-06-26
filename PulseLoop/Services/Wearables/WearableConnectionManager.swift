import Foundation
import SwiftData
import Observation

/// Owns the connect / disconnect / sync lifecycle for third-party wearable health
/// sources (Fitbit, Google Fit) and persists their samples into the same
/// `ActivityDaily` (steps) + `Measurement` (HR/SpO2) stores Apple Health uses — so
/// the dashboard and the coach surface them automatically (no consumer changes).
@MainActor
@Observable
final class WearableConnectionManager {
    static let shared = WearableConnectionManager()

    struct SyncResult: Equatable {
        var steps: Int?
        var heartRate: Int?
        var spo2: Int?
    }

    /// Per-provider last error message (for the connectors UI).
    private(set) var lastError: [WearableProvider: String] = [:]
    private(set) var lastSyncedAt: [WearableProvider: Date] = [:]
    private(set) var isSyncing: Set<WearableProvider> = []

    private let authenticator: WearableOAuthAuthenticator
    private let transport: HTTPTransport

    init(authenticator: WearableOAuthAuthenticator? = nil,
         transport: HTTPTransport = URLSession.shared) {
        self.authenticator = authenticator ?? WearableOAuthAuthenticator(transport: transport)
        self.transport = transport
        for provider in WearableProvider.allCases {
            let key = "wearable.lastSyncedAt.\(provider.rawValue)"
            if let ts = UserDefaults.standard.object(forKey: key) as? Date {
                lastSyncedAt[provider] = ts
            }
        }
    }

    // MARK: - State

    func isConnected(_ provider: WearableProvider) -> Bool {
        WearableTokenStore(provider: provider).isConnected
    }

    func isConfigured(_ provider: WearableProvider) -> Bool {
        WearableOAuthConfig.isConfigured(provider)
    }

    private func source(for provider: WearableProvider) -> WearableDataSource {
        switch provider {
        case .fitbit: return FitbitDataSource(authenticator: authenticator, transport: transport)
        case .googleFit: return GoogleFitDataSource(authenticator: authenticator, transport: transport)
        case .oura: return OuraDataSource(authenticator: authenticator, transport: transport)
        case .whoop: return WhoopDataSource(authenticator: authenticator, transport: transport)
        case .garmin: return GarminDataSource(authenticator: authenticator, transport: transport)
        }
    }

    // MARK: - Connect / disconnect

    /// Run the interactive OAuth consent flow and then an initial sync.
    @discardableResult
    func connect(_ provider: WearableProvider, context: ModelContext) async -> Bool {
        lastError[provider] = nil
        do {
            try await source(for: provider).requestAuthorization()
            _ = try await sync(provider, context: context)
            return true
        } catch {
            lastError[provider] = (error as? LocalizedError)?.errorDescription ?? "Couldn't connect \(provider.displayName)."
            return false
        }
    }

    func disconnect(_ provider: WearableProvider) {
        try? WearableTokenStore(provider: provider).clear()
        lastError[provider] = nil
        lastSyncedAt[provider] = nil
        UserDefaults.standard.removeObject(forKey: "wearable.lastSyncedAt.\(provider.rawValue)")
    }

    // MARK: - Sync

    /// Pull today's steps + HR (+ SpO2 where available) and persist them.
    @discardableResult
    func sync(_ provider: WearableProvider, context: ModelContext, date: Date = Date()) async throws -> SyncResult {
        guard isConnected(provider) else { throw WearableOAuthError.notConfigured(provider) }
        isSyncing.insert(provider)
        defer { isSyncing.remove(provider) }

        let src = source(for: provider)
        var result = SyncResult()

        if let steps = try await src.fetchSteps(for: date) {
            result.steps = steps
            WearableConnectionManager.upsertSteps(steps, source: provider.activitySource, date: date, context: context)
        }
        if let hr = try await src.fetchLatestHeartRate() {
            result.heartRate = Int(hr.rounded())
            context.insert(Measurement(kind: .heartRate, value: hr, unit: "bpm", timestamp: date, source: provider.measurementSource))
        }
        if let spo2 = try await src.fetchLatestSpO2() {
            result.spo2 = Int(spo2.rounded())
            context.insert(Measurement(kind: .spo2, value: spo2, unit: "%", timestamp: date, source: provider.measurementSource))
        }
        if let sleep = try await src.fetchSleep(for: date) {
            WearableConnectionManager.upsertSleep(
                start: sleep.start, end: sleep.end, minutes: sleep.minutes, date: date, context: context
            )
        }

        context.saveOrLog("wearable.sync")
        let now = Date()
        lastSyncedAt[provider] = now
        UserDefaults.standard.set(now, forKey: "wearable.lastSyncedAt.\(provider.rawValue)")
        lastError[provider] = nil
        return result
    }

    /// Upsert a daily step count for a given source, taking the larger value so a
    /// later partial sync never lowers a day's total.
    static func upsertSteps(_ steps: Int, source: String, date: Date, context: ModelContext) {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<ActivityDaily>()
        let existing = ((try? context.fetch(descriptor)) ?? []).first {
            Calendar.current.isDate($0.date, inSameDayAs: day) && $0.source == source
        }
        if let row = existing {
            row.steps = max(row.steps, steps)
            row.syncedAt = Date()
            row.updatedAt = Date()
        } else {
            let row = ActivityDaily(date: day, steps: steps, source: source)
            row.syncedAt = Date()
            context.insert(row)
        }
    }

    /// Upsert a night's sleep session for a given day. Replaces an existing
    /// same-day session only when the new one is at least as long, so a partial
    /// re-sync never shrinks a recorded night.
    static func upsertSleep(start: Date, end: Date, minutes: Int, date: Date, context: ModelContext) {
        guard minutes > 0, end > start else { return }
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<SleepSession>()
        let existing = ((try? context.fetch(descriptor)) ?? []).first {
            Calendar.current.isDate($0.date, inSameDayAs: day)
        }
        if let row = existing {
            guard minutes >= row.totalMinutes else { return }
            row.startAt = start
            row.endAt = end
            row.totalMinutes = minutes
            row.syncedAt = Date()
            row.updatedAt = Date()
        } else {
            let session = SleepSession(date: day, startAt: start, endAt: end, totalMinutes: minutes, syncedAt: Date())
            context.insert(session)
        }
    }
}
