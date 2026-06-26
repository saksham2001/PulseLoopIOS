import Foundation

/// Notion read-only task pull. Queries a tasks database the user authorized and
/// maps pages → `RemoteTask` for the `TaskItem` store (pull-in direction). Pushing
/// changes back to Notion is confirmation-gated and lives outside this source.
/// Network is behind `AccountHTTPClient`; parsing is `nonisolated static`,
/// unit-tested with canned responses.
///
/// API reference: https://developers.notion.com/reference
@MainActor
final class NotionDataSource: AccountDataSource {
    let provider: AccountProvider = .notion
    private let client: AccountHTTPClient

    init(authenticator: AccountOAuthAuthenticator, transport: HTTPTransport = URLSession.shared) {
        self.client = AccountHTTPClient(provider: .notion, authenticator: authenticator, transport: transport)
    }

    func requestAuthorization() async throws { try await client.authorize() }

    func fetchTasks() async throws -> [RemoteTask] {
        // Notion search for pages, then map their title + checkbox/date properties.
        let url = URL(string: "https://api.notion.com/v1/search")!
        let body: [String: Any] = ["filter": ["property": "object", "value": "page"], "page_size": 50]
        let json = try await client.postJSON(url, body: body, extraHeaders: ["Notion-Version": "2022-06-28"])
        return NotionDataSource.parseTasks(json)
    }

    // MARK: - Pure parser (unit-tested)

    nonisolated static func parseTasks(_ json: [String: Any]) -> [RemoteTask] {
        guard let results = json["results"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        let dayOnly = DateFormatter()
        dayOnly.dateFormat = "yyyy-MM-dd"
        dayOnly.locale = Locale(identifier: "en_US_POSIX")

        return results.compactMap { page -> RemoteTask? in
            guard let id = page["id"] as? String,
                  let properties = page["properties"] as? [String: Any] else { return nil }
            var title = "(Untitled)"
            var due: Date?
            var done = false
            for (_, value) in properties {
                guard let prop = value as? [String: Any], let type = prop["type"] as? String else { continue }
                switch type {
                case "title":
                    if let arr = prop["title"] as? [[String: Any]],
                       let text = arr.first?["plain_text"] as? String, !text.isEmpty {
                        title = text
                    }
                case "checkbox":
                    if let checked = prop["checkbox"] as? Bool { done = checked }
                case "date":
                    if let date = prop["date"] as? [String: Any], let start = date["start"] as? String {
                        due = iso.date(from: start) ?? dayOnly.date(from: start)
                    }
                default:
                    break
                }
            }
            return RemoteTask(id: id, title: title, due: due, isCompleted: done)
        }
    }
}
