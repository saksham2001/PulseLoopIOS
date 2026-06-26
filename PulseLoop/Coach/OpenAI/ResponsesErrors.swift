import Foundation

/// Errors surfaced by the Responses client. The orchestrator catches these and
/// degrades to a graceful fallback rather than crashing the chat.
enum ResponsesError: Error, LocalizedError {
    case missingAPIKey
    case insufficientCredits
    case transport(Error)
    case http(status: Int, body: String)
    case decoding(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No OpenAI API key configured."
        case .insufficientCredits: return "You're out of AI credits. Add more to keep using the assistant."
        case .transport(let e): return "Network error: \(e.localizedDescription)"
        case .http(let status, let body): return "OpenAI returned HTTP \(status): \(body.prefix(200))"
        case .decoding(let msg): return "Could not parse OpenAI response: \(msg)"
        case .emptyOutput: return "OpenAI returned no output."
        }
    }
}
