import Foundation
import CoreLocation

// MARK: - Live travel search (Travel+ T8)
//
// A networked travel-data layer behind a testable seam. Every provider takes an
// injectable `HTTPTransport` (default `URLSession.shared`) so request-building and
// response-parsing are unit-testable with a stub, mirroring the wearables layer.
//
// API keys are read from Info.plist and gated by `isConfigured` (placeholders like
// `REPLACE_*` / `YOUR_*` are rejected) so the app degrades gracefully when a key is
// missing — it never crashes and falls back to keyless sources (Apple MapKit) or to
// the coach's web_search.

/// One normalized travel option. Maps 1:1 onto a `CoachTravelCard` and `TripItem`
/// so a searched result can be shown as a chat card and saved into a trip.
struct TravelSearchResult: Equatable, Sendable {
    enum Kind: String, Sendable { case flight, lodging, activity, restaurant, transport }

    var kind: Kind
    var title: String
    var subtitle: String?
    var price: Double?
    var currency: String?
    /// Human "when"/time label (e.g. "Nonstop · 11h 20m" or "Sat, Oct 3").
    var time: String?
    var location: String?
    var rating: Double?
    var bookingURL: String?
    var thumbnailURL: String?
    var latitude: Double?
    var longitude: Double?

    /// As the chat-card shape (verbatim into `CoachResponse.travelCards`).
    var asCoachCard: CoachTravelCard {
        CoachTravelCard(
            kind: CoachTravelCardKind(rawValue: kind.rawValue) ?? .activity,
            title: title,
            subtitle: subtitle,
            price: price,
            currency: currency,
            time: time,
            location: location,
            rating: rating,
            thumbnailURL: thumbnailURL,
            bookingURL: bookingURL,
            latitude: latitude,
            longitude: longitude
        )
    }

    /// As a tool-output dictionary (snake_case) the model copies into prepare_travel_cards.
    var asDictionary: [String: Any] {
        var d: [String: Any] = ["kind": kind.rawValue, "title": title]
        if let v = subtitle { d["subtitle"] = v }
        if let v = price { d["price"] = v }
        if let v = currency { d["currency"] = v }
        if let v = time { d["time"] = v }
        if let v = location { d["location"] = v }
        if let v = rating { d["rating"] = v }
        if let v = bookingURL { d["booking_url"] = v }
        if let v = thumbnailURL { d["thumbnail_url"] = v }
        if let v = latitude { d["latitude"] = v }
        if let v = longitude { d["longitude"] = v }
        return d
    }
}

/// A request to search flights between two places on a date.
struct FlightSearchQuery: Equatable, Sendable {
    var origin: String        // IATA code or city, e.g. "SFO"
    var destination: String   // IATA code or city, e.g. "HND"
    var departureDate: Date
    var returnDate: Date?
    var adults: Int = 1
    var currency: String = "USD"
}

/// A request to search places (stays, activities, restaurants) near a location.
struct PlaceSearchQuery: Equatable, Sendable {
    var kind: TravelSearchResult.Kind
    /// Free-text "what" (e.g. "ramen", "boutique hotel", "art museum").
    var query: String
    /// Free-text "where" (e.g. "Shinjuku, Tokyo").
    var near: String
    var limit: Int = 6
}

/// Errors a provider can surface; callers degrade gracefully on `.notConfigured`.
enum TravelSearchError: Error, Equatable {
    case notConfigured
    case badResponse(Int)
    case decoding
    case noResults
}

/// Abstraction over the live travel data sources. Concrete providers implement the
/// methods they support; unsupported ones throw `.notConfigured` so the facade can
/// fall back.
protocol TravelSearchProvider: Sendable {
    func searchFlights(_ query: FlightSearchQuery) async throws -> [TravelSearchResult]
    func searchPlaces(_ query: PlaceSearchQuery) async throws -> [TravelSearchResult]
}
