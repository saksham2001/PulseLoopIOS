import Foundation

// MARK: - Live travel search facade (Travel+ T8)
//
// Picks the right provider per query type and degrades gracefully:
//   - Flights → Amadeus when configured, else throws `.notConfigured` so the caller
//     (coach) falls back to web_search.
//   - Places  → Apple MapKit (keyless), always available.
//
// Injectable providers keep the facade unit-testable.
struct LiveTravelSearch: TravelSearchProvider {
    private let flightProvider: TravelSearchProvider
    private let placeProvider: TravelSearchProvider

    init(
        flightProvider: TravelSearchProvider = AmadeusFlightProvider(),
        placeProvider: TravelSearchProvider = AppleMapsPlaceProvider()
    ) {
        self.flightProvider = flightProvider
        self.placeProvider = placeProvider
    }

    /// Whether live flight search is available (real Amadeus credentials present).
    var isFlightSearchConfigured: Bool { TravelSearchConfig.isAmadeusConfigured }

    func searchFlights(_ query: FlightSearchQuery) async throws -> [TravelSearchResult] {
        try await flightProvider.searchFlights(query)
    }

    func searchPlaces(_ query: PlaceSearchQuery) async throws -> [TravelSearchResult] {
        try await placeProvider.searchPlaces(query)
    }
}
