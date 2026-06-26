import XCTest
import SwiftData
@testable import PulseLoop

@MainActor
final class CoachFeedbackTelemetryTests: XCTestCase {

    // MARK: - Feedback round-trips

    func testFeedbackRecordsThenFetches() throws {
        let ctx = try TestSupport.makeContext()
        let messageId = UUID()
        let convoId = UUID()

        let saved = CoachFeedbackStore.record(
            messageId: messageId, conversationId: convoId, rating: .up, in: ctx)
        XCTAssertEqual(saved.rating, "up")

        let fetched = try XCTUnwrap(CoachFeedbackStore.fetch(messageId: messageId, in: ctx))
        XCTAssertEqual(fetched.rating, "up")
        XCTAssertEqual(fetched.messageId, messageId)
        XCTAssertEqual(fetched.conversationId, convoId)
    }

    func testReRatingUpdatesInPlaceNoDuplicate() throws {
        let ctx = try TestSupport.makeContext()
        let messageId = UUID()
        let convoId = UUID()

        CoachFeedbackStore.record(messageId: messageId, conversationId: convoId, rating: .up, in: ctx)
        CoachFeedbackStore.record(messageId: messageId, conversationId: convoId, rating: .down, reason: "too_long", in: ctx)

        let all = try ctx.fetch(FetchDescriptor<CoachFeedback>())
        XCTAssertEqual(all.count, 1, "Re-rating the same message must not create a duplicate row")
        XCTAssertEqual(all.first?.rating, "down")
        XCTAssertEqual(all.first?.reason, "too_long")
    }

    func testFeedbackSnapshotsRoleAndModelFromTelemetry() throws {
        let ctx = try TestSupport.makeContext()
        let messageId = UUID()
        let convoId = UUID()

        // A decision row exists for this message; feedback should snapshot it.
        ctx.insert(TurnTelemetry(
            messageId: messageId, conversationId: convoId,
            roleLabel: "Researcher", model: "minimax/minimax-m2"))
        try ctx.save()

        let saved = CoachFeedbackStore.record(
            messageId: messageId, conversationId: convoId, rating: .down, reason: "inaccurate", in: ctx)
        XCTAssertEqual(saved.roleLabel, "Researcher")
        XCTAssertEqual(saved.model, "minimax/minimax-m2")
    }

    // MARK: - Telemetry: one row per turn with expected fields

    func testMakeTelemetryCapturesDecisionFields() {
        let trace = [
            CoachToolCallTrace(toolName: "search_web", label: "Searching", status: "success",
                               argsRedacted: "", resultSummary: "", startedAt: Date(), finishedAt: Date()),
            CoachToolCallTrace(toolName: "search_web", label: "Searching", status: "success",
                               argsRedacted: "", resultSummary: "", startedAt: Date(), finishedAt: Date()),
            CoachToolCallTrace(toolName: "prepare_chart", label: "Charting", status: "success",
                               argsRedacted: "", resultSummary: "", startedAt: Date(), finishedAt: Date()),
        ]
        var result = CoachOrchestrator.TurnResult(
            assistant: CoachResponse(responseType: .insight, title: "", summary: "Hi"),
            trace: trace)
        result.usedLLM = true
        result.roleLabel = "Researcher"
        result.model = "minimax/minimax-m2"
        result.rounds = 2
        result.inputTokens = 1200
        result.outputTokens = 300
        result.recovered = true

        let messageId = UUID()
        let convoId = UUID()
        let telemetry = CoachViewModel.makeTelemetry(result, messageId: messageId, conversationId: convoId, latencyMs: 4200)

        XCTAssertEqual(telemetry.messageId, messageId)
        XCTAssertEqual(telemetry.conversationId, convoId)
        XCTAssertEqual(telemetry.roleLabel, "Researcher")
        XCTAssertEqual(telemetry.model, "minimax/minimax-m2")
        XCTAssertEqual(telemetry.rounds, 2)
        XCTAssertEqual(telemetry.inputTokens, 1200)
        XCTAssertEqual(telemetry.outputTokens, 300)
        XCTAssertEqual(telemetry.latencyMs, 4200)
        XCTAssertTrue(telemetry.recovered)
        XCTAssertEqual(telemetry.toolNames, "search_web,prepare_chart",
                       "Tool names should be de-duplicated and ordered by first use")
        XCTAssertTrue(telemetry.errorReason.isEmpty)
    }

    func testMakeTelemetryRecordsErrorReason() {
        var result = CoachOrchestrator.TurnResult(
            assistant: CoachResponse(responseType: .errorRecovery, title: "", summary: "fallback"),
            trace: [])
        result.usedLLM = true
        result.errorMessage = "The request timed out. Try again in a moment."

        let telemetry = CoachViewModel.makeTelemetry(result, messageId: UUID(), conversationId: UUID(), latencyMs: 100)
        XCTAssertEqual(telemetry.errorReason, "The request timed out. Try again in a moment.")
        XCTAssertEqual(telemetry.toolNames, "")
    }
}
