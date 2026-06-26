import Foundation
import SwiftData

// MARK: - Coach quality report (Life OS T6)
//
// A PURE aggregation over the T0 signal (TurnTelemetry + CoachFeedback) plus the
// deterministic eval harness, summarized for an at-a-glance quality readout. No
// network, no provider calls — it reads what's already on device and computes
// rates. Used by the Quality dashboard (dev/settings) and by tests.

/// Per-model rollup for the dashboard table.
struct ModelQualityRow: Identifiable, Hashable {
    var id: String { model }
    let model: String
    let displayName: String
    let turns: Int
    let upVotes: Int
    let downVotes: Int
    let recoveredTurns: Int
    let erroredTurns: Int

    var totalVotes: Int { upVotes + downVotes }
    /// 0...1 satisfaction (nil when there are no votes, so the UI can show "—").
    var satisfaction: Double? { totalVotes == 0 ? nil : Double(upVotes) / Double(totalVotes) }
    var recoveryRate: Double { turns == 0 ? 0 : Double(recoveredTurns) / Double(turns) }
    var errorRate: Double { turns == 0 ? 0 : Double(erroredTurns) / Double(turns) }
}

/// The whole report: headline counters, per-model rows, top down-vote reasons, and
/// the eval pass rate.
struct CoachQualityReport {
    var totalTurns: Int = 0
    var totalUp: Int = 0
    var totalDown: Int = 0
    var totalRecovered: Int = 0
    var totalErrored: Int = 0
    var models: [ModelQualityRow] = []
    /// Down-vote reason code → count, highest first.
    var downReasons: [(code: String, label: String, count: Int)] = []
    /// Deterministic eval results (shape + routing).
    var evalResults: [EvalResult] = []

    var totalVotes: Int { totalUp + totalDown }
    var satisfaction: Double? { totalVotes == 0 ? nil : Double(totalUp) / Double(totalVotes) }
    var recoveryRate: Double { totalTurns == 0 ? 0 : Double(totalRecovered) / Double(totalTurns) }
    var errorRate: Double { totalTurns == 0 ? 0 : Double(totalErrored) / Double(totalTurns) }
    var evalPassCount: Int { evalResults.filter { $0.passed }.count }
    var evalPassRate: Double { evalResults.isEmpty ? 1 : Double(evalPassCount) / Double(evalResults.count) }
    var hasSignal: Bool { totalTurns > 0 || totalVotes > 0 }
}

enum CoachQualityReportBuilder {
    /// Build the full report from on-device data. Pure read; never throws (returns a
    /// zeroed report when there's no data). `evalResults` defaults to running the
    /// bundled deterministic harness.
    @MainActor
    static func build(
        in context: ModelContext,
        limit: Int = 500,
        reasonLabels: [String: String] = Dictionary(uniqueKeysWithValues: CoachFeedbackStore.downReasons.map { ($0.code, $0.label) }),
        evalResults: [EvalResult]? = nil
    ) -> CoachQualityReport {
        var report = CoachQualityReport()

        // Telemetry rollup.
        var telemetryDescriptor = FetchDescriptor<TurnTelemetry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        telemetryDescriptor.fetchLimit = limit
        let telemetry = (try? context.fetch(telemetryDescriptor)) ?? []

        var byModel: [String: ModelOutcomeStats] = [:]
        for t in telemetry where !t.model.isEmpty {
            var s = byModel[t.model] ?? ModelOutcomeStats(model: t.model)
            s.turns += 1
            if t.recovered { s.recoveredTurns += 1 }
            if !t.errorReason.isEmpty { s.erroredTurns += 1 }
            byModel[t.model] = s
            report.totalTurns += 1
            if t.recovered { report.totalRecovered += 1 }
            if !t.errorReason.isEmpty { report.totalErrored += 1 }
        }

        // Feedback rollup + down-reason histogram.
        var feedbackDescriptor = FetchDescriptor<CoachFeedback>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        feedbackDescriptor.fetchLimit = limit
        let feedback = (try? context.fetch(feedbackDescriptor)) ?? []

        var reasonCounts: [String: Int] = [:]
        for f in feedback where !f.model.isEmpty {
            var s = byModel[f.model] ?? ModelOutcomeStats(model: f.model)
            if f.rating == CoachFeedbackStore.Rating.up.rawValue {
                s.upVotes += 1; report.totalUp += 1
            } else if f.rating == CoachFeedbackStore.Rating.down.rawValue {
                s.downVotes += 1; report.totalDown += 1
                let code = f.reason.trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty { reasonCounts[code, default: 0] += 1 }
            }
            byModel[f.model] = s
        }

        report.models = byModel.values
            .map { stat in
                ModelQualityRow(
                    model: stat.model,
                    displayName: ModelRegistry.displayName(for: stat.model),
                    turns: stat.turns,
                    upVotes: stat.upVotes,
                    downVotes: stat.downVotes,
                    recoveredTurns: stat.recoveredTurns,
                    erroredTurns: stat.erroredTurns
                )
            }
            .sorted { lhs, rhs in
                if lhs.turns != rhs.turns { return lhs.turns > rhs.turns }
                return lhs.model < rhs.model
            }

        report.downReasons = reasonCounts
            .map { (code: $0.key, label: reasonLabels[$0.key] ?? $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        report.evalResults = evalResults ?? CoachEvalHarness.runAll()
        return report
    }
}
