import Foundation

/// The hosted web-search tool. Unlike function tools it has no local handler  - 
/// OpenAI runs it server-side and returns `web_search_call` output items the
/// orchestrator ignores. Only its spec is contributed to the request.
enum WebSearchTool {
    /// Hosted tool name; "web_search" with a "web_search_preview" fallback if the
    /// account doesn't expose the GA name.
    static let toolName = "web_search"

    static var spec: [String: Any] { ["type": toolName] }
}
