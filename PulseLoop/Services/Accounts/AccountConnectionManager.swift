import Foundation
import SwiftData
import Observation

/// Owns the connect / disconnect / sync lifecycle for OAuth-backed **account**
/// connectors (Gmail, Google & Apple Calendar, Slack, Notion, Todoist) and ingests
/// their data into the app's shared stores: calendar events + messages flow into
/// the `InboxItem` capture surface (so the assistant can file them), and tasks flow
/// into `TaskItem`. Mirrors `WearableConnectionManager`. All ingestion is read-only;
/// any write back to a provider goes through the assistant's PendingAction
/// confirmation path, never silently here.
@MainActor
@Observable
final class AccountConnectionManager {
    static let shared = AccountConnectionManager()

    struct SyncResult: Equatable {
        var events: Int = 0
        var messages: Int = 0
        var tasks: Int = 0
    }

    private(set) var lastError: [AccountProvider: String] = [:]
    private(set) var lastSyncedAt: [AccountProvider: Date] = [:]
    private(set) var isSyncing: Set<AccountProvider> = []

    private let authenticator: AccountOAuthAuthenticator
    private let transport: HTTPTransport
    private let eventStore: EventKitCalendarSource

    init(authenticator: AccountOAuthAuthenticator? = nil,
         transport: HTTPTransport = URLSession.shared,
         eventStore: EventKitCalendarSource? = nil) {
        self.authenticator = authenticator ?? AccountOAuthAuthenticator(transport: transport)
        self.transport = transport
        self.eventStore = eventStore ?? EventKitCalendarSource()
        for provider in AccountOAuthConfig.oauthProviders + [.appleCalendar] {
            let key = "account.lastSyncedAt.\(provider.rawValue)"
            if let ts = UserDefaults.standard.object(forKey: key) as? Date {
                lastSyncedAt[provider] = ts
            }
        }
    }

    // MARK: - State

    func isConfigured(_ provider: AccountProvider) -> Bool {
        if provider == .appleCalendar { return true } // local EventKit
        return AccountOAuthConfig.isConfigured(provider)
    }

    func isConnected(_ provider: AccountProvider) -> Bool {
        if provider == .appleCalendar { return eventStore.isAuthorized }
        return AccountTokenStore(provider: provider).isConnected
    }

    func source(for provider: AccountProvider) -> AccountDataSource? {
        switch provider {
        case .gmail: return GmailDataSource(authenticator: authenticator, transport: transport)
        case .googleCalendar: return GoogleCalendarDataSource(authenticator: authenticator, transport: transport)
        case .appleCalendar: return eventStore
        case .slack: return SlackDataSource(authenticator: authenticator, transport: transport)
        case .notion: return NotionDataSource(authenticator: authenticator, transport: transport)
        case .todoist: return TodoistDataSource(authenticator: authenticator, transport: transport)
        default: return nil
        }
    }

    // MARK: - Connect / disconnect

    @discardableResult
    func connect(_ provider: AccountProvider, context: ModelContext) async -> Bool {
        lastError[provider] = nil
        guard let src = source(for: provider) else {
            lastError[provider] = "\(provider.rawValue) isn't supported."
            return false
        }
        do {
            try await src.requestAuthorization()
            _ = try await sync(provider, context: context)
            return true
        } catch {
            lastError[provider] = (error as? LocalizedError)?.errorDescription ?? "Couldn't connect."
            return false
        }
    }

    func disconnect(_ provider: AccountProvider) {
        if provider != .appleCalendar {
            try? AccountTokenStore(provider: provider).clear()
        }
        lastError[provider] = nil
        lastSyncedAt[provider] = nil
        UserDefaults.standard.removeObject(forKey: "account.lastSyncedAt.\(provider.rawValue)")
    }

    // MARK: - Sync (read-only ingestion)

    @discardableResult
    func sync(_ provider: AccountProvider, context: ModelContext) async throws -> SyncResult {
        guard isConnected(provider), let src = source(for: provider) else {
            throw AccountOAuthError.notConfigured(provider)
        }
        isSyncing.insert(provider)
        defer { isSyncing.remove(provider) }

        var result = SyncResult()

        let events = try await src.fetchUpcomingEvents(daysAhead: 7)
        for event in events {
            AccountConnectionManager.upsertEventInbox(event, provider: provider, context: context)
            result.events += 1
        }

        let messages = try await src.fetchRecentMessages(limit: 20)
        for message in messages {
            AccountConnectionManager.upsertMessageInbox(message, provider: provider, context: context)
            result.messages += 1
        }

        let tasks = try await src.fetchTasks()
        for task in tasks {
            AccountConnectionManager.upsertTask(task, provider: provider, context: context)
            result.tasks += 1
        }

        context.saveOrLog("account.sync")
        let now = Date()
        lastSyncedAt[provider] = now
        UserDefaults.standard.set(now, forKey: "account.lastSyncedAt.\(provider.rawValue)")
        lastError[provider] = nil
        return result
    }

    // MARK: - Ingestion mappers (pure-ish, de-duped by stable external id)

    static func inboxSource(for provider: AccountProvider) -> InboxSource {
        switch provider {
        case .gmail: return .gmail
        case .googleCalendar, .appleCalendar: return .calendar
        case .slack: return .slack
        default: return .other
        }
    }

    /// Upsert a calendar event into the inbox so the assistant can act on it, keyed
    /// by a stable subtitle marker so re-sync doesn't duplicate.
    static func upsertEventInbox(_ event: RemoteCalendarEvent, provider: AccountProvider, context: ModelContext) {
        let marker = "evt:\(provider.rawValue):\(event.id)"
        guard !inboxContainsMarker(marker, context: context) else { return }
        let timeLabel = Self.timeLabel(start: event.start, end: event.end, isAllDay: event.isAllDay)
        let item = InboxItem(
            title: event.title,
            subtitle: "\(timeLabel)\u{2007}\u{2007}#\(marker)",
            source: inboxSource(for: provider),
            icon: "calendar",
            suggestedAction: nil,
            actionType: .addToCalendar
        )
        context.insert(item)
    }

    static func upsertMessageInbox(_ message: RemoteMessage, provider: AccountProvider, context: ModelContext) {
        let marker = "msg:\(provider.rawValue):\(message.id)"
        guard !inboxContainsMarker(marker, context: context) else { return }
        let item = InboxItem(
            title: message.title,
            subtitle: "\(message.snippet)\u{2007}\u{2007}#\(marker)",
            source: inboxSource(for: provider),
            icon: provider == .slack ? "number" : "envelope",
            suggestedAction: provider == .slack ? "Reply by voice" : nil,
            actionType: .createTask
        )
        context.insert(item)
    }

    /// Pull a remote task into `TaskItem`, keyed by a stable label so re-sync updates
    /// the same row instead of creating a duplicate. Read-only pull; push-out is
    /// confirmation-gated elsewhere.
    static func upsertTask(_ task: RemoteTask, provider: AccountProvider, context: ModelContext) {
        let externalLabel = "\(provider.rawValue)#\(task.id)"
        let descriptor = FetchDescriptor<TaskItem>()
        let existing = ((try? context.fetch(descriptor)) ?? []).first { $0.label == externalLabel }
        if let row = existing {
            row.title = task.title
            row.dueDate = task.due
            row.status = task.isCompleted ? .done : (row.status == .done ? .todo : row.status)
            row.updatedAt = Date()
        } else {
            let item = TaskItem(
                title: task.title,
                status: task.isCompleted ? .done : .todo,
                group: provider.rawValue.capitalized,
                label: externalLabel,
                dueDate: task.due
            )
            context.insert(item)
        }
    }

    private static func inboxContainsMarker(_ marker: String, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<InboxItem>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.contains { $0.subtitle.contains("#\(marker)") }
    }

    static func timeLabel(start: Date, end: Date?, isAllDay: Bool) -> String {
        if isAllDay { return "All day" }
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: start)
    }
}
