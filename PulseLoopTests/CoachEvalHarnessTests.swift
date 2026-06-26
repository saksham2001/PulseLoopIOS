import Foundation
import XCTest
@testable import PulseLoop

// MARK: - Deterministic eval harness tests (Life OS T6)
//
// Exercises the network-free `CoachEvalHarness`: routing classifies turns to the
// right specialist, and the parse + boundary-guard pipeline yields a response that
// satisfies the rendered invariants (no em dashes, chart only on the chart type,
// a non-empty summary). Same input → same result, so these never flake.

@MainActor
final class CoachEvalHarnessTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Pin routing on so routing cases are deterministic regardless of stored prefs.
        UserDefaults.standard.set(true, forKey: AgentRouter.routingEnabledKey)
    }

    func testAllDefaultEvalsPass() {
        let results = CoachEvalHarness.runAll()
        XCTAssertFalse(results.isEmpty)
        let failed = results.filter { !$0.passed }
        XCTAssertTrue(failed.isEmpty,
                      "Eval failures:\n" + failed.map { "• \($0.name): \($0.failures.joined(separator: "; "))" }.joined(separator: "\n"))
    }

    func testRoutingCasesClassifyCorrectly() {
        for c in CoachEvalHarness.routingCases {
            let result = CoachEvalHarness.run(c)
            XCTAssertTrue(result.passed, "\(c.name): \(result.failures.joined(separator: "; "))")
        }
    }

    func testEmDashAlwaysStripped() {
        let r = CoachEvalHarness.shaped(#"{"response_type":"insight","title":"A — B","summary":"x — y"}"#)
        XCTAssertFalse(r.title.contains("—"))
        XCTAssertFalse(r.summary.contains("—"))
    }

    func testStrayChartDroppedButKeptOnChartType() {
        let dropped = CoachEvalHarness.shaped(#"{"response_type":"insight","title":"t","summary":"s","chart":{"chart_type":"line","title":"c","metric":"hr","range":{"start":"a","end":"b"},"data":[]}}"#)
        XCTAssertNil(dropped.chart, "A chart on a plain insight must be dropped.")

        let kept = CoachEvalHarness.shaped(#"{"response_type":"insight_with_chart","title":"t","summary":"s","chart":{"chart_type":"line","title":"c","metric":"steps","range":{"start":"a","end":"b"},"data":[{"x":"1","y":1}]}}"#)
        XCTAssertNotNil(kept.chart, "A chart on insight_with_chart must be kept.")
    }

    func testProseFallbackBecomesSummary() {
        let r = CoachEvalHarness.shaped("just some prose, no json here")
        XCTAssertEqual(r.summary, "just some prose, no json here")
    }

    /// A failing assertion is reported (not silently swallowed) so the dashboard
    /// can surface regressions.
    func testFailingAssertionIsReported() {
        let badCase = ShapeEvalCase(
            "summary missing",
            rawModelOutput: #"{"response_type":"insight","title":"t","summary":""}"#,
            assertions: [.hasSummary]
        )
        let result = CoachEvalHarness.run(badCase)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.failures.count, 1)
    }
}
