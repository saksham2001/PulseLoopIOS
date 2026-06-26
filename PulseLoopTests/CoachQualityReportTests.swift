import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

// MARK: - Quality report tests (Life OS T6)
//
// The dashboard's pure aggregator: rolls up TurnTelemetry + CoachFeedback into
// per-model rows, headline rates, and a down-reason histogram, and folds in the
// deterministic eval results. Reads only on-device data; never throws.

@MainActor
final class CoachQualityReportTests: XCTestCase {

    private func inMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TurnTelemetry.self, CoachFeedback.self, configurations: config)
        return ModelContext(container)
    }

    private func seedTurn(_ ctx: ModelContext, model: String, recovered: Bool = false, error: String = "") {
        let t = TurnTelemetry(messageId: UUID(), conversationId: UUID(),
                              roleLabel: "Generalist", model: model,
                              recovered: recovered, errorReason: error)
        ctx.insert(t)
    }

    private func seedFeedback(_ ctx: ModelContext, model: String, up: Bool, reason: String = "") {
        let f = CoachFeedback(messageId: UUID(), conversationId: UUID(),
                              rating: up ? "up" : "down", reason: reason,
                              roleLabel: "Generalist", model: model)
        ctx.insert(f)
    }

    func testEmptyReportHasNoSignalButRunsEvals() throws {
        let ctx = try inMemoryContext()
        let report = CoachQualityReportBuilder.build(in: ctx)
        XCTAssertFalse(report.hasSignal)
        XCTAssertEqual(report.totalTurns, 0)
        // Evals still run (and should all pass).
        XCTAssertFalse(report.evalResults.isEmpty)
        XCTAssertEqual(report.evalPassRate, 1.0, accuracy: 0.0001)
    }

    func testRollsUpTurnsAndVotesByModel() throws {
        let ctx = try inMemoryContext()
        seedTurn(ctx, model: "a")
        seedTurn(ctx, model: "a", recovered: true)
        seedTurn(ctx, model: "a", error: "timeout")
        seedTurn(ctx, model: "b")
        seedFeedback(ctx, model: "a", up: true)
        seedFeedback(ctx, model: "a", up: false, reason: "too_long")

        let report = CoachQualityReportBuilder.build(in: ctx)
        XCTAssertTrue(report.hasSignal)
        XCTAssertEqual(report.totalTurns, 4)
        XCTAssertEqual(report.totalUp, 1)
        XCTAssertEqual(report.totalDown, 1)
        XCTAssertEqual(report.totalRecovered, 1)
        XCTAssertEqual(report.totalErrored, 1)

        // Model "a" has the most turns → sorts first.
        let first = try XCTUnwrap(report.models.first)
        XCTAssertEqual(first.model, "a")
        XCTAssertEqual(first.turns, 3)
        XCTAssertEqual(first.upVotes, 1)
        XCTAssertEqual(first.downVotes, 1)
        XCTAssertEqual(first.satisfaction ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(first.errorRate, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(first.recoveryRate, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testDownReasonHistogramRanksByCount() throws {
        let ctx = try inMemoryContext()
        seedFeedback(ctx, model: "a", up: false, reason: "too_long")
        seedFeedback(ctx, model: "a", up: false, reason: "too_long")
        seedFeedback(ctx, model: "b", up: false, reason: "inaccurate")

        let report = CoachQualityReportBuilder.build(in: ctx)
        XCTAssertEqual(report.downReasons.first?.code, "too_long")
        XCTAssertEqual(report.downReasons.first?.count, 2)
        XCTAssertEqual(report.downReasons.first?.label, "Too long")
    }

    func testInjectedEvalResultsAreUsed() throws {
        let ctx = try inMemoryContext()
        let evals = [
            EvalResult(name: "x", passed: true, failures: []),
            EvalResult(name: "y", passed: false, failures: ["boom"]),
        ]
        let report = CoachQualityReportBuilder.build(in: ctx, evalResults: evals)
        XCTAssertEqual(report.evalResults.count, 2)
        XCTAssertEqual(report.evalPassCount, 1)
        XCTAssertEqual(report.evalPassRate, 0.5, accuracy: 0.0001)
    }
}
