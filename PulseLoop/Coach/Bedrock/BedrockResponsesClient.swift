import Foundation

/// `ResponsesClient` that runs the coach against **Anthropic Claude on AWS
/// Bedrock** using only on-device IAM credentials (no PulseLoop server).
///
/// ## Why this is non-trivial
/// The orchestrator speaks the **OpenAI Responses** wire format (an `input[]`
/// array of message / `function_call_output` items, OpenAI-style `tools`, a
/// strict `text.format` JSON schema, and `previous_response_id` for server-side
/// conversation state) and expects an `OpenAIResponse` back. Bedrock speaks the
/// **Anthropic Messages** format, authenticates with **AWS SigV4** (not a bearer
/// token), and is **stateless** (no `previous_response_id`). This client bridges
/// all of that:
///   1. Translates the Responses request body → an Anthropic Messages body.
///   2. Because Bedrock has no server-side state, it keeps the running
///      `messages[]` transcript **in memory**, keyed by the synthetic response id
///      it hands back, and rehydrates it when the orchestrator sends a follow-up
///      round with `previous_response_id`.
///   3. Signs the request with SigV4 and POSTs to the `bedrock-runtime`
///      `InvokeModel` endpoint.
///   4. Translates the Anthropic response (`text` / `tool_use` blocks + `usage`)
///      back into an `OpenAIResponse`.
///
/// ## Structured-output fidelity
/// Anthropic has no exact analogue of OpenAI's `text.format` strict schema, so the
/// requested JSON schema is injected into the system prompt with a firm
/// instruction to emit only conforming JSON. The orchestrator already has a
/// JSON-repair round, which covers the residual risk.
///
/// This is a `final class` (not a `struct`) because it owns mutable conversation
/// state; access is serialized through an `actor` cache to stay `Sendable`.
final class BedrockResponsesClient: ResponsesClient, @unchecked Sendable {
    private let credentials: AWSSigV4Signer.Credentials
    private let region: String
    private let modelID: String
    private let session: URLSession
    private let store = ConversationStore()

    init(
        accessKeyID: String,
        secretAccessKey: String,
        sessionToken: String?,
        region: String,
        modelID: String,
        session: URLSession = .shared
    ) {
        self.credentials = AWSSigV4Signer.Credentials(
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken
        )
        self.region = region
        self.modelID = modelID
        self.session = session
    }

    func send(requestBody: Data) async throws -> OpenAIResponse {
        guard !credentials.accessKeyID.isEmpty, !credentials.secretAccessKey.isEmpty else {
            throw ResponsesError.missingAPIKey
        }
        guard let root = (try? JSONSerialization.jsonObject(with: requestBody)) as? [String: Any] else {
            throw ResponsesError.decoding("request body was not a JSON object")
        }

        // Reconstruct the full transcript. On the first round there's no
        // previous id; on later rounds rehydrate prior turns from the cache.
        let previousId = root["previous_response_id"] as? String
        var transcript = await store.transcript(for: previousId)

        let (systemText, newMessages) = Self.translateInput(
            root["input"],
            textFormat: (root["text"] as? [String: Any])?["format"] as? [String: Any]
        )
        transcript.append(contentsOf: newMessages)

        let anthropicTools = Self.translateTools(root["tools"] as? [[String: Any]] ?? [])

        var body: [String: Any] = [
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "messages": transcript,
        ]
        if !systemText.isEmpty { body["system"] = systemText }
        if !anthropicTools.isEmpty { body["tools"] = anthropicTools }

        let payload = try JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes])

        // Bedrock InvokeModel endpoint. The model id is path-encoded by the signer.
        let host = "bedrock-runtime.\(region).amazonaws.com"
        guard let url = URL(string: "https://\(host)/model/\(modelID)/invoke") else {
            throw ResponsesError.decoding("invalid Bedrock endpoint for model \(modelID)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = payload
        request.timeoutInterval = 60
        AWSSigV4Signer.sign(&request, service: "bedrock", region: region, credentials: credentials)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ResponsesError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ResponsesError.http(status: http.statusCode, body: bodyText)
        }

        let (parsed, assistantMessage) = try Self.translateResponse(data, modelID: modelID)
        // Record the assistant turn so a follow-up round can rebuild the transcript.
        transcript.append(assistantMessage)
        await store.save(transcript, for: parsed.id)
        return parsed
    }

    // MARK: - Request translation (OpenAI Responses → Anthropic Messages)

    /// Translates the Responses `input` array into Anthropic `messages` plus any
    /// extracted system text (the strict-schema instruction). Roles map directly;
    /// `function_call_output` items become `tool_result` user-turn blocks.
    private static func translateInput(
        _ input: Any?,
        textFormat: [String: Any]?
    ) -> (system: String, messages: [[String: Any]]) {
        var messages: [[String: Any]] = []
        var systemParts: [String] = []
        let items = (input as? [[String: Any]]) ?? []

        for item in items {
            if let type = item["type"] as? String, type == "function_call_output" {
                let callID = item["call_id"] as? String ?? ""
                let output = item["output"] as? String ?? ""
                messages.append([
                    "role": "user",
                    "content": [[
                        "type": "tool_result",
                        "tool_use_id": callID,
                        "content": output,
                    ]],
                ])
                continue
            }

            let role = item["role"] as? String ?? "user"
            let content = item["content"] as? String ?? ""
            // Anthropic takes system prompts in a separate field and rejects
            // non-alternating roles. Fold "system"/"developer" turns into the system
            // string rather than emitting them as extra leading user messages.
            if role == "system" || role == "developer" {
                if !content.isEmpty { systemParts.append(content) }
                continue
            }
            messages.append([
                "role": role == "assistant" ? "assistant" : "user",
                "content": content,
            ])
        }

        if let format = textFormat {
            systemParts.append(Self.schemaInstruction(format))
        }
        return (systemParts.joined(separator: "\n\n"), messages)
    }

    /// Builds a system instruction that asks the model to emit only JSON matching
    /// the requested strict schema (Anthropic has no native `text.format`).
    private static func schemaInstruction(_ format: [String: Any]) -> String {
        let schema = format["schema"] ?? format
        let schemaText = (try? JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        You must respond with a single JSON object that strictly conforms to this JSON Schema. \
        Output ONLY the JSON object. No markdown, no code fences, no commentary.

        JSON Schema:
        \(schemaText)
        """
    }

    /// Translates OpenAI function tools → Anthropic tools (`input_schema`).
    private static func translateTools(_ tools: [[String: Any]]) -> [[String: Any]] {
        tools.compactMap { tool in
            // OpenAI Responses tools are either {type:"function", name, parameters,...}
            // or wrap the function under a "function" key. Built-in tools like
            // web_search have no Anthropic analogue and are skipped.
            let type = tool["type"] as? String
            if type == "web_search" || type == "web_search_preview" { return nil }

            let fn = (tool["function"] as? [String: Any]) ?? tool
            guard let name = fn["name"] as? String else { return nil }
            let description = fn["description"] as? String ?? ""
            let parameters = (fn["parameters"] as? [String: Any]) ?? ["type": "object", "properties": [:]]
            return [
                "name": name,
                "description": description,
                "input_schema": parameters,
            ]
        }
    }

    // MARK: - Response translation (Anthropic → OpenAIResponse)

    /// Returns the parsed `OpenAIResponse` plus the assistant message (in
    /// Anthropic format) to append to the cached transcript.
    private static func translateResponse(
        _ data: Data,
        modelID: String
    ) throws -> (OpenAIResponse, [String: Any]) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ResponsesError.decoding("Bedrock response was not a JSON object")
        }

        let id = root["id"] as? String ?? UUID().uuidString
        let contentBlocks = root["content"] as? [[String: Any]] ?? []

        var items: [ResponseOutputItem] = []
        // Keep the raw assistant content for the transcript so tool_use ids line up.
        var assistantContent: [[String: Any]] = []

        for block in contentBlocks {
            let type = block["type"] as? String ?? ""
            switch type {
            case "text":
                let text = block["text"] as? String ?? ""
                items.append(.message(text: text))
                assistantContent.append(["type": "text", "text": text])
            case "tool_use":
                let name = block["name"] as? String ?? ""
                let toolID = block["id"] as? String ?? UUID().uuidString
                let inputObj = block["input"] ?? [:]
                let argsData = (try? JSONSerialization.data(withJSONObject: inputObj, options: [.withoutEscapingSlashes])) ?? Data("{}".utf8)
                let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                items.append(.functionCall(ResponseFunctionCall(name: name, callID: toolID, arguments: argsString)))
                assistantContent.append([
                    "type": "tool_use",
                    "id": toolID,
                    "name": name,
                    "input": inputObj,
                ])
            default:
                items.append(.other(type: type))
            }
        }

        var usage: OpenAIResponse.TokenUsage?
        if let usageObj = root["usage"] as? [String: Any] {
            let input = usageObj["input_tokens"] as? Int ?? 0
            let output = usageObj["output_tokens"] as? Int ?? 0
            usage = OpenAIResponse.TokenUsage(inputTokens: input, outputTokens: output)
        }

        let parsed = OpenAIResponse(id: id, outputItems: items, usage: usage)
        let assistantMessage: [String: Any] = ["role": "assistant", "content": assistantContent]
        return (parsed, assistantMessage)
    }

    // MARK: - Conversation state

    /// Serializes access to the per-response transcript cache. Bounded so a long
    /// session doesn't grow without limit.
    private actor ConversationStore {
        private var byResponseID: [String: [[String: Any]]] = [:]
        private var order: [String] = []
        private let limit = 32

        func transcript(for previousID: String?) -> [[String: Any]] {
            guard let previousID, let existing = byResponseID[previousID] else { return [] }
            return existing
        }

        func save(_ transcript: [[String: Any]], for responseID: String) {
            if byResponseID[responseID] == nil {
                order.append(responseID)
            }
            byResponseID[responseID] = transcript
            while order.count > limit {
                let evicted = order.removeFirst()
                byResponseID.removeValue(forKey: evicted)
            }
        }
    }
}
