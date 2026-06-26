import Foundation

/// Shared authorized-request plumbing for OAuth-backed account data sources
/// (Gmail, Google Calendar, Slack, Notion, Todoist). Handles transparent token
/// refresh against the provider's `AccountTokenStore` and performs GET/POST over
/// the injectable `HTTPTransport`. Response *parsing* stays in each source as
/// `nonisolated static` functions so it's unit-tested without networking.
@MainActor
final class AccountHTTPClient {
    let provider: AccountProvider
    private let store: AccountTokenStore
    private let authenticator: AccountOAuthAuthenticator
    private let transport: HTTPTransport

    init(provider: AccountProvider,
         store: AccountTokenStore? = nil,
         authenticator: AccountOAuthAuthenticator,
         transport: HTTPTransport = URLSession.shared) {
        self.provider = provider
        self.store = store ?? AccountTokenStore(provider: provider)
        self.authenticator = authenticator
        self.transport = transport
    }

    private func validAccessToken() async throws -> String {
        guard var bundle = store.read() else { throw AccountOAuthError.notConfigured(provider) }
        if bundle.isExpired() {
            bundle = try await authenticator.refresh(bundle, provider: provider)
            try store.save(bundle)
        }
        return bundle.accessToken
    }

    func authorize() async throws {
        // Persist the exchanged tokens; `connect` only returns the bundle, so
        // without saving here every later `validAccessToken()` would find an empty
        // store and throw `.notConfigured`, leaving the account never connected.
        let bundle = try await authenticator.connect(provider: provider)
        try store.save(bundle)
    }

    /// Authorized GET returning a JSON object (empty dict on non-object bodies).
    func getJSON(_ url: URL, extraHeaders: [String: String] = [:]) async throws -> [String: Any] {
        let token = try await validAccessToken()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await NetworkRetry.send(request, transport: transport)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AccountOAuthError.tokenExchangeFailed("\(provider.rawValue) HTTP error")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Authorized GET returning a top-level JSON array (e.g. Todoist /tasks).
    func getJSONArray(_ url: URL, extraHeaders: [String: String] = [:]) async throws -> [[String: Any]] {
        let token = try await validAccessToken()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await NetworkRetry.send(request, transport: transport)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AccountOAuthError.tokenExchangeFailed("\(provider.rawValue) HTTP error")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    /// Authorized POST with a JSON body returning a JSON object.
    func postJSON(_ url: URL, body: [String: Any], extraHeaders: [String: String] = [:]) async throws -> [String: Any] {
        let token = try await validAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await NetworkRetry.send(request, transport: transport)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AccountOAuthError.tokenExchangeFailed("\(provider.rawValue) HTTP error")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
