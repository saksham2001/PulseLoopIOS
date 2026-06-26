import Foundation
import XCTest
import SwiftData
@testable import PulseLoop

// MARK: - Live web-search layer tests (Assistant+ T1)
//
// Covers the provider-agnostic search layer with no real network:
//   - TravelSearchConfig web-search key gating
//   - Brave request building + freshness codes + JSON parsing + tag stripping
//   - WebSearchResult → CoachSource mapping
//   - search_web coach tool: results, not-configured, no-results, registry wiring
@MainActor
final class WebSearchTests: XCTestCase {

    // MARK: Config gating

    func testWebSearchKeyGating() {
        XCTAssertTrue(TravelSearchConfig.isPlaceholder("REPLACE_WITH_YOUR_WEB_SEARCH_API_KEY"))
        XCTAssertFalse(TravelSearchConfig.isPlaceholder("brave-real-token"))
    }

    // MARK: Brave request building

    func testBraveSearchRequestBuildsQuery() throws {
        let provider = BraveWebSearchProvider(apiKey: "tok123")
        let req = provider.searchRequest(WebSearchQuery(query: "best ramen tokyo", count: 8, recency: .week))
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Subscription-Token"), "tok123")
        let url = try XCTUnwrap(req.url)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://api.search.brave.com/res/v1/web/search"))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["q"], "best ramen tokyo")
        XCTAssertEqual(dict["count"], "8")
        XCTAssertEqual(dict["freshness"], "pw")
    }

    func testBraveRequestClampsCountAndOmitsFreshnessForAny() throws {
        let provider = BraveWebSearchProvider(apiKey: "tok")
        let req = provider.searchRequest(WebSearchQuery(query: "x", count: 99, recency: .any))
        let items = try XCTUnwrap(URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems)
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["count"], "20") // clamped to max
        XCTAssertNil(dict["freshness"])
    }

    func testFreshnessCodes() {
        XCTAssertNil(BraveWebSearchProvider.freshnessCode(.any))
        XCTAssertEqual(BraveWebSearchProvider.freshnessCode(.day), "pd")
        XCTAssertEqual(BraveWebSearchProvider.freshnessCode(.week), "pw")
        XCTAssertEqual(BraveWebSearchProvider.freshnessCode(.month), "pm")
        XCTAssertEqual(BraveWebSearchProvider.freshnessCode(.year), "py")
    }

    // MARK: Parsing

    func testBraveParseMapsResults() throws {
        let provider = BraveWebSearchProvider(apiKey: "tok")
        let json = """
        {
          "web": {
            "results": [
              {"title": "Best <strong>Ramen</strong> in Tokyo", "url": "https://example.com/ramen",
               "description": "Top <strong>ramen</strong> shops", "age": "2 days ago",
               "profile": {"name": "Example Eats"}},
              {"title": "No URL row"},
              {"url": "https://nytimes.com/food", "description": "Food"}
            ]
          }
        }
        """
        let results = try provider.parse(Data(json.utf8))
        XCTAssertEqual(results.count, 2) // the row with no URL is dropped
        XCTAssertEqual(results[0].title, "Best Ramen in Tokyo") // tags stripped
        XCTAssertEqual(results[0].snippet, "Top ramen shops")
        XCTAssertEqual(results[0].publisher, "Example Eats")
        XCTAssertEqual(results[0].publishedAt, "2 days ago")
        // Missing publisher falls back to host.
        XCTAssertEqual(results[1].publisher, "nytimes.com")
    }

    func testStripTags() {
        XCTAssertNil(BraveWebSearchProvider.stripTags(nil))
        XCTAssertEqual(BraveWebSearchProvider.stripTags("a <b>bold</b> word"), "a bold word")
    }

    func testWebSearchResultMapsToCoachSource() {
        let r = WebSearchResult(title: "T", url: "https://www.example.com/x", snippet: nil, publisher: nil, publishedAt: nil)
        // publisher nil → host of url (www. stripped) when building source.
        let src = WebSearchResult(title: "T", url: "https://www.example.com/x", snippet: nil,
                                  publisher: WebSearchResult.host(of: "https://www.example.com/x")).asCoachSource
        XCTAssertEqual(WebSearchResult.host(of: r.url), "example.com")
        XCTAssertEqual(src.publisher, "example.com")
        XCTAssertEqual(src.url, "https://www.example.com/x")
    }

    // MARK: search_web coach tool via stub provider

    /// Canned web-search provider for offline tool tests.
    struct StubWebProvider: WebSearchProvider {
        var configured: Bool
        var result: Result<[WebSearchResult], Error>
        var isConfigured: Bool { configured }
        func search(_ query: WebSearchQuery) async throws -> [WebSearchResult] { try result.get() }
    }

    private func tool(_ name: String) throws -> AnyCoachTool {
        try XCTUnwrap(SearchTools.all.first { $0.name == name }, "missing tool \(name)")
    }

    private func parse(_ result: ToolResult) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.jsonString.utf8)) as? [String: Any])
    }

    private func readCtx(_ c: ModelContext) -> ToolExecutionContext {
        ToolExecutionContext(modelContext: c, flags: CoachFeatureFlags(settings: .default, hasAPIKey: true))
    }

    func testSearchWebToolReturnsResults() async throws {
        let original = SearchTools.provider
        defer { SearchTools.provider = original }
        SearchTools.provider = StubWebProvider(configured: true, result: .success([
            WebSearchResult(title: "Bali eats", url: "https://example.com/bali", snippet: "Great food",
                            publisher: "Example", publishedAt: nil)
        ]))
        let c = try TestSupport.makeContext()
        let out = try parse(try await tool("search_web").run(
            Data(#"{"query":"best restaurants in Bali","count":6,"recency":"any"}"#.utf8), readCtx(c)))
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(out["configured"] as? Bool, true)
        XCTAssertEqual(out["count"] as? Int, 1)
        let results = try XCTUnwrap(out["results"] as? [[String: Any]])
        XCTAssertEqual(results.first?["title"] as? String, "Bali eats")
        XCTAssertEqual(results.first?["url"] as? String, "https://example.com/bali")
    }

    func testSearchWebToolReportsNotConfigured() async throws {
        let original = SearchTools.provider
        defer { SearchTools.provider = original }
        SearchTools.provider = StubWebProvider(configured: false, result: .failure(WebSearchError.notConfigured))
        let c = try TestSupport.makeContext()
        let out = try parse(try await tool("search_web").run(
            Data(#"{"query":"news today","count":6,"recency":"day"}"#.utf8), readCtx(c)))
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(out["configured"] as? Bool, false)
        XCTAssertEqual(out["count"] as? Int, 0)
        XCTAssertTrue((out["note"] as? String ?? "").lowercased().contains("don't have live web access")
            || (out["note"] as? String ?? "").lowercased().contains("isn't configured"))
    }

    func testSearchWebToolHandlesNoResults() async throws {
        let original = SearchTools.provider
        defer { SearchTools.provider = original }
        SearchTools.provider = StubWebProvider(configured: true, result: .failure(WebSearchError.noResults))
        let c = try TestSupport.makeContext()
        let out = try parse(try await tool("search_web").run(
            Data(#"{"query":"asdkfjqwoeiruzzz","count":6,"recency":"any"}"#.utf8), readCtx(c)))
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(out["count"] as? Int, 0)
    }

    func testSearchWebToolRequiresQuery() async throws {
        let c = try TestSupport.makeContext()
        let out = try parse(try await tool("search_web").run(
            Data(#"{"query":"","count":6,"recency":"any"}"#.utf8), readCtx(c)))
        XCTAssertNotNil(out["error"])
    }

    // MARK: Registry wiring — search tool present for every provider when enabled

    func testRegistryIncludesSearchWebWhenWebSearchEnabled() {
        var settings = CoachSettings.default
        settings.enableWebSearch = true
        let flags = CoachFeatureFlags(settings: settings, hasAPIKey: true)
        let registry = ToolRegistry(flags: flags)
        XCTAssertNotNil(registry.tool(named: "search_web"),
                        "search_web must be available on every provider when web search is on")
        // The hosted-only web_search spec must NOT be in the specs (it's dead on OpenRouter).
        let names = registry.toolSpecs.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("search_web"))
        XCTAssertFalse(registry.toolSpecs.contains { ($0["type"] as? String) == "web_search" })
    }

    func testRegistryOmitsSearchWebWhenDisabled() {
        var settings = CoachSettings.default
        settings.enableWebSearch = false
        let flags = CoachFeatureFlags(settings: settings, hasAPIKey: true)
        let registry = ToolRegistry(flags: flags)
        XCTAssertNil(registry.tool(named: "search_web"))
    }

    // MARK: Citations backfill helpers (T2)

    func testSourcesFromSearchResultJSON() {
        let json = """
        {"ok":true,"configured":true,"count":2,"results":[
          {"title":"A","url":"https://a.com/x","publisher":"A Pub"},
          {"title":"","url":"https://b.com/y"},
          {"title":"No URL"}
        ]}
        """
        let sources = CoachOrchestrator.sources(fromSearchResult: json)
        XCTAssertEqual(sources.count, 2) // the row with no URL is dropped
        XCTAssertEqual(sources[0].title, "A")
        XCTAssertEqual(sources[0].publisher, "A Pub")
        XCTAssertEqual(sources[1].title, "https://b.com/y") // empty title → url
        XCTAssertEqual(sources[1].publisher, "b.com")       // missing publisher → host
    }

    func testDedupedSourcesPreservesOrderAndCaps() {
        let raw = [
            CoachSource(title: "1", url: "https://a.com", publisher: "a"),
            CoachSource(title: "1 dup", url: "https://a.com", publisher: "a"),
            CoachSource(title: "2", url: "https://b.com", publisher: "b"),
            CoachSource(title: "3", url: "https://c.com", publisher: "c"),
        ]
        let out = CoachOrchestrator.dedupedSources(raw, limit: 2)
        XCTAssertEqual(out.map(\.url), ["https://a.com", "https://b.com"])
    }
}
