import Foundation

/// Gmail API (v1) read-only data source. Pulls recent messages (receipts, bills,
/// invites) over OAuth2 (gmail.readonly scope) and exposes them as `RemoteMessage`
/// for routing into the inbox capture path. Never sends mail. Network is behind
/// `AccountHTTPClient`; the JSON → `RemoteMessage` mapping is a `nonisolated static`
/// parser, unit-tested with canned responses.
///
/// API reference: https://developers.google.com/gmail/api/reference/rest
@MainActor
final class GmailDataSource: AccountDataSource {
    let provider: AccountProvider = .gmail
    private let client: AccountHTTPClient

    init(authenticator: AccountOAuthAuthenticator, transport: HTTPTransport = URLSession.shared) {
        self.client = AccountHTTPClient(provider: .gmail, authenticator: authenticator, transport: transport)
    }

    func requestAuthorization() async throws { try await client.authorize() }

    func fetchRecentMessages(limit: Int) async throws -> [RemoteMessage] {
        var listComponents = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        listComponents.queryItems = [
            URLQueryItem(name: "maxResults", value: String(limit)),
            // Surface actionable mail: receipts/bills/invites in the primary inbox.
            URLQueryItem(name: "q", value: "category:primary newer_than:7d"),
        ]
        let listJSON = try await client.getJSON(listComponents.url!)
        let ids = GmailDataSource.parseMessageIDs(listJSON)

        var results: [RemoteMessage] = []
        for id in ids.prefix(limit) {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=metadata&metadataHeaders=Subject&metadataHeaders=From")!
            if let detail = try? await client.getJSON(url),
               let message = GmailDataSource.parseMessage(detail) {
                results.append(message)
            }
        }
        return results
    }

    // MARK: - Pure parsers (unit-tested)

    nonisolated static func parseMessageIDs(_ json: [String: Any]) -> [String] {
        guard let messages = json["messages"] as? [[String: Any]] else { return [] }
        return messages.compactMap { $0["id"] as? String }
    }

    /// A `format=metadata` message → subject/from headers + snippet.
    nonisolated static func parseMessage(_ json: [String: Any]) -> RemoteMessage? {
        guard let id = json["id"] as? String else { return nil }
        let snippet = (json["snippet"] as? String) ?? ""
        var subject = "(No subject)"
        var from: String?
        if let payload = json["payload"] as? [String: Any],
           let headers = payload["headers"] as? [[String: Any]] {
            for header in headers {
                guard let name = header["name"] as? String, let value = header["value"] as? String else { continue }
                if name.caseInsensitiveCompare("Subject") == .orderedSame { subject = value }
                if name.caseInsensitiveCompare("From") == .orderedSame { from = value }
            }
        }
        let receivedAt: Date
        if let internalMs = (json["internalDate"] as? String).flatMap({ Double($0) }) {
            receivedAt = Date(timeIntervalSince1970: internalMs / 1000)
        } else {
            receivedAt = Date()
        }
        return RemoteMessage(id: id, title: subject, snippet: snippet, from: from, receivedAt: receivedAt)
    }
}
