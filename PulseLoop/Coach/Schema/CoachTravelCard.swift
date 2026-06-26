import Foundation

/// A single travel result rendered inline in the chat (a flight, stay, activity,
/// restaurant, or transport option) — the same shape that backs a `TripItem` on
/// the Travel screen, so "one shape, two surfaces". Copied verbatim by the model
/// from a `prepare_travel_cards` tool result into `CoachResponse.travelCards`.
///
/// Lenient decoding (snake_case on the wire) so an off-spec payload never breaks
/// the whole reply.
struct CoachTravelCard: Codable, Equatable, Identifiable {
    var kind: CoachTravelCardKind
    var title: String
    var subtitle: String?
    /// Free-text price label is avoided; numeric price + ISO currency so we format
    /// consistently and can roll it up when saved to a trip.
    var price: Double?
    var currency: String?
    /// Human time/when label (e.g. "Sat, Oct 3 · 10:45 AM" or "Nonstop · 11h 20m").
    var time: String?
    var location: String?
    /// Rating out of 5 (e.g. 4.6) for stays/activities/restaurants.
    var rating: Double?
    var thumbnailURL: String?
    var bookingURL: String?
    var latitude: Double?
    var longitude: Double?

    var id: String { kind.rawValue + title + (time ?? "") + (location ?? "") }

    enum CodingKeys: String, CodingKey {
        case kind, title, subtitle, price, currency, time, location, rating
        case thumbnailURL = "thumbnail_url"
        case bookingURL = "booking_url"
        case latitude, longitude
    }

    init(
        kind: CoachTravelCardKind,
        title: String,
        subtitle: String? = nil,
        price: Double? = nil,
        currency: String? = nil,
        time: String? = nil,
        location: String? = nil,
        rating: Double? = nil,
        thumbnailURL: String? = nil,
        bookingURL: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.price = price
        self.currency = currency
        self.time = time
        self.location = location
        self.rating = rating
        self.thumbnailURL = thumbnailURL
        self.bookingURL = bookingURL
        self.latitude = latitude
        self.longitude = longitude
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(CoachTravelCardKind.self, forKey: .kind) ?? .activity
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        price = try c.decodeIfPresent(Double.self, forKey: .price)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        time = try c.decodeIfPresent(String.self, forKey: .time)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        thumbnailURL = try c.decodeIfPresent(String.self, forKey: .thumbnailURL)
        bookingURL = try c.decodeIfPresent(String.self, forKey: .bookingURL)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
    }

    var resolvedThumbnail: URL? { thumbnailURL.flatMap(URL.init(string:)) }
    var resolvedBookingURL: URL? { bookingURL.flatMap(URL.init(string:)) }
    var hasCoordinate: Bool { latitude != nil && longitude != nil }
}

/// Travel card modality — mirrors `TripItemKind` so a chat card maps 1:1 to a
/// saved `TripItem`.
enum CoachTravelCardKind: String, Codable, Equatable, CaseIterable {
    case flight, lodging, activity, restaurant, transport

    /// SF Symbol for the card (design-system: SF Symbols only, no emoji).
    var icon: String {
        switch self {
        case .flight: return "airplane"
        case .lodging: return "bed.double.fill"
        case .activity: return "figure.walk"
        case .restaurant: return "fork.knife"
        case .transport: return "tram.fill"
        }
    }

    var label: String {
        switch self {
        case .flight: return "Flight"
        case .lodging: return "Stay"
        case .activity: return "Activity"
        case .restaurant: return "Restaurant"
        case .transport: return "Transport"
        }
    }

    /// The `TripItemKind` this card persists as when saved to a trip.
    var tripItemKindRaw: String { rawValue }
}

/// One day of a proposed itinerary, grouping a few card titles under a day label.
/// Rendered as a compact day list in chat.
struct CoachItineraryDay: Codable, Equatable, Identifiable {
    var dayOffset: Int
    var label: String?
    var items: [String]

    var id: Int { dayOffset }

    enum CodingKeys: String, CodingKey {
        case dayOffset = "day_offset"
        case label, items
    }

    init(dayOffset: Int, label: String? = nil, items: [String] = []) {
        self.dayOffset = dayOffset
        self.label = label
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayOffset = try c.decodeIfPresent(Int.self, forKey: .dayOffset) ?? 0
        label = try c.decodeIfPresent(String.self, forKey: .label)
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
    }

    var displayLabel: String { label ?? "Day \(dayOffset + 1)" }
}
