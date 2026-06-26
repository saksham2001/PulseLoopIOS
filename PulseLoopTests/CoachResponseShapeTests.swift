import Foundation
import XCTest
@testable import PulseLoop

// MARK: - Adaptive response-shape tests (Experience loop Track M / M1)
//
// Pins the deterministic shape guard that keeps a chart from being rendered on a
// conversational reply — the "I'm horny must not render a heart-rate card" rule.
final class CoachResponseShapeTests: XCTestCase {

    private func chart() -> CoachChart {
        CoachChart(
            chartType: .line,
            title: "Heart rate",
            metric: .hr,
            range: .init(start: "2026-06-23", end: "2026-06-23"),
            data: [.init(x: "08:00", y: 72, series: nil)],
            annotations: []
        )
    }

    func testConversationalInsightDropsStrayChart() {
        let response = CoachResponse(
            responseType: .insight,
            title: "",
            summary: "Totally normal, want to talk about it or take your mind off things?",
            chart: chart()
        )
        let shaped = response.adaptiveShaped()
        XCTAssertNil(shaped.chart, "An .insight reply must not carry a chart")
        XCTAssertEqual(shaped.summary, response.summary)
    }

    func testInsightWithChartKeepsChart() {
        let response = CoachResponse(
            responseType: .insightWithChart,
            title: "Your heart rate today",
            summary: "Here's your HR across today.",
            chart: chart()
        )
        let shaped = response.adaptiveShaped()
        XCTAssertNotNil(shaped.chart, "An explicit insight_with_chart must keep its chart")
    }

    func testQuestionDropsStrayChart() {
        let response = CoachResponse(
            responseType: .question,
            title: "",
            summary: "Which day did you mean?",
            chart: chart()
        )
        XCTAssertNil(response.adaptiveShaped().chart)
    }

    func testNoChartIsUnchanged() {
        let response = CoachResponse(
            responseType: .insight,
            title: "Hey",
            summary: "Sounds good!"
        )
        XCTAssertEqual(response.adaptiveShaped(), response)
    }

    // MARK: - Em/en dash sanitizing

    func testDeDashSpacedEmDashBecomesComma() {
        XCTAssertEqual(CoachResponse.deDash("Totally normal — want to talk?"),
                       "Totally normal, want to talk?")
        XCTAssertEqual(CoachResponse.deDash("First — second — third"),
                       "First, second, third")
    }

    func testDeDashTightDashBecomesHyphen() {
        XCTAssertEqual(CoachResponse.deDash("evidence—based"), "evidence-based")
        XCTAssertEqual(CoachResponse.deDash("evidence--based"), "evidence-based")
    }

    func testDeDashEnDashHandled() {
        XCTAssertEqual(CoachResponse.deDash("10 – 15 reps"), "10, 15 reps")
        XCTAssertEqual(CoachResponse.deDash("pre–workout"), "pre-workout")
    }

    func testDeDashLeavesCleanTextUnchanged() {
        XCTAssertEqual(CoachResponse.deDash("Just clean text, nothing fancy."),
                       "Just clean text, nothing fancy.")
        XCTAssertEqual(CoachResponse.deDash(""), "")
    }

    func testTextSanitizedStripsAcrossAllFields() {
        let response = CoachResponse(
            responseType: .insight,
            title: "Plan — overview",
            summary: "Here — is the plan.",
            bullets: ["Step one — go", "Step two — stop"],
            safetyNote: "Be careful — really",
            followUpChips: ["Show more — now"],
            actionsTaken: ["Logged — done"]
        )
        let clean = response.textSanitized()
        XCTAssertFalse(clean.title.contains("—"))
        XCTAssertFalse(clean.summary.contains("—"))
        XCTAssertTrue(clean.bullets.allSatisfy { !$0.contains("—") })
        XCTAssertFalse((clean.safetyNote ?? "").contains("—"))
        XCTAssertTrue(clean.followUpChips.allSatisfy { !$0.contains("—") })
        XCTAssertTrue(clean.actionsTaken.allSatisfy { !$0.contains("—") })
    }

    func testAdaptiveShapedAlsoSanitizes() {
        let response = CoachResponse(
            responseType: .insight,
            title: "",
            summary: "A — B"
        )
        XCTAssertEqual(response.adaptiveShaped().summary, "A, B")
    }
}
