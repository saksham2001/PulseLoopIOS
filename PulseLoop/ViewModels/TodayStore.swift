import Foundation
import SwiftData

/// Owns the prepared state for `TodayView` so the SwiftUI `body` is a cheap projection rather than
/// a query engine. `MetricsService.buildTodaySummary` is expensive (it aggregates the day's metrics);
/// previously it ran on every `body` evaluation. This store computes it once and reuses the result,
/// rebuilding only when a cheap data-signature changes (or when explicitly invalidated).
///
/// Refresh is driven from the view's `.task`; a cheap signature short-circuits no-op rebuilds. Phase F
/// will additionally invalidate this from the coalesced "today data changed" sync signal.
@MainActor
@Observable
final class TodayStore {
    nonisolated deinit {}   // skip the main-actor isolated-deinit hop (crashes on older sim runtimes)

    /// The cached dashboard summary + its cheap derivations, recomputed together.
    private(set) var summary: TodaySummary
    private(set) var hero: TodayInsights.Hero
    private(set) var capabilities: Set<WearableCapability>

    private let modelContext: ModelContext
    /// Signature of the inputs behind the current `summary`; a mismatch triggers a rebuild.
    private var signature: String = ""

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let built = MetricsService.buildTodaySummary(context: modelContext)
        self.summary = built
        self.hero = TodayInsights.deriveHero(built)
        self.capabilities = MetricsService.deviceCapabilities(modelContext)
        self.signature = Self.currentSignature(context: modelContext)
    }

    /// Rebuild only if the underlying data changed since the last build. Cheap to call every appear.
    func refreshIfNeeded() {
        let sig = Self.currentSignature(context: modelContext)
        guard sig != signature else { return }
        rebuild(signature: sig)
    }

    /// Force a rebuild regardless of signature (used by the coalesced sync-changed signal in Phase F).
    func invalidate() {
        rebuild(signature: Self.currentSignature(context: modelContext))
    }

    private func rebuild(signature sig: String) {
        let built = MetricsService.buildTodaySummary(context: modelContext)
        summary = built
        hero = TodayInsights.deriveHero(built)
        capabilities = MetricsService.deviceCapabilities(modelContext)
        signature = sig
    }

    /// A cheap fingerprint of everything that can change the Today dashboard, assembled from
    /// `fetchLimit:1`-style probes rather than a full summary build. If this is unchanged, the
    /// summary is unchanged, so we skip the expensive rebuild.
    private static func currentSignature(context: ModelContext) -> String {
        let hr = MetricsRepository.latestMeasurement(kind: .heartRate, context: context)
        let spo2 = MetricsRepository.latestMeasurement(kind: .spo2, context: context)
        let activity = MetricsRepository.latestActivity(context: context)
        let sleep = SleepRepository.latestSession(context: context)
        let device = DeviceRepository.current(context: context)

        func stamp(_ date: Date?) -> String { date.map { String(Int($0.timeIntervalSince1970)) } ?? "·" }

        return [
            hr.map { "\(Int($0.value))@\(stamp($0.timestamp))" } ?? "·",
            spo2.map { "\(Int($0.value))@\(stamp($0.timestamp))" } ?? "·",
            activity.map { "\($0.steps)/\(Int($0.distanceMeters))/\($0.activeMinutes)@\(stamp($0.syncedAt))" } ?? "·",
            sleep.map { "\($0.totalMinutes)@\(stamp($0.syncedAt))" } ?? "·",
            device.map { "\($0.batteryPercent)/\($0.state.rawValue)@\(stamp($0.lastSyncAt))" } ?? "·",
        ].joined(separator: "|")
    }
}
