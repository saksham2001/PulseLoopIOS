import SwiftData
import Foundation

// MARK: - Travel module models
//
// A `Trip` is one planned journey (a destination + dates). Each `TripItem` is one
// concrete element of the plan — a flight, a place to stay (hotel/Airbnb), a thing
// to do, a restaurant, ground transport, or a free-form note. The coach fills
// these in by searching the live web for real options and saving the good ones, so
// the user ends up with an organized, bookable itinerary instead of a chat log.

@Model
final class Trip {
    @Attribute(.unique) var id: UUID
    /// Where the trip is to, e.g. "Tokyo, Japan".
    var destination: String
    /// Optional origin city for flight searches, e.g. "San Francisco".
    var originCity: String?
    var startDate: Date?
    var endDate: Date?
    var notes: String?
    var statusRaw: String
    /// Number of travelers on the trip (for flight/hotel sizing). Defaulted for
    /// lightweight migration.
    var travelerCount: Int = 1
    /// Optional overall budget for the trip and its currency (ISO code, e.g. "USD").
    var budgetAmount: Double?
    var budgetCurrency: String?
    /// Optional cover image URL (a representative photo of the destination).
    var coverImageURL: String?
    /// Optional cached destination facts (currency code, language, IANA time zone,
    /// and a short "good to know" tip), filled by the coach's `get_destination_info`
    /// tool. Additive + defaulted for lightweight migration.
    var destinationCurrency: String?
    var destinationLanguage: String?
    var destinationTimeZoneId: String?
    var destinationTip: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade) var items: [TripItem]

    var status: TripStatus {
        get { TripStatus(rawValue: statusRaw) ?? .planning }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        destination: String,
        originCity: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        notes: String? = nil,
        status: TripStatus = .planning,
        travelerCount: Int = 1,
        budgetAmount: Double? = nil,
        budgetCurrency: String? = nil,
        coverImageURL: String? = nil
    ) {
        self.id = id
        self.destination = destination
        self.originCity = originCity
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.statusRaw = status.rawValue
        self.travelerCount = travelerCount
        self.budgetAmount = budgetAmount
        self.budgetCurrency = budgetCurrency
        self.coverImageURL = coverImageURL
        self.createdAt = Date()
        self.updatedAt = Date()
        self.items = []
    }
}

@Model
final class TripItem {
    @Attribute(.unique) var id: UUID
    var tripId: UUID
    var kindRaw: String
    var title: String
    /// Free-form details — itinerary specifics, confirmation numbers, why it's a
    /// good pick, etc.
    var details: String?
    /// Where it is (address / neighborhood / airport codes like "SFO → HND").
    var location: String?
    /// A booking/info link found via web search.
    var url: String?
    var price: Double?
    var currency: String?
    var startAt: Date?
    var endAt: Date?
    /// Day of the trip this belongs to (0 = arrival day), for itinerary ordering.
    var dayOffset: Int?
    /// Whether the user has booked/confirmed this item.
    var booked: Bool
    /// Optional rating (e.g. 4.6) for activities/restaurants/lodging found via search.
    var rating: Double?
    /// Optional coordinates for map pins (lodging/activities/restaurants).
    var latitude: Double?
    var longitude: Double?
    /// Optional booking/reservation confirmation number once booked.
    var confirmationNumber: String?
    var order: Int
    var createdAt: Date

    var kind: TripItemKind {
        get { TripItemKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        tripId: UUID,
        kind: TripItemKind,
        title: String,
        details: String? = nil,
        location: String? = nil,
        url: String? = nil,
        price: Double? = nil,
        currency: String? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        dayOffset: Int? = nil,
        booked: Bool = false,
        rating: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        confirmationNumber: String? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.tripId = tripId
        self.kindRaw = kind.rawValue
        self.title = title
        self.details = details
        self.location = location
        self.url = url
        self.price = price
        self.currency = currency
        self.startAt = startAt
        self.endAt = endAt
        self.dayOffset = dayOffset
        self.booked = booked
        self.rating = rating
        self.latitude = latitude
        self.longitude = longitude
        self.confirmationNumber = confirmationNumber
        self.order = order
        self.createdAt = Date()
    }
}

enum TripStatus: String, Codable, CaseIterable {
    case planning, booked, completed, cancelled
}

enum TripItemKind: String, Codable, CaseIterable, Identifiable {
    case flight, lodging, activity, restaurant, transport, note

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .flight: return "airplane"
        case .lodging: return "bed.double.fill"
        case .activity: return "figure.walk"
        case .restaurant: return "fork.knife"
        case .transport: return "tram.fill"
        case .note: return "note.text"
        }
    }

    var label: String {
        switch self {
        case .flight: return "Flights"
        case .lodging: return "Stay"
        case .activity: return "Things to do"
        case .restaurant: return "Food"
        case .transport: return "Getting around"
        case .note: return "Notes"
        }
    }
}

// MARK: - Budget rollup

extension Trip {
    /// The trip's effective currency for display: explicit budget currency, else the
    /// most common item currency, else "USD".
    var effectiveCurrency: String {
        if let c = budgetCurrency, !c.isEmpty { return c }
        let counts = Dictionary(grouping: items.compactMap { $0.currency?.uppercased() }, by: { $0 })
            .mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key ?? "USD"
    }

    /// Total estimated cost = sum of all item prices that have a value.
    var estimatedCost: Double { items.compactMap(\.price).reduce(0, +) }

    /// Total cost of items the user has marked booked.
    var bookedCost: Double { items.filter(\.booked).compactMap(\.price).reduce(0, +) }

    /// Per-category (kind) estimated spend, only for kinds with any priced items.
    var costByKind: [(TripItemKind, Double)] {
        TripItemKind.allCases.compactMap { kind in
            let total = items.filter { $0.kind == kind }.compactMap(\.price).reduce(0, +)
            return total > 0 ? (kind, total) : nil
        }
    }
}

// MARK: - Destination info

extension Trip {
    /// Whether any destination facts have been captured for this trip.
    var hasDestinationInfo: Bool {
        destinationCurrency?.isEmpty == false
            || destinationLanguage?.isEmpty == false
            || destinationTimeZoneId?.isEmpty == false
            || destinationTip?.isEmpty == false
    }

    /// A human-readable time-zone difference vs the user's current zone, e.g.
    /// "+9h from you" or "Same time as you". Returns nil when the destination zone
    /// is unknown/unresolvable so the UI can simply omit the row.
    var timeZoneDeltaDescription: String? {
        guard let id = destinationTimeZoneId, let tz = TimeZone(identifier: id) else { return nil }
        let now = Date()
        let deltaSeconds = tz.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)
        let hours = Double(deltaSeconds) / 3600.0
        if abs(hours) < 0.01 { return "Same time as you" }
        let rounded = (hours * 10).rounded() / 10
        let sign = rounded > 0 ? "+" : "−"
        let mag = abs(rounded)
        let magText = mag.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(mag)) : String(format: "%.1f", mag)
        return "\(sign)\(magText)h from you"
    }
}
