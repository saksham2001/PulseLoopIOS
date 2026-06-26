import Foundation
import MapKit
import CoreLocation

// MARK: - Apple Maps places provider (Travel+ T8)
//
// Keyless stays/activities/restaurants/transport search via MapKit `MKLocalSearch`.
// Works without any API key, so it's the reliable default for places. Returns real,
// tappable POIs with coordinates and (when Apple provides it) a phone/website.
//
// Flights aren't a MapKit concept, so `searchFlights` throws `.notConfigured`.
struct AppleMapsPlaceProvider: TravelSearchProvider {

    func searchFlights(_ query: FlightSearchQuery) async throws -> [TravelSearchResult] {
        throw TravelSearchError.notConfigured  // handled by a flight provider
    }

    func searchPlaces(_ query: PlaceSearchQuery) async throws -> [TravelSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(query.query) in \(query.near)"
        request.resultTypes = [.pointOfInterest]

        let search = MKLocalSearch(request: request)
        let response: MKLocalSearch.Response
        do {
            response = try await search.start()
        } catch {
            throw TravelSearchError.noResults
        }

        let items = response.mapItems.prefix(max(1, query.limit))
        let results: [TravelSearchResult] = items.map { item in
            let placemark = item.placemark
            let locality = [placemark.thoroughfare, placemark.locality]
                .compactMap { $0 }
                .joined(separator: ", ")
            return TravelSearchResult(
                kind: query.kind,
                title: item.name ?? query.query.capitalized,
                subtitle: item.pointOfInterestCategory.map { Self.categoryLabel($0) },
                price: nil,
                currency: nil,
                time: nil,
                location: locality.isEmpty ? query.near : locality,
                rating: nil,
                bookingURL: item.url?.absoluteString,
                thumbnailURL: nil,
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude
            )
        }
        if results.isEmpty { throw TravelSearchError.noResults }
        return results
    }

    /// A friendly label for an Apple POI category (best-effort, falls back to nil-ish).
    static func categoryLabel(_ category: MKPointOfInterestCategory) -> String {
        switch category {
        case .restaurant: return "Restaurant"
        case .cafe: return "Café"
        case .hotel: return "Hotel"
        case .museum: return "Museum"
        case .nationalPark, .park: return "Park"
        case .nightlife: return "Nightlife"
        case .store: return "Shopping"
        case .theater: return "Theater"
        case .winery: return "Winery"
        case .aquarium: return "Aquarium"
        case .zoo: return "Zoo"
        case .beach: return "Beach"
        default: return "Point of interest"
        }
    }
}
