import Foundation

/// Slack read-only data source. Pulls recent messages from channels/DMs the user
/// authorized (history scopes) and exposes them as `RemoteMessage` for the inbox
/// capture path. Never posts (no chat:write scope). Network is behind
/// `AccountHTTPClient`; parsing is a `nonisolated static` function, unit-tested.
///
/// API reference: https://api.slack.com/methods
@MainActor
final class SlackDataSource: AccountDataSource {
    let provider: AccountProvider = .slack
    private let client: AccountHTTPClient

    init(authenticator: AccountOAuthAuthenticator, transport: HTTPTransport = URLSession.shared) {
        self.client = AccountHTTPClient(provider: .slack, authenticator: authenticator, transport: transport)
    }

    func requestAuthorization() async throws { try await client.authorize() }

    func fetchRecentMessages(limit: Int) async throws -> [RemoteMessage] {
        // Use search.messages over the user's authorized scope to find recent
        // mentions/DMs. (Slack's Web API returns a uniform message envelope.)
        var components = URLComponents(string: "https://slack.com/api/search.messages")!
        components.queryItems = [
            URLQueryItem(name: "query", value: "is:unread"),
            URLQueryItem(name: "count", value: String(limit)),
        ]
        let json = try await client.getJSON(components.url!)
        return SlackDataSource.parseMessages(json)
    }

    // MARK: - Pure parser (unit-tested)

    nonisolated static func parseMessages(_ json: [String: Any]) -> [RemoteMessage] {
        guard let messages = json["messages"] as? [String: Any],
              let matches = messages["matches"] as? [[String: Any]] else { return [] }
        return matches.compactMap { match -> RemoteMessage? in
            let text = (match["text"] as? String) ?? ""
            guard !text.isEmpty else { return nil }
            let channel = (match["channel"] as? [String: Any])?["name"] as? String
            let user = match["username"] as? String
            let ts = (match["ts"] as? String).flatMap { Double($0) }
            let id = (match["iid"] as? String) ?? (match["ts"] as? String) ?? UUID().uuidString
            return RemoteMessage(
                id: id,
                title: channel.map { "#\($0)" } ?? (user ?? "Slack"),
                snippet: text,
                from: user,
                receivedAt: ts.map { Date(timeIntervalSince1970: $0) } ?? Date()
            )
        }
    }
}
