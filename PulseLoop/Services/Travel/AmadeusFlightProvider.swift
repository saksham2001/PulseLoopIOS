import Foundation
import os

// MARK: - Amadeus flight provider (Travel+ T8)
//
// Real flight routes & fares via the Amadeus Self-Service "Flight Offers Search" API.
// Two steps: (1) OAuth2 client-credentials token, (2) GET /v2/shopping/flight-offers.
// Everything goes through an injectable `HTTPTransport` so request-building and
// response parsing are unit-testable with a stubbed transport (no network).
//
// Degrades gracefully: throws `.notConfigured` when credentials are missing so the
// facade falls back to keyless sources / web_search. Places search isn't supported
// here (Apple MapKit handles it), so it throws `.notConfigured`.
struct AmadeusFlightProvider: TravelSearchProvider {
    private let transport: HTTPTransport
    private let clientID: String
    private let clientSecret: String
    private let baseURL: URL
    private let tokenStore: AmadeusTokenStore

    /// Hosts: production is `api.amadeus.com`; the free test tier is
    /// `test.api.amadeus.com`. Default to test so sandbox keys work out of the box.
    init(
        transport: HTTPTransport = URLSession.shared,
        clientID: String = TravelSearchConfig.amadeusClientID,
        clientSecret: String = TravelSearchConfig.amadeusClientSecret,
        baseURL: URL = URL(string: "https://test.api.amadeus.com")!,
        tokenStore: AmadeusTokenStore = .shared
    ) {
        self.transport = transport
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.baseURL = baseURL
        self.tokenStore = tokenStore
    }

    private var isConfigured: Bool {
        !TravelSearchConfig.isPlaceholder(clientID) && !TravelSearchConfig.isPlaceholder(clientSecret)
    }

    // MARK: Token

    /// Build the client-credentials token request. Exposed for testing.
    func tokenRequest() -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/security/oauth2/token"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Percent-encode each value: API secrets routinely contain "+", "/", "="
        // which would otherwise corrupt the form body and fail the token exchange.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        let body = "grant_type=client_credentials&client_id=\(enc(clientID))&client_secret=\(enc(clientSecret))"
        req.httpBody = body.data(using: .utf8)
        return req
    }

    /// Parse an access token + ttl out of the token response body. Exposed for testing.
    func parseToken(_ data: Data) throws -> (token: String, expiresIn: TimeInterval) {
        struct TokenResponse: Decodable { let access_token: String; let expires_in: Double? }
        guard let resp = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw TravelSearchError.decoding
        }
        return (resp.access_token, resp.expires_in ?? 1800)
    }

    private func accessToken() async throws -> String {
        if let cached = await tokenStore.valid() { return cached }
        let (data, response) = try await NetworkRetry.send(tokenRequest(), transport: transport)
        guard let http = response as? HTTPURLResponse else { throw TravelSearchError.badResponse(-1) }
        guard (200...299).contains(http.statusCode) else { throw TravelSearchError.badResponse(http.statusCode) }
        let parsed = try parseToken(data)
        await tokenStore.set(parsed.token, expiresIn: parsed.expiresIn)
        return parsed.token
    }

    // MARK: Flight search

    /// Build the flight-offers search request given a bearer token. Exposed for testing.
    func flightRequest(_ query: FlightSearchQuery, token: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("v2/shopping/flight-offers"), resolvingAgainstBaseURL: false)!
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "originLocationCode", value: query.origin.uppercased()),
            URLQueryItem(name: "destinationLocationCode", value: query.destination.uppercased()),
            URLQueryItem(name: "departureDate", value: df.string(from: query.departureDate)),
            URLQueryItem(name: "adults", value: String(max(1, query.adults))),
            URLQueryItem(name: "currencyCode", value: query.currency.uppercased()),
            URLQueryItem(name: "max", value: "6"),
        ]
        if let ret = query.returnDate {
            items.append(URLQueryItem(name: "returnDate", value: df.string(from: ret)))
        }
        components.queryItems = items
        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    /// Parse flight offers into normalized results. Exposed for testing.
    func parseFlights(_ data: Data, query: FlightSearchQuery) throws -> [TravelSearchResult] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let offers = root["data"] as? [[String: Any]] else {
            throw TravelSearchError.decoding
        }
        var results: [TravelSearchResult] = []
        for offer in offers {
            guard let itineraries = offer["itineraries"] as? [[String: Any]],
                  let first = itineraries.first,
                  let segments = first["segments"] as? [[String: Any]],
                  let firstSeg = segments.first,
                  let lastSeg = segments.last else { continue }

            let depCode = ((firstSeg["departure"] as? [String: Any])?["iataCode"] as? String) ?? query.origin.uppercased()
            let arrCode = ((lastSeg["arrival"] as? [String: Any])?["iataCode"] as? String) ?? query.destination.uppercased()
            let carrier = (firstSeg["carrierCode"] as? String) ?? ""
            let stops = max(0, segments.count - 1)
            let stopLabel = stops == 0 ? "Nonstop" : (stops == 1 ? "1 stop" : "\(stops) stops")
            let duration = (first["duration"] as? String).map { Self.prettyDuration($0) }

            var price: Double?
            var currency = query.currency.uppercased()
            if let priceDict = offer["price"] as? [String: Any] {
                if let total = priceDict["grandTotal"] as? String ?? priceDict["total"] as? String {
                    price = Double(total)
                }
                if let cur = priceDict["currency"] as? String { currency = cur }
            }

            var timeParts: [String] = [stopLabel]
            if let duration { timeParts.append(duration) }

            results.append(TravelSearchResult(
                kind: .flight,
                title: carrier.isEmpty ? "\(depCode) → \(arrCode)" : "\(carrier) · \(depCode) → \(arrCode)",
                subtitle: "\(depCode) → \(arrCode)",
                price: price,
                currency: currency,
                time: timeParts.joined(separator: " · "),
                location: "\(depCode) → \(arrCode)"
            ))
        }
        if results.isEmpty { throw TravelSearchError.noResults }
        return results
    }

    /// Turn an ISO-8601 duration like "PT11H20M" into "11h 20m".
    static func prettyDuration(_ iso: String) -> String {
        var s = iso
        if s.hasPrefix("PT") { s.removeFirst(2) }
        var hours = ""
        var mins = ""
        var num = ""
        for ch in s {
            if ch.isNumber { num.append(ch) }
            else if ch == "H" { hours = num; num = "" }
            else if ch == "M" { mins = num; num = "" }
            else { num = "" }
        }
        var parts: [String] = []
        if !hours.isEmpty { parts.append("\(hours)h") }
        if !mins.isEmpty { parts.append("\(mins)m") }
        return parts.isEmpty ? iso : parts.joined(separator: " ")
    }

    func searchFlights(_ query: FlightSearchQuery) async throws -> [TravelSearchResult] {
        guard isConfigured else { throw TravelSearchError.notConfigured }
        let token = try await accessToken()
        let (data, response) = try await NetworkRetry.send(flightRequest(query, token: token), transport: transport)
        guard let http = response as? HTTPURLResponse else { throw TravelSearchError.badResponse(-1) }
        guard (200...299).contains(http.statusCode) else { throw TravelSearchError.badResponse(http.statusCode) }
        return try parseFlights(data, query: query)
    }

    func searchPlaces(_ query: PlaceSearchQuery) async throws -> [TravelSearchResult] {
        throw TravelSearchError.notConfigured  // handled by Apple MapKit provider
    }
}

/// Caches the Amadeus bearer token across calls (it's valid ~30 min). Actor for
/// safe concurrent access.
actor AmadeusTokenStore {
    static let shared = AmadeusTokenStore()

    private var token: String?
    private var expiry: Date?

    func valid() -> String? {
        guard let token, let expiry, expiry > Date().addingTimeInterval(30) else { return nil }
        return token
    }

    func set(_ token: String, expiresIn: TimeInterval) {
        self.token = token
        self.expiry = Date().addingTimeInterval(expiresIn)
    }

    func clear() {
        token = nil
        expiry = nil
    }
}
