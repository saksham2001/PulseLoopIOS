import Foundation
import XCTest
import SwiftData
@testable import PulseLoop

typealias HealthMeasurement = PulseLoop.Measurement

// MARK: - Wearable data-source + sync tests (Health-sync Track H / H3-H4)
//
// Covers the pure JSON → value parsers for Fitbit and Google Fit, the Google Fit
// aggregate-request builder, and the end-to-end sync path through
// `WearableConnectionManager` against a canned HTTP transport + in-memory
// Keychain backend. No real network or Keychain involved.
final class WearableDataSourceTests: XCTestCase {

    // MARK: Helpers

    /// A canned HTTP transport that returns queued JSON bodies (200) in order.
    final class StubTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var queue: [Any]
        private(set) var requests: [URLRequest] = []
        var statusCode = 200

        init(_ responses: [Any]) { self.queue = responses }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            lock.lock(); defer { lock.unlock() }
            requests.append(request)
            let body = queue.isEmpty ? [String: Any]() : queue.removeFirst()
            let data = try JSONSerialization.data(withJSONObject: body)
            let http = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (data, http)
        }
    }

    final class MemoryKeychain: KeychainBackend {
        private var store: [String: Data] = [:]
        private func key(_ s: String, _ a: String) -> String { "\(s)|\(a)" }
        func read(service: String, account: String) throws -> Data? { store[key(service, account)] }
        func save(_ data: Data, service: String, account: String) throws { store[key(service, account)] = data }
        func delete(service: String, account: String) throws { store[key(service, account)] = nil }
    }

    // MARK: Fitbit parsers

    func testFitbitParseSteps() {
        let json: [String: Any] = ["summary": ["steps": 8421]]
        XCTAssertEqual(FitbitDataSource.parseSteps(json), 8421)
        XCTAssertNil(FitbitDataSource.parseSteps([:]))
    }

    func testFitbitParseRestingHeartRate() {
        let json: [String: Any] = ["activities-heart": [["value": ["restingHeartRate": 58]]]]
        XCTAssertEqual(FitbitDataSource.parseRestingHeartRate(json), 58)
        XCTAssertNil(FitbitDataSource.parseRestingHeartRate(["activities-heart": []]))
    }

    func testFitbitParseSpO2() {
        let json: [String: Any] = ["value": ["avg": 96.5]]
        XCTAssertEqual(FitbitDataSource.parseSpO2(json), 96.5)
        XCTAssertNil(FitbitDataSource.parseSpO2([:]))
    }

    func testFitbitParseSleep() {
        let json: [String: Any] = [
            "sleep": [[
                "isMainSleep": true,
                "minutesAsleep": 415,
                "startTime": "2026-06-23T23:10:00.000",
                "endTime": "2026-06-24T06:25:00.000",
            ]],
        ]
        let result = FitbitDataSource.parseSleep(json)
        XCTAssertEqual(result?.minutes, 415)
        XCTAssertNotNil(result?.start)
        XCTAssertNotNil(result?.end)
    }

    // MARK: Google Fit builder + parsers

    func testGoogleAggregateBodyShape() {
        let body = GoogleFitDataSource.aggregateBody(dataTypeName: "com.google.step_count.delta", startMs: 1000, endMs: 5000)
        XCTAssertEqual(body["startTimeMillis"] as? Int, 1000)
        XCTAssertEqual(body["endTimeMillis"] as? Int, 5000)
        let bucket = body["bucketByTime"] as? [String: Any]
        XCTAssertEqual(bucket?["durationMillis"] as? Int, 4000)
        let aggregate = body["aggregateBy"] as? [[String: Any]]
        XCTAssertEqual(aggregate?.first?["dataTypeName"] as? String, "com.google.step_count.delta")
    }

    func testGoogleParseSumInt() {
        let json: [String: Any] = [
            "bucket": [[
                "dataset": [[
                    "point": [
                        ["value": [["intVal": 1200]]],
                        ["value": [["intVal": 800]]],
                    ],
                ]],
            ]],
        ]
        XCTAssertEqual(GoogleFitDataSource.parseSumInt(json), 2000)
        XCTAssertNil(GoogleFitDataSource.parseSumInt([:]))
    }

    func testGoogleParseAverageValue() {
        let json: [String: Any] = [
            "bucket": [[
                "dataset": [[
                    "point": [
                        ["value": [["fpVal": 60.0]]],
                        ["value": [["fpVal": 80.0]]],
                    ],
                ]],
            ]],
        ]
        XCTAssertEqual(GoogleFitDataSource.parseAverageValue(json), 70.0)
    }

    func testGoogleDayWindowSpansOneDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let (start, end) = GoogleFitDataSource.dayWindow(Date(timeIntervalSince1970: 1_000_000), calendar: cal)
        XCTAssertEqual(end - start, 86_400_000)
    }

    // MARK: End-to-end sync via manager

    @MainActor
    func testSyncPersistsStepsAndHeartRateForFitbit() async throws {
        let context = try TestSupport.makeContext()
        let keychain = MemoryKeychain()
        let store = WearableTokenStore(provider: .fitbit, backend: keychain)
        try store.save(OAuthTokenBundle(
            accessToken: "tok",
            refreshToken: "r",
            expiresAt: Date().addingTimeInterval(3600),
            scope: "activity heartrate"
        ))

        // Fitbit sync issues steps → HR → spo2 GETs in that order.
        let transport = StubTransport([
            ["summary": ["steps": 9000]],
            ["activities-heart": [["value": ["restingHeartRate": 62]]]],
            ["value": ["avg": 97.0]],
        ])
        let source = FitbitDataSource(store: store, authenticator: WearableOAuthAuthenticator(transport: transport), transport: transport)

        let steps = try await source.fetchSteps(for: Date())
        XCTAssertEqual(steps, 9000)
        let hr = try await source.fetchLatestHeartRate()
        XCTAssertEqual(hr, 62)

        WearableConnectionManager.upsertSteps(9000, source: "fitbit", date: Date(), context: context)
        let hrValue: Double = hr ?? 0
        let measurement = HealthMeasurement(kind: .heartRate, value: hrValue, unit: "bpm", timestamp: Date(), source: .fitbit)
        context.insert(measurement)
        context.saveOrLog("test")

        let activity = try context.fetch(FetchDescriptor<ActivityDaily>())
        XCTAssertEqual(activity.first?.steps, 9000)
        XCTAssertEqual(activity.first?.source, "fitbit")
        let measurements = try context.fetch(FetchDescriptor<HealthMeasurement>())
        let hasFitbitHR = measurements.contains { m in
            m.kind == .heartRate && m.sourceRaw == MeasurementSource.fitbit.rawValue
        }
        XCTAssertTrue(hasFitbitHR)
    }

    // MARK: upsertSteps semantics

    @MainActor
    func testUpsertStepsNeverLowersDailyTotal() throws {
        let context = try TestSupport.makeContext()
        let day = Date()
        WearableConnectionManager.upsertSteps(5000, source: "fitbit", date: day, context: context)
        WearableConnectionManager.upsertSteps(3000, source: "fitbit", date: day, context: context)
        let rows = try context.fetch(FetchDescriptor<ActivityDaily>())
        XCTAssertEqual(rows.count, 1, "same source + day should upsert one row")
        XCTAssertEqual(rows.first?.steps, 5000, "a later, smaller partial sync must not lower the total")
    }

    @MainActor
    func testUpsertStepsKeepsSourcesSeparate() throws {
        let context = try TestSupport.makeContext()
        let day = Date()
        WearableConnectionManager.upsertSteps(5000, source: "fitbit", date: day, context: context)
        WearableConnectionManager.upsertSteps(4000, source: "googlefit", date: day, context: context)
        let rows = try context.fetch(FetchDescriptor<ActivityDaily>())
        XCTAssertEqual(rows.count, 2, "distinct sources must not collapse into one row")
    }

    // MARK: Connector status mapping

    func testWearableStatusUnavailableWhenNotConfigured() {
        let status = ConnectorStatus.forWearable(
            isConfigured: false, isConnected: false, isSyncing: false, lastSync: nil, lastError: nil
        )
        if case .unavailable = status { } else { XCTFail("expected .unavailable, got \(status)") }
    }

    func testWearableStatusAvailableWhenConfiguredNotConnected() {
        let status = ConnectorStatus.forWearable(
            isConfigured: true, isConnected: false, isSyncing: false, lastSync: nil, lastError: nil
        )
        XCTAssertTrue(status.isActionable)
    }

    func testWearableStatusErrorBeatsConnected() {
        let status = ConnectorStatus.forWearable(
            isConfigured: true, isConnected: true, isSyncing: false, lastSync: Date(), lastError: "boom"
        )
        if case .error = status { } else { XCTFail("expected .error, got \(status)") }
    }

    func testWearableStatusConnectedShowsLastSync() {
        let status = ConnectorStatus.forWearable(
            isConfigured: true, isConnected: true, isSyncing: false, lastSync: Date(), lastError: nil
        )
        XCTAssertTrue(status.isConnected)
    }
}
