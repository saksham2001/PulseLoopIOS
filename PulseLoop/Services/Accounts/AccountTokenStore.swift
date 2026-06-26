import Foundation

/// Keychain-backed OAuth token store for a connected **account** provider
/// (Gmail, Google Calendar, Slack, Notion, Todoist). Mirrors `WearableTokenStore`
/// but namespaced separately so health and account links never share token slots.
/// Reuses the same `OAuthTokenBundle` + `KeychainBackend` seam as wearables.
struct AccountTokenStore {
    private let provider: AccountProvider
    private let backend: KeychainBackend

    init(provider: AccountProvider, backend: KeychainBackend = SystemKeychainBackend()) {
        self.provider = provider
        self.backend = backend
    }

    private var service: String { "com.pulseloop.account.\(provider.rawValue)" }
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
