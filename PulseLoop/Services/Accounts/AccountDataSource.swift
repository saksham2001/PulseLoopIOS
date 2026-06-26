import Foundation

// MARK: - Account data DTOs
//
// Provider-neutral value types that account data sources parse their JSON into,
// before the connection manager maps them into the app's shared stores
// (`InboxItem`, `TaskItem`, calendar surfaces). Keeping these pure makes every
// data source's response-parsing unit-testable with a stubbed transport.

/// A calendar event pulled from Google Calendar (or EventKit), read-only.
struct RemoteCalendarEvent: Equatable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date?
    let location: String?
    let isAllDay: Bool
}

/// A message / notification pulled from Gmail or Slack, routed into the inbox.
struct RemoteMessage: Equatable, Identifiable {
    let id: String
    let title: String
    let snippet: String
    let from: String?
    let receivedAt: Date
}

/// A task pulled from Notion or Todoist, mapped into `TaskItem`.
struct RemoteTask: Equatable, Identifiable {
    let id: String
    let title: String
    let due: Date?
    let isCompleted: Bool
}

/// A read-only account data source. Each provider implements only the fetches it
/// supports (the default implementations return empty), all over `HTTPTransport`
/// so parsing is testable. Mutations (create/update) NEVER live here — they go
/// through the assistant's PendingAction confirmation path.
protocol AccountDataSource {
    var provider: AccountProvider { get }
    func requestAuthorization() async throws
    func fetchUpcomingEvents(daysAhead: Int) async throws -> [RemoteCalendarEvent]
    func fetchRecentMessages(limit: Int) async throws -> [RemoteMessage]
    func fetchTasks() async throws -> [RemoteTask]
}

extension AccountDataSource {
    func fetchUpcomingEvents(daysAhead: Int) async throws -> [RemoteCalendarEvent] { [] }
    func fetchRecentMessages(limit: Int) async throws -> [RemoteMessage] { [] }
    func fetchTasks() async throws -> [RemoteTask] { [] }
}
