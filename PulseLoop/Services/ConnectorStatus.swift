import SwiftUI

// MARK: - ConnectorStatus
//
// A single, honest representation of a data-connector's live state, shared by every
// connector surface (HealthKit, ring BLE, GPS, cloud sync / web pairing, account
// links). The goal (Experience loop Track C) is that the UI NEVER shows a
// "connected"/"synced" state that isn't real: each connector maps its own service
// state into this enum, and the UI renders it uniformly.
//
// Truth table (state of each connector as of C1 — see docs/EXPERIENCE_PROGRESS.md):
//   • HealthKit      REAL — `HealthKitIngestion.authorizationState` + `isAvailable`.
//   • Ring (BLE)     REAL — `RingBLEClient.state` / `isBluetoothReady` / `batteryPercent`.
//   • GPS workouts   REAL — `GpsRouteRecorder` (CoreLocation authorization).
//   • Cloud sync     REAL — `CloudSyncService` (token + consent + lastSyncAt).
//   • Oura/Whoop/Garmin/Gmail/Calendar/etc.  NOT IMPLEMENTED — must render `.unavailable`,
//     never a fake "Paired"/"Connected" badge.

/// Unified, honest status for any data connector.
enum ConnectorStatus: Equatable {
    /// Working and connected. `detail` is an optional short status line
    /// (e.g. "Battery 82%", "Authorized").
    case connected(detail: String?)
    /// Actively connecting / scanning / syncing right now.
    case working(detail: String?)
    /// Available on this device but not yet connected/authorized — the user can act.
    case available(actionTitle: String)
    /// Connected previously; shows when the connector last synced successfully.
    case lastSynced(Date)
    /// Something went wrong; carries a human-readable reason.
    case error(String)
    /// Genuinely not available: not implemented yet, or unsupported on this device.
    /// This is the honest replacement for fake "coming soon connect" toggles.
    case unavailable(reason: String)

    /// Whether this status represents a live, healthy connection.
    var isConnected: Bool {
        switch self {
        case .connected, .lastSynced: return true
        default: return false
        }
    }

    /// Whether the user can take a connect/authorize action from this state.
    var isActionable: Bool {
        if case .available = self { return true }
        return false
    }
}

// MARK: - Presentation

extension ConnectorStatus {
    /// Short label for the status pill.
    var label: String {
        switch self {
        case .connected: return "Connected"
        case .working(let d): return d ?? "Working…"
        case .available(let title): return title
        case .lastSynced(let date): return "Synced \(Self.relative(date))"
        case .error: return "Error"
        case .unavailable: return "Unavailable"
        }
    }

    /// Optional secondary detail line shown under the connector name.
    var detail: String? {
        switch self {
        case .connected(let d): return d
        case .working(let d): return d
        case .available: return nil
        case .lastSynced(let date): return "Last synced \(Self.relative(date))"
        case .error(let reason): return reason
        case .unavailable(let reason): return reason
        }
    }

    var tint: Color {
        switch self {
        case .connected, .lastSynced: return PulseColors.success
        case .working: return PulseColors.warning
        case .available: return PulseColors.accent
        case .error: return PulseColors.alert
        case .unavailable: return PulseColors.textFaint
        }
    }

    var background: Color {
        switch self {
        case .connected, .lastSynced: return PulseColors.successBackground
        case .working: return PulseColors.warningBackground
        case .available: return PulseColors.fillSubtle
        case .error: return PulseColors.alertBackground
        case .unavailable: return PulseColors.fillSubtle
        }
    }

    /// SF Symbol that reads the status at a glance.
    var systemImage: String {
        switch self {
        case .connected, .lastSynced: return "checkmark.circle.fill"
        case .working: return "arrow.triangle.2.circlepath"
        case .available: return "plus.circle"
        case .error: return "exclamationmark.triangle.fill"
        case .unavailable: return "minus.circle"
        }
    }

    private static func relative(_ date: Date) -> String {
        let secs = max(0, Date().timeIntervalSince(date))
        if secs < 60 { return "just now" }
        let mins = Int(secs / 60)
        if mins < 60 { return "\(mins) min ago" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs) hr ago" }
        let days = hrs / 24
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }
}

// MARK: - Mappers (each connector's real state → ConnectorStatus)

extension ConnectorStatus {
    /// Map HealthKit availability + authorization into an honest status.
    static func forHealthKit(_ state: HealthAuthorizationState, lastSync: Date? = nil) -> ConnectorStatus {
        switch state {
        case .unavailable:
            return .unavailable(reason: "Apple Health isn't available on this device.")
        case .notAuthorized:
            return .available(actionTitle: "Allow")
        case .authorized:
            if let lastSync { return .lastSynced(lastSync) }
            return .connected(detail: "Authorized")
        }
    }

    /// Map the ring's BLE connection state into an honest status.
    static func forRing(
        state: RingConnectionState,
        bluetoothReady: Bool,
        batteryPercent: Int?,
        lastError: String?
    ) -> ConnectorStatus {
        if !bluetoothReady {
            return .unavailable(reason: "Bluetooth is off. Turn it on to connect your ring.")
        }
        switch state {
        case .connected:
            if let battery = batteryPercent {
                return .connected(detail: "Battery \(battery)%")
            }
            return .connected(detail: nil)
        case .scanning:
            return .working(detail: "Scanning…")
        case .connecting:
            return .working(detail: "Connecting…")
        case .reconnecting:
            return .working(detail: "Reconnecting…")
        case .failed:
            return .error(lastError ?? "Couldn't connect to the ring.")
        case .idle, .disconnected:
            return .available(actionTitle: "Scan")
        }
    }

    /// Map cloud-sync / web-pairing state into an honest status.
    static func forCloudSync(
        isConfigured: Bool,
        hasConsent: Bool,
        isPaired: Bool,
        lastSync: Date?
    ) -> ConnectorStatus {
        guard isConfigured else {
            return .unavailable(reason: "Web sync isn't configured in this build.")
        }
        guard hasConsent && isPaired else {
            return .available(actionTitle: "Connect")
        }
        if let lastSync { return .lastSynced(lastSync) }
        return .connected(detail: "Paired")
    }

    /// Map a third-party wearable OAuth connector (Fitbit / Google Fit) into an
    /// honest status. `isConfigured` is whether the build ships a client ID for the
    /// provider; without one the row is genuinely unavailable.
    static func forWearable(
        isConfigured: Bool,
        isConnected: Bool,
        isSyncing: Bool,
        lastSync: Date?,
        lastError: String?,
        unsupportedReason: String? = nil
    ) -> ConnectorStatus {
        if let unsupportedReason { return .unavailable(reason: unsupportedReason) }
        guard isConfigured else {
            return .unavailable(reason: "Not configured in this build.")
        }
        if isSyncing { return .working(detail: "Syncing…") }
        if let lastError { return .error(lastError) }
        guard isConnected else {
            return .available(actionTitle: "Connect")
        }
        if let lastSync { return .lastSynced(lastSync) }
        return .connected(detail: "Connected")
    }

    /// Map an OAuth-backed account connector (Gmail, Calendar, Slack, Notion,
    /// Todoist) into an honest status. Same shape as `forWearable` — without a real
    /// client id the row is genuinely unavailable, never a fake "Connect".
    static func forAccount(
        isConfigured: Bool,
        isConnected: Bool,
        isSyncing: Bool,
        lastSync: Date?,
        lastError: String?
    ) -> ConnectorStatus {
        guard isConfigured else {
            return .unavailable(reason: "Not configured in this build.")
        }
        if isSyncing { return .working(detail: "Syncing…") }
        if let lastError { return .error(lastError) }
        guard isConnected else {
            return .available(actionTitle: "Connect")
        }
        if let lastSync { return .lastSynced(lastSync) }
        return .connected(detail: "Connected")
    }

    /// Map Apple Calendar (EventKit, local — no OAuth) into an honest status based
    /// on its authorization state.
    static func forEventKit(authorized: Bool, denied: Bool, lastSync: Date?) -> ConnectorStatus {
        if denied { return .error("Calendar access denied. Enable it in Settings.") }
        guard authorized else { return .available(actionTitle: "Allow") }
        if let lastSync { return .lastSynced(lastSync) }
        return .connected(detail: "Authorized")
    }
}

// MARK: - Reusable status pill

/// Compact pill rendering a `ConnectorStatus` consistently across connector surfaces.
struct ConnectorStatusPill: View {
    let status: ConnectorStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(status.label)
                .font(PulseFont.bodyMedium(12))
        }
        .foregroundStyle(status.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(status.background)
        .clipShape(Capsule())
    }
}
