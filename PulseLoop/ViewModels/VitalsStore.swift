import Foundation
import SwiftData

/// Owns the prepared state for `VitalsView`. Previously `body` ran `buildTodaySummary` plus five
/// `metricRange` queries on every render (six aggregations per frame). This store computes them
/// once and reuses the result, rebuilding only when a cheap data-signature changes.
@MainActor
@Observable
final class VitalsStore {
    nonisolated deinit {}   // skip the main-actor isolated-deinit hop (crashes on older sim runtimes)

    private(set) var summary: TodaySummary
    private(set) var hrSamples: [MetricSample]
    private(set) var spo2Samples: [MetricSample]
    private(set) var stressSamples: [MetricSample]
    private(set) var hrvSamples: [MetricSample]
    private(set) var tempSamples: [MetricSample]
    private(set) var capabilities: Set<WearableCapability>

    private let modelContext: ModelContext
    private var signature: String = ""

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.summary = MetricsService.buildTodaySummary(context: modelContext)
        self.hrSamples = MetricsService.metricRange(metric: .heartRate, range: .twentyFourHours, context: modelContext)
        self.spo2Samples = MetricsService.metricRange(metric: .spo2, range: .twentyFourHours, context: modelContext)
        self.stressSamples = MetricsService.metricRange(metric: .stress, range: .twentyFourHours, context: modelContext)
        self.hrvSamples = MetricsService.metricRange(metric: .hrv, range: .twentyFourHours, context: modelContext)
        self.tempSamples = MetricsService.metricRange(metric: .temperature, range: .twentyFourHours, context: modelContext)
        self.capabilities = MetricsService.deviceCapabilities(modelContext)
        self.signature = Self.currentSignature(context: modelContext)
    }

    func refreshIfNeeded() {
        let sig = Self.currentSignature(context: modelContext)
        guard sig != signature else { return }
        rebuild(signature: sig)
    }

    func invalidate() {
        rebuild(signature: Self.currentSignature(context: modelContext))
    }

    private func rebuild(signature sig: String) {
        summary = MetricsService.buildTodaySummary(context: modelContext)
        hrSamples = MetricsService.metricRange(metric: .heartRate, range: .twentyFourHours, context: modelContext)
        spo2Samples = MetricsService.metricRange(metric: .spo2, range: .twentyFourHours, context: modelContext)
        stressSamples = MetricsService.metricRange(metric: .stress, range: .twentyFourHours, context: modelContext)
        hrvSamples = MetricsService.metricRange(metric: .hrv, range: .twentyFourHours, context: modelContext)
        tempSamples = MetricsService.metricRange(metric: .temperature, range: .twentyFourHours, context: modelContext)
        capabilities = MetricsService.deviceCapabilities(modelContext)
        signature = sig
    }

    /// Cheap fingerprint of the latest reading of every vitals metric + device state. A change here
    /// means at least one chart/value changed, so we rebuild; otherwise we skip the six aggregations.
    private static func currentSignature(context: ModelContext) -> String {
        func latest(_ kind: MeasurementKind) -> String {
            guard let m = MetricsRepository.latestMeasurement(kind: kind, context: context) else { return "·" }
            return "\(Int(m.value))@\(Int(m.timestamp.timeIntervalSince1970))"
        }
        let device = DeviceRepository.current(context: context)
        return [
            latest(.heartRate), latest(.spo2), latest(.stress), latest(.hrv), latest(.temperature),
            device.map { "\($0.batteryPercent)/\($0.state.rawValue)" } ?? "·",
        ].joined(separator: "|")
    }
}
