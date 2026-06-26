import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

// MARK: - Diagnostics & content-free telemetry (roadmap F1)
//
// Privacy-first observability with **no third-party SDK**:
//   - Crash / hang / disk-write diagnostics come from Apple's MetricKit, which
//     delivers payloads on-device. We log them via `AppLog` (and could forward to
//     the backend later) — never any user content.
//   - Usage telemetry is a thin seam (`Telemetry`) that records event *names* and
//     a small set of non-PII string parameters only. The default implementation
//     just logs; a network sink can be added behind the same protocol.
//
// Everything is gated behind an explicit, revocable opt-in
// (`DiagnosticsConsent.isEnabled`). When off, nothing is collected or emitted.

/// Explicit, revocable opt-in for diagnostics + anonymous usage telemetry.
enum DiagnosticsConsent {
    private static let key = "pulseloop.diagnostics.consent.v1"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Telemetry seam

/// A named app event with optional non-PII parameters. Keep names stable and
/// low-cardinality (e.g. `coach_turn_started`, `export_local`); parameters must
/// never include user content, free text, health values, identifiers, etc.
struct TelemetryEvent {
    let name: String
    let parameters: [String: String]

    init(_ name: String, parameters: [String: String] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

/// Sink for usage telemetry. Implementations must respect `DiagnosticsConsent`.
protocol Telemetry: AnyObject {
    func track(_ event: TelemetryEvent)
}

/// Default content-free sink: logs event names/params via `AppLog` only when the
/// user has opted in. No network, no storage, no PII — a seam a hosted analytics
/// backend can later replace without touching call sites.
final class LoggingTelemetry: Telemetry {
    static let shared = LoggingTelemetry()

    func track(_ event: TelemetryEvent) {
        guard DiagnosticsConsent.isEnabled else { return }
        if event.parameters.isEmpty {
            AppLog.ui.info("📊 event=\(event.name, privacy: .public)")
        } else {
            let params = event.parameters
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            AppLog.ui.info("📊 event=\(event.name, privacy: .public) \(params, privacy: .public)")
        }
    }
}

/// Global, swappable telemetry entry point. Call `Analytics.track(...)` from
/// anywhere; it routes to the current sink and is a no-op without consent.
enum Analytics {
    static var sink: Telemetry = LoggingTelemetry.shared

    static func track(_ name: String, _ parameters: [String: String] = [:]) {
        sink.track(TelemetryEvent(name, parameters: parameters))
    }
}

// MARK: - MetricKit diagnostics

/// Subscribes to MetricKit so crash/hang/disk diagnostics surface in logs (and,
/// later, can be forwarded to the backend). Content-free and opt-in. Retain the
/// shared instance for the app's lifetime.
final class DiagnosticsService: NSObject {
    static let shared = DiagnosticsService()

    private var started = false

    /// Begins receiving MetricKit payloads if the user has opted in. Idempotent;
    /// safe to call on every launch and after the consent toggle flips on.
    func startIfEnabled() {
        guard DiagnosticsConsent.isEnabled else { return }
        #if canImport(MetricKit) && !targetEnvironment(simulator)
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
        AppLog.ui.info("Diagnostics: MetricKit subscriber started.")
        #endif
    }

    /// Stops receiving payloads (e.g. when the user revokes consent).
    func stop() {
        #if canImport(MetricKit) && !targetEnvironment(simulator)
        guard started else { return }
        started = false
        MXMetricManager.shared.remove(self)
        AppLog.ui.info("Diagnostics: MetricKit subscriber stopped.")
        #endif
    }
}

#if canImport(MetricKit) && !targetEnvironment(simulator)
extension DiagnosticsService: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        guard DiagnosticsConsent.isEnabled else { return }
        for payload in payloads {
            AppLog.ui.info("MetricKit metrics payload received (\(payload.latestApplicationVersion, privacy: .public)).")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard DiagnosticsConsent.isEnabled else { return }
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let cpuExceptions = payload.cpuExceptionDiagnostics?.count ?? 0
            let diskWrites = payload.diskWriteExceptionDiagnostics?.count ?? 0
            AppLog.ui.error(
                "MetricKit diagnostics: crashes=\(crashes, privacy: .public) hangs=\(hangs, privacy: .public) cpu=\(cpuExceptions, privacy: .public) disk=\(diskWrites, privacy: .public)"
            )
        }
    }
}
#endif
