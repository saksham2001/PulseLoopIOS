import Foundation
import XCTest
@testable import PulseLoop

// MARK: - ConnectorStatus mapping tests (Experience loop Track C / C6)
//
// Verifies that each connector's real service state maps into an HONEST
// `ConnectorStatus`, and that the presentation invariants hold (connected ⇒ green,
// unavailable ⇒ never actionable / never "connected", etc.). The core guardrail of
// Track C is that the UI never claims a connection that isn't real, so these tests
// pin the mapping rules.
final class ConnectorStatusTests: XCTestCase {

    // MARK: HealthKit

    func testHealthKitUnavailableMapsToUnavailable() {
        let status = ConnectorStatus.forHealthKit(.unavailable)
        guard case .unavailable = status else {
            return XCTFail("HealthKit .unavailable should map to .unavailable, got \(status)")
        }
        XCTAssertFalse(status.isConnected)
        XCTAssertFalse(status.isActionable)
    }

    func testHealthKitNotAuthorizedIsActionable() {
        let status = ConnectorStatus.forHealthKit(.notAuthorized)
        XCTAssertTrue(status.isActionable, "Not-authorized HealthKit should offer an action")
        XCTAssertFalse(status.isConnected)
    }

    func testHealthKitAuthorizedWithoutSyncIsConnected() {
        let status = ConnectorStatus.forHealthKit(.authorized)
        guard case .connected = status else {
            return XCTFail("Authorized HealthKit (no last-sync) should be .connected, got \(status)")
        }
        XCTAssertTrue(status.isConnected)
    }

    func testHealthKitAuthorizedWithSyncShowsLastSynced() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let status = ConnectorStatus.forHealthKit(.authorized, lastSync: date)
        guard case .lastSynced(let d) = status else {
            return XCTFail("Authorized + last-sync should be .lastSynced, got \(status)")
        }
        XCTAssertEqual(d, date)
        XCTAssertTrue(status.isConnected)
    }

    // MARK: Ring BLE

    func testRingBluetoothOffIsUnavailable() {
        let status = ConnectorStatus.forRing(state: .idle, bluetoothReady: false, batteryPercent: nil, lastError: nil)
        guard case .unavailable = status else {
            return XCTFail("Bluetooth off should be .unavailable, got \(status)")
        }
        XCTAssertFalse(status.isActionable)
    }

    func testRingIdleWithBluetoothIsActionable() {
        let status = ConnectorStatus.forRing(state: .idle, bluetoothReady: true, batteryPercent: nil, lastError: nil)
        XCTAssertTrue(status.isActionable, "Idle + bluetooth ready should offer Scan")
    }

    func testRingScanningIsWorkingNotConnected() {
        let status = ConnectorStatus.forRing(state: .scanning, bluetoothReady: true, batteryPercent: nil, lastError: nil)
        guard case .working = status else {
            return XCTFail("Scanning should be .working, got \(status)")
        }
        XCTAssertFalse(status.isConnected)
        XCTAssertFalse(status.isActionable)
    }

    func testRingConnectedSurfacesBattery() {
        let status = ConnectorStatus.forRing(state: .connected, bluetoothReady: true, batteryPercent: 82, lastError: nil)
        guard case .connected(let detail) = status else {
            return XCTFail("Connected ring should be .connected, got \(status)")
        }
        XCTAssertEqual(detail, "Battery 82%")
        XCTAssertTrue(status.isConnected)
    }

    func testRingFailedSurfacesError() {
        let status = ConnectorStatus.forRing(state: .failed, bluetoothReady: true, batteryPercent: nil, lastError: "Boom")
        guard case .error(let reason) = status else {
            return XCTFail("Failed ring should be .error, got \(status)")
        }
        XCTAssertEqual(reason, "Boom")
        XCTAssertFalse(status.isConnected)
    }

    // MARK: Cloud sync / web pairing

    func testCloudNotConfiguredIsUnavailable() {
        let status = ConnectorStatus.forCloudSync(isConfigured: false, hasConsent: true, isPaired: true, lastSync: Date())
        guard case .unavailable = status else {
            return XCTFail("Unconfigured cloud sync should be .unavailable, got \(status)")
        }
    }

    func testCloudConfiguredButNotPairedIsActionable() {
        let status = ConnectorStatus.forCloudSync(isConfigured: true, hasConsent: false, isPaired: false, lastSync: nil)
        XCTAssertTrue(status.isActionable, "Configured but unpaired should offer Connect")
        XCTAssertFalse(status.isConnected)
    }

    func testCloudPairedWithConsentAndSyncShowsLastSynced() {
        let date = Date(timeIntervalSince1970: 2_000_000)
        let status = ConnectorStatus.forCloudSync(isConfigured: true, hasConsent: true, isPaired: true, lastSync: date)
        guard case .lastSynced(let d) = status else {
            return XCTFail("Paired + consent + last-sync should be .lastSynced, got \(status)")
        }
        XCTAssertEqual(d, date)
        XCTAssertTrue(status.isConnected)
    }

    func testCloudPairedConsentNoSyncIsConnected() {
        let status = ConnectorStatus.forCloudSync(isConfigured: true, hasConsent: true, isPaired: true, lastSync: nil)
        XCTAssertTrue(status.isConnected)
    }

    // MARK: Presentation invariants

    func testUnavailableIsNeverConnectedOrActionable() {
        let status = ConnectorStatus.unavailable(reason: "Not yet available")
        XCTAssertFalse(status.isConnected)
        XCTAssertFalse(status.isActionable)
        XCTAssertEqual(status.detail, "Not yet available")
    }

    func testConnectedStatesAreNeverActionable() {
        let connected: [ConnectorStatus] = [
            .connected(detail: nil),
            .lastSynced(Date())
        ]
        for status in connected {
            XCTAssertTrue(status.isConnected)
            XCTAssertFalse(status.isActionable, "A connected state must not also be actionable")
        }
    }
}
