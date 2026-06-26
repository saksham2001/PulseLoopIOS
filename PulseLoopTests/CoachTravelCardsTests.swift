import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

/// Verifies the in-chat travel cards path: a coach reply carrying `travel_cards`
/// + `itinerary` decodes correctly, the strict schema advertises those fields,
/// the `prepare_travel_cards` tool echoes cards for verbatim copy, and saving a
/// chat card persists a real `TripItem` ("one shape, two surfaces").
@MainActor
final class CoachTravelCardsTests: XCTestCase {

    private func writeFlags() -> CoachFeatureFlags {
        var s = CoachSettings.default
        s.enableWriteTools = true
        return CoachFeatureFlags(settings: s, hasAPIKey: true)
    }

    /// A travel-planning response decodes the new card fields.
    func testResponseDecodesTravelCards() throws {
        let json = """
        {
          "response_type": "insight",
          "title": "Tokyo options",
          "summary": "Here are a few picks.",
          "bullets": [],
          "chart": null,
          "safety_note": null,
          "data_quality_note": null,
          "sources": [],
          "follow_up_chips": [],
          "actions_taken": [],
          "confidence": "high",
          "media": [],
          "diagram": null,
          "travel_cards": [
            {"kind":"flight","title":"UA837 SFO→HND","subtitle":"Nonstop","price":920,"currency":"USD","time":"Oct 3 · 10:45","location":"SFO → HND","rating":null,"thumbnail_url":null,"booking_url":"https://united.com","latitude":null,"longitude":null},
            {"kind":"lodging","title":"Park Hyatt Tokyo","subtitle":"Shinjuku","price":380,"currency":"USD","time":null,"location":"Shinjuku","rating":4.7,"thumbnail_url":null,"booking_url":null,"latitude":35.6855,"longitude":139.6917}
          ],
          "itinerary": [
            {"day_offset":0,"label":"Arrival","items":["Land at HND","Check in"]}
          ]
        }
        """
        let response = try XCTUnwrap(CoachResponse.decode(fromJSON: json))
        XCTAssertEqual(response.travelCards.count, 2)
        XCTAssertEqual(response.travelCards.first?.kind, .flight)
        XCTAssertEqual(response.travelCards.first?.price, 920)
        let stay = try XCTUnwrap(response.travelCards.first { $0.kind == .lodging })
        XCTAssertEqual(stay.rating, 4.7)
        XCTAssertTrue(stay.hasCoordinate)
        XCTAssertEqual(response.itinerary.count, 1)
        XCTAssertEqual(response.itinerary.first?.items.count, 2)
    }

    /// A round-trip encode/decode preserves the travel cards.
    func testTravelCardsRoundTrip() throws {
        let card = CoachTravelCard(kind: .restaurant, title: "Narisawa", price: 250, currency: "USD", rating: 4.8)
        let response = CoachResponse(
            responseType: .insight, title: "Dinner", summary: "A great option.",
            travelCards: [card],
            itinerary: [CoachItineraryDay(dayOffset: 1, label: "Day 2", items: ["Dinner at Narisawa"])]
        )
        let json = try XCTUnwrap(response.encodedJSON())
        let decoded = try XCTUnwrap(CoachResponse.decode(fromJSON: json))
        XCTAssertEqual(decoded.travelCards.first?.title, "Narisawa")
        XCTAssertEqual(decoded.travelCards.first?.kind, .restaurant)
        XCTAssertEqual(decoded.itinerary.first?.dayOffset, 1)
    }

    /// The strict schema advertises travel_cards + itinerary and keeps them required.
    func testSchemaIncludesTravelCards() throws {
        let schema = CoachResponseSchema.jsonSchema
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertNotNil(properties["travel_cards"])
        XCTAssertNotNil(properties["itinerary"])
        let required = try XCTUnwrap(schema["required"] as? [String])
        XCTAssertTrue(required.contains("travel_cards"))
        XCTAssertTrue(required.contains("itinerary"))
    }

    /// prepare_travel_cards echoes the authored cards for verbatim copy.
    func testPrepareTravelCardsTool() async throws {
        let c = try TestSupport.makeContext()
        let tool = try XCTUnwrap(TravelTools.readTools.first { $0.name == "prepare_travel_cards" })
        let args = Data(#"""
        {"cards":[{"kind":"activity","title":"teamLab Planets","subtitle":null,"price":35,"currency":"USD","time":null,"location":"Toyosu","rating":4.5,"thumbnail_url":null,"booking_url":null,"latitude":null,"longitude":null}],"itinerary":[{"day_offset":1,"label":null,"items":["teamLab Planets"]}]}
        """#.utf8)
        let result = try await tool.run(args, ToolExecutionContext(modelContext: c, flags: writeFlags()))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.jsonString.utf8)) as? [String: Any])
        let cards = try XCTUnwrap(obj["travel_cards"] as? [[String: Any]])
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?["title"] as? String, "teamLab Planets")
        XCTAssertEqual(cards.first?["kind"] as? String, "activity")
    }

    /// Saving a chat card persists a TripItem (creating a trip when none exists).
    func testSaveTravelCardPersistsTripItem() throws {
        let c = try TestSupport.makeContext()
        let vm = CoachViewModel()
        let card = CoachTravelCard(
            kind: .lodging, title: "Hotel Eden", subtitle: "Rome",
            price: 600, currency: "USD", location: "Via Ludovisi", rating: 4.8,
            bookingURL: "https://example.com", latitude: 41.9078, longitude: 12.4880
        )
        vm.saveTravelCard(card, context: c)

        let trips = try c.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(trips.count, 1)
        let items = try c.fetch(FetchDescriptor<TripItem>())
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.kind, .lodging)
        XCTAssertEqual(item.title, "Hotel Eden")
        XCTAssertEqual(item.price, 600)
        XCTAssertEqual(item.rating, 4.8)
        XCTAssertEqual(item.latitude, 41.9078)

        // Saving a second card reuses the same active trip.
        vm.saveTravelCard(CoachTravelCard(kind: .flight, title: "AZ611"), context: c)
        XCTAssertEqual(try c.fetch(FetchDescriptor<Trip>()).count, 1)
        XCTAssertEqual(try c.fetch(FetchDescriptor<TripItem>()).count, 2)
    }
}
