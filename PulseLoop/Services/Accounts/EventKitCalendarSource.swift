import Foundation
import EventKit

/// Apple Calendar source over EventKit (local, no OAuth). Reads upcoming events
/// from the user's calendars after authorization. Conforms to `AccountDataSource`
/// so the connection manager treats it uniformly; its "connect" is an EventKit
/// authorization request rather than a web OAuth flow. Read-only.
@MainActor
final class EventKitCalendarSource: AccountDataSource {
    let provider: AccountProvider = .appleCalendar
    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            return status == .fullAccess || status == .authorized
        } else {
            return status == .authorized
        }
    }

    var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    func requestAuthorization() async throws {
        if #available(iOS 17.0, *) {
            let granted = try await store.requestFullAccessToEvents()
            if !granted { throw AccountOAuthError.userCancelled }
        } else {
            let granted = try await store.requestAccess(to: .event)
            if !granted { throw AccountOAuthError.userCancelled }
        }
    }

    func fetchUpcomingEvents(daysAhead: Int) async throws -> [RemoteCalendarEvent] {
        guard isAuthorized else { return [] }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now.addingTimeInterval(Double(daysAhead) * 86400)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        return events.map { ev in
            RemoteCalendarEvent(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "(No title)",
                start: ev.startDate,
                end: ev.endDate,
                location: ev.location,
                isAllDay: ev.isAllDay
            )
        }
    }
}
