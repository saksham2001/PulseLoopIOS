import Foundation

// MARK: - Points valuation provider (Travel+ T9)
//
// Supplies cents-per-point (cpp) valuations for rewards currencies. When a valuation
// API is configured it pulls live numbers over the testable `HTTPTransport` seam;
// otherwise it degrades gracefully to sensible built-in defaults so the best-deal
// engine always has *something* to rank with (clearly labeled as an estimate).

/// A single rewards-currency valuation.
struct PointValuation: Equatable, Sendable {
    /// Rewards currency, e.g. "Chase UR".
    var currency: String
    /// Value of one point in cents.
    var centsPerPoint: Double
    /// Whether this came from a live API (vs a built-in default).
    var isLive: Bool
}

protocol PointsValuationProvider: Sendable {
    /// Returns the cpp valuation for a currency. Never throws for a missing key — it
    /// falls back to a default. May throw on network/parse errors when configured.
    func valuation(for currency: String) async throws -> PointValuation
}

/// Built-in default cents-per-point by program family. Conservative, well-known
/// "baseline" values used when no live valuation API is configured.
enum DefaultPointValues {
    /// Keyed by a lowercased substring of the rewards-currency name.
    static let table: [(match: String, cpp: Double)] = [
        ("chase ur", 1.5), ("ultimate rewards", 1.5),
        ("amex mr", 1.6), ("membership rewards", 1.6),
        ("capital one", 1.4), ("venture", 1.4),
        ("citi", 1.4), ("typ", 1.4), ("thankyou", 1.4),
        ("bilt", 1.6),
        ("united", 1.35), ("delta", 1.2), ("skymiles", 1.2),
        ("american", 1.4), ("aadvantage", 1.4),
        ("alaska", 1.45), ("southwest", 1.35), ("rapid rewards", 1.35),
        ("hyatt", 1.7), ("marriott", 0.8), ("bonvoy", 0.8), ("hilton", 0.6),
        ("avios", 1.4), ("flying blue", 1.3),
    ]

    static func cpp(for currency: String) -> Double {
        let c = currency.lowercased()
        for entry in table where c.contains(entry.match) { return entry.cpp }
        return 1.0  // generic fallback: 1 cent per point
    }
}

/// Live valuation via an HTTP API, with default fallback. The API is expected to
/// expose `GET {base}/valuation?currency=...` returning `{ "cents_per_point": 1.5 }`.
struct LivePointsValuationProvider: PointsValuationProvider {
    private let transport: HTTPTransport
    private let baseURL: String
    private let apiKey: String

    init(
        transport: HTTPTransport = URLSession.shared,
        baseURL: String = TravelSearchConfig.pointsValuationBaseURL,
        apiKey: String = TravelSearchConfig.pointsValuationAPIKey
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    private var isConfigured: Bool {
        !TravelSearchConfig.isPlaceholder(baseURL) && !TravelSearchConfig.isPlaceholder(apiKey)
    }

    /// Build the valuation request. Exposed for testing.
    func valuationRequest(for currency: String) -> URLRequest? {
        guard var comps = URLComponents(string: baseURL) else { return nil }
        comps.path = (comps.path.isEmpty ? "" : comps.path) + "/valuation"
        comps.queryItems = [URLQueryItem(name: "currency", value: currency)]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return req
    }

    /// Parse a cpp value out of the API body. Exposed for testing.
    func parseCPP(_ data: Data) throws -> Double {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TravelSearchError.decoding
        }
        if let v = obj["cents_per_point"] as? Double { return v }
        if let v = obj["cents_per_point"] as? Int { return Double(v) }
        if let s = obj["cents_per_point"] as? String, let v = Double(s) { return v }
        throw TravelSearchError.decoding
    }

    func valuation(for currency: String) async throws -> PointValuation {
        guard isConfigured, let request = valuationRequest(for: currency) else {
            return PointValuation(currency: currency, centsPerPoint: DefaultPointValues.cpp(for: currency), isLive: false)
        }
        do {
            let (data, response) = try await NetworkRetry.send(request, transport: transport)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw TravelSearchError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            let cpp = try parseCPP(data)
            return PointValuation(currency: currency, centsPerPoint: cpp, isLive: true)
        } catch {
            // Never let a valuation failure break planning — fall back to defaults.
            return PointValuation(currency: currency, centsPerPoint: DefaultPointValues.cpp(for: currency), isLive: false)
        }
    }
}
