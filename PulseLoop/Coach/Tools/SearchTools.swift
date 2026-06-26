import Foundation

// MARK: - Web Search Coach Tools (Assistant+ T1)
//
// A provider-agnostic `search_web` *function* tool. Unlike the hosted `web_search`
// tool (OpenAI Responses only — stripped by the OpenRouter bridge), this runs a
// real search over the testable `HTTPTransport` seam, so live search works on
// every model/provider (Gemini, GLM, Claude, GPT). This is the fix for the
// "I can't search / having trouble with web searches" replies on the default model.
//
// Degrades gracefully: when no search key is configured the tool returns
// `configured:false` with guidance, and the prompt tells the assistant to be honest
// about not having live web access rather than hallucinating.
@MainActor
enum SearchTools {
    /// Always available (read-only); the orchestrator/registry decides whether to
    /// include it based on `flags.webSearchEnabled` + provider.
    static var all: [AnyCoachTool] { [searchWeb] }

    /// Live web-search source. Overridable in tests to inject a stub (no network).
    static var provider: WebSearchProvider = LiveWebSearch()

    private struct SearchArgs: Decodable {
        let query: String
        let count: Int?
        let recency: String?
    }

    private static var searchWeb: AnyCoachTool {
        .make(
            name: "search_web",
            label: "Searching the web",
            description: "Search the LIVE web for real, current information — facts, news, prices, hours, schedules, reviews, products, places, how-tos, anything external. ALWAYS use this instead of guessing for anything you don't already know or that may have changed. `query` is the search string (be specific). `count` is how many results (default 6, max 20). `recency` filters by freshness: one of any|day|week|month|year (use day/week for news/current events). Returns real results with title, url, snippet, publisher — read them, synthesize a grounded answer, and CITE the specific sources you used by putting them in your reply's `sources`. If this returns configured=false, tell the user you don't have live web access configured (don't fabricate).",
            parameters: JSONSchema.object([
                "query": JSONSchema.string,
                "count": ["type": ["integer", "null"]],
                "recency": ["type": ["string", "null"], "enum": ["any", "day", "week", "month", "year"]],
            ], required: ["query", "count", "recency"]),
            argsType: SearchArgs.self
        ) { args, _ in
            let trimmed = args.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .error("query is required.")
            }
            let recency = WebSearchRecency(rawValue: (args.recency ?? "any").lowercased()) ?? .any
            let query = WebSearchQuery(
                query: trimmed,
                count: min(20, max(1, args.count ?? 6)),
                recency: recency
            )
            do {
                let results = try await provider.search(query)
                return .object([
                    "ok": true,
                    "configured": true,
                    "count": results.count,
                    "results": results.map(\.asDictionary),
                    "note": "Real web results. Synthesize a grounded answer and cite the sources you used in your reply's `sources` (title, url, publisher).",
                ])
            } catch WebSearchError.notConfigured {
                return .object([
                    "ok": true,
                    "configured": false,
                    "count": 0,
                    "results": [[String: Any]](),
                    "note": "Live web search isn't configured (no search API key). Tell the user you don't have live web access right now and answer only from what you reliably know — do not fabricate current facts, prices, or links.",
                ])
            } catch WebSearchError.noResults {
                return .object([
                    "ok": true,
                    "configured": true,
                    "count": 0,
                    "results": [[String: Any]](),
                    "note": "No results for that query. Try a broader or rephrased query.",
                ])
            } catch {
                return .object([
                    "ok": false,
                    "configured": true,
                    "count": 0,
                    "results": [[String: Any]](),
                    "note": "Web search failed (\(String(describing: error))). Try again with a simpler query.",
                ])
            }
        }
    }
}
