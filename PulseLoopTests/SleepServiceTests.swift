import XCTest
import SwiftData
@testable import PulseLoop

@MainActor
final class SleepServiceTests: XCTestCase {
    private func night(_ dayOffset: Int) -> Date {
        // Anchor on the day-view's reference night (which flips at 4 AM) rather than
        // wall-clock "today" so `night(0)` is always the night the Day view targets,
        // even when the suite runs between midnight and 4 AM.
        let ref = SleepService.dayReferenceNight()
        let base = Calendar.current.date(byAdding: .day, value: dayOffset, to: ref) ?? ref
        return Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: base) ?? base
    }

    func testStaleSleepHiddenFromLatest() throws {
        let context = try TestSupport.makeContext()
        TestSupport.insertSleep(nightStart: night(-3), stages: Array(repeating: .light, count: 60), into: context)
        XCTAssertNil(SleepService.latestSleep(context: context), "a 3-day-old session is stale")
    }

    func testRecentSleepShown() throws {
        let context = try TestSupport.makeContext()
        TestSupport.insertSleep(nightStart: night(0), stages: Array(repeating: .deep, count: 90), into: context)
        let latest = SleepService.latestSleep(context: context)
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.deepMinutes, 90)
    }

    func testStaleSleepHiddenFromToday() throws {
        let context = try TestSupport.makeContext()
        TestSupport.insertSleep(nightStart: night(-4), stages: Array(repeating: .light, count: 30), into: context)
        XCTAssertNil(MetricsService.buildTodaySummary(context: context).sleep)
    }

    func testSummaryStageMinutes() throws {
        let context = try TestSupport.makeContext()
        let stages = Array(repeating: SleepStage.light, count: 40) + Array(repeating: .deep, count: 20) + Array(repeating: .awake, count: 5)
        let session = TestSupport.insertSleep(nightStart: night(0), stages: stages, into: context)
        let summary = SleepService.summary(for: session, context: context)
        XCTAssertEqual(summary.lightMinutes, 40)
        XCTAssertEqual(summary.deepMinutes, 20)
        XCTAssertEqual(summary.awakeMinutes, 5)
    }

    func testExpectedNightsPerRange() throws {
        let context = try TestSupport.makeContext()
        TestSupport.insertSleep(nightStart: night(0), stages: Array(repeating: .light, count: 60), into: context)
        XCTAssertEqual(SleepService.sleepRange(.day, context: context).expectedNights, 1)
        XCTAssertEqual(SleepService.sleepRange(.week, context: context).expectedNights, 7)
        XCTAssertEqual(SleepService.sleepRange(.month, context: context).expectedNights, 30)
        XCTAssertEqual(SleepService.sleepRange(.year, context: context).expectedNights, 365)
    }

    func testWeekRangeWindowsSessions() throws {
        let context = try TestSupport.makeContext()
        TestSupport.insertSleep(nightStart: night(0), stages: Array(repeating: .light, count: 60), into: context)
        TestSupport.insertSleep(nightStart: night(-2), stages: Array(repeating: .deep, count: 60), into: context)
        TestSupport.insertSleep(nightStart: night(-20), stages: Array(repeating: .light, count: 60), into: context)
        let week = SleepService.sleepRange(.week, context: context)
        XCTAssertEqual(week.sessions.count, 2, "only sessions within the 7-night window")
    }

    func testBlocksOnlyForDayRange() throws {
        let context = try TestSupport.makeContext()
        TestSupport.insertSleep(nightStart: night(0), stages: Array(repeating: .light, count: 60), into: context)
        XCTAssertFalse(SleepService.sleepRange(.day, context: context).sessions.first?.blocks.isEmpty ?? true)
        XCTAssertTrue(SleepService.sleepRange(.week, context: context).sessions.first?.blocks.isEmpty ?? false)
    }

    /// The Day view used to show the last recorded sleep even when "last night"
    /// had no data — so a 3-day-old session masqueraded as last night. Now the
    /// day anchor is "today's reference night", so an old session is excluded.
    func testDayRangeShowsNoDataWhenLastNightMissing() throws {
        let context = try TestSupport.makeContext()
        TestSupport.insertSleep(nightStart: night(-3), stages: Array(repeating: .light, count: 60), into: context)
        XCTAssertTrue(SleepService.sleepRange(.day, context: context).sessions.isEmpty)
        // But the week view still surfaces it.
        XCTAssertFalse(SleepService.sleepRange(.week, context: context).sessions.isEmpty)
    }

    func testDayReferenceNightFlipsAt4AM() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let at3am = cal.date(bySettingHour: 3, minute: 0, second: 0, of: today)!
        let at4am = cal.date(bySettingHour: 4, minute: 0, second: 0, of: today)!
        XCTAssertEqual(SleepService.dayReferenceNight(now: at3am), yesterday, "before 4 AM, still last night")
        XCTAssertEqual(SleepService.dayReferenceNight(now: at4am), today, "from 4 AM, flip to today")
    }

    /// Regression for the README "known bug": when last night has data AND an
    /// older session also exists, the Day view must surface *last night*, never
    /// the most-recently-recorded older night. (Day range carries a single
    /// reference night, so this also proves the stale night is excluded.)
    func testDayRangeShowsLastNightNotStaleRecord() throws {
        let context = try TestSupport.makeContext()
        // An older night with a distinctive deep total, plus last night with a
        // different, distinctive light total.
        TestSupport.insertSleep(nightStart: night(-5), stages: Array(repeating: .deep, count: 77), into: context)
        TestSupport.insertSleep(nightStart: night(0), stages: Array(repeating: .light, count: 88), into: context)
        let day = SleepService.sleepRange(.day, context: context)
        XCTAssertEqual(day.sessions.count, 1, "day range is a single reference night")
        let shown = SleepInsights.validSessions(day.sessions).last
        XCTAssertEqual(shown?.lightMinutes, 88, "day view shows last night")
        XCTAssertEqual(shown?.deepMinutes, 0, "the 5-day-old deep session must not leak in")
    }
}
