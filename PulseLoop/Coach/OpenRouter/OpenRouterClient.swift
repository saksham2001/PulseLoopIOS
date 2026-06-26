import Foundation

/// Adapts the app's `ResponsesClient` protocol to OpenRouter's OpenAI-compatible
/// **Chat Completions** API (`POST /api/v1/chat/completions`). OpenRouter is an
/// aggregator: `model` is a `vendor/model` slug (e.g. `anthropic/claude-sonnet-4.6`)
/// that it routes to the underlying provider. Translates the app's Responses-API
/// request bodies into Chat Completions requests and maps responses back, so no
/// other component needs to know which provider is active.
///
/// State across turns: the OpenAI Responses API is stateful (server tracks
/// history via `previous_response_id`); Chat Completions is stateless (caller
/// sends the full message list each time). This class accumulates the
/// conversation as Chat Completions `messages` across `send` calls; each instance
/// covers exactly one agent turn (the orchestrator creates a fresh client per
/// turn via the factory).
final class OpenRouterClient: ResponsesClient, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    // Accumulated Chat Completions messages for this turn.
    private var messages: [[String: Any]] = []
    // Maps generated response IDs → the assistant message dict (content + tool_calls)
    // so a continuation turn can re-insert it before the matching tool results.
    private var storedAssistantMessage: [String: [String: Any]] = [:]

    init(apiKey: String, model: String = OpenRouterModel.default.rawValue, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func send(requestBody: Data) async throws -> OpenAIResponse {
        guard !apiKey.isEmpty else { throw ResponsesError.missingAPIKey }

        guard let req = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any] else {
            throw ResponsesError.decoding("OpenRouterClient: invalid request body")
        }

        let input = req["input"] as? [[String: Any]] ?? []
        let tools = req["tools"] as? [[String: Any]] ?? []
        let previousResponseId = req["previous_response_id"] as? String
        // OpenRouter accepts the same unified `reasoning` object the app already
        // builds (`{ "effort": "low|medium|high" }`); it's ignored for models that
        // don't reason, so forward it as-is when present.
        let reasoning = req["reasoning"]

        if previousResponseId == nil {
            setupConversation(from: input)
        } else {
            appendContinuation(previousId: previousResponseId!, input: input)
        }

        let body = buildChatBody(tools: convertTools(tools), reasoning: reasoning)
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes])

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Optional attribution headers OpenRouter uses for its app leaderboard.
        request.setValue("https://github.com/hoveeman/PulseLoopIOS", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("PulseLoop", forHTTPHeaderField: "X-Title")
        request.httpBody = bodyData
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ResponsesError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ResponsesError.http(status: http.statusCode, body: body)
        }

        return try parseChatResponse(data)
    }

    // MARK: - Conversation setup

    /// First turn: convert the Responses `input` items into Chat Completions
    /// `messages`. Responses uses a `developer` role; Chat Completions doesn't, so
    /// fold it into `system`.
    private func setupConversation(from input: [[String: Any]]) {
        messages = []
        storedAssistantMessage = [:]
        for item in input {
            guard let role = item["role"] as? String,
                  let content = item["content"] as? String else { continue }
            messages.append(["role": chatRole(role), "content": content])
        }
    }

    /// Subsequent turns: replay the stored assistant message for `previousId`
    /// (Chat Completions requires the assistant `tool_calls` message to precede the
    /// `tool` results answering them), then append the new tool results / messages.
    private func appendContinuation(previousId: String, input: [[String: Any]]) {
        if let assistant = storedAssistantMessage[previousId] {
            messages.append(assistant)
        }
        for item in input {
            if (item["type"] as? String) == "function_call_output",
               let callId = item["call_id"] as? String,
               let output = item["output"] as? String {
                messages.append(["role": "tool", "tool_call_id": callId, "content": output])
            } else if let role = item["role"] as? String,
                      let content = item["content"] as? String {
                messages.append(["role": chatRole(role), "content": content])
            }
        }
    }

    private func chatRole(_ responsesRole: String) -> String {
        responsesRole == "developer" ? "system" : responsesRole
    }

    // MARK: - Tool conversion (Responses flat → Chat Completions nested)

    /// Converts the app's flat Responses function specs
    /// (`{type, name, description, parameters}`) into Chat Completions' nested
    /// shape (`{type: function, function: {...}}`). The OpenAI-hosted
    /// `web_search` tool (type != "function") has no Chat Completions equivalent
    /// and is silently dropped, matching the Gemini adapter. (OpenRouter offers web
    /// search via a `:online` model suffix or a `plugins` entry — a future option.)
    private func convertTools(_ tools: [[String: Any]]) -> [[String: Any]] {
        tools.compactMap { tool -> [String: Any]? in
            guard (tool["type"] as? String) == "function",
                  let name = tool["name"] as? String else { return nil }
            var fn: [String: Any] = ["name": name]
            if let desc = tool["description"] as? String { fn["description"] = desc }
            if let params = tool["parameters"] as? [String: Any] { fn["parameters"] = params }
            if let strict = tool["strict"] as? Bool { fn["strict"] = strict }
            return ["type": "function", "function": fn]
        }
    }

    // MARK: - Build request body

    private func buildChatBody(tools: [[String: Any]], reasoning: Any?) -> [String: Any] {
        var body: [String: Any] = ["model": model, "messages": cacheControlledMessages()]

        if !tools.isEmpty {
            // Cache the (large, static) tool block — re-sent on every round and
            // identical across questions. A breakpoint on the last tool caches the
            // whole tools prefix on providers that support it (Anthropic, etc.);
            // OpenRouter strips `cache_control` for providers that don't.
            var cachedTools = tools
            cachedTools[cachedTools.count - 1]["cache_control"] = ["type": "ephemeral"]
            body["tools"] = cachedTools
        }

        // Deliberately NO `response_format`. OpenAI-style `json_schema` (and even
        // `json_object`) isn't reliably accepted across OpenRouter's catalog — in
        // particular Anthropic rejects this app's OpenAI-shaped coach_response schema
        // (maxLength / maxItems / union-null types its structured outputs don't
        // support), which broke the tool-less repair turn. The system prompt already
        // demands the coach_response JSON and the orchestrator runs a 3-attempt JSON
        // repair loop, so we let the model comply via the prompt instead.

        if let reasoning { body["reasoning"] = reasoning }

        return body
    }

    // MARK: - Prompt caching

    /// Returns `messages` with Anthropic-style `cache_control` breakpoints on the
    /// system messages so the large static prefix isn't re-billed at full price on
    /// every tool-loop round / question. The first system message (the static coach
    /// system prompt) caches cross-question; the last (the per-question data context)
    /// caches across this question's rounds. `cache_control` is ignored by providers
    /// that don't support it.
    private func cacheControlledMessages() -> [[String: Any]] {
        var out = messages
        let systemIdxs = out.indices.filter { (out[$0]["role"] as? String) == "system" }
        if let first = systemIdxs.first { out[first] = withCacheControl(out[first]) }
        if let last = systemIdxs.last, last != systemIdxs.first { out[last] = withCacheControl(out[last]) }
        return out
    }

    /// Converts a string-content message into the Chat Completions content-array
    /// form carrying a `cache_control` breakpoint.
    private func withCacheControl(_ message: [String: Any]) -> [String: Any] {
        guard let text = message["content"] as? String else { return message }
        var m = message
        m["content"] = [["type": "text", "text": text, "cache_control": ["type": "ephemeral"]]]
        return m
    }

    // MARK: - Parse Chat Completions response → OpenAIResponse

    private func parseChatResponse(_ data: Data) throws -> OpenAIResponse {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ResponsesError.decoding("OpenRouterClient: response was not a JSON object")
        }

        // OpenRouter can surface an upstream provider error in an `error` object
        // even on an HTTP 200.
        if let err = root["error"] as? [String: Any] {
            let msg = err["message"] as? String ?? "unknown error"
            throw ResponsesError.decoding("OpenRouter error: \(msg)")
        }

        guard let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ResponsesError.decoding("OpenRouterClient: no choices in response — \(body.prefix(300))")
        }

        let responseId = (root["id"] as? String).map { $0.isEmpty ? UUID().uuidString : $0 } ?? UUID().uuidString
        var outputItems: [ResponseOutputItem] = []
        // Persist the raw assistant message so a continuation turn can replay it.
        var assistantMessage: [String: Any] = ["role": "assistant"]

        if let content = message["content"] as? String, !content.isEmpty {
            outputItems.append(.message(text: content))
            assistantMessage["content"] = content
        } else {
            // Chat Completions allows null content when tool_calls are present.
            assistantMessage["content"] = NSNull()
        }

        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            var storedCalls: [[String: Any]] = []
            for call in toolCalls {
                guard let fn = call["function"] as? [String: Any],
                      let name = fn["name"] as? String else { continue }
                // Reuse OpenRouter's own tool_call id as the orchestrator's call_id so
                // the tool result message can reference it on the next turn.
                let callId = (call["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? "or_call_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
                let args = fn["arguments"] as? String ?? "{}"
                outputItems.append(.functionCall(ResponseFunctionCall(name: name, callID: callId, arguments: args)))
                storedCalls.append([
                    "id": callId,
                    "type": "function",
                    "function": ["name": name, "arguments": args],
                ])
            }
            if !storedCalls.isEmpty { assistantMessage["tool_calls"] = storedCalls }
        }

        if outputItems.isEmpty { throw ResponsesError.emptyOutput }

        storedAssistantMessage[responseId] = assistantMessage
        return OpenAIResponse(id: responseId, outputItems: outputItems)
    }
}
