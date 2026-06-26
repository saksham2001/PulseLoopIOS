import Foundation
import XCTest
import SwiftData
@testable import PulseLoop

// MARK: - Connect loop: account OAuth layer (T4–T8)
//
// Pure-logic coverage for the account OAuth config gating, the token store, the
// authorize-URL builder + callback parser, every account data source's JSON
// parser, the ingestion mappers (events/messages → InboxItem, tasks → TaskItem),
// and the cross-source sync coordinator. No real network or Keychain involved.
final class AccountConnectorTests: XCTestCase {

    // MARK: Helpers

    final class MemoryKeychain: KeychainBackend {
        private var store: [String: Data] = [:]
        private func key(_ s: String, _ a: String) -> String { "\(s)|\(a)" }
        func read(service: String, account: String) throws -> Data? { store[key(service, account)] }
        func save(_ data: Data, service: String, account: String) throws { store[key(service, account)] = data }
        func delete(service: String, account: String) throws { store[key(service, account)] = nil }
    }

    // MARK: T4 — config gating + token store

    func testOAuthProvidersAreExactlyTheExpectedSet() {
        XCTAssertEqual(Set(AccountOAuthConfig.oauthProviders), [.gmail, .googleCalendar, .slack, .notion, .todoist])
    }

    func testAppleCalendarIsLocalNotOAuth() {
        XCTAssertTrue(AccountOAuthConfig.isLocal(.appleCalendar))
        XCTAssertFalse(AccountOAuthConfig.isConfigured(.appleCalendar), "EventKit isn't gated on a client id")
        XCTAssertNil(AccountOAuthConfig.config(for: .appleCalendar))
    }

    func testPlaceholderClientIDsAreNotConfigured() {
        // Info.plist ships REPLACE_* placeholders for all account providers.
        for provider in AccountOAuthConfig.oauthProviders {
            XCTAssertFalse(AccountOAuthConfig.isConfigured(provider), "\(provider) should be unconfigured with placeholder id")
        }
    }

    func testAccountTokenStoreRoundTripsAndIsolatesProviders() throws {
        let backend = MemoryKeychain()
        let gmail = AccountTokenStore(provider: .gmail, backend: backend)
        let slack = AccountTokenStore(provider: .slack, backend: backend)
        XCTAssertFalse(gmail.isConnected)
        try gmail.save(OAuthTokenBundle(accessToken: "g", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600), scope: nil))
        XCTAssertTrue(gmail.isConnected)
        XCTAssertFalse(slack.isConnected, "account providers must not share token slots")
        try gmail.clear()
        XCTAssertFalse(gmail.isConnected)
    }

    func testAccountTokenStoreIsolatedFromWearableStore() throws {
        let backend = MemoryKeychain()
        let gmailAccount = AccountTokenStore(provider: .gmail, backend: backend)
        let fitbitWearable = WearableTokenStore(provider: .fitbit, backend: backend)
        try gmailAccount.save(OAuthTokenBundle(accessToken: "a", refreshToken: nil, expiresAt: Date().addingTimeInterval(60), scope: nil))
        XCTAssertFalse(fitbitWearable.isConnected, "account and wearable token namespaces must not collide")
    }

    func testAccountStatusGating() {
        let unconfigured = ConnectorStatus.forAccount(isConfigured: false, isConnected: false, isSyncing: false, lastSync: nil, lastError: nil)
        if case .unavailable = unconfigured {} else { XCTFail("expected .unavailable") }
        let actionable = ConnectorStatus.forAccount(isConfigured: true, isConnected: false, isSyncing: false, lastSync: nil, lastError: nil)
        XCTAssertTrue(actionable.isActionable)
        let connected = ConnectorStatus.forAccount(isConfigured: true, isConnected: true, isSyncing: false, lastSync: Date(), lastError: nil)
        XCTAssertTrue(connected.isConnected)
    }

    func testEventKitStatusReflectsAuthorization() {
        if case .available = ConnectorStatus.forEventKit(authorized: false, denied: false, lastSync: nil) {} else { XCTFail() }
        if case .error = ConnectorStatus.forEventKit(authorized: false, denied: true, lastSync: nil) {} else { XCTFail() }
        XCTAssertTrue(ConnectorStatus.forEventKit(authorized: true, denied: false, lastSync: nil).isConnected)
    }

    // MARK: Authorize URL + callback

    func testAccountAuthorizeURLContainsPKCEAndScopes() {
        let config = AccountOAuthConfig(
            authorizeURL: URL(string: "https://example.com/auth")!,
            tokenURL: URL(string: "https://example.com/token")!,
            clientID: "client123",
            scopes: ["read"],
            redirectURI: "pulseloop://oauth-callback/gmail",
            extraAuthorizeItems: [URLQueryItem(name: "access_type", value: "offline")]
        )
        let pkce = PKCEChallenge(verifier: "verifier")
        let items = URLComponents(url: config.authorizeRequestURL(pkce: pkce, state: "s1"), resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("client_id"), "client123")
        XCTAssertEqual(value("code_challenge"), pkce.challenge)
        XCTAssertEqual(value("state"), "s1")
        XCTAssertEqual(value("scope"), "read")
        XCTAssertEqual(value("access_type"), "offline")
    }

    @MainActor
    func testAccountCallbackParsing() throws {
        let auth = AccountOAuthAuthenticator(transport: URLSession.shared)
        let (code, state) = try auth.parseCallback(URL(string: "pulseloop://oauth-callback/gmail?code=ABC&state=xyz")!)
        XCTAssertEqual(code, "ABC")
        XCTAssertEqual(state, "xyz")
        XCTAssertThrowsError(try auth.parseCallback(URL(string: "pulseloop://oauth-callback/gmail?error=access_denied")!))
    }

    // MARK: T5 — Google Calendar + Gmail parsers

    func testGoogleCalendarParseEvents() {
        let json: [String: Any] = ["items": [
            ["id": "e1", "summary": "Standup", "start": ["dateTime": "2026-06-25T09:30:00Z"], "end": ["dateTime": "2026-06-25T10:00:00Z"]],
            ["id": "e2", "summary": "Holiday", "start": ["date": "2026-06-26"], "end": ["date": "2026-06-27"]],
        ]]
        let events = GoogleCalendarDataSource.parseEvents(json)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.title, "Standup")
        XCTAssertFalse(events.first?.isAllDay ?? true)
        XCTAssertTrue(events.last?.isAllDay ?? false)
    }

    func testGmailParseMessageIDsAndMessage() {
        XCTAssertEqual(GmailDataSource.parseMessageIDs(["messages": [["id": "m1"], ["id": "m2"]]]), ["m1", "m2"])
        let detail: [String: Any] = [
            "id": "m1",
            "snippet": "Your electric bill is due",
            "internalDate": "1750000000000",
            "payload": ["headers": [
                ["name": "Subject", "value": "Electric bill"],
                ["name": "From", "value": "billing@utility.com"],
            ]],
        ]
        let message = GmailDataSource.parseMessage(detail)
        XCTAssertEqual(message?.title, "Electric bill")
        XCTAssertEqual(message?.from, "billing@utility.com")
        XCTAssertEqual(message?.snippet, "Your electric bill is due")
    }

    // MARK: T6 — Slack / Notion / Todoist parsers

    func testSlackParseMessages() {
        let json: [String: Any] = ["messages": ["matches": [
            ["iid": "s1", "text": "can you review the deck?", "username": "maya", "channel": ["name": "launch"], "ts": "1750000000.0001"],
        ]]]
        let messages = SlackDataSource.parseMessages(json)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.title, "#launch")
        XCTAssertEqual(messages.first?.from, "maya")
    }

    func testNotionParseTasks() {
        let json: [String: Any] = ["results": [[
            "id": "p1",
            "properties": [
                "Name": ["type": "title", "title": [["plain_text": "Write spec"]]],
                "Done": ["type": "checkbox", "checkbox": false],
                "Due": ["type": "date", "date": ["start": "2026-06-30"]],
            ],
        ]]]
        let tasks = NotionDataSource.parseTasks(json)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.title, "Write spec")
        XCTAssertFalse(tasks.first?.isCompleted ?? true)
        XCTAssertNotNil(tasks.first?.due)
    }

    func testTodoistParseTasks() {
        let items: [[String: Any]] = [
            ["id": "t1", "content": "Buy milk", "is_completed": false, "due": ["date": "2026-06-28"]],
            ["id": "t2", "content": "Done thing", "is_completed": true],
        ]
        let tasks = TodoistDataSource.parseTasks(items)
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks.first?.title, "Buy milk")
        XCTAssertNotNil(tasks.first?.due)
        XCTAssertTrue(tasks.last?.isCompleted ?? false)
    }

    // MARK: T5/T6 — ingestion mappers

    @MainActor
    func testUpsertEventInboxIsIdempotent() throws {
        let context = try TestSupport.makeContext()
        let event = RemoteCalendarEvent(id: "e1", title: "Standup", start: Date(), end: nil, location: nil, isAllDay: false)
        AccountConnectionManager.upsertEventInbox(event, provider: .googleCalendar, context: context)
        AccountConnectionManager.upsertEventInbox(event, provider: .googleCalendar, context: context)
        let items = try context.fetch(FetchDescriptor<InboxItem>())
        XCTAssertEqual(items.count, 1, "re-syncing the same event must not duplicate")
        XCTAssertEqual(items.first?.source, .calendar)
        XCTAssertEqual(items.first?.actionType, .addToCalendar)
    }

    @MainActor
    func testUpsertMessageInboxRoutesBySource() throws {
        let context = try TestSupport.makeContext()
        let msg = RemoteMessage(id: "m1", title: "Bill", snippet: "due soon", from: "x", receivedAt: Date())
        AccountConnectionManager.upsertMessageInbox(msg, provider: .gmail, context: context)
        let items = try context.fetch(FetchDescriptor<InboxItem>())
        XCTAssertEqual(items.first?.source, .gmail)
        XCTAssertEqual(items.first?.icon, "envelope")
    }

    @MainActor
    func testUpsertTaskCreatesThenUpdatesSameRow() throws {
        let context = try TestSupport.makeContext()
        AccountConnectionManager.upsertTask(RemoteTask(id: "t1", title: "Old", due: nil, isCompleted: false), provider: .todoist, context: context)
        AccountConnectionManager.upsertTask(RemoteTask(id: "t1", title: "New", due: nil, isCompleted: true), provider: .todoist, context: context)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.count, 1, "same external id must upsert one row")
        XCTAssertEqual(tasks.first?.title, "New")
        XCTAssertEqual(tasks.first?.status, .done)
        XCTAssertEqual(tasks.first?.label, "todoist#t1")
    }

    // MARK: T8 — sync coordinator never throws on empty/unconnected state

    @MainActor
    func testSyncCoordinatorWithNothingConnectedSucceedsZero() async throws {
        let context = try TestSupport.makeContext()
        let count = await ConnectedSourcesSyncCoordinator.syncAll(context: context)
        XCTAssertEqual(count, 0, "nothing connected → zero synced, no crash")
    }
}
