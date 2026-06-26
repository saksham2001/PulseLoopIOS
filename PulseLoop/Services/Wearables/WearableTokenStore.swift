import Foundation
import Security

/// The set of third-party health sources we can connect via OAuth2.
enum WearableProvider: String, CaseIterable, Codable, Identifiable {
    case fitbit
    case googleFit
    case oura
    case whoop
    case garmin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fitbit: return "Fitbit"
        case .googleFit: return "Google Fit"
        case .oura: return "Oura Ring"
        case .whoop: return "Whoop"
        case .garmin: return "Garmin"
        }
    }

    var iconSystemName: String {
        switch self {
        case .fitbit: return "figure.run"
        case .googleFit: return "heart.text.square"
        case .oura: return "circle.circle"
        case .whoop: return "bolt.heart"
        case .garmin: return "location.north.circle"
        }
    }

    /// The `MeasurementSource` rows from this provider are tagged with, so the
    /// dashboard + coach can attribute and de-dupe by origin.
    var measurementSource: MeasurementSource {
        switch self {
        case .fitbit: return .fitbit
        case .googleFit: return .googleFit
        case .oura: return .oura
        case .whoop: return .whoop
        case .garmin: return .garmin
        }
    }

    /// String used in `ActivityDaily.source` (matches HealthKit's lowercase style).
    var activitySource: String {
        switch self {
        case .fitbit: return "fitbit"
        case .googleFit: return "googlefit"
        case .oura: return "oura"
        case .whoop: return "whoop"
        case .garmin: return "garmin"
        }
    }

    /// Whether Apple Health / on-device data already covers this provider's
    /// metrics. (Always false here — these are external OAuth sources.)
    static var oauthProviders: [WearableProvider] { allCases }
}

/// A persisted OAuth2 token bundle. Stored as JSON in the Keychain so refresh
/// tokens and expiry survive relaunches without ever touching UserDefaults.
struct OAuthTokenBundle: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scope: String?

    /// True when the access token is expired (or within a 60s safety margin).
    func isExpired(now: Date = Date()) -> Bool {
        now >= expiresAt.addingTimeInterval(-60)
    }
}

/// Keychain-backed store for a provider's `OAuthTokenBundle`. Mirrors the
/// `APIKeyStore` upsert pattern but stores a Codable bundle (JSON) rather than a
/// bare string. Injectable for tests via the `KeychainBackend` seam.
struct WearableTokenStore {
    private let provider: WearableProvider
    private let backend: KeychainBackend

    init(provider: WearableProvider, backend: KeychainBackend = SystemKeychainBackend()) {
        self.provider = provider
        self.backend = backend
    }

    private var service: String { "com.pulseloop.wearable.\(provider.rawValue)" }
    private let account = "oauth_token_bundle"

    func read() -> OAuthTokenBundle? {
        guard let data = (try? backend.read(service: service, account: account)) ?? nil else { return nil }
        return try? JSONDecoder.iso.decode(OAuthTokenBundle.self, from: data)
    }

    func save(_ bundle: OAuthTokenBundle) throws {
        let data = try JSONEncoder.iso.encode(bundle)
        try backend.save(data, service: service, account: account)
    }

    func clear() throws {
        try backend.delete(service: service, account: account)
    }

    var isConnected: Bool { read() != nil }
}

// MARK: - Keychain backend seam (testable)

/// A minimal data-blob secret store so token persistence can be unit-tested with
/// an in-memory fake (the real one talks to the iOS Keychain).
protocol KeychainBackend {
    func read(service: String, account: String) throws -> Data?
    func save(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

struct SystemKeychainBackend: KeychainBackend {
    private func baseQuery(_ service: String, _ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read(service: String, account: String) throws -> Data? {
        var query = baseQuery(service, account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return item as? Data
    }

    func save(_ data: Data, service: String, account: String) throws {
        let base = baseQuery(service, account)
        let updateStatus = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var insert = base
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
            return
        }
        throw KeychainError.unexpectedStatus(updateStatus)
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service, account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
