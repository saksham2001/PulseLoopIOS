import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

// MARK: - Coach trip-awareness tests (Interconnect Track X / X5)
//
// The context packet's `trips` array makes the assistant travel-aware without a
// `list_trips` round-trip: it surfaces active/upcoming trips with their phase,
// days-until, item count, and open pre-trip checklist count. These tests prove
// the builder gates on the Travel module being installed and computes phases.
@MainActor
final class CoachTripContextTests: XCTestCase {

    private func installTravel() {
        SubAppRegistry.shared.installedIDs = []
        SubAppRegistry.shared.install(SubAppID(AppModule.travel.rawValue))
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
    }

    func testTripsEmptyWhenModuleNotInstalled() throws {
        SubAppRegistry.shared.installedIDs = []
        let c = try TestSupport.makeContext()
        c.insert(Trip(destination: "Tokyo"))
        try c.save()

        let packet = CoachContextBuilder.build(context: c)
        XCTAssertTrue(packet.trips.isEmpty, "Travel context must be gated by module install")
    }

    func testUpcomingTripSurfacedWithDaysUntil() throws {
        installTravel()
        let c = try TestSupport.makeContext()
        let trip = Trip(destination: "Lisbon")
        trip.startDate = day(5)
        trip.endDate = day(9)
        c.insert(trip)
        try c.save()

        let packet = CoachContextBuilder.build(context: c)
        let t = try XCTUnwrap(packet.trips.first { $0.destination == "Lisbon" })
        XCTAssertEqual(t.phase, "upcoming")
        XCTAssertEqual(t.daysUntil, 5)
    }

    func testActiveTripSurfacedAsActiveToday() throws {
        installTravel()
        let c = try TestSupport.makeContext()
        let trip = Trip(destination: "Rome")
        trip.startDate = day(-1)
        trip.endDate = day(2)
        c.insert(trip)
        try c.save()

        let packet = CoachContextBuilder.build(context: c)
        let t = try XCTUnwrap(packet.trips.first { $0.destination == "Rome" })
        XCTAssertEqual(t.phase, "active today")
    }

    func testPastTripDropped() throws {
        installTravel()
        let c = try TestSupport.makeContext()
        let trip = Trip(destination: "Oslo")
        trip.startDate = day(-20)
        trip.endDate = day(-15)
        c.insert(trip)
        try c.save()

        let packet = CoachContextBuilder.build(context: c)
        XCTAssertNil(packet.trips.first { $0.destination == "Oslo" }, "Ended trips should not clutter context")
    }

    func testOpenChecklistCountReflectsLinkedTasks() throws {
        installTravel()
        let c = try TestSupport.makeContext()
        let trip = Trip(destination: "Bali")
        trip.startDate = day(10)
        c.insert(trip)
        let t1 = TaskItem(title: "Passport", tripId: trip.id)
        let t2 = TaskItem(title: "Insurance", tripId: trip.id)
        let done = TaskItem(title: "Pack", status: .done, tripId: trip.id)
        c.insert(t1); c.insert(t2); c.insert(done)
        try c.save()

        let packet = CoachContextBuilder.build(context: c)
        let ctx = try XCTUnwrap(packet.trips.first { $0.destination == "Bali" })
        XCTAssertEqual(ctx.openChecklistCount, 2, "only not-done linked tasks count")
    }
}
