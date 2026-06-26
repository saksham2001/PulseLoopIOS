import Foundation
import XCTest
@testable import PulseLoop

// MARK: - VoiceCaptureRouter tests
//
// Focuses on the deterministic local fallback (no network / no API key) and the
// week-scheduling math. This is the path that guarantees a voice capture is
// always regenerated into structured note + tasks rather than dumped as a raw
// "Transcript", which is exactly what the AI path mirrors.

@MainActor
final class VoiceCaptureRouterTests: XCTestCase {

    /// The transcript from the reported screenshot.
    private let sample = """
    Hello can you hear me nice so I want to be able to plan out my week I have \
    a lot of things to do I need to finish up oravilles.com packaging horizon AURA please save it
    """

    private func router(onMonday: Bool = true) -> VoiceCaptureRouter {
        var r = VoiceCaptureRouter()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        r.calendar = cal
        // A fixed Monday so day labels/offsets are deterministic.
        r.now = { DateComponents(calendar: cal, year: 2026, month: 6, day: 22, hour: 9).date! }
        return r
    }

    func testLocalPlanNeverProducesRawTranscriptDump() {
        let plan = router().localPlan(from: sample)
        // No section should just be a verbatim "Transcript".
        XCTAssertFalse(plan.sections.contains { $0.heading == "Transcript" })
        XCTAssertFalse(plan.title.isEmpty)
    }

    func testWeekPlanningDetectedAndTitled() {
        let plan = router().localPlan(from: sample)
        XCTAssertEqual(plan.title, "Plan My Week")
    }

    func testActionItemsBecomeTasks() {
        let plan = router().localPlan(from: sample)
        XCTAssertFalse(plan.tasks.isEmpty, "Expected at least the 'finish packaging' task")
        XCTAssertTrue(plan.tasks.contains { $0.title.lowercased().contains("finish") })
    }

    func testProjectDomainIsExtractedAsGroup() {
        let plan = router().localPlan(from: "I need to finish oravilles.com packaging")
        let task = plan.tasks.first
        XCTAssertEqual(task?.group.lowercased(), "oravilles.com")
    }

    func testWeekPlanningSchedulesTasksAcrossDays() {
        let multi = "Plan my week. I need to email Sam. Then I have to call the bank. Also buy groceries."
        let plan = router().localPlan(from: multi)
        let scheduled = plan.tasks.filter { $0.dayOffset != nil }
        XCTAssertEqual(scheduled.count, plan.tasks.count, "Week planning should schedule every task")
        // Offsets should start at 0 and increment.
        XCTAssertEqual(plan.tasks.first?.dayOffset, 0)
    }

    func testNoWeekPlanningLeavesTasksUnscheduled() {
        let plan = router().localPlan(from: "I need to email Sam.")
        XCTAssertEqual(plan.tasks.first?.dayOffset, nil)
    }

    func testDueDateResolvesFromOffset() {
        let r = router()
        let today = r.dueDate(forDayOffset: 0)
        let tomorrow = r.dueDate(forDayOffset: 1)
        XCTAssertNotNil(today)
        XCTAssertNotNil(tomorrow)
        XCTAssertEqual(r.calendar.dateComponents([.day], from: today!, to: tomorrow!).day, 1)
        XCTAssertNil(r.dueDate(forDayOffset: nil))
    }

    func testTaskTitleStripsSpokenPrefixesAndCapitalizes() {
        XCTAssertEqual(VoiceCaptureRouter.taskTitle(from: "i need to finish packaging"), "Finish packaging")
        XCTAssertEqual(VoiceCaptureRouter.taskTitle(from: "remember to call mom"), "Call mom")
    }

    func testEmptyTranscriptYieldsEmptyPlan() async {
        let plan = await router().plan(from: "   ")
        XCTAssertTrue(plan.tasks.isEmpty)
        XCTAssertTrue(plan.sections.isEmpty)
    }

    // MARK: - AI envelope parsing

    func testParseValidEnvelope() {
        let json = """
        {"title":"Plan My Week","sections":[{"heading":"Focus","bullets":["Ship Aura"]}],
        "tasks":[{"title":"Finish packaging","group":"Oravilles.com","dayOffset":0}]}
        """
        let plan = VoiceCaptureRouter.parse(json, transcript: "raw")
        XCTAssertEqual(plan?.title, "Plan My Week")
        XCTAssertEqual(plan?.tasks.first?.group, "Oravilles.com")
        XCTAssertEqual(plan?.tasks.first?.dayOffset, 0)
        XCTAssertEqual(plan?.transcript, "raw")
    }

    func testParseTolerateProseAndCodeFences() {
        let raw = """
        Sure! Here is the plan:
        ```json
        {"title":"T","sections":[],"tasks":[{"title":"Do thing","group":"Inbox","dayOffset":null}]}
        ```
        """
        let plan = VoiceCaptureRouter.parse(raw, transcript: "x")
        XCTAssertEqual(plan?.title, "T")
        XCTAssertEqual(plan?.tasks.first?.dayOffset, nil)
    }

    func testParseClampsOutOfRangeDayOffset() {
        let json = #"{"title":"T","sections":[],"tasks":[{"title":"a","group":"Inbox","dayOffset":99}]}"#
        let plan = VoiceCaptureRouter.parse(json, transcript: "x")
        XCTAssertEqual(plan?.tasks.first?.dayOffset, 6)
    }

    func testParseRejectsEmptyPlan() {
        let json = #"{"title":"T","sections":[],"tasks":[]}"#
        XCTAssertNil(VoiceCaptureRouter.parse(json, transcript: "x"))
    }
}
