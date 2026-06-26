import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

/// Verifies the Travel module's coach tools end to end against an in-memory store:
/// the AI can create a trip, save searched options (flights/lodging/activities)
/// into it, read the itinerary back, mark items booked, and archive the trip.
@MainActor
final class TravelToolsTests: XCTestCase {

    private func writeFlags() -> CoachFeatureFlags {
        var s = CoachSettings.default
        s.enableWriteTools = true
        return CoachFeatureFlags(settings: s, hasAPIKey: true)
    }

    private func ctx(_ c: ModelContext) -> ToolExecutionContext {
        ToolExecutionContext(modelContext: c, flags: writeFlags())
    }

    /// Resolve a Travel tool by name directly from `TravelTools` (so the test
    /// doesn't depend on the Travel module being installed in the registry).
    private func tool(_ name: String) throws -> AnyCoachTool {
        let all = TravelTools.readTools + TravelTools.writeTools
        return try XCTUnwrap(all.first { $0.name == name }, "missing travel tool \(name)")
    }

    private func parse(_ result: ToolResult) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.jsonString.utf8)) as? [String: Any])
    }

    func testCreateTripPersists() async throws {
        let c = try TestSupport.makeContext()
        let result = try await tool("create_trip").run(
            Data(#"{"destination":"Tokyo, Japan","origin":"San Francisco","start_date":"2026-10-03","end_date":"2026-10-07","notes":"4-day October trip"}"#.utf8),
            ctx(c)
        )
        let out = try parse(result)
        XCTAssertEqual(out["ok"] as? Bool, true)
        let tripId = try XCTUnwrap(out["trip_id"] as? String)
        XCTAssertNotNil(UUID(uuidString: tripId))

        let trips = try c.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?.destination, "Tokyo, Japan")
        XCTAssertEqual(trips.first?.originCity, "San Francisco")
        XCTAssertNotNil(trips.first?.startDate)
    }

    func testAddItemsAndReadItinerary() async throws {
        let c = try TestSupport.makeContext()
        let created = try await tool("create_trip").run(
            Data(#"{"destination":"Tokyo","origin":null,"start_date":null,"end_date":null,"notes":null}"#.utf8),
            ctx(c)
        )
        let tripId = try XCTUnwrap((try parse(created))["trip_id"] as? String)

        // A flight option (the kind of thing the AI saves after a web search).
        let flight = try await tool("add_trip_item").run(
            Data(#"{"trip_id":"\#(tripId)","kind":"flight","title":"United UA837 SFO→HND","details":"nonstop, 11h","location":"SFO → HND","url":"https://united.com","price":920,"currency":"USD","start_at":null,"end_at":null,"day_offset":0}"#.utf8),
            ctx(c)
        )
        XCTAssertEqual((try parse(flight))["ok"] as? Bool, true)

        // A lodging option.
        _ = try await tool("add_trip_item").run(
            Data(#"{"trip_id":"\#(tripId)","kind":"lodging","title":"Park Hyatt Tokyo","details":"Shinjuku","location":"Shinjuku","url":null,"price":380,"currency":"USD","start_at":null,"end_at":null,"day_offset":0}"#.utf8),
            ctx(c)
        )
        // An activity.
        _ = try await tool("add_trip_item").run(
            Data(#"{"trip_id":"\#(tripId)","kind":"activity","title":"teamLab Planets","details":null,"location":"Toyosu","url":null,"price":null,"currency":null,"start_at":null,"end_at":null,"day_offset":1}"#.utf8),
            ctx(c)
        )

        // Read the itinerary back.
        let trip = try parse(try await tool("get_trip").run(Data(#"{"trip_id":"\#(tripId)"}"#.utf8), ctx(c)))
        let items = try XCTUnwrap(trip["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 3)
        let kinds = Set(items.compactMap { $0["kind"] as? String })
        XCTAssertEqual(kinds, ["flight", "lodging", "activity"])

        // Stored model reflects the items too.
        let stored = try c.fetch(FetchDescriptor<Trip>()).first
        XCTAssertEqual(stored?.items.count, 3)
        XCTAssertEqual(stored?.items.first(where: { $0.kind == .flight })?.price, 920)
    }

    func testSetBookedAndArchive() async throws {
        let c = try TestSupport.makeContext()
        let createdResult = try await tool("create_trip").run(
            Data(#"{"destination":"Lisbon","origin":null,"start_date":null,"end_date":null,"notes":null}"#.utf8), ctx(c))
        let tripId = try XCTUnwrap(try parse(createdResult)["trip_id"] as? String)
        let addResult = try await tool("add_trip_item").run(
            Data(#"{"trip_id":"\#(tripId)","kind":"flight","title":"TAP TP202","details":null,"location":null,"url":null,"price":null,"currency":null,"start_at":null,"end_at":null,"day_offset":null}"#.utf8), ctx(c))
        let itemId = try XCTUnwrap(try parse(addResult)["item_id"] as? String)

        _ = try await tool("set_trip_item_booked").run(Data(#"{"item_id":"\#(itemId)","booked":true}"#.utf8), ctx(c))
        let item = try c.fetch(FetchDescriptor<TripItem>()).first { $0.id.uuidString == itemId }
        XCTAssertEqual(item?.booked, true)

        // Archiving a whole trip is destructive, so it now proposes a confirm card
        // rather than applying immediately (BUG-3). The trip stays active until the
        // user confirms; executing the pending action archives it.
        let archiveCtx = ctx(c)
        let archiveResult = try await tool("update_trip").run(
            Data(#"{"trip_id":"\#(tripId)","destination":null,"origin":null,"start_date":null,"end_date":null,"notes":null,"status":"cancelled"}"#.utf8), archiveCtx)
        XCTAssertEqual(try parse(archiveResult)["needs_confirmation"] as? Bool, true)

        let pending = try XCTUnwrap(archiveCtx.pendingActions.first, "archive should queue a confirm card")
        XCTAssertEqual(pending.entity?.entityType, "trip")

        let beforeConfirm = try c.fetch(FetchDescriptor<Trip>()).first { $0.id.uuidString == tripId }
        XCTAssertEqual(beforeConfirm?.status, .planning, "trip stays active until confirmed")

        _ = PendingActionExecutor.execute(pending, context: c)
        let trip = try c.fetch(FetchDescriptor<Trip>()).first { $0.id.uuidString == tripId }
        XCTAssertEqual(trip?.status, .cancelled)
    }

    /// The Travel module surfaces its tools to the coach only when installed.
    func testToolsGatedByModuleInstall() {
        let installedTools = TravelSubApp().aiTools(flags: writeFlags()).map(\.name)
        XCTAssertTrue(installedTools.contains("create_trip"))
        XCTAssertTrue(installedTools.contains("add_trip_item"))
        XCTAssertTrue(installedTools.contains("get_trip"))
    }

    /// create_trip persists the richer fields (travelers, budget, cover image).
    func testCreateTripPersistsRichFields() async throws {
        let c = try TestSupport.makeContext()
        let result = try await tool("create_trip").run(
            Data(#"{"destination":"Paris","origin":null,"start_date":null,"end_date":null,"notes":null,"traveler_count":3,"budget_amount":4200,"budget_currency":"EUR","cover_image_url":"https://example.com/paris.jpg"}"#.utf8),
            ctx(c)
        )
        XCTAssertEqual(try parse(result)["ok"] as? Bool, true)
        let trip = try XCTUnwrap(try c.fetch(FetchDescriptor<Trip>()).first)
        XCTAssertEqual(trip.travelerCount, 3)
        XCTAssertEqual(trip.budgetAmount, 4200)
        XCTAssertEqual(trip.budgetCurrency, "EUR")
        XCTAssertEqual(trip.coverImageURL, "https://example.com/paris.jpg")
    }

    /// add_trip_item persists rating + coordinates, and the budget rollup sums prices.
    func testItemRichFieldsAndBudgetRollup() async throws {
        let c = try TestSupport.makeContext()
        let created = try await tool("create_trip").run(
            Data(#"{"destination":"Rome","origin":null,"start_date":null,"end_date":null,"notes":null,"traveler_count":2,"budget_amount":3000,"budget_currency":"USD","cover_image_url":null}"#.utf8),
            ctx(c)
        )
        let tripId = try XCTUnwrap(try parse(created)["trip_id"] as? String)

        _ = try await tool("add_trip_item").run(
            Data(#"{"trip_id":"\#(tripId)","kind":"lodging","title":"Hotel Eden","details":null,"location":"Via Ludovisi","url":null,"price":600,"currency":"USD","start_at":null,"end_at":null,"day_offset":0,"rating":4.8,"latitude":41.9078,"longitude":12.4880}"#.utf8),
            ctx(c)
        )
        _ = try await tool("add_trip_item").run(
            Data(#"{"trip_id":"\#(tripId)","kind":"flight","title":"AZ611","details":null,"location":null,"url":null,"price":900,"currency":"USD","start_at":null,"end_at":null,"day_offset":0,"rating":null,"latitude":null,"longitude":null}"#.utf8),
            ctx(c)
        )

        let trip = try XCTUnwrap(try c.fetch(FetchDescriptor<Trip>()).first)
        let lodging = try XCTUnwrap(trip.items.first { $0.kind == .lodging })
        XCTAssertEqual(lodging.rating, 4.8)
        XCTAssertEqual(lodging.latitude, 41.9078)
        XCTAssertEqual(lodging.longitude, 12.4880)

        XCTAssertEqual(trip.estimatedCost, 1500)
        XCTAssertEqual(trip.effectiveCurrency, "USD")
        let costByKind = Dictionary(uniqueKeysWithValues: trip.costByKind.map { ($0.0, $0.1) })
        XCTAssertEqual(costByKind[.lodging], 600)
        XCTAssertEqual(costByKind[.flight], 900)

        // get_trip surfaces the new fields to the model.
        let read = try parse(try await tool("get_trip").run(Data(#"{"trip_id":"\#(tripId)"}"#.utf8), ctx(c)))
        XCTAssertEqual(read["traveler_count"] as? Int, 2)
        XCTAssertEqual(read["budget_amount"] as? Double, 3000)
        XCTAssertEqual(read["estimated_cost"] as? Double, 1500)
        let items = try XCTUnwrap(read["items"] as? [[String: Any]])
        let lodgingDict = try XCTUnwrap(items.first { ($0["kind"] as? String) == "lodging" })
        XCTAssertEqual(lodgingDict["rating"] as? Double, 4.8)
        XCTAssertEqual(lodgingDict["latitude"] as? Double, 41.9078)
    }

    /// bookedCost only counts items the user has confirmed.
    func testBookedCostRollup() async throws {
        let c = try TestSupport.makeContext()
        let created = try await tool("create_trip").run(
            Data(#"{"destination":"Oslo","origin":null,"start_date":null,"end_date":null,"notes":null,"traveler_count":1,"budget_amount":null,"budget_currency":null,"cover_image_url":null}"#.utf8),
            ctx(c)
        )
        let tripId = try XCTUnwrap(try parse(created)["trip_id"] as? String)
        let add = try await tool("add_trip_item").run(
            Data(#"{"trip_id":"\#(tripId)","kind":"flight","title":"SK","details":null,"location":null,"url":null,"price":450,"currency":"USD","start_at":null,"end_at":null,"day_offset":null,"rating":null,"latitude":null,"longitude":null}"#.utf8),
            ctx(c)
        )
        let itemId = try XCTUnwrap(try parse(add)["item_id"] as? String)

        let trip = try XCTUnwrap(try c.fetch(FetchDescriptor<Trip>()).first)
        XCTAssertEqual(trip.bookedCost, 0)
        _ = try await tool("set_trip_item_booked").run(Data(#"{"item_id":"\#(itemId)","booked":true}"#.utf8), ctx(c))
        XCTAssertEqual(trip.bookedCost, 450)
    }

    /// create_trip_checklist creates pre-trip tasks linked to the trip.
    func testCreateTripChecklistLinksTasks() async throws {
        let c = try TestSupport.makeContext()
        let created = try await tool("create_trip").run(
            Data(#"{"destination":"Bali","origin":null,"start_date":null,"end_date":null,"notes":null}"#.utf8),
            ctx(c)
        )
        let tripId = try XCTUnwrap(try parse(created)["trip_id"] as? String)

        let result = try await tool("create_trip_checklist").run(
            Data(#"{"trip_id":"\#(tripId)","tasks":["Renew passport","Buy travel insurance","Exchange currency"]}"#.utf8),
            ctx(c)
        )
        let out = try parse(result)
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(out["created_count"] as? Int, 3)

        let uuid = try XCTUnwrap(UUID(uuidString: tripId))
        let tasks = try c.fetch(FetchDescriptor<TaskItem>()).filter { $0.tripId == uuid }
        XCTAssertEqual(tasks.count, 3)
        XCTAssertTrue(tasks.allSatisfy { $0.tripId == uuid })
        XCTAssertTrue(tasks.contains { $0.title == "Renew passport" })
    }

    /// set_destination_info persists currency/language/time-zone/tip onto the trip.
    func testSetDestinationInfoPersists() async throws {
        let c = try TestSupport.makeContext()
        let created = try await tool("create_trip").run(
            Data(#"{"destination":"Tokyo, Japan","origin":null,"start_date":null,"end_date":null,"notes":null}"#.utf8),
            ctx(c)
        )
        let tripId = try XCTUnwrap(try parse(created)["trip_id"] as? String)

        let result = try await tool("set_destination_info").run(
            Data(#"{"trip_id":"\#(tripId)","currency":"jpy","language":"Japanese","time_zone_id":"Asia/Tokyo","tip":"Carry cash; many places are cash-only."}"#.utf8),
            ctx(c)
        )
        XCTAssertEqual(try parse(result)["ok"] as? Bool, true)

        let uuid = try XCTUnwrap(UUID(uuidString: tripId))
        let trip = try XCTUnwrap(try c.fetch(FetchDescriptor<Trip>()).first { $0.id == uuid })
        XCTAssertEqual(trip.destinationCurrency, "JPY")
        XCTAssertEqual(trip.destinationLanguage, "Japanese")
        XCTAssertEqual(trip.destinationTimeZoneId, "Asia/Tokyo")
        XCTAssertNotNil(trip.destinationTip)
        XCTAssertTrue(trip.hasDestinationInfo)
    }

    /// An invalid time-zone id is rejected so the UI's offset math stays valid.
    func testSetDestinationInfoRejectsBadTimeZone() async throws {
        let c = try TestSupport.makeContext()
        let created = try await tool("create_trip").run(
            Data(#"{"destination":"X","origin":null,"start_date":null,"end_date":null,"notes":null}"#.utf8),
            ctx(c)
        )
        let tripId = try XCTUnwrap(try parse(created)["trip_id"] as? String)
        _ = try await tool("set_destination_info").run(
            Data(#"{"trip_id":"\#(tripId)","currency":null,"language":null,"time_zone_id":"Bogus/Zone","tip":null}"#.utf8),
            ctx(c)
        )
        let uuid = try XCTUnwrap(UUID(uuidString: tripId))
        let trip = try XCTUnwrap(try c.fetch(FetchDescriptor<Trip>()).first { $0.id == uuid })
        XCTAssertNil(trip.destinationTimeZoneId)
    }

    /// create_packing_list creates packing tasks in the Packing group linked to the trip.
    func testCreatePackingListLinksTasks() async throws {
        let c = try TestSupport.makeContext()
        let created = try await tool("create_trip").run(
            Data(#"{"destination":"Reykjavik","origin":null,"start_date":null,"end_date":null,"notes":null}"#.utf8),
            ctx(c)
        )
        let tripId = try XCTUnwrap(try parse(created)["trip_id"] as? String)

        let result = try await tool("create_packing_list").run(
            Data(#"{"trip_id":"\#(tripId)","items":["Passport","Thermal layers","Universal adapter"]}"#.utf8),
            ctx(c)
        )
        let out = try parse(result)
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(out["created_count"] as? Int, 3)

        let uuid = try XCTUnwrap(UUID(uuidString: tripId))
        let tasks = try c.fetch(FetchDescriptor<TaskItem>()).filter { $0.tripId == uuid }
        XCTAssertEqual(tasks.count, 3)
        XCTAssertTrue(tasks.allSatisfy { $0.group == TravelTools.packingGroup })
        XCTAssertTrue(tasks.contains { $0.title == "Thermal layers" })
    }

    /// create_trip_note creates a Note linked to the trip with a body block.
    func testCreateTripNoteLinksNote() async throws {
        let c = try TestSupport.makeContext()
        let created = try await tool("create_trip").run(
            Data(#"{"destination":"Kyoto","origin":null,"start_date":null,"end_date":null,"notes":null}"#.utf8),
            ctx(c)
        )
        let tripId = try XCTUnwrap(try parse(created)["trip_id"] as? String)

        let result = try await tool("create_trip_note").run(
            Data(#"{"trip_id":"\#(tripId)","title":"Ryokan reservation","body":"Confirmation #ABC123, check-in 3pm"}"#.utf8),
            ctx(c)
        )
        let out = try parse(result)
        XCTAssertEqual(out["ok"] as? Bool, true)

        let uuid = try XCTUnwrap(UUID(uuidString: tripId))
        let notes = try c.fetch(FetchDescriptor<Note>()).filter { $0.linkedTripId == uuid }
        XCTAssertEqual(notes.count, 1)
        let note = try XCTUnwrap(notes.first)
        XCTAssertEqual(note.title, "Ryokan reservation")
        XCTAssertEqual(note.blocks.first?.content, "Confirmation #ABC123, check-in 3pm")
    }
}
