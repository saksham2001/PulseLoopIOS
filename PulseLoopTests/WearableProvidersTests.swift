import Foundation
import XCTest
@testable import PulseLoop

// MARK: - Connect loop: new wearable providers (T2/T3)
//
// Pure-logic coverage for the generalized provider model (Oura/Whoop/Garmin
// metadata + config gating) and the new data-source JSON parsers. No network
// or Keychain involved — every parser is `nonisolated static`.
final class WearableProvidersTests: XCTestCase {

    // MARK: T2 — provider metadata + config gating

    func testAllProvidersHaveDistinctActivitySources() {
        let sources = WearableProvider.allCases.map(\.activitySource)
        XCTAssertEqual(Set(sources).count, sources.count, "activity sources must be unique per provider")
    }

    func testNewProvidersHaveMeasurementSources() {
        XCTAssertEqual(WearableProvider.oura.measurementSource, .oura)
        XCTAssertEqual(WearableProvider.whoop.measurementSource, .whoop)
        XCTAssertEqual(WearableProvider.garmin.measurementSource, .garmin)
    }

    func testRedirectURIForNewProviders() {
        XCTAssertEqual(WearableOAuthConfig.redirectURI(for: .oura), "pulseloop://oauth-callback/oura")
        XCTAssertEqual(WearableOAuthConfig.redirectURI(for: .whoop), "pulseloop://oauth-callback/whoop")
        XCTAssertEqual(WearableOAuthConfig.redirectURI(for: .garmin), "pulseloop://oauth-callback/garmin")
    }

    func testGarminFlowIsUnsupportedAndHonest() {
        XCTAssertFalse(WearableOAuthConfig.isFlowSupported(.garmin))
        XCTAssertFalse(WearableOAuthConfig.isConfigured(.garmin), "Garmin must never report configured until a backend exists")
        XCTAssertNotNil(WearableOAuthConfig.unsupportedReason(for: .garmin))
    }

    func testOuraAndWhoopFlowsAreSupported() {
        XCTAssertTrue(WearableOAuthConfig.isFlowSupported(.oura))
        XCTAssertTrue(WearableOAuthConfig.isFlowSupported(.whoop))
        XCTAssertNil(WearableOAuthConfig.unsupportedReason(for: .oura))
        XCTAssertNil(WearableOAuthConfig.unsupportedReason(for: .whoop))
    }

    func testPlaceholderClientIDsAreNotConfigured() {
        // Info.plist ships REPLACE_* placeholders, so none are configured in this build.
        XCTAssertFalse(WearableOAuthConfig.isConfigured(.oura))
        XCTAssertFalse(WearableOAuthConfig.isConfigured(.whoop))
    }

    func testWearableUnsupportedStatusOverridesEverything() {
        let status = ConnectorStatus.forWearable(
            isConfigured: true, isConnected: true, isSyncing: true,
            lastSync: Date(), lastError: nil, unsupportedReason: "Garmin needs a backend."
        )
        if case .unavailable(let reason) = status {
            XCTAssertEqual(reason, "Garmin needs a backend.")
        } else {
            XCTFail("unsupported reason must force .unavailable, got \(status)")
        }
    }

    // MARK: T3 — Oura parsers

    func testOuraParseSteps() {
        let json: [String: Any] = ["data": [["steps": 9123]]]
        XCTAssertEqual(OuraDataSource.parseSteps(json), 9123)
        XCTAssertNil(OuraDataSource.parseSteps(["data": []]))
    }

    func testOuraParseAverageHeartRate() {
        let json: [String: Any] = ["data": [["bpm": 60], ["bpm": 80]]]
        XCTAssertEqual(OuraDataSource.parseAverageHeartRate(json), 70.0)
    }

    func testOuraParseSpO2() {
        let json: [String: Any] = ["data": [["spo2_percentage": ["average": 96.4]]]]
        XCTAssertEqual(OuraDataSource.parseSpO2(json), 96.4)
    }

    func testOuraParseSleep() {
        let json: [String: Any] = [
            "data": [[
                "total_sleep_duration": 27000, // 450 minutes
                "bedtime_start": "2026-06-23T23:00:00+00:00",
                "bedtime_end": "2026-06-24T07:00:00+00:00",
            ]],
        ]
        let result = OuraDataSource.parseSleep(json)
        XCTAssertEqual(result?.minutes, 450)
        XCTAssertNotNil(result?.start)
        XCTAssertNotNil(result?.end)
    }

    // MARK: T3 — Whoop parsers

    func testWhoopParseRestingHeartRate() {
        let json: [String: Any] = ["records": [["score": ["resting_heart_rate": 55]]]]
        XCTAssertEqual(WhoopDataSource.parseRestingHeartRate(json), 55)
        XCTAssertNil(WhoopDataSource.parseRestingHeartRate(["records": []]))
    }

    func testWhoopParseHRV() {
        let json: [String: Any] = ["records": [["score": ["hrv_rmssd_milli": 42.5]]]]
        XCTAssertEqual(WhoopDataSource.parseHRV(json), 42.5)
    }

    func testWhoopParseSleepUsesStageSummary() {
        let json: [String: Any] = [
            "records": [[
                "start": "2026-06-23T23:00:00.000Z",
                "end": "2026-06-24T07:00:00.000Z",
                "score": ["stage_summary": [
                    "total_in_bed_time_milli": 28_800_000, // 480 min in bed
                    "total_awake_time_milli": 1_800_000,    // 30 min awake → 450 asleep
                ]],
            ]],
        ]
        let result = WhoopDataSource.parseSleep(json)
        XCTAssertEqual(result?.minutes, 450)
    }

    func testWhoopHasNoSteps() async throws {
        let source = await WhoopDataSource(
            store: WearableTokenStore(provider: .whoop, backend: MemoryKeychain()),
            authenticator: await WearableOAuthAuthenticator(transport: URLSession.shared)
        )
        let steps = try await source.fetchSteps(for: Date())
        XCTAssertNil(steps, "Whoop does not report steps")
    }

    // MARK: helpers

    final class MemoryKeychain: KeychainBackend {
        private var store: [String: Data] = [:]
        private func key(_ s: String, _ a: String) -> String { "\(s)|\(a)" }
        func read(service: String, account: String) throws -> Data? { store[key(service, account)] }
        func save(_ data: Data, service: String, account: String) throws { store[key(service, account)] = data }
        func delete(service: String, account: String) throws { store[key(service, account)] = nil }
    }
}
