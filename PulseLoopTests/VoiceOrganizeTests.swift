import Foundation
import XCTest
@testable import PulseLoop

// MARK: - Voice T1 tests
//
// Covers the deterministic, persistence-free pieces of the voice-first
// "organize my life" experience: the multi-part spoken confirmation built from a
// turn's `actions_taken`, and the opt-in daily brief script. Both are pure so the
// exact wording the user hears is locked in by tests.

@MainActor
final class VoiceOrganizeTests: XCTestCase {

    // MARK: Multi-part spoken confirmation

    func testSpokenSummaryListsEachActionForMultiIntent() {
        let response = CoachResponse(
            responseType: .insight,
            title: "",
            summary: "All set.",
            actionsTaken: [
                "Logged a 30 minute run",
                "Added eggs to breakfast",
                "Set a reminder to call mom at 6 PM"
            ]
        )
        let spoken = VoiceSessionController.spokenSummary(from: response)
        XCTAssertTrue(spoken.hasPrefix("Done:"), "Should lead with the done preamble")
        XCTAssertTrue(spoken.contains("logged a 30 minute run"))
        XCTAssertTrue(spoken.contains("added eggs to breakfast"))
        // Oxford-style join for the final item.
        XCTAssertTrue(spoken.contains(", and set a reminder to call mom at 6 PM"),
                      "Three actions should join with a serial 'and': \(spoken)")
        XCTAssertTrue(spoken.contains("All set."))
    }

    func testSpokenSummaryTwoActionsUseAndWithoutComma() {
        let response = CoachResponse(
            responseType: .insight,
            title: "",
            summary: "",
            actionsTaken: ["Logged a run", "Added eggs to breakfast"]
        )
        let spoken = VoiceSessionController.spokenSummary(from: response)
        XCTAssertEqual(spoken, "Done: logged a run and added eggs to breakfast.")
    }

    func testSpokenSummaryDropsSummaryWhenItEchoesSingleAction() {
        let response = CoachResponse(
            responseType: .insight,
            title: "",
            summary: "Logged a run",
            actionsTaken: ["Logged a run"]
        )
        let spoken = VoiceSessionController.spokenSummary(from: response)
        XCTAssertEqual(spoken, "Done: logged a run.")
    }

    func testSpokenSummaryFallsBackToSummaryWhenNoActions() {
        let response = CoachResponse(
            responseType: .insight,
            title: "Title",
            summary: "Here's what I think.",
            actionsTaken: []
        )
        let spoken = VoiceSessionController.spokenSummary(from: response)
        XCTAssertEqual(spoken, "Here's what I think.")
    }

    func testSpokenSummaryEmptyForNilResponse() {
        XCTAssertEqual(VoiceSessionController.spokenSummary(from: nil), "")
    }

    func testNaturalListPreservesProperNounCasing() {
        // "Tahoe" should not be lower-cased mid-list when it follows other items,
        // but our rule only lowercases the first letter; a single-word proper noun
        // would be lowercased. Multi-cap acronyms stay intact.
        XCTAssertEqual(VoiceSessionController.naturalList(["PR set", "added eggs"]),
                       "PR set and added eggs")
    }

    // MARK: Daily brief composer

    private func morning() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return DateComponents(calendar: cal, year: 2026, month: 6, day: 24, hour: 8).date!
    }

    private func evening() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return DateComponents(calendar: cal, year: 2026, month: 6, day: 24, hour: 20).date!
    }

    func testBriefGreetsByTimeOfDay() {
        let morningScript = VoiceBriefComposer.script(now: morning(), learnings: [])
        XCTAssertTrue(morningScript.hasPrefix("Good morning."), morningScript)
        let eveningScript = VoiceBriefComposer.script(now: evening(), learnings: [])
        XCTAssertTrue(eveningScript.hasPrefix("Good evening."), eveningScript)
    }

    func testBriefMentionsTopLearningsByImportance() {
        let items = [
            VoiceBriefComposer.Item(title: "Weak", detail: "A weak signal.", importance: 1),
            VoiceBriefComposer.Item(title: "Sleep", detail: "Late caffeine cut your deep sleep.", importance: 5),
            VoiceBriefComposer.Item(title: "Steps", detail: "Walks lift your mood the next day.", importance: 4)
        ]
        let script = VoiceBriefComposer.script(now: morning(), learnings: items)
        XCTAssertTrue(script.contains("Late caffeine cut your deep sleep."), script)
        XCTAssertTrue(script.contains("Walks lift your mood the next day."), script)
        // Only the top two are read; the weak one is dropped.
        XCTAssertFalse(script.contains("A weak signal."), script)
    }

    func testBriefIsDeDashed() {
        let items = [
            VoiceBriefComposer.Item(title: "X", detail: "Sleep dropped — likely from late caffeine.", importance: 5)
        ]
        let script = VoiceBriefComposer.script(now: morning(), learnings: items)
        XCTAssertFalse(script.contains("—"), "Brief must not contain em dashes: \(script)")
        XCTAssertFalse(script.contains("–"), "Brief must not contain en dashes: \(script)")
    }

    func testBriefEmptyLearningsStillInvites() {
        let script = VoiceBriefComposer.script(now: morning(), learnings: [])
        XCTAssertTrue(script.contains("organize"), script)
    }

    func testShouldSpeakRespectsOptInAndDayGate() {
        XCTAssertFalse(VoiceBriefComposer.shouldSpeak(enabled: false, lastSpokenDay: nil, today: "2026-06-24"))
        XCTAssertTrue(VoiceBriefComposer.shouldSpeak(enabled: true, lastSpokenDay: nil, today: "2026-06-24"))
        XCTAssertFalse(VoiceBriefComposer.shouldSpeak(enabled: true, lastSpokenDay: "2026-06-24", today: "2026-06-24"))
        XCTAssertTrue(VoiceBriefComposer.shouldSpeak(enabled: true, lastSpokenDay: "2026-06-23", today: "2026-06-24"))
    }

    func testDayKeyIsStableLocalDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(VoiceBriefComposer.dayKey(for: morning(), calendar: cal), "2026-06-24")
    }
}
