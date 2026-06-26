import Foundation

/// One output item from a Responses API result. We only model what the agent
/// loop needs; everything else collapses to `.other`.
enum ResponseOutputItem: Sendable {
    case message(text: String)
    case functionCall(ResponseFunctionCall)
    case webSearchCall(id: String)
    case other(type: String)
}

struct ResponseFunctionCall: Sendable {
    let name: String
    let callID: String
    let arguments: String
}

/// Parsed, Sendable view of a `POST /v1/responses` result.
struct OpenAIResponse: Sendable {
    let id: String
    let outputItems: [ResponseOutputItem]
    /// Token usage reported by the API, when present. Used for credit metering (E1).
    let usage: TokenUsage?

    struct TokenUsage: Sendable {
        let inputTokens: Int
        let outputTokens: Int
        var totalTokens: Int { inputTokens + outputTokens }
    }

    init(id: String, outputItems: [ResponseOutputItem], usage: TokenUsage? = nil) {
        self.id = id
        self.outputItems = outputItems
        self.usage = usage
    }

    var functionCalls: [ResponseFunctionCall] {
        outputItems.compactMap { if case .functionCall(let fc) = $0 { return fc } else { return nil } }
    }

    var webSearchCallIDs: [String] {
        outputItems.compactMap { if case .webSearchCall(let id) = $0 { return id } else { return nil } }
    }

    /// Concatenated assistant text (the final structured-output JSON lives here).
    var outputText: String {
        outputItems.compactMap { if case .message(let text) = $0 { return text } else { return nil } }
            .joined()
    }

    // MARK: Parsing

    static func parse(_ data: Data) throws -> OpenAIResponse {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ResponsesError.decoding("response was not a JSON object")
        }
        let id = root["id"] as? String ?? ""
        let rawOutput = root["output"] as? [[String: Any]] ?? []
        var items: [ResponseOutputItem] = []
        for item in rawOutput {
            let type = item["type"] as? String ?? ""
            switch type {
            case "message":
                items.append(.message(text: extractText(item)))
            case "function_call":
                let fc = ResponseFunctionCall(
                    name: item["name"] as? String ?? "",
                    callID: item["call_id"] as? String ?? "",
                    arguments: item["arguments"] as? String ?? "{}"
                )
                items.append(.functionCall(fc))
            case "web_search_call":
                items.append(.webSearchCall(id: item["id"] as? String ?? UUID().uuidString))
            default:
                items.append(.other(type: type))
            }
        }
        var usage: OpenAIResponse.TokenUsage?
        if let usageObj = root["usage"] as? [String: Any] {
            let input = (usageObj["input_tokens"] as? Int) ?? (usageObj["prompt_tokens"] as? Int) ?? 0
            let output = (usageObj["output_tokens"] as? Int) ?? (usageObj["completion_tokens"] as? Int) ?? 0
            usage = OpenAIResponse.TokenUsage(inputTokens: input, outputTokens: output)
        }
        return OpenAIResponse(id: id, outputItems: items, usage: usage)
    }

    private static func extractText(_ messageItem: [String: Any]) -> String {
        let content = messageItem["content"] as? [[String: Any]] ?? []
        return content.compactMap { part -> String? in
            let t = part["type"] as? String
            if t == "output_text" || t == "text" { return part["text"] as? String }
            return nil
        }.joined()
    }
}

/// Builds the `[String: Any]` request body for a Responses turn and serializes
/// it. Kept dictionary-based because tool specs and the strict output schema are
/// naturally arbitrary JSON.
enum OpenAIRequestBuilder {
    /// One input message item. Plain-text by default; when `imageDataURLs` are
    /// provided the content becomes a multimodal part array (text + image_url)
    /// so vision-capable models can read attached photos. The OpenRouter chat
    /// bridge passes the array straight through to chat-completions, which uses
    /// the same `{type:"image_url", image_url:{url}}` shape.
    static func message(role: String, content: String, imageDataURLs: [String] = []) -> [String: Any] {
        guard !imageDataURLs.isEmpty else {
            return ["role": role, "content": content]
        }
        var parts: [[String: Any]] = []
        if !content.isEmpty {
            parts.append(["type": "text", "text": content])
        }
        for url in imageDataURLs {
            parts.append(["type": "image_url", "image_url": ["url": url]])
        }
        return ["role": role, "content": parts]
    }

    /// A function-call result item to feed back into the next turn.
    static func functionCallOutput(callID: String, output: String) -> [String: Any] {
        ["type": "function_call_output", "call_id": callID, "output": output]
    }

    static func body(
        model: String,
        input: [[String: Any]],
        tools: [[String: Any]],
        textFormat: [String: Any]?,
        previousResponseId: String?,
        reasoningEffort: String?
    ) -> [String: Any] {
        var body: [String: Any] = ["model": model, "input": input]
        if !tools.isEmpty { body["tools"] = tools }
        if let textFormat { body["text"] = ["format": textFormat] }
        if let previousResponseId { body["previous_response_id"] = previousResponseId }
        if let reasoningEffort, !reasoningEffort.isEmpty { body["reasoning"] = ["effort": reasoningEffort] }
        return body
    }

    static func data(
        model: String,
        input: [[String: Any]],
        tools: [[String: Any]],
        textFormat: [String: Any]?,
        previousResponseId: String?,
        reasoningEffort: String?
    ) throws -> Data {
        let dict = body(model: model, input: input, tools: tools, textFormat: textFormat,
                        previousResponseId: previousResponseId, reasoningEffort: reasoningEffort)
        return try JSONSerialization.data(withJSONObject: dict, options: [.withoutEscapingSlashes])
    }
}
