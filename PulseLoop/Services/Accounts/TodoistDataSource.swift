import Foundation

/// Todoist (REST v2) read-only task pull. Maps active tasks → `RemoteTask` for the
/// `TaskItem` store (pull-in direction). Pushing changes back to Todoist is
/// confirmation-gated and lives outside this source. Network is behind
/// `AccountHTTPClient`; parsing is `nonisolated static`, unit-tested.
///
/// API reference: https://developer.todoist.com/rest/v2
@MainActor
final class TodoistDataSource: AccountDataSource {
    let provider: AccountProvider = .todoist
    private let client: AccountHTTPClient

    init(authenticator: AccountOAuthAuthenticator, transport: HTTPTransport = URLSession.shared) {
        self.client = AccountHTTPClient(provider: .todoist, authenticator: authenticator, transport: transport)
    }

    func requestAuthorization() async throws { try await client.authorize() }

    func fetchTasks() async throws -> [RemoteTask] {
        // The REST v2 /tasks endpoint returns a top-level JSON array.
        let url = URL(string: "https://api.todoist.com/rest/v2/tasks")!
        let items = try await client.getJSONArray(url)
        return TodoistDataSource.parseTasks(items)
    }

    /// Public entry the source uses; also the unit-test seam (array in → tasks out).
    nonisolated static func parseTasks(_ items: [[String: Any]]) -> [RemoteTask] {
        let iso = ISO8601DateFormatter()
        let dayOnly = DateFormatter()
        dayOnly.dateFormat = "yyyy-MM-dd"
        dayOnly.locale = Locale(identifier: "en_US_POSIX")

        return items.compactMap { item -> RemoteTask? in
            guard let content = item["content"] as? String else { return nil }
            let id = (item["id"] as? String) ?? ((item["id"] as? Int).map(String.init)) ?? UUID().uuidString
            let isCompleted = (item["is_completed"] as? Bool) ?? (item["completed"] as? Bool) ?? false
            var due: Date?
            if let dueDict = item["due"] as? [String: Any] {
                if let datetime = dueDict["datetime"] as? String { due = iso.date(from: datetime) }
                else if let date = dueDict["date"] as? String { due = dayOnly.date(from: date) }
            }
            return RemoteTask(id: id, title: content, due: due, isCompleted: isCompleted)
        }
    }
}
