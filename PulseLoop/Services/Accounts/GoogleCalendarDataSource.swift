import Foundation

/// Google Calendar API (v3) read-only data source. Pulls upcoming events over
/// OAuth2 and exposes them via `AccountDataSource`. Network is behind
/// `AccountHTTPClient`/`HTTPTransport`; the JSON → `RemoteCalendarEvent` mapping is
/// a `nonisolated static` parser so it's unit-tested with canned responses.
///
/// API reference: https://developers.google.com/calendar/api/v3/reference
@MainActor
final class GoogleCalendarDataSource: AccountDataSource {
    let provider: AccountProvider = .googleCalendar
    private let client: AccountHTTPClient

    init(authenticator: AccountOAuthAuthenticator, transport: HTTPTransport = URLSession.shared) {
        self.client = AccountHTTPClient(provider: .googleCalendar, authenticator: authenticator, transport: transport)
    }

    func requestAuthorization() async throws { try await client.authorize() }

    func fetchUpcomingEvents(daysAhead: Int) async throws -> [RemoteCalendarEvent] {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now
        let iso = ISO8601DateFormatter()
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: iso.string(from: now)),
            URLQueryItem(name: "timeMax", value: iso.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50"),
        ]
        let json = try await client.getJSON(components.url!)
        return GoogleCalendarDataSource.parseEvents(json)
    }

    // MARK: - Pure parser (unit-tested)

    nonisolated static func parseEvents(_ json: [String: Any]) -> [RemoteCalendarEvent] {
        guard let items = json["items"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        let dayOnly = DateFormatter()
        dayOnly.dateFormat = "yyyy-MM-dd"
        dayOnly.locale = Locale(identifier: "en_US_POSIX")

        func parseDateNode(_ node: Any?) -> (date: Date, allDay: Bool)? {
            guard let dict = node as? [String: Any] else { return nil }
            if let dt = dict["dateTime"] as? String {
                if let d = iso.date(from: dt) ?? isoPlain.date(from: dt) { return (d, false) }
            }
            if let d = dict["date"] as? String, let day = dayOnly.date(from: d) {
                return (day, true)
            }
            return nil
        }

        return items.compactMap { item -> RemoteCalendarEvent? in
            guard let start = parseDateNode(item["start"]) else { return nil }
            let end = parseDateNode(item["end"])?.date
            let id = (item["id"] as? String) ?? UUID().uuidString
            let title = (item["summary"] as? String) ?? "(No title)"
            return RemoteCalendarEvent(
                id: id,
                title: title,
                start: start.date,
                end: end,
                location: item["location"] as? String,
                isAllDay: start.allDay
            )
        }
    }
}
