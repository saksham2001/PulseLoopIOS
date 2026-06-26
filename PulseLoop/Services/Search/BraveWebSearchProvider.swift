import Foundation
import os

// MARK: - Brave web search provider (Assistant+ T1)
//
// Real web results via the Brave Search API (https://api.search.brave.com).
// Simple REST + JSON: GET /res/v1/web/search?q=... with an `X-Subscription-Token`
// header. Everything goes through an injectable `HTTPTransport` so request-building
// and response parsing are unit-testable with a stubbed transport (no network).
//
// Degrades gracefully: `isConfigured` is false when the key is missing/placeholder,
// and `search` throws `.notConfigured` so the facade/tool reports `configured:false`.
struct BraveWebSearchProvider: WebSearchProvider {
    private let transport: HTTPTransport
    private let apiKey: String
    private let baseURL: URL

    init(
        transport: HTTPTransport = URLSession.shared,
        apiKey: String = TravelSearchConfig.webSearchAPIKey,
        baseURL: URL = URL(string: "https://api.search.brave.com")!
    ) {
        self.transport = transport
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    var isConfigured: Bool { !TravelSearchConfig.isPlaceholder(apiKey) }

    /// Build the search request. Exposed for testing.
    func searchRequest(_ query: WebSearchQuery) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("res/v1/web/search"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query.query),
            URLQueryItem(name: "count", value: String(max(1, min(query.count, 20)))),
            URLQueryItem(name: "safesearch", value: "moderate"),
        ]
        if query.recency != .any, let code = Self.freshnessCode(query.recency) {
            items.append(URLQueryItem(name: "freshness", value: code))
        }
        components.queryItems = items
        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        req.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        return req
    }

    /// Brave freshness codes: pd (day), pw (week), pm (month), py (year).
    static func freshnessCode(_ recency: WebSearchRecency) -> String? {
        switch recency {
        case .any: return nil
        case .day: return "pd"
        case .week: return "pw"
        case .month: return "pm"
        case .year: return "py"
        }
    }

    /// Parse Brave's web-results payload into normalized results. Exposed for testing.
    func parse(_ data: Data) throws -> [WebSearchResult] {
        struct BraveResponse: Decodable {
            struct Web: Decodable { let results: [Result]? }
            struct Result: Decodable {
                let title: String?
                let url: String?
                let description: String?
                let age: String?
                struct Profile: Decodable { let name: String? }
                let profile: Profile?
            }
            let web: Web?
        }
        guard let resp = try? JSONDecoder().decode(BraveResponse.self, from: data) else {
            throw WebSearchError.decoding
        }
        let results = (resp.web?.results ?? []).compactMap { r -> WebSearchResult? in
            guard let url = r.url, !url.isEmpty else { return nil }
            return WebSearchResult(
                title: Self.stripTags(r.title) ?? url,
                url: url,
                snippet: Self.stripTags(r.description),
                publisher: r.profile?.name ?? WebSearchResult.host(of: url),
                publishedAt: r.age
            )
        }
        return results
    }

    /// Brave wraps query terms in <strong> tags in descriptions; strip them for
    /// clean snippets the model can quote.
    static func stripTags(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    func search(_ query: WebSearchQuery) async throws -> [WebSearchResult] {
        guard isConfigured else { throw WebSearchError.notConfigured }
        let (data, response) = try await NetworkRetry.send(searchRequest(query), transport: transport)
        guard let http = response as? HTTPURLResponse else { throw WebSearchError.badResponse(-1) }
        guard (200...299).contains(http.statusCode) else { throw WebSearchError.badResponse(http.statusCode) }
        let results = try parse(data)
        if results.isEmpty { throw WebSearchError.noResults }
        return results
    }
}
