import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

/// Tests for the Travel+ loop (docs/TRAVEL_PLUS_LOOP_PROMPT.md).
@MainActor
final class TravelPlusTests: XCTestCase {

    // MARK: - T1: Coach prefill plumbing

    func testAskAISetsPrefill() {
        let nav = CoachNavigation.shared
        nav.prefill = nil
        nav.askAI("Plan a 5-day trip to Lisbon")
        XCTAssertEqual(nav.prefill, "Plan a 5-day trip to Lisbon")
        nav.prefill = nil
    }

    func testPrefillRoundTrips() {
        let nav = CoachNavigation.shared
        nav.prefill = "Find flights SFO → HND"
        XCTAssertEqual(nav.prefill, "Find flights SFO → HND")
        nav.prefill = nil
        XCTAssertNil(nav.prefill)
    }

    // MARK: - T3: Manual create & edit (AI-independent)

    func testCreateTripPersists() throws {
        let ctx = try TestSupport.makeContext()
        let trip = Trip(destination: "placeholder")
        ctx.insert(trip)
        TravelEditing.apply(
            to: trip,
            destination: "Lisbon, Portugal",
            origin: "San Francisco",
            startDate: TestSupport.day(10),
            endDate: TestSupport.day(15),
            travelerCount: 2,
            budgetAmount: 3500,
            budgetCurrency: "usd",
            notes: "Anniversary trip"
        )
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(fetched.count, 1)
        let saved = try XCTUnwrap(fetched.first)
        XCTAssertEqual(saved.destination, "Lisbon, Portugal")
        XCTAssertEqual(saved.originCity, "San Francisco")
        XCTAssertEqual(saved.travelerCount, 2)
        XCTAssertEqual(saved.budgetAmount, 3500)
        XCTAssertEqual(saved.budgetCurrency, "usd")
        XCTAssertEqual(saved.notes, "Anniversary trip")
        XCTAssertNotNil(saved.startDate)
    }

    func testApplyTripTrimsAndClampsTravelers() throws {
        let ctx = try TestSupport.makeContext()
        let trip = Trip(destination: "x")
        ctx.insert(trip)
        TravelEditing.apply(
            to: trip,
            destination: "  Tokyo  ",
            origin: "   ",
            startDate: nil,
            endDate: nil,
            travelerCount: 0,
            budgetAmount: nil,
            budgetCurrency: "   ",
            notes: "   "
        )
        XCTAssertEqual(trip.destination, "Tokyo")
        XCTAssertNil(trip.originCity, "Whitespace-only origin should become nil")
        XCTAssertNil(trip.budgetCurrency)
        XCTAssertNil(trip.notes)
        XCTAssertEqual(trip.travelerCount, 1, "Travelers should clamp to at least 1")
    }

    func testAddTripItemPersistsAndRollsUp() throws {
        let ctx = try TestSupport.makeContext()
        let trip = Trip(destination: "Tokyo")
        ctx.insert(trip)
        let item = TripItem(tripId: trip.id, kind: .flight, title: "placeholder", order: 0)
        ctx.insert(item)
        trip.items.append(item)
        TravelEditing.apply(
            to: item,
            kind: .lodging,
            title: "Park Hyatt Tokyo",
            details: "Club room",
            location: "Shinjuku",
            url: "https://example.com",
            price: 620,
            currency: "USD",
            dayOffset: 1,
            booked: true
        )
        try ctx.save()

        let saved = try XCTUnwrap(try ctx.fetch(FetchDescriptor<TripItem>()).first)
        XCTAssertEqual(saved.kind, .lodging)
        XCTAssertEqual(saved.title, "Park Hyatt Tokyo")
        XCTAssertEqual(saved.location, "Shinjuku")
        XCTAssertEqual(saved.price, 620)
        XCTAssertEqual(saved.dayOffset, 1)
        XCTAssertTrue(saved.booked)
        XCTAssertEqual(trip.estimatedCost, 620, accuracy: 0.001)
        XCTAssertEqual(trip.bookedCost, 620, accuracy: 0.001)
    }

    // MARK: - T5: Destination info

    func testTimeZoneDeltaSameZoneIsNil() {
        let trip = Trip(destination: "Local City")
        // No destination zone set → no delta row.
        XCTAssertNil(trip.timeZoneDeltaDescription)
        XCTAssertFalse(trip.hasDestinationInfo)
    }

    func testTimeZoneDeltaDescribesOffset() {
        let trip = Trip(destination: "Tokyo")
        trip.destinationTimeZoneId = "Asia/Tokyo"
        let desc = trip.timeZoneDeltaDescription
        XCTAssertNotNil(desc)
        // Either "+Nh from you", "−Nh from you", or "Same time as you" depending on
        // the test machine's zone — assert it's a well-formed, non-empty phrase.
        XCTAssertTrue(desc!.contains("from you") || desc! == "Same time as you")
        XCTAssertTrue(trip.hasDestinationInfo)
    }

    func testInvalidTimeZoneIsIgnoredForDelta() {
        let trip = Trip(destination: "Nowhere")
        trip.destinationTimeZoneId = "Not/AZone"
        XCTAssertNil(trip.timeZoneDeltaDescription)
    }
}
