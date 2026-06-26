import Foundation

/// Bridges the Coach's OpenAI Responses-API agent loop onto OpenRouter's
/// (stateless) OpenAI-*chat-completions*-compatible endpoint.
///
/// The orchestrator (`CoachOrchestrator`) speaks the Responses API: it sends a
/// serialized `{model, input, tools, text.format, previous_response_id}` body and
/// expects an `OpenAIResponse` back, relying on `previous_response_id` for
/// server-side conversation state. OpenRouter has neither `/v1/responses` nor
/// server-side state, so this client:
///   1. accumulates the full chat `messages` history itself across turns, and
///   2. translates each request to chat-completions and each reply back to an
///      `OpenAIResponse`.
///
/// Implemented as an `actor` so the mutable message buffer is safe to share
/// across the loop's awaits while still satisfying `ResponsesClient: Sendable`.
actor OpenRouterResponsesClient: ResponsesClient {
    private let apiKey: String
    private let endpoint: URL
    private let session: URLSession

    /// Full chat-completions message history for this conversation. Grows each
    /// `send` because OpenRouter is stateless (no `previous_response_id`).
    private var messages: [[String: Any]] = []

    /// Upper bound on output tokens per request. Without this, OpenRouter reserves
    /// each model's *default* max output (64k+ on large models) up front and rejects
    /// the call with HTTP 402 unless the balance can cover that worst case. The
    /// coach reply is a small JSON object, so this cap is generous while keeping
    /// turns affordable.
    private static let maxOutputTokens = 8192

    /// `tool_calls` emitted by the most recent assistant turn. Held so the next
    /// `send` (which carries the matching `function_call_output` results) can
    /// re-emit the assistant message that requested them — chat-completions
    /// requires each `tool` message to follow an assistant message with the
    /// corresponding `tool_calls`.
    private var pendingToolCalls: [[String: Any]] = []

    init(
        apiKey: String,
        endpoint: URL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.session = session
    }

    func send(requestBody: Data) async throws -> OpenAIResponse {
        guard !apiKey.isEmpty else { throw ResponsesError.missingAPIKey }

        guard let root = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any] else {
            throw ResponsesError.decoding("request body was not a JSON object")
        }

        let model = root["model"] as? String ?? AIModel.smart.toolCapableResolvedSlug
        ingestInput(root["input"] as? [[String: Any]] ?? [])

        let chatToolList = chatTools(from: root["tools"] as? [[String: Any]] ?? [])
        let hasTools = !(chatToolList?.isEmpty ?? true)
        let wantsStructured = responseFormat(from: root["text"] as? [String: Any]) != nil

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            // Cap output so OpenRouter doesn't reserve the model's full context
            // window (some models default to 64k+), which forces a 402 "requires
            // more credits" even on a tiny balance. The coach_response JSON is small
            // (summary <= 900 chars, <= 5 bullets), so 8k is comfortably enough.
            "max_tokens": Self.maxOutputTokens,
        ]
        if let chatToolList, hasTools {
            body["tools"] = chatToolList
        }

        // Gemini (and some other providers) reject `response_format` json mode when
        // `tools` are also present ("Function calling with a response mime type ...
        // is unsupported"), and reject the full strict schema as "too many states".
        // So: never send the giant strict schema. Only request lightweight JSON-object
        // mode on tool-free turns, and steer shape via a prompt nudge instead.
        if wantsStructured {
            if !hasTools {
                body["response_format"] = ["type": "json_object"]
            }
            ensureJSONInstruction()
            // The messages array was mutated; reflect it in the body.
            body["messages"] = messages
        }

        let data = try await post(body)
        let parsed = try parseChatCompletion(data)

        // Record the assistant turn so the next request's tool results (and any
        // follow-up turns) have correct conversation history.
        recordAssistantTurn(parsed)
        return parsed
    }

    /// Whether the `coach_response` JSON-shape nudge has been injected this
    /// conversation (added once, kept in history thereafter).
    private var didInjectJSONInstruction = false

    /// Appends a single system message describing the required `coach_response`
    /// JSON shape. Used in place of a provider-specific strict schema so the loop
    /// works across Gemini/GLM/Claude/GPT. The orchestrator's repair loop catches
    /// any malformed output.
    private func ensureJSONInstruction() {
        guard !didInjectJSONInstruction else { return }
        didInjectJSONInstruction = true
        messages.append([
            "role": "system",
            "content": Self.coachJSONInstruction,
        ])
    }

    private static let coachJSONInstruction = """
    IMPORTANT OUTPUT CONTRACT: Every time you reply to the user (including simple greetings), your message content MUST be ONLY a single JSON object — no markdown, no code fences, no text before or after. Use this exact shape:
    {
      "response_type": one of "insight","insight_with_chart","question","action_confirmation","data_missing","safety_guidance","error_recovery",
      "title": string (<= 90 chars),
      "summary": string (<= 900 chars),
      "bullets": array of strings (<= 5),
      "chart": null,
      "safety_note": string or null,
      "data_quality_note": string or null,
      "sources": array of {"title": string, "url": string, "publisher": string},
      "follow_up_chips": array of strings (<= 4),
      "actions_taken": array of strings,
      "confidence": one of "low","medium","high",
      "media": [],
      "diagram": null
    }
    Every key is required. To call a tool, use the normal tool-call mechanism (not JSON in content). Only your FINAL textual answer must be this JSON object.
    """

    // MARK: - Request translation

    /// Appends incoming Responses `input` items to the chat history.
    private func ingestInput(_ input: [[String: Any]]) {
        // Tool results arrive together; emit the assistant `tool_calls` message
        // they answer first (once), then the individual tool messages.
        let toolOutputs = input.filter { ($0["type"] as? String) == "function_call_output" }
        if !pendingToolCalls.isEmpty {
            if !toolOutputs.isEmpty {
                // Normal case: the assistant requested tools and the results are here.
                messages.append([
                    "role": "assistant",
                    "content": NSNull(),
                    "tool_calls": pendingToolCalls,
                ])
            } else {
                // Orphaned tool calls: a new user/repair turn arrived without the
                // matching results (e.g. the round budget was hit, or the orchestrator
                // is asking for a plain final). A chat-completions history with an
                // assistant `tool_calls` and no following `tool` messages is invalid
                // and 400s, so drop the dangling request rather than corrupt history.
                NSLog("[OpenRouterCoach] dropping %d orphaned tool_calls (no results before next turn)", pendingToolCalls.count)
            }
            pendingToolCalls = []
        }

        for item in input {
            if (item["type"] as? String) == "function_call_output" {
                messages.append([
                    "role": "tool",
                    "tool_call_id": item["call_id"] as? String ?? "",
                    "content": item["output"] as? String ?? "",
                ])
            } else if let role = item["role"] as? String {
                // Responses uses a `developer` role; chat-completions uses `system`.
                let mapped = role == "developer" ? "system" : role
                // Content may be a plain string or a multimodal part array
                // (text + image_url) — pass either straight through; chat
                // completions accepts the same content-part shape.
                let content: Any = item["content"] ?? ""
                messages.append([
                    "role": mapped,
                    "content": content,
                ])
            }
        }
    }

    /// Converts flat Responses function specs to nested chat-completions specs,
    /// dropping any non-function (hosted) tools like `web_search`.
    private func chatTools(from tools: [[String: Any]]) -> [[String: Any]]? {
        let functions = tools.compactMap { spec -> [String: Any]? in
            guard (spec["type"] as? String) == "function", let name = spec["name"] as? String else {
                return nil
            }
            var function: [String: Any] = ["name": name]
            if let description = spec["description"] as? String { function["description"] = description }
            if let parameters = spec["parameters"] as? [String: Any] { function["parameters"] = parameters }
            return ["type": "function", "function": function]
        }
        return functions
    }

    /// Maps Responses `text.format` (json_schema) to chat-completions
    /// `response_format`.
    private func responseFormat(from text: [String: Any]?) -> [String: Any]? {
        guard let format = text?["format"] as? [String: Any],
              (format["type"] as? String) == "json_schema",
              let schema = format["schema"] as? [String: Any] else {
            return nil
        }
        return [
            "type": "json_schema",
            "json_schema": [
                "name": format["name"] as? String ?? "response",
                "strict": format["strict"] as? Bool ?? true,
                "schema": schema,
            ],
        ]
    }

    // MARK: - Networking

    private func post(_ body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("PulseLoop iOS", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ResponsesError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            NSLog("[OpenRouterCoach] HTTP %d: %@", http.statusCode, String(bodyText.prefix(800)))
            if http.statusCode == 402 { throw ResponsesError.insufficientCredits }
            throw ResponsesError.http(status: http.statusCode, body: bodyText)
        }
        return data
    }

    // MARK: - Response translation

    /// Parses a chat-completions reply into the `OpenAIResponse` shape the
    /// orchestrator expects (message text + function calls + usage).
    private func parseChatCompletion(_ data: Data) throws -> OpenAIResponse {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ResponsesError.decoding("response was not a JSON object")
        }
        let id = root["id"] as? String ?? UUID().uuidString
        guard let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            NSLog("[OpenRouterCoach] no choices/message in reply: %@", String((String(data: data, encoding: .utf8) ?? "").prefix(800)))
            throw ResponsesError.emptyOutput
        }

        var items: [ResponseOutputItem] = []
        if let content = message["content"] as? String, !content.isEmpty {
            items.append(.message(text: content))
        }
        for call in message["tool_calls"] as? [[String: Any]] ?? [] {
            guard let function = call["function"] as? [String: Any] else { continue }
            items.append(.functionCall(ResponseFunctionCall(
                name: function["name"] as? String ?? "",
                callID: call["id"] as? String ?? "",
                arguments: function["arguments"] as? String ?? "{}"
            )))
        }

        var usage: OpenAIResponse.TokenUsage?
        if let usageObj = root["usage"] as? [String: Any] {
            let input = (usageObj["prompt_tokens"] as? Int) ?? (usageObj["input_tokens"] as? Int) ?? 0
            let output = (usageObj["completion_tokens"] as? Int) ?? (usageObj["output_tokens"] as? Int) ?? 0
            usage = OpenAIResponse.TokenUsage(inputTokens: input, outputTokens: output)
        }

        return OpenAIResponse(id: id, outputItems: items, usage: usage)
    }

    /// Persists the assistant's reply to the running history. When the model
    /// asked for tools, stash the raw `tool_calls` so the next request can emit
    /// the matching assistant message ahead of the tool results.
    private func recordAssistantTurn(_ response: OpenAIResponse) {
        let toolCalls: [[String: Any]] = response.functionCalls.map { fc in
            [
                "id": fc.callID,
                "type": "function",
                "function": ["name": fc.name, "arguments": fc.arguments],
            ]
        }
        if toolCalls.isEmpty {
            // Pure text turn: record it as assistant content.
            messages.append(["role": "assistant", "content": response.outputText])
            pendingToolCalls = []
        } else {
            // Defer emitting until the tool results come back (so the tool
            // messages immediately follow their assistant `tool_calls`).
            pendingToolCalls = toolCalls
        }
    }
}
