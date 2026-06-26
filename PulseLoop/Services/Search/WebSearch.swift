import Foundation

// MARK: - Live web search (Assistant+ T1)
//
// A provider-agnostic web-search layer behind the testable `HTTPTransport` seam.
// This is the fix for "I can't search" on non-OpenAI providers: the hosted
// `web_search` tool only runs on the OpenAI Responses API, and the OpenRouter
// bridge strips every hosted (non-function) tool. So on the shipping default
// (OpenRouter + Gemini) the model had NO search capability at all. This adds a
// real `search_web` *function* tool that works on every provider/model.
//
// API key is read from Info.plist and gated by `isConfigured` (placeholders like
// `REPLACE_*` / `YOUR_*` are rejected) so the app degrades gracefully — when no
// key is set the tool returns `configured:false` and the assistant is honest
// rather than hallucinating.

/// One normalized web search result. Maps onto `CoachSource` for citations.
struct WebSearchResult: Equatable, Sendable, Encodable {
    var title: String
    var url: String
    var snippet: String?
    var publisher: String?
    /// ISO-ish published date string when the provider supplies one.
    var publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case title, url, snippet, publisher
        case publishedAt = "published_at"
    }

    /// Tool-output dictionary (snake_case) the model reads + cites.
    var asDictionary: [String: Any] {
        var d: [String: Any] = ["title": title, "url": url]
        if let v = snippet { d["snippet"] = v }
        if let v = publisher { d["publisher"] = v }
        if let v = publishedAt { d["published_at"] = v }
        return d
    }

    /// As a `CoachSource` for the response's `sources` (citations) array.
    var asCoachSource: CoachSource {
        CoachSource(title: title, url: url, publisher: publisher ?? Self.host(of: url))
    }

    /// Best-effort publisher from a URL host (drops a leading "www.").
    static func host(of urlString: String) -> String {
        guard let host = URL(string: urlString)?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Recency filter for time-sensitive queries.
enum WebSearchRecency: String, Sendable {
    case any
    case day
    case week
    case month
    case year
}

/// A web-search request.
struct WebSearchQuery: Equatable, Sendable {
    var query: String
    var count: Int = 6
    var recency: WebSearchRecency = .any
}

/// Errors a web-search provider can surface; callers degrade gracefully on
/// `.notConfigured`.
enum WebSearchError: Error, Equatable {
    case notConfigured
    case badResponse(Int)
    case decoding
    case noResults
}

/// Abstraction over a live web-search source. Concrete providers implement
/// `search`; the facade picks one and degrades gracefully.
protocol WebSearchProvider: Sendable {
    var isConfigured: Bool { get }
    func search(_ query: WebSearchQuery) async throws -> [WebSearchResult]
}
