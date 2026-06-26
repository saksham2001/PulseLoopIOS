import Foundation

// MARK: - Live web search facade (Assistant+ T1)
//
// Wraps the configured web-search provider behind one type the coach tool calls.
// Default provider is Brave Search; injectable for tests. Degrades gracefully:
// `isConfigured` is false when no key is set, and `search` surfaces
// `WebSearchError.notConfigured` so the tool reports `configured:false`.
struct LiveWebSearch: WebSearchProvider {
    private let provider: WebSearchProvider

    init(provider: WebSearchProvider = BraveWebSearchProvider()) {
        self.provider = provider
    }

    var isConfigured: Bool { provider.isConfigured }

    func search(_ query: WebSearchQuery) async throws -> [WebSearchResult] {
        try await provider.search(query)
    }
}
