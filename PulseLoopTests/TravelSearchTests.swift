import Foundation
import XCTest
import SwiftData
@testable import PulseLoop

// MARK: - Live travel-search layer tests (Travel+ T8)
//
// Covers the pure pieces of the live-data layer with no real network:
//   - TravelSearchConfig placeholder gating
//   - Amadeus request building + token/flight JSON parsing + duration formatting
//   - TravelSearchResult ↔ CoachTravelCard / tool-dictionary mapping
//   - search_flights / search_places coach tools degrading gracefully via a stub
@MainActor
final class TravelSearchTests: XCTestCase {

    // MARK: Config gating

    func testConfigTreatsPlaceholdersAsUnset() {
        XCTAssertTrue(TravelSearchConfig.isPlaceholder(""))
        XCTAssertTrue(TravelSearchConfig.isPlaceholder("REPLACE_WITH_YOUR_AMADEUS_CLIENT_ID"))
        XCTAssertTrue(TravelSearchConfig.isPlaceholder("YOUR_KEY"))
        XCTAssertTrue(TravelSearchConfig.isPlaceholder("REPLACE_ME"))
        XCTAssertFalse(TravelSearchConfig.isPlaceholder("abc123realkey"))
    }

    // MARK: Amadeus request building

    func testAmadeusTokenRequestIsFormEncodedPost() {
        let provider = AmadeusFlightProvider(
            clientID: "id123",
            clientSecret: "secret456",
            baseURL: URL(string: "https://test.api.amadeus.com")!
        )
        let req = provider.tokenRequest()
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.absoluteString, "https://test.api.amadeus.com/v1/security/oauth2/token")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("grant_type=client_credentials"))
        XCTAssertTrue(body.contains("client_id=id123"))
        XCTAssertTrue(body.contains("client_secret=secret456"))
    }

    func testAmadeusFlightRequestBuildsQuery() throws {
        let provider = AmadeusFlightProvider(clientID: "id", clientSecret: "s")
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 3
        let dep = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: comps))
        let query = FlightSearchQuery(origin: "sfo", destination: "hnd", departureDate: dep, adults: 2, currency: "usd")

        let req = provider.flightRequest(query, token: "tok")
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let url = try XCTUnwrap(req.url)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["originLocationCode"], "SFO")
        XCTAssertEqual(dict["destinationLocationCode"], "HND")
        XCTAssertEqual(dict["departureDate"], "2026-10-03")
        XCTAssertEqual(dict["adults"], "2")
        XCTAssertEqual(dict["currencyCode"], "USD")
        XCTAssertNil(dict["returnDate"])
    }

    func testAmadeusFlightRequestIncludesReturnDate() throws {
        let provider = AmadeusFlightProvider(clientID: "id", clientSecret: "s")
        let cal = Calendar(identifier: .gregorian)
        let dep = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 3)))
        let ret = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 9)))
        let query = FlightSearchQuery(origin: "SFO", destination: "HND", departureDate: dep, returnDate: ret)
        let url = try XCTUnwrap(provider.flightRequest(query, token: "t").url)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["returnDate"], "2026-10-09")
    }

    // MARK: Amadeus parsing

    func testParseTokenReadsAccessTokenAndTTL() throws {
        let provider = AmadeusFlightProvider(clientID: "id", clientSecret: "s")
        let json = #"{"access_token":"abc.def","expires_in":1799,"token_type":"Bearer"}"#
        let parsed = try provider.parseToken(Data(json.utf8))
        XCTAssertEqual(parsed.token, "abc.def")
        XCTAssertEqual(parsed.expiresIn, 1799)
    }

    func testParseTokenThrowsOnGarbage() {
        let provider = AmadeusFlightProvider(clientID: "id", clientSecret: "s")
        XCTAssertThrowsError(try provider.parseToken(Data("not json".utf8))) {
            XCTAssertEqual($0 as? TravelSearchError, .decoding)
        }
    }

    func testParseFlightsMapsOffers() throws {
        let provider = AmadeusFlightProvider(clientID: "id", clientSecret: "s")
        let json = """
        {"data":[
          {"itineraries":[{"duration":"PT11H20M","segments":[
              {"carrierCode":"UA","departure":{"iataCode":"SFO"},"arrival":{"iataCode":"HND"}}
          ]}],
           "price":{"grandTotal":"912.34","currency":"USD"}},
          {"itineraries":[{"duration":"PT14H05M","segments":[
              {"carrierCode":"NH","departure":{"iataCode":"SFO"},"arrival":{"iataCode":"NRT"}},
              {"carrierCode":"NH","departure":{"iataCode":"NRT"},"arrival":{"iataCode":"HND"}}
          ]}],
           "price":{"total":"640.00","currency":"USD"}}
        ]}
        """
        let cal = Calendar(identifier: .gregorian)
        let dep = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 3)))
        let query = FlightSearchQuery(origin: "SFO", destination: "HND", departureDate: dep)
        let results = try provider.parseFlights(Data(json.utf8), query: query)

        XCTAssertEqual(results.count, 2)
        let nonstop = results[0]
        XCTAssertEqual(nonstop.kind, .flight)
        XCTAssertEqual(nonstop.price, 912.34)
        XCTAssertEqual(nonstop.currency, "USD")
        XCTAssertTrue(nonstop.title.contains("UA"))
        XCTAssertEqual(nonstop.time, "Nonstop · 11h 20m")

        let oneStop = results[1]
        XCTAssertEqual(oneStop.price, 640.0)
        XCTAssertEqual(oneStop.time, "1 stop · 14h 05m")
        XCTAssertEqual(oneStop.location, "SFO → HND")
    }

    func testParseFlightsThrowsNoResultsOnEmpty() {
        let provider = AmadeusFlightProvider(clientID: "id", clientSecret: "s")
        let cal = Calendar(identifier: .gregorian)
        let dep = cal.date(from: DateComponents(year: 2026, month: 10, day: 3))!
        let query = FlightSearchQuery(origin: "SFO", destination: "HND", departureDate: dep)
        XCTAssertThrowsError(try provider.parseFlights(Data(#"{"data":[]}"#.utf8), query: query)) {
            XCTAssertEqual($0 as? TravelSearchError, .noResults)
        }
    }

    func testPrettyDuration() {
        XCTAssertEqual(AmadeusFlightProvider.prettyDuration("PT11H20M"), "11h 20m")
        XCTAssertEqual(AmadeusFlightProvider.prettyDuration("PT2H"), "2h")
        XCTAssertEqual(AmadeusFlightProvider.prettyDuration("PT45M"), "45m")
        XCTAssertEqual(AmadeusFlightProvider.prettyDuration("garbage"), "garbage")
    }

    func testUnconfiguredAmadeusThrowsNotConfigured() async {
        let provider = AmadeusFlightProvider(clientID: "REPLACE_ME", clientSecret: "REPLACE_ME")
        let cal = Calendar(identifier: .gregorian)
        let dep = cal.date(from: DateComponents(year: 2026, month: 10, day: 3))!
        let query = FlightSearchQuery(origin: "SFO", destination: "HND", departureDate: dep)
        do {
            _ = try await provider.searchFlights(query)
            XCTFail("expected notConfigured")
        } catch {
            XCTAssertEqual(error as? TravelSearchError, .notConfigured)
        }
    }

    // MARK: Result mapping

    func testResultMapsToCoachCardAndDictionary() {
        let r = TravelSearchResult(
            kind: .lodging, title: "Park Hyatt", subtitle: "Shinjuku",
            price: 380, currency: "USD", time: "Fri–Sun", location: "Tokyo",
            rating: 4.8, bookingURL: "https://hyatt.com", thumbnailURL: nil,
            latitude: 35.685, longitude: 139.69
        )
        let card = r.asCoachCard
        XCTAssertEqual(card.kind, .lodging)
        XCTAssertEqual(card.title, "Park Hyatt")
        XCTAssertEqual(card.price, 380)
        XCTAssertEqual(card.latitude, 35.685)

        let d = r.asDictionary
        XCTAssertEqual(d["kind"] as? String, "lodging")
        XCTAssertEqual(d["title"] as? String, "Park Hyatt")
        XCTAssertEqual(d["price"] as? Double, 380)
        XCTAssertEqual(d["booking_url"] as? String, "https://hyatt.com")
        XCTAssertEqual(d["rating"] as? Double, 4.8)
        XCTAssertNil(d["thumbnail_url"])
    }

    // MARK: Coach-tool integration via a stub provider

    /// Returns canned results / errors so the tools can be exercised offline.
    struct StubProvider: TravelSearchProvider {
        var flights: Result<[TravelSearchResult], Error>
        var places: Result<[TravelSearchResult], Error>
        func searchFlights(_ query: FlightSearchQuery) async throws -> [TravelSearchResult] {
            try flights.get()
        }
        func searchPlaces(_ query: PlaceSearchQuery) async throws -> [TravelSearchResult] {
            try places.get()
        }
    }

    private func tool(_ name: String) throws -> AnyCoachTool {
        let all = TravelTools.readTools + TravelTools.writeTools
        return try XCTUnwrap(all.first { $0.name == name }, "missing tool \(name)")
    }

    private func parse(_ result: ToolResult) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.jsonString.utf8)) as? [String: Any])
    }

    private func readCtx(_ c: ModelContext) -> ToolExecutionContext {
        ToolExecutionContext(modelContext: c, flags: CoachFeatureFlags(settings: .default, hasAPIKey: true))
    }

    func testSearchFlightsToolReturnsOptions() async throws {
        let original = TravelTools.searchProvider
        defer { TravelTools.searchProvider = original }
        TravelTools.searchProvider = StubProvider(
            flights: .success([
                TravelSearchResult(kind: .flight, title: "UA · SFO → HND", subtitle: "SFO → HND",
                                   price: 912, currency: "USD", time: "Nonstop · 11h 20m", location: "SFO → HND")
            ]),
            places: .success([])
        )
        let c = try TestSupport.makeContext()
        let out = try parse(try await tool("search_flights").run(
            Data(#"{"origin":"SFO","destination":"HND","departure_date":"2026-10-03","return_date":null,"adults":1,"currency":"USD"}"#.utf8),
            readCtx(c)
        ))
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(out["configured"] as? Bool, true)
        XCTAssertEqual(out["count"] as? Int, 1)
        let options = try XCTUnwrap(out["options"] as? [[String: Any]])
        XCTAssertEqual(options.first?["kind"] as? String, "flight")
    }

    func testSearchFlightsToolReportsNotConfigured() async throws {
        let original = TravelTools.searchProvider
        defer { TravelTools.searchProvider = original }
        TravelTools.searchProvider = StubProvider(
            flights: .failure(TravelSearchError.notConfigured), places: .success([]))
        let c = try TestSupport.makeContext()
        let out = try parse(try await tool("search_flights").run(
            Data(#"{"origin":"SFO","destination":"HND","departure_date":"2026-10-03","return_date":null,"adults":1,"currency":"USD"}"#.utf8),
            readCtx(c)
        ))
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(out["configured"] as? Bool, false)
        XCTAssertEqual(out["count"] as? Int, 0)
        XCTAssertTrue((out["note"] as? String ?? "").contains("web_search"))
    }

    func testSearchFlightsToolRejectsBadDate() async throws {
        let c = try TestSupport.makeContext()
        let out = try parse(try await tool("search_flights").run(
            Data(#"{"origin":"SFO","destination":"HND","departure_date":"not-a-date","return_date":null,"adults":1,"currency":"USD"}"#.utf8),
            readCtx(c)
        ))
        XCTAssertNotNil(out["error"])
    }

    func testSearchPlacesToolReturnsOptions() async throws {
        let original = TravelTools.searchProvider
        defer { TravelTools.searchProvider = original }
        TravelTools.searchProvider = StubProvider(
            flights: .success([]),
            places: .success([
                TravelSearchResult(kind: .restaurant, title: "Ichiran Ramen", subtitle: nil,
                                   price: nil, currency: nil, time: nil, location: "Shinjuku",
                                   rating: 4.5, latitude: 35.69, longitude: 139.70)
            ])
        )
        let c = try TestSupport.makeContext()
        let out = try parse(try await tool("search_places").run(
            Data(#"{"kind":"restaurant","query":"ramen","near":"Shinjuku, Tokyo","limit":6}"#.utf8),
            readCtx(c)
        ))
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(out["count"] as? Int, 1)
        let options = try XCTUnwrap(out["options"] as? [[String: Any]])
        XCTAssertEqual(options.first?["title"] as? String, "Ichiran Ramen")
    }

    func testSearchPlacesToolRejectsBadKind() async throws {
        let c = try TestSupport.makeContext()
        let out = try parse(try await tool("search_places").run(
            Data(#"{"kind":"spaceship","query":"x","near":"y","limit":6}"#.utf8),
            readCtx(c)
        ))
        XCTAssertNotNil(out["error"])
    }
}
