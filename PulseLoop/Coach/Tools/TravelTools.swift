import Foundation
import SwiftData

// MARK: - Travel Coach Tools (Trips · Flights · Lodging · Activities)
//
// These tools let the coach turn a travel request into an organized itinerary.
// The *searching* (real flights, hotels, Airbnbs, things to do, restaurants) is
// done with the hosted web_search tool; these tools then SAVE the chosen options
// into a Trip as structured items the user can review, price out, and book.
//
// Reads are always on; writes gated by `flags.writeToolsEnabled`. Additive writes
// (create trip, add item, toggle booked, edit fields) apply immediately. Destructive
// writes — removing an item or archiving a whole trip — queue a Confirm/Cancel card
// (PendingAction) like tasks/notes, so the user approves them first.
@MainActor
enum TravelTools {
    static var readTools: [AnyCoachTool] {
        [listTrips, getTrip, prepareTravelCards, searchFlights, searchPlaces, listRewardCards, valueWithPoints]
    }
    static var writeTools: [AnyCoachTool] {
        [createTrip, updateTrip, addTripItem, updateTripItem, setTripItemBooked, deleteTripItem, createTripChecklist, createTripNote, createPackingList, setDestinationInfo, addRewardCard]
    }

    /// Live travel-data source for `search_flights` / `search_places`. Overridable in
    /// tests to inject a stubbed provider (no network).
    static var searchProvider: TravelSearchProvider = LiveTravelSearch()

    private static let isoDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f
    }()
    private static let isoDateTime = ISO8601DateFormatter()

    private static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return isoDateTime.date(from: s) ?? isoDate.date(from: s)
    }

    private static func trips(_ ctx: ToolExecutionContext) -> [Trip] {
        (try? ctx.modelContext.fetch(FetchDescriptor<Trip>())) ?? []
    }

    private static func trip(_ id: String, _ ctx: ToolExecutionContext) -> Trip? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return trips(ctx).first { $0.id == uuid }
    }

    private static func itemDict(_ i: TripItem) -> [String: Any] {
        var d: [String: Any] = [
            "id": i.id.uuidString,
            "kind": i.kindRaw,
            "title": i.title,
            "booked": i.booked,
        ]
        if let v = i.details { d["details"] = v }
        if let v = i.location { d["location"] = v }
        if let v = i.url { d["url"] = v }
        if let v = i.price { d["price"] = v }
        if let v = i.currency { d["currency"] = v }
        if let v = i.startAt { d["start_at"] = isoDateTime.string(from: v) }
        if let v = i.endAt { d["end_at"] = isoDateTime.string(from: v) }
        if let v = i.dayOffset { d["day_offset"] = v }
        if let v = i.rating { d["rating"] = v }
        if let v = i.latitude { d["latitude"] = v }
        if let v = i.longitude { d["longitude"] = v }
        if let v = i.confirmationNumber { d["confirmation_number"] = v }
        return d
    }

    private static func tripSummary(_ t: Trip) -> [String: Any] {
        var d: [String: Any] = [
            "id": t.id.uuidString,
            "destination": t.destination,
            "status": t.statusRaw,
            "item_count": t.items.count,
        ]
        if let v = t.originCity { d["origin"] = v }
        if let v = t.startDate { d["start_date"] = isoDate.string(from: v) }
        if let v = t.endDate { d["end_date"] = isoDate.string(from: v) }
        d["traveler_count"] = t.travelerCount
        if let v = t.budgetAmount { d["budget_amount"] = v }
        d["budget_currency"] = t.effectiveCurrency
        d["estimated_cost"] = t.estimatedCost
        return d
    }

    // MARK: - Reads

    private static var listTrips: AnyCoachTool {
        .make(
            name: "list_trips",
            label: "Reviewing your trips",
            description: "List the user's trips with id, destination, dates, status, and item count. Use this to find a trip id before reading or editing it.",
            parameters: JSONSchema.empty,
            argsType: NoArgs.self
        ) { _, ctx in
            let rows = trips(ctx)
                .sorted { ($0.startDate ?? $0.createdAt) > ($1.startDate ?? $1.createdAt) }
                .map(tripSummary)
            return .object(["trips": rows, "count": rows.count])
        }
    }

    private static var getTrip: AnyCoachTool {
        struct Args: Decodable { let tripId: String; enum CodingKeys: String, CodingKey { case tripId = "trip_id" } }
        return .make(
            name: "get_trip",
            label: "Opening your trip",
            description: "Get one trip's full itinerary: its details plus every saved item (flights, lodging, activities, restaurants, transport, notes) with ids for editing.",
            parameters: JSONSchema.object(["trip_id": JSONSchema.string], required: ["trip_id"]),
            argsType: Args.self
        ) { args, ctx in
            guard let t = trip(args.tripId, ctx) else {
                return .error("trip '\(args.tripId)' not found. Call list_trips.")
            }
            var out = tripSummary(t)
            out["notes"] = t.notes ?? ""
            out["items"] = t.items.sorted {
                ($0.dayOffset ?? 0, $0.order, $0.createdAt) < ($1.dayOffset ?? 0, $1.order, $1.createdAt)
            }.map(itemDict)
            return .object(out)
        }
    }

    // MARK: - prepare_travel_cards (render results inline in chat)

    private struct TravelCardArg: Decodable {
        let kind: String
        let title: String
        let subtitle: String?
        let price: Double?
        let currency: String?
        let time: String?
        let location: String?
        let rating: Double?
        let thumbnailUrl: String?
        let bookingUrl: String?
        let latitude: Double?
        let longitude: Double?
        enum CodingKeys: String, CodingKey {
            case kind, title, subtitle, price, currency, time, location, rating
            case thumbnailUrl = "thumbnail_url", bookingUrl = "booking_url", latitude, longitude
        }
    }

    private struct ItineraryDayArg: Decodable {
        let dayOffset: Int?
        let label: String?
        let items: [String]?
        enum CodingKeys: String, CodingKey { case dayOffset = "day_offset", label, items }
    }

    private struct PrepareCardsArgs: Decodable {
        let cards: [TravelCardArg]
        let itinerary: [ItineraryDayArg]?
    }

    private struct PreparedTravelCards: Encodable {
        let travelCards: [CoachTravelCard]
        let itinerary: [CoachItineraryDay]
        let note: String
        enum CodingKeys: String, CodingKey { case travelCards = "travel_cards", itinerary, note }
    }

    private static var prepareTravelCards: AnyCoachTool {
        .make(
            name: "prepare_travel_cards",
            label: "Showing travel options",
            description: """
            Render real travel options as rich cards INLINE in the chat. Use this after web_search when the user is planning travel — turn the flights, stays (hotels/Airbnbs), activities, and restaurants you found into cards the user can see and tap "Save to trip" on. \
            Each card: kind (flight/lodging/activity/restaurant/transport), a clear title (e.g. "United UA837 SFO→HND" or "Park Hyatt Tokyo"), optional subtitle, numeric price (+currency ISO code), a human time/when label, location, rating out of 5 for places, thumbnail_url and booking_url when known, and latitude/longitude when known so it can map. \
            Optionally include an `itinerary` outline (one entry per day with day_offset, label, and short item strings). \
            Returns travel_cards and itinerary objects to COPY VERBATIM into the final response's `travel_cards` and `itinerary` fields. Set response_type to "insight". Do NOT also dump the same options as plain text — the cards are the presentation.
            """,
            parameters: JSONSchema.object([
                "cards": JSONSchema.array(JSONSchema.object([
                    "kind": JSONSchema.enumString(CoachTravelCardKind.allCases.map(\.rawValue)),
                    "title": JSONSchema.string,
                    "subtitle": ["type": ["string", "null"]],
                    "price": ["type": ["number", "null"]],
                    "currency": ["type": ["string", "null"]],
                    "time": ["type": ["string", "null"]],
                    "location": ["type": ["string", "null"]],
                    "rating": ["type": ["number", "null"]],
                    "thumbnail_url": ["type": ["string", "null"]],
                    "booking_url": ["type": ["string", "null"]],
                    "latitude": ["type": ["number", "null"]],
                    "longitude": ["type": ["number", "null"]],
                ], required: ["kind", "title", "subtitle", "price", "currency", "time", "location", "rating", "thumbnail_url", "booking_url", "latitude", "longitude"])),
                "itinerary": JSONSchema.array(JSONSchema.object([
                    "day_offset": ["type": "integer"],
                    "label": ["type": ["string", "null"]],
                    "items": JSONSchema.array(JSONSchema.string),
                ], required: ["day_offset", "label", "items"])),
            ], required: ["cards", "itinerary"]),
            argsType: PrepareCardsArgs.self
        ) { args, _ in
            let cards: [CoachTravelCard] = args.cards.compactMap { c in
                let title = c.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                return CoachTravelCard(
                    kind: CoachTravelCardKind(rawValue: c.kind) ?? .activity,
                    title: title,
                    subtitle: c.subtitle,
                    price: c.price,
                    currency: c.currency,
                    time: c.time,
                    location: c.location,
                    rating: c.rating,
                    thumbnailURL: c.thumbnailUrl,
                    bookingURL: c.bookingUrl,
                    latitude: c.latitude,
                    longitude: c.longitude
                )
            }
            guard !cards.isEmpty else {
                return .error("no valid cards — provide at least one option with a title.")
            }
            let days: [CoachItineraryDay] = (args.itinerary ?? []).map {
                CoachItineraryDay(dayOffset: $0.dayOffset ?? 0, label: $0.label, items: $0.items ?? [])
            }
            return .encoding(PreparedTravelCards(
                travelCards: cards,
                itinerary: days,
                note: "Copy travel_cards (and itinerary if present) verbatim into the final response's `travel_cards` and `itinerary` fields. Don't restate the options as plain text."
            ))
        }
    }

    // MARK: - Live search (real APIs · Travel+ T8)

    private struct FlightSearchArgs: Decodable {
        let origin: String
        let destination: String
        let departureDate: String
        let returnDate: String?
        let adults: Int?
        let currency: String?
        enum CodingKeys: String, CodingKey {
            case origin, destination
            case departureDate = "departure_date"
            case returnDate = "return_date"
            case adults, currency
        }
    }

    private static var searchFlights: AnyCoachTool {
        .make(
            name: "search_flights",
            label: "Searching live flights",
            description: "Search REAL, current flight options between two airports/cities using a live flights API. Provide origin and destination as IATA codes when known (e.g. 'SFO', 'HND') and a departure_date (YYYY-MM-DD); optionally a return_date, adults, and currency. Returns real fares & routes as options — then call prepare_travel_cards with them and copy the cards into your reply. If live search isn't configured this returns configured=false; in that case fall back to web_search for options.",
            parameters: JSONSchema.object([
                "origin": JSONSchema.string,
                "destination": JSONSchema.string,
                "departure_date": JSONSchema.string,
                "return_date": ["type": ["string", "null"]],
                "adults": ["type": ["integer", "null"]],
                "currency": ["type": ["string", "null"]],
            ], required: ["origin", "destination", "departure_date", "return_date", "adults", "currency"]),
            argsType: FlightSearchArgs.self
        ) { args, _ in
            guard let dep = parseDate(args.departureDate) else {
                return .error("departure_date must be a valid date (YYYY-MM-DD).")
            }
            let query = FlightSearchQuery(
                origin: args.origin,
                destination: args.destination,
                departureDate: dep,
                returnDate: parseDate(args.returnDate),
                adults: max(1, args.adults ?? 1),
                currency: (args.currency?.nilIfEmpty ?? "USD").uppercased()
            )
            do {
                let results = try await searchProvider.searchFlights(query)
                return .object([
                    "ok": true,
                    "configured": true,
                    "count": results.count,
                    "options": results.map(\.asDictionary),
                    "note": "Real flight options. Call prepare_travel_cards with these (kind=flight) and copy the cards into your reply.",
                ])
            } catch TravelSearchError.notConfigured {
                return .object([
                    "ok": true,
                    "configured": false,
                    "count": 0,
                    "options": [[String: Any]](),
                    "note": "Live flight search isn't configured. Use web_search to find real flight options, then prepare_travel_cards.",
                ])
            } catch TravelSearchError.noResults {
                return .object(["ok": true, "configured": true, "count": 0, "options": [[String: Any]](),
                                "note": "No flights found for those dates. Suggest alternative dates or use web_search."])
            } catch {
                return .object(["ok": false, "configured": true, "count": 0, "options": [[String: Any]](),
                                "note": "Live flight search failed (\(String(describing: error))). Fall back to web_search."])
            }
        }
    }

    private struct PlaceSearchArgs: Decodable {
        let kind: String
        let query: String
        let near: String
        let limit: Int?
    }

    private static var searchPlaces: AnyCoachTool {
        .make(
            name: "search_places",
            label: "Searching places nearby",
            description: "Search REAL places — stays (lodging), things to do (activity), restaurants, or transport hubs — near a location using live map data. kind ∈ {lodging, activity, restaurant, transport}; query is what to look for (e.g. 'ramen', 'boutique hotel', 'art museum'); near is where (e.g. 'Shinjuku, Tokyo'). Returns real POIs with coordinates and links — then call prepare_travel_cards with them and copy the cards into your reply.",
            parameters: JSONSchema.object([
                "kind": JSONSchema.string,
                "query": JSONSchema.string,
                "near": JSONSchema.string,
                "limit": ["type": ["integer", "null"]],
            ], required: ["kind", "query", "near", "limit"]),
            argsType: PlaceSearchArgs.self
        ) { args, _ in
            guard let kind = TravelSearchResult.Kind(rawValue: args.kind.lowercased()) else {
                return .error("kind must be one of: lodging, activity, restaurant, transport.")
            }
            guard let what = args.query.nilIfEmpty, let near = args.near.nilIfEmpty else {
                return .error("query and near are required.")
            }
            let query = PlaceSearchQuery(kind: kind, query: what, near: near, limit: min(10, max(1, args.limit ?? 6)))
            do {
                let results = try await searchProvider.searchPlaces(query)
                return .object([
                    "ok": true,
                    "count": results.count,
                    "options": results.map(\.asDictionary),
                    "note": "Real places. Call prepare_travel_cards with these and copy the cards into your reply.",
                ])
            } catch TravelSearchError.noResults, TravelSearchError.notConfigured {
                return .object(["ok": true, "count": 0, "options": [[String: Any]](),
                                "note": "No places found. Try a broader query or use web_search."])
            } catch {
                return .object(["ok": false, "count": 0, "options": [[String: Any]](),
                                "note": "Place search failed (\(String(describing: error))). Fall back to web_search."])
            }
        }
    }

    // MARK: - Writes

    private struct CreateTripArgs: Decodable {
        let destination: String
        let origin: String?
        let startDate: String?
        let endDate: String?
        let notes: String?
        let travelerCount: Int?
        let budgetAmount: Double?
        let budgetCurrency: String?
        let coverImageUrl: String?
        enum CodingKeys: String, CodingKey {
            case destination, origin, startDate = "start_date", endDate = "end_date", notes
            case travelerCount = "traveler_count", budgetAmount = "budget_amount"
            case budgetCurrency = "budget_currency", coverImageUrl = "cover_image_url"
        }
    }

    private static var createTrip: AnyCoachTool {
        .make(
            name: "create_trip",
            label: "Starting a trip plan",
            description: "Create a new trip. destination is required (e.g. 'Lisbon, Portugal'). origin (departure city), start_date/end_date (ISO yyyy-MM-dd), notes, traveler_count, budget_amount (+budget_currency ISO code), and cover_image_url are optional. Returns the trip_id to add items to. Applies immediately.",
            parameters: JSONSchema.object([
                "destination": JSONSchema.string,
                "origin": ["type": ["string", "null"]],
                "start_date": ["type": ["string", "null"]],
                "end_date": ["type": ["string", "null"]],
                "notes": ["type": ["string", "null"]],
                "traveler_count": ["type": ["integer", "null"]],
                "budget_amount": ["type": ["number", "null"]],
                "budget_currency": ["type": ["string", "null"]],
                "cover_image_url": ["type": ["string", "null"]],
            ], required: ["destination", "origin", "start_date", "end_date", "notes", "traveler_count", "budget_amount", "budget_currency", "cover_image_url"]),
            argsType: CreateTripArgs.self
        ) { args, ctx in
            let dest = args.destination.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dest.isEmpty else { return .error("destination is empty.") }
            let trip = Trip(
                destination: dest,
                originCity: args.origin?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                startDate: parseDate(args.startDate),
                endDate: parseDate(args.endDate),
                notes: args.notes?.nilIfEmpty,
                travelerCount: max(1, args.travelerCount ?? 1),
                budgetAmount: args.budgetAmount,
                budgetCurrency: args.budgetCurrency?.nilIfEmpty,
                coverImageURL: args.coverImageUrl?.nilIfEmpty
            )
            ctx.modelContext.insert(trip)
            ctx.modelContext.saveOrLog("coach.travel")
            return .object(["ok": true, "trip_id": trip.id.uuidString, "destination": trip.destination])
        }
    }

    private struct UpdateTripArgs: Decodable {
        let tripId: String
        let destination: String?
        let origin: String?
        let startDate: String?
        let endDate: String?
        let notes: String?
        let status: String?
        enum CodingKeys: String, CodingKey {
            case tripId = "trip_id", destination, origin, startDate = "start_date", endDate = "end_date", notes, status
        }
    }

    private static var updateTrip: AnyCoachTool {
        .make(
            name: "update_trip",
            label: "Updating your trip",
            description: "Update a trip's destination, origin, dates (ISO yyyy-MM-dd), notes, or status (planning/booked/completed/cancelled). Leave a field null to keep it. Use status='cancelled' to archive a trip instead of deleting it. Applies immediately.",
            parameters: JSONSchema.object([
                "trip_id": JSONSchema.string,
                "destination": ["type": ["string", "null"]],
                "origin": ["type": ["string", "null"]],
                "start_date": ["type": ["string", "null"]],
                "end_date": ["type": ["string", "null"]],
                "notes": ["type": ["string", "null"]],
                "status": ["type": ["string", "null"], "enum": ["planning", "booked", "completed", "cancelled"]],
            ], required: ["trip_id", "destination", "origin", "start_date", "end_date", "notes", "status"]),
            argsType: UpdateTripArgs.self
        ) { args, ctx in
            guard let t = trip(args.tripId, ctx) else {
                return .error("trip '\(args.tripId)' not found. Call list_trips.")
            }
            // Cancelling/archiving a whole trip is destructive — route it through a
            // confirm card rather than applying instantly (BUG-3). Other edits apply.
            if let raw = args.status, TripStatus(rawValue: raw) == .cancelled, t.status != .cancelled {
                ctx.pendingActions.append(PendingAction(
                    kind: .deleteEntity,
                    summary: "Archive your trip to \(t.destination)? It will be marked cancelled.",
                    confirmLabel: "Archive",
                    entity: EntityActionPayload(entityType: "trip", id: t.id.uuidString, displayName: t.destination)
                ))
                return .object(["ok": true, "needs_confirmation": true,
                                "summary": "Awaiting your confirmation to archive the trip to \(t.destination)."])
            }
            if let v = args.destination?.nilIfEmpty { t.destination = v }
            if let v = args.origin?.nilIfEmpty { t.originCity = v }
            if let v = parseDate(args.startDate) { t.startDate = v }
            if let v = parseDate(args.endDate) { t.endDate = v }
            if let v = args.notes?.nilIfEmpty { t.notes = v }
            if let raw = args.status, let s = TripStatus(rawValue: raw) { t.status = s }
            t.updatedAt = Date()
            ctx.modelContext.saveOrLog("coach.travel")
            return .object(["ok": true, "trip_id": t.id.uuidString, "status": t.statusRaw])
        }
    }

    private struct AddItemArgs: Decodable {
        let tripId: String
        let kind: String
        let title: String
        let details: String?
        let location: String?
        let url: String?
        let price: Double?
        let currency: String?
        let startAt: String?
        let endAt: String?
        let dayOffset: Int?
        let rating: Double?
        let latitude: Double?
        let longitude: Double?
        enum CodingKeys: String, CodingKey {
            case tripId = "trip_id", kind, title, details, location, url, price, currency
            case startAt = "start_at", endAt = "end_at", dayOffset = "day_offset"
            case rating, latitude, longitude
        }
    }

    private static var addTripItem: AnyCoachTool {
        .make(
            name: "add_trip_item",
            label: "Saving an option to your trip",
            description: """
            Add one item to a trip's itinerary. Use this to SAVE a real option you found via web_search — a flight, a hotel/Airbnb, a thing to do, a restaurant, or ground transport. \
            kind is one of: flight, lodging, activity, restaurant, transport, note. title is required (e.g. 'United UA837 SFO→HND' or 'Park Hyatt Tokyo'). \
            Put specifics in details, the booking/info link in url, the price in price (+currency), location (address or 'SFO → HND'), and start_at/end_at (ISO datetime) when known. day_offset orders it within the trip (0 = first day). rating (e.g. 4.6) for places; latitude/longitude when known so it appears on the trip map. Applies immediately.
            """,
            parameters: JSONSchema.object([
                "trip_id": JSONSchema.string,
                "kind": JSONSchema.enumString(TripItemKind.allCases.map(\.rawValue)),
                "title": JSONSchema.string,
                "details": ["type": ["string", "null"]],
                "location": ["type": ["string", "null"]],
                "url": ["type": ["string", "null"]],
                "price": ["type": ["number", "null"]],
                "currency": ["type": ["string", "null"]],
                "start_at": ["type": ["string", "null"]],
                "end_at": ["type": ["string", "null"]],
                "day_offset": ["type": ["integer", "null"]],
                "rating": ["type": ["number", "null"]],
                "latitude": ["type": ["number", "null"]],
                "longitude": ["type": ["number", "null"]],
            ], required: ["trip_id", "kind", "title", "details", "location", "url", "price", "currency", "start_at", "end_at", "day_offset", "rating", "latitude", "longitude"]),
            argsType: AddItemArgs.self
        ) { args, ctx in
            guard let t = trip(args.tripId, ctx) else {
                return .error("trip '\(args.tripId)' not found. Call list_trips or create_trip first.")
            }
            let title = args.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return .error("item title is empty.") }
            let kind = TripItemKind(rawValue: args.kind) ?? .note
            let nextOrder = (t.items.map(\.order).max() ?? -1) + 1
            let item = TripItem(
                tripId: t.id,
                kind: kind,
                title: title,
                details: args.details?.nilIfEmpty,
                location: args.location?.nilIfEmpty,
                url: args.url?.nilIfEmpty,
                price: args.price,
                currency: args.currency?.nilIfEmpty,
                startAt: parseDate(args.startAt),
                endAt: parseDate(args.endAt),
                dayOffset: args.dayOffset,
                rating: args.rating,
                latitude: args.latitude,
                longitude: args.longitude,
                order: nextOrder
            )
            ctx.modelContext.insert(item)
            t.items.append(item)
            t.updatedAt = Date()
            ctx.modelContext.saveOrLog("coach.travel")
            return .object(["ok": true, "item_id": item.id.uuidString, "kind": item.kindRaw, "title": item.title])
        }
    }

    private struct UpdateItemArgs: Decodable {
        let itemId: String
        let title: String?
        let details: String?
        let location: String?
        let url: String?
        let price: Double?
        let dayOffset: Int?
        enum CodingKeys: String, CodingKey {
            case itemId = "item_id", title, details, location, url, price, dayOffset = "day_offset"
        }
    }

    private static func item(_ id: String, _ ctx: ToolExecutionContext) -> TripItem? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return ((try? ctx.modelContext.fetch(FetchDescriptor<TripItem>())) ?? []).first { $0.id == uuid }
    }

    private static var updateTripItem: AnyCoachTool {
        .make(
            name: "update_trip_item",
            label: "Updating a trip item",
            description: "Edit a saved trip item's title, details, location, url, price, or day_offset (ids from get_trip). Leave a field null to keep it. Applies immediately.",
            parameters: JSONSchema.object([
                "item_id": JSONSchema.string,
                "title": ["type": ["string", "null"]],
                "details": ["type": ["string", "null"]],
                "location": ["type": ["string", "null"]],
                "url": ["type": ["string", "null"]],
                "price": ["type": ["number", "null"]],
                "day_offset": ["type": ["integer", "null"]],
            ], required: ["item_id", "title", "details", "location", "url", "price", "day_offset"]),
            argsType: UpdateItemArgs.self
        ) { args, ctx in
            guard let i = item(args.itemId, ctx) else {
                return .error("item '\(args.itemId)' not found. Call get_trip.")
            }
            if let v = args.title?.nilIfEmpty { i.title = v }
            if let v = args.details?.nilIfEmpty { i.details = v }
            if let v = args.location?.nilIfEmpty { i.location = v }
            if let v = args.url?.nilIfEmpty { i.url = v }
            if let v = args.price { i.price = v }
            if let v = args.dayOffset { i.dayOffset = v }
            ctx.modelContext.saveOrLog("coach.travel")
            return .object(["ok": true, "item_id": i.id.uuidString])
        }
    }

    private struct BookedArgs: Decodable {
        let itemId: String
        let booked: Bool
        enum CodingKeys: String, CodingKey { case itemId = "item_id", booked }
    }

    private static var setTripItemBooked: AnyCoachTool {
        .make(
            name: "set_trip_item_booked",
            label: "Marking as booked",
            description: "Mark a trip item booked/confirmed (true) or not (false). Use when the user says they've booked a flight/hotel/activity. Applies immediately.",
            parameters: JSONSchema.object([
                "item_id": JSONSchema.string,
                "booked": JSONSchema.boolean,
            ], required: ["item_id", "booked"]),
            argsType: BookedArgs.self
        ) { args, ctx in
            guard let i = item(args.itemId, ctx) else {
                return .error("item '\(args.itemId)' not found. Call get_trip.")
            }
            i.booked = args.booked
            ctx.modelContext.saveOrLog("coach.travel")
            return .object(["ok": true, "item_id": i.id.uuidString, "booked": i.booked])
        }
    }

    private struct DeleteItemArgs: Decodable {
        let itemId: String
        enum CodingKeys: String, CodingKey { case itemId = "item_id" }
    }

    private static var deleteTripItem: AnyCoachTool {
        .make(
            name: "delete_trip_item",
            label: "Removing a trip item",
            description: "Remove one item from a trip (e.g. an option the user rejected). To remove a whole trip, use update_trip with status='cancelled' instead. Proposes a confirm card the user must approve.",
            parameters: JSONSchema.object(["item_id": JSONSchema.string], required: ["item_id"]),
            argsType: DeleteItemArgs.self
        ) { args, ctx in
            guard let i = item(args.itemId, ctx) else {
                return .error("item '\(args.itemId)' not found. Call get_trip.")
            }
            let title = i.title
            ctx.pendingActions.append(PendingAction(
                kind: .deleteEntity,
                summary: "Remove \"\(title)\" from the trip? This can't be undone.",
                confirmLabel: "Remove",
                entity: EntityActionPayload(entityType: "trip_item", id: i.id.uuidString, displayName: title)
            ))
            return .object(["ok": true, "needs_confirmation": true,
                            "summary": "Awaiting your confirmation to remove \"\(title)\"."])
        }
    }

    private struct ChecklistArgs: Decodable {
        let tripId: String
        let tasks: [String]
        enum CodingKeys: String, CodingKey { case tripId = "trip_id", tasks }
    }

    private static var createTripChecklist: AnyCoachTool {
        .make(
            name: "create_trip_checklist",
            label: "Building a pre-trip checklist",
            description: "Create pre-trip to-do tasks (e.g. 'Renew passport', 'Buy travel insurance', 'Exchange currency') linked to a trip. Each task appears in the user's task list and on the trip's checklist. Applies immediately.",
            parameters: JSONSchema.object([
                "trip_id": JSONSchema.string,
                "tasks": ["type": "array", "items": JSONSchema.string],
            ], required: ["trip_id", "tasks"]),
            argsType: ChecklistArgs.self
        ) { args, ctx in
            guard let t = trip(args.tripId, ctx) else {
                return .error("trip '\(args.tripId)' not found. Call get_trip first.")
            }
            let titles = args.tasks.compactMap { $0.nilIfEmpty }
            guard !titles.isEmpty else { return .error("no task titles provided.") }
            var created: [String] = []
            for title in titles {
                let task = TaskItem(title: title, group: "Travel", label: t.destination, tripId: t.id)
                ctx.modelContext.insert(task)
                created.append(task.id.uuidString)
            }
            ctx.modelContext.saveOrLog("coach.travel")
            return .object([
                "ok": true,
                "trip_id": t.id.uuidString,
                "created_count": titles.count,
                "task_ids": created,
            ])
        }
    }

    private struct PackingArgs: Decodable {
        let tripId: String
        let items: [String]
        enum CodingKeys: String, CodingKey { case tripId = "trip_id", items }
    }

    /// The task group used for packing-list items so the UI can separate them from
    /// the pre-trip checklist. Keep in sync with `TravelView`'s packing filter.
    static let packingGroup = "Packing"

    private static var createPackingList: AnyCoachTool {
        .make(
            name: "create_packing_list",
            label: "Building a packing list",
            description: "Create a smart packing list for a trip as checkable items (e.g. 'Passport', 'Universal adapter', 'Rain jacket'). Tailor it to the destination, trip length, season, and planned activities. Each item appears on the trip's Packing list. Applies immediately.",
            parameters: JSONSchema.object([
                "trip_id": JSONSchema.string,
                "items": ["type": "array", "items": JSONSchema.string],
            ], required: ["trip_id", "items"]),
            argsType: PackingArgs.self
        ) { args, ctx in
            guard let t = trip(args.tripId, ctx) else {
                return .error("trip '\(args.tripId)' not found. Call get_trip first.")
            }
            let titles = args.items.compactMap { $0.nilIfEmpty }
            guard !titles.isEmpty else { return .error("no packing items provided.") }
            var created: [String] = []
            let base = (try? ctx.modelContext.fetch(FetchDescriptor<TaskItem>()).filter { $0.tripId == t.id && $0.group == packingGroup }.count) ?? 0
            for (offset, title) in titles.enumerated() {
                let task = TaskItem(title: title, group: packingGroup, label: t.destination, order: base + offset, tripId: t.id)
                ctx.modelContext.insert(task)
                created.append(task.id.uuidString)
            }
            ctx.modelContext.saveOrLog("coach.travel")
            return .object([
                "ok": true,
                "trip_id": t.id.uuidString,
                "created_count": titles.count,
                "task_ids": created,
            ])
        }
    }

    private struct TripNoteArgs: Decodable {
        let tripId: String
        let title: String
        let body: String?
        enum CodingKeys: String, CodingKey { case tripId = "trip_id", title, body }
    }

    private struct DestinationInfoArgs: Decodable {
        let tripId: String
        let currency: String?
        let language: String?
        let timeZoneId: String?
        let tip: String?
        enum CodingKeys: String, CodingKey {
            case tripId = "trip_id", currency, language
            case timeZoneId = "time_zone_id", tip
        }
    }

    private static var setDestinationInfo: AnyCoachTool {
        .make(
            name: "set_destination_info",
            label: "Saving destination info",
            description: "Save key facts about a trip's destination so they show on the trip: local currency (ISO code like 'JPY'), primary language, the IANA time-zone identifier (e.g. 'Asia/Tokyo' — used to compute the time difference from the user), and one short 'good to know' tip. Research the real values via web_search first, then call this. Applies immediately.",
            parameters: JSONSchema.object([
                "trip_id": JSONSchema.string,
                "currency": ["type": ["string", "null"]],
                "language": ["type": ["string", "null"]],
                "time_zone_id": ["type": ["string", "null"]],
                "tip": ["type": ["string", "null"]],
            ], required: ["trip_id", "currency", "language", "time_zone_id", "tip"]),
            argsType: DestinationInfoArgs.self
        ) { args, ctx in
            guard let t = trip(args.tripId, ctx) else {
                return .error("trip '\(args.tripId)' not found. Call get_trip first.")
            }
            if let c = args.currency?.nilIfEmpty { t.destinationCurrency = c.uppercased() }
            if let l = args.language?.nilIfEmpty { t.destinationLanguage = l }
            if let tz = args.timeZoneId?.nilIfEmpty {
                // Only accept identifiers iOS can resolve, so the UI's offset math is valid.
                if TimeZone(identifier: tz) != nil { t.destinationTimeZoneId = tz }
            }
            if let tip = args.tip?.nilIfEmpty { t.destinationTip = tip }
            t.updatedAt = Date()
            ctx.modelContext.saveOrLog("coach.travel")
            return .object([
                "ok": true,
                "trip_id": t.id.uuidString,
                "currency": t.destinationCurrency as Any,
                "language": t.destinationLanguage as Any,
                "time_zone_id": t.destinationTimeZoneId as Any,
            ])
        }
    }

    private static var createTripNote: AnyCoachTool {
        .make(
            name: "create_trip_note",
            label: "Saving a trip note",
            description: "Save a note linked to a trip (e.g. reservation details, packing list, local tips, a travel journal entry). The note shows in the Notes module and on the trip. Applies immediately.",
            parameters: JSONSchema.object([
                "trip_id": JSONSchema.string,
                "title": JSONSchema.string,
                "body": ["type": ["string", "null"]],
            ], required: ["trip_id", "title", "body"]),
            argsType: TripNoteArgs.self
        ) { args, ctx in
            guard let t = trip(args.tripId, ctx) else {
                return .error("trip '\(args.tripId)' not found. Call get_trip first.")
            }
            guard let title = args.title.nilIfEmpty else { return .error("note needs a title.") }
            let note = Note(title: title, linkedTripId: t.id)
            ctx.modelContext.insert(note)
            if let body = args.body?.nilIfEmpty {
                let block = NoteBlock(noteId: note.id, order: 0, kind: .paragraph, content: body)
                ctx.modelContext.insert(block)
                note.blocks.append(block)
            }
            ctx.modelContext.saveOrLog("coach.travel")
            return .object([
                "ok": true,
                "trip_id": t.id.uuidString,
                "note_id": note.id.uuidString,
                "title": title,
            ])
        }
    }

    // MARK: - Rewards / points (T9)

    /// Points-valuation source for `value_with_points`. Overridable in tests.
    static var pointsProvider: PointsValuationProvider = LivePointsValuationProvider()

    private static func rewardCards(_ ctx: ToolExecutionContext) -> [RewardCard] {
        (try? ctx.modelContext.fetch(FetchDescriptor<RewardCard>())) ?? []
    }

    private static func cardDict(_ c: RewardCard) -> [String: Any] {
        [
            "id": c.id.uuidString,
            "name": c.name,
            "currency": c.currency,
            "points_balance": c.pointsBalance,
            "cents_per_point": c.centsPerPoint,
            "earn_travel": c.earnTravel,
            "earn_dining": c.earnDining,
            "earn_other": c.earnOther,
        ]
    }

    private static var listRewardCards: AnyCoachTool {
        .make(
            name: "list_reward_cards",
            label: "Checking your rewards",
            description: "List the user's saved credit cards / loyalty programs with their rewards currency, points balance, value per point (cents), and category earn multipliers. Use this before recommending how to pay for travel so you account for points, not just cash.",
            parameters: JSONSchema.empty,
            argsType: NoArgs.self
        ) { _, ctx in
            let rows = rewardCards(ctx).map(cardDict)
            return .object(["cards": rows, "count": rows.count])
        }
    }

    private struct RewardCardArgs: Decodable {
        let name: String
        let currency: String
        let pointsBalance: Int?
        let centsPerPoint: Double?
        let earnTravel: Double?
        let earnDining: Double?
        let earnOther: Double?
        enum CodingKeys: String, CodingKey {
            case name, currency
            case pointsBalance = "points_balance"
            case centsPerPoint = "cents_per_point"
            case earnTravel = "earn_travel"
            case earnDining = "earn_dining"
            case earnOther = "earn_other"
        }
    }

    private static var addRewardCard: AnyCoachTool {
        .make(
            name: "add_reward_card",
            label: "Saving a rewards card",
            description: "Save a credit card / loyalty program the user holds so Travel can value points. Provide name (e.g. 'Chase Sapphire Reserve'), currency (the rewards currency, e.g. 'Chase UR', 'Amex MR', 'United miles'), optional points_balance, cents_per_point (value of one point in cents), and per-category earn multipliers (points per $1): earn_travel, earn_dining, earn_other. Applies immediately.",
            parameters: JSONSchema.object([
                "name": JSONSchema.string,
                "currency": JSONSchema.string,
                "points_balance": ["type": ["integer", "null"]],
                "cents_per_point": ["type": ["number", "null"]],
                "earn_travel": ["type": ["number", "null"]],
                "earn_dining": ["type": ["number", "null"]],
                "earn_other": ["type": ["number", "null"]],
            ], required: ["name", "currency", "points_balance", "cents_per_point", "earn_travel", "earn_dining", "earn_other"]),
            argsType: RewardCardArgs.self
        ) { args, ctx in
            guard let name = args.name.nilIfEmpty, let currency = args.currency.nilIfEmpty else {
                return .error("name and currency are required.")
            }
            let card = RewardCard(
                name: name,
                currency: currency,
                pointsBalance: max(0, args.pointsBalance ?? 0),
                centsPerPoint: args.centsPerPoint ?? DefaultPointValues.cpp(for: currency),
                earnTravel: max(0, args.earnTravel ?? 1),
                earnDining: max(0, args.earnDining ?? 1),
                earnOther: max(0, args.earnOther ?? 1)
            )
            ctx.modelContext.insert(card)
            ctx.modelContext.saveOrLog("coach.travel")
            return .object(["ok": true, "card_id": card.id.uuidString, "name": name])
        }
    }

    private struct ValueOptionsArgs: Decodable {
        struct Option: Decodable {
            let title: String
            let kind: String?
            let cashPrice: Double?
            let currency: String?
            let awardPoints: Int?
            let awardFees: Double?
            let awardCurrency: String?
            enum CodingKeys: String, CodingKey {
                case title, kind
                case cashPrice = "cash_price"
                case currency
                case awardPoints = "award_points"
                case awardFees = "award_fees"
                case awardCurrency = "award_currency"
            }
        }
        let options: [Option]
    }

    private static var valueWithPoints: AnyCoachTool {
        .make(
            name: "value_with_points",
            label: "Finding the best value",
            description: "Rank travel options by their TRUE cost using the user's saved reward cards — not just the lowest cash price. For each option pass title, kind (flight/lodging/activity/restaurant/transport), cash_price + currency, and optionally an award redemption (award_points, award_fees, award_currency). Returns each option with an effective cost, the recommended way to pay, and a concise 'best value' line to put on the card. Call list_reward_cards first. Then feed the results into prepare_travel_cards. Values may be estimates — they're labeled as such.",
            parameters: JSONSchema.object([
                "options": ["type": "array", "items": JSONSchema.object([
                    "title": JSONSchema.string,
                    "kind": ["type": ["string", "null"]],
                    "cash_price": ["type": ["number", "null"]],
                    "currency": ["type": ["string", "null"]],
                    "award_points": ["type": ["integer", "null"]],
                    "award_fees": ["type": ["number", "null"]],
                    "award_currency": ["type": ["string", "null"]],
                ], required: ["title", "kind", "cash_price", "currency", "award_points", "award_fees", "award_currency"])],
            ], required: ["options"]),
            argsType: ValueOptionsArgs.self
        ) { args, ctx in
            let cards = rewardCards(ctx)
            var out: [[String: Any]] = []
            for opt in args.options {
                let kind = opt.kind.flatMap { TravelSearchResult.Kind(rawValue: $0.lowercased()) } ?? .activity
                let category = SpendCategory.from(kind)
                let currency = opt.currency?.nilIfEmpty ?? "USD"

                // Look up a live valuation for the award currency when present.
                var valuationIsLive = false
                var cards2 = cards
                if let awardCurrency = opt.awardCurrency?.nilIfEmpty {
                    let valuation = try await pointsProvider.valuation(for: awardCurrency)
                    valuationIsLive = valuation.isLive
                    // If the user has no matching card, synthesize a transient one so
                    // the award can still be valued at the live/default cpp.
                    if PointsValuator.card(for: awardCurrency, in: cards2) == nil {
                        cards2.append(RewardCard(name: awardCurrency, currency: awardCurrency, centsPerPoint: valuation.centsPerPoint))
                    }
                }

                var award: AwardPrice?
                if let pts = opt.awardPoints, pts > 0, let cur = opt.awardCurrency?.nilIfEmpty {
                    award = AwardPrice(points: pts, fees: opt.awardFees ?? 0, currency: cur)
                }

                let v = PointsValuator.evaluate(
                    cashPrice: opt.cashPrice,
                    currency: currency,
                    category: category,
                    cards: cards2,
                    award: award,
                    valuationIsLive: valuationIsLive
                )
                var row: [String: Any] = [
                    "title": opt.title,
                    "recommendation": v.recommendation,
                    "is_estimate": v.isEstimate,
                ]
                if let c = v.cashPrice { row["cash_price"] = c }
                if let e = v.effectiveCashCost { row["effective_cash_cost"] = e }
                if let a = v.awardCost { row["award_cost"] = a }
                if let b = v.bestEffectiveCost { row["best_effective_cost"] = b }
                if v.earnedValue > 0 { row["earned_value"] = v.earnedValue }
                if let name = v.earnCardName { row["earn_card"] = name }
                if let name = v.awardCardName { row["award_card"] = name }
                out.append(row)
            }
            // Rank ascending by best effective cost (unknowns sort last).
            out.sort { lhs, rhs in
                let l = (lhs["best_effective_cost"] as? Double) ?? .greatestFiniteMagnitude
                let r = (rhs["best_effective_cost"] as? Double) ?? .greatestFiniteMagnitude
                return l < r
            }
            return .object([
                "ok": true,
                "count": out.count,
                "ranked_options": out,
                "note": "Ranked by effective cost (points-aware). Put each option's 'recommendation' line on its travel card via prepare_travel_cards. Label estimated values as estimates.",
            ])
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
