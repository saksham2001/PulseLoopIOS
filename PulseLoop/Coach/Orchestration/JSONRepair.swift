import Foundation

/// Best-effort parsing of the model's final structured output into a
/// `CoachResponse`. Tries a direct decode, then extracts the outermost JSON
/// object if the model wrapped it in prose or a code fence.
enum CoachResponseParser {
    static func parse(_ text: String) -> CoachResponse? {
        let reasoningStripped = stripReasoningTokens(text)
        let trimmed = reasoningStripped.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = CoachResponse.decode(fromJSON: trimmed) { return direct }
        if let stripped = stripCodeFence(trimmed), let r = CoachResponse.decode(fromJSON: stripped) { return r }
        if let object = extractOutermostObject(trimmed), let r = CoachResponse.decode(fromJSON: object) { return r }
        return nil
    }

    /// Reasoning-first specialists (e.g. Nemotron with `detailed thinking on`) can
    /// leak their chain-of-thought into the message body as `<think>…</think>`,
    /// `<reasoning>…</reasoning>`, or `<thinking>…</thinking>` blocks before the JSON
    /// answer. Those blocks can themselves contain `{ }`, which would otherwise
    /// confuse outermost-object extraction. Strip them so only the final answer
    /// (the JSON object) remains. Pure + idempotent.
    static func stripReasoningTokens(_ text: String) -> String {
        var out = text
        for tag in ["think", "reasoning", "thinking", "thought"] {
            out = removeBlocks(open: "<\(tag)>", close: "</\(tag)>", in: out)
            // Some providers emit a closing tag only (open implied at start).
            if let closeRange = out.range(of: "</\(tag)>") {
                out = String(out[closeRange.upperBound...])
            }
        }
        return out
    }

    private static func removeBlocks(open: String, close: String, in text: String) -> String {
        var result = text
        while let openRange = result.range(of: open),
              let closeRange = result.range(of: close, range: openRange.upperBound..<result.endIndex) {
            result.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
        }
        return result
    }

    private static func stripCodeFence(_ text: String) -> String? {
        guard text.hasPrefix("```") else { return nil }
        var body = text
        if let firstNewline = body.firstIndex(of: "\n") {
            body = String(body[body.index(after: firstNewline)...])
        }
        if let fenceRange = body.range(of: "```", options: .backwards) {
            body = String(body[..<fenceRange.lowerBound])
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractOutermostObject(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(text[start...end])
    }
}
