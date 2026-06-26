import Foundation
import SwiftData

/// Central AI service using OpenRouter for all AI-native features across the app.
/// Provides streaming and non-streaming completions via OpenRouter's OpenAI-compatible API.
@MainActor
@Observable
final class AIService {
    static let shared = AIService()

    private let keyStore: APIKeyStore = OpenRouterKeychainStore()
    private let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let deviceTokenStore = CloudSyncKeychainStore()

    // MARK: - Backend proxy (server-held key)
    //
    // Preferred transport: when the device is paired to the web backend, all AI
    // calls route through `POST {web}/api/v1/ai/complete`, authenticated with the
    // paired device token. The OpenRouter key then lives ONLY on the server and is
    // never shipped to the device. We fall back to a direct OpenRouter call (using
    // a local key, if any) when the device isn't paired or the web URL is unset.

    /// Base URL of the web backend (same resolution as `CloudSyncService`).
    private var webBaseURL: URL? {
        guard let override = Bundle.main.object(forInfoDictionaryKey: "PULSELOOP_WEB_URL") as? String else { return nil }
        let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let host = url.host else { return nil }
        let isLocal = host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local")
        #if DEBUG
        return url
        #else
        return isLocal ? nil : url
        #endif
    }

    /// The paired device token, when present.
    private var deviceToken: String? {
        guard let token = (try? deviceTokenStore.readKey()) ?? nil, !token.isEmpty else { return nil }
        return token
    }

    /// The proxy endpoint to use when paired + configured, else nil.
    private var proxyEndpoint: URL? {
        guard deviceToken != nil, let base = webBaseURL else { return nil }
        return base.appendingPathComponent("api/v1/ai/complete")
    }

    /// Resolves the OpenRouter API key at runtime. Never embeds a secret in the
    /// binary: prefers a key stored in the Keychain, then a build-time value
    /// supplied via the `OPENROUTER_API_KEY` environment variable or Info.plist
    /// entry. Throws `AIError.missingAPIKey` when none is available so callers
    /// fail gracefully instead of sending an unauthenticated request.
    private func resolvedAPIKey() throws -> String {
        if let stored = (try? keyStore.readKey()) ?? nil, !stored.isEmpty {
            return stored
        }
        if let env = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let key = env.trimmingCharacters(in: .whitespacesAndNewlines)
            // Persist an env-supplied key into the Keychain so subsequent launches
            // (from the home screen, without the env var) keep working.
            try? keyStore.saveKey(key)
            return key
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "OPENROUTER_API_KEY") as? String {
            let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
            // Ignore the committed placeholder so AI fails gracefully (rather than
            // sending a bogus 401-bound request) until a real key is dropped in.
            if !trimmed.isEmpty, trimmed != "REPLACE_WITH_YOUR_OPENROUTER_KEY" {
                return trimmed
            }
        }
        throw AIError.missingAPIKey
    }

    /// True when AI can run: either the device is paired to the backend proxy
    /// (server holds the key) OR a local OpenRouter key is available. UI uses this
    /// to enable/disable AI affordances.
    var hasAPIKey: Bool {
        proxyEndpoint != nil || (try? resolvedAPIKey()) != nil
    }

    /// The resolved OpenRouter key, or nil when none is configured. Lets other
    /// OpenRouter-backed components (e.g. the Coach's `OpenRouterResponsesClient`)
    /// reuse the same Keychain -> env -> Info.plist resolution.
    var currentAPIKey: String? {
        (try? resolvedAPIKey())
    }

    /// Lets the user supply their own OpenRouter key (stored in the Keychain).
    func saveAPIKey(_ key: String) throws {
        try keyStore.saveKey(key)
    }

    /// The model used for each tier. Resolved at call time from a user override
    /// (`@AppStorage` via `AIModelPreferences`) falling back to the tier default.
    /// Centralizes all OpenRouter model selection so call sites pick a *tier*
    /// (smart/fast/vision/reasoning) instead of hard-coding a slug.
    private var fastModel: String { AIModel.fast.resolvedSlug }
    private var smartModel: String { AIModel.smart.resolvedSlug }

    var isProcessing = false

    struct Message {
        let role: String
        /// Either a plain string, or a multimodal content-part array
        /// (`[["type":"text",...],["type":"image_url",...]]`). Stored as `Any` so
        /// it serializes straight into the OpenRouter `messages[].content` field.
        let content: Any

        init(role: String, content: String) {
            self.role = role
            self.content = content
        }

        /// Multimodal message: text plus one or more base64 image data URLs.
        init(role: String, text: String, imageDataURLs: [String]) {
            self.role = role
            var parts: [[String: Any]] = [["type": "text", "text": text]]
            for url in imageDataURLs {
                parts.append(["type": "image_url", "image_url": ["url": url]])
            }
            self.content = parts
        }
    }

    /// Build a `data:` URL (base64 JPEG) for a vision `image_url` content part.
    static func imageDataURL(_ imageData: Data) -> String {
        "data:image/jpeg;base64,\(imageData.base64EncodedString())"
    }

    struct AIResponse {
        let content: String
        let model: String
    }

    // MARK: - Core Completion

    func complete(
        messages: [Message],
        systemPrompt: String? = nil,
        model: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 1024,
        jsonMode: Bool = false,
        usageKind: AIUsageKind = .other
    ) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        var allMessages: [[String: Any]] = []
        if let system = systemPrompt {
            allMessages.append(["role": "system", "content": system])
        }
        for msg in messages {
            allMessages.append(["role": msg.role, "content": msg.content])
        }

        var body: [String: Any] = [
            "model": model ?? fastModel,
            "messages": allMessages,
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }

        let (data, viaProxy) = try await sendChat(body: body, usageKind: usageKind)

        guard let content = Self.decodeChatContent(data) else {
            throw AIError.parseError
        }

        // The proxy debits the server-authoritative ledger; only meter locally on
        // the direct path to avoid double-counting.
        if !viaProxy { meter(usageKind, responseBody: data) }
        return content
    }

    /// Central transport for a chat-completions request. Routes through the
    /// backend proxy (server-held key) when the device is paired + the web URL is
    /// configured; otherwise calls OpenRouter directly with a local key. Returns
    /// the raw OpenRouter-shaped response body plus whether the proxy was used (so
    /// callers can avoid double-metering credits the server already debited).
    private func sendChat(body: [String: Any], usageKind: AIUsageKind) async throws -> (data: Data, viaProxy: Bool) {
        if let proxy = proxyEndpoint, let token = deviceToken {
            var proxyBody = body
            proxyBody["usage_kind"] = usageKind.rawValue
            var request = URLRequest(url: proxy)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 60
            request.httpBody = try JSONSerialization.data(withJSONObject: proxyBody)

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIError.httpError(status: http.statusCode, body: errorBody)
            }
            return (data, true)
        }

        // Direct fallback: requires a local key.
        let apiKey = try resolvedAPIKey()
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("PulseLoop iOS", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.httpError(status: http.statusCode, body: errorBody)
        }
        return (data, false)
    }

    /// Decodes the assistant message content from an OpenAI/OpenRouter chat-completion
    /// response using `Codable` (migrated from hand-rolled `JSONSerialization`). This is
    /// the template for converting the remaining `JSONSerialization` call sites.
    private static func decodeChatContent(_ data: Data) -> String? {
        struct ChatCompletionResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data) else {
            return nil
        }
        return decoded.choices.first?.message.content
    }

    /// Parses the `usage` object (`prompt_tokens` / `completion_tokens`) from a
    /// chat-completion response body, when present. Used to attach real token counts
    /// to the credit ledger entry.
    private static func decodeUsage(_ data: Data) -> OpenAIResponse.TokenUsage? {
        struct UsageEnvelope: Decodable {
            struct Usage: Decodable {
                let prompt_tokens: Int?
                let completion_tokens: Int?
            }
            let usage: Usage?
        }
        guard let env = try? JSONDecoder().decode(UsageEnvelope.self, from: data),
              let usage = env.usage else { return nil }
        return OpenAIResponse.TokenUsage(
            inputTokens: usage.prompt_tokens ?? 0,
            outputTokens: usage.completion_tokens ?? 0
        )
    }

    /// Meter a successful legacy-`AIService` call against the credit ledger so AI usage
    /// is never billing-blind (roadmap B2). All `AIService` features are OpenRouter-backed
    /// today; once the metered backend proxy lands (Phase C) these calls route through it
    /// and the server becomes authoritative. Metering here keeps accounting correct in the
    /// meantime and for the BYO-key path.
    private func meter(_ kind: AIUsageKind, responseBody: Data?) {
        let usage = responseBody.flatMap { Self.decodeUsage($0) }
        CreditsLedger.shared.meter(kind, usage: usage)
    }

    /// Meter a completed streaming call. Token usage may be nil if the provider didn't
    /// emit a final usage chunk; the flat per-call cost still applies.
    private func meterStream(_ kind: AIUsageKind, usage: OpenAIResponse.TokenUsage?) {
        CreditsLedger.shared.meter(kind, usage: usage)
    }

    // MARK: - Streaming Completion

    func stream(
        messages: [Message],
        systemPrompt: String? = nil,
        model: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 1024,
        usageKind: AIUsageKind = .other
    ) -> AsyncThrowingStream<String, Error> {
        // The backend proxy is request/response (no SSE). When proxying, fall back
        // to a single non-streamed completion and yield it as one chunk so callers
        // that consume the stream still work and the key stays server-side.
        if proxyEndpoint != nil {
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let text = try await self.complete(
                            messages: messages,
                            systemPrompt: systemPrompt,
                            model: model ?? self.smartModel,
                            temperature: temperature,
                            maxTokens: maxTokens,
                            usageKind: usageKind
                        )
                        continuation.yield(text)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                var streamUsage: OpenAIResponse.TokenUsage? = nil
                do {
                    let apiKey = try self.resolvedAPIKey()
                    var allMessages: [[String: Any]] = []
                    if let system = systemPrompt {
                        allMessages.append(["role": "system", "content": system])
                    }
                    for msg in messages {
                        allMessages.append(["role": msg.role, "content": msg.content])
                    }

                    let body: [String: Any] = [
                        "model": model ?? self.fastModel,
                        "messages": allMessages,
                        "temperature": temperature,
                        "max_tokens": maxTokens,
                        "stream": true,
                        "stream_options": ["include_usage": true]
                    ]

                    var request = URLRequest(url: self.baseURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("PulseLoop iOS", forHTTPHeaderField: "X-Title")
                    request.timeoutInterval = 60
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw AIError.httpError(status: http.statusCode, body: "Stream error: \(http.statusCode)")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        // The final chunk (with stream_options.include_usage) carries the
                        // token usage and an empty choices array; capture it for metering.
                        if let usage = json["usage"] as? [String: Any] {
                            let input = usage["prompt_tokens"] as? Int ?? 0
                            let output = usage["completion_tokens"] as? Int ?? 0
                            streamUsage = OpenAIResponse.TokenUsage(inputTokens: input, outputTokens: output)
                        }

                        guard let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }

                        continuation.yield(content)
                    }
                    self.meterStream(usageKind, usage: streamUsage)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Vision / Food Analysis

    struct FoodAnalysis {
        let name: String
        let calories: Int
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let description: String
    }

    func analyzeFoodImage(_ imageData: Data) async -> FoodAnalysis? {
        let dataURL = Self.imageDataURL(imageData)
        let visionModel = AIModel.vision.resolvedSlug

        let messages: [[String: Any]] = [
            ["role": "system", "content": "You are a nutritionist AI. Analyze food photos and return JSON with: name (string), calories (int), protein_g (double), carbs_g (double), fat_g (double), description (string - brief description of what you see). Be accurate with calorie estimates based on portion sizes visible. Return ONLY valid JSON, no markdown."],
            ["role": "user", "content": [
                ["type": "text", "text": "What food is this? Estimate the calories and macros."],
                ["type": "image_url", "image_url": ["url": dataURL]]
            ] as [Any]]
        ]

        let body: [String: Any] = [
            "model": visionModel,
            "messages": messages,
            "max_tokens": 300,
            "temperature": 0.3
        ]

        do {
            let (data, viaProxy) = try await sendChat(body: body, usageKind: .imageAnalysis)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }

            let cleaned = content
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let jsonData = cleaned.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return nil
            }

            if !viaProxy { meter(.imageAnalysis, responseBody: data) }
            return FoodAnalysis(
                name: parsed["name"] as? String ?? "Unknown food",
                calories: parsed["calories"] as? Int ?? 0,
                proteinG: (parsed["protein_g"] as? Double) ?? Double(parsed["protein_g"] as? Int ?? 0),
                carbsG: (parsed["carbs_g"] as? Double) ?? Double(parsed["carbs_g"] as? Int ?? 0),
                fatG: (parsed["fat_g"] as? Double) ?? Double(parsed["fat_g"] as? Int ?? 0),
                description: parsed["description"] as? String ?? ""
            )
        } catch {
            return nil
        }
    }

    // MARK: - High-Level AI Features

    /// Generate a personalized daily brief based on user data
    func generateDailyBrief(context: UserContext, focus: String = "balanced") async -> String {
        let focusInstruction: String
        switch focus {
        case "nutrition":
            focusInstruction = "Focus primarily on nutrition: calorie intake, macros, meal timing, and dietary suggestions."
        case "supplements":
            focusInstruction = "Focus primarily on supplement/medication protocol: what's due, interactions, cycling, and optimization."
        case "sleep":
            focusInstruction = "Focus primarily on sleep quality, recovery, and evening routines."
        case "productivity":
            focusInstruction = "Focus primarily on tasks, time management, and what to prioritize today."
        default:
            focusInstruction = "Give a balanced overview across health, nutrition, and tasks."
        }

        let prompt = """
        You are PulseLoop AI, a personal life operating system assistant. Generate a brief, warm insight for the user.
        
        Focus: \(focusInstruction)
        
        Context:
        - Name: \(context.name)
        - Time: \(context.timeOfDay)
        - Medications due: \(context.medicationsDue.joined(separator: ", "))
        - Tasks pending: \(context.pendingTasks.joined(separator: ", "))
        - Recent meals: \(context.recentMeals.joined(separator: ", "))
        - Calories today: \(context.caloriesToday)
        - Streak days: \(context.streakDays)
        
        Respond in 2-3 short sentences. Be specific to their data. No greetings, just the insight. Use a warm, concise tone.
        """

        do {
            return try await complete(
                messages: [Message(role: "user", content: prompt)],
                temperature: 0.8,
                maxTokens: 150
            )
        } catch {
            return fallbackDailyBrief(context: context)
        }
    }

    /// Parse and understand natural language input for the command palette
    func parseNaturalLanguage(input: String, knownMedications: [String]) async -> [AIParseResult] {
        let prompt = """
        Parse this user input into structured items. The user is logging health/life data.
        
        Known medications/supplements: \(knownMedications.joined(separator: ", "))
        
        Input: "\(input)"
        
        Respond ONLY in this JSON format (no other text):
        [{"title": "item name", "category": "supplement|medication|peptide|vitamin|meal|task|note|workout", "emoji": "relevant emoji", "dose": "dose if mentioned", "benefit": "one line benefit", "confidence": 0.9}]
        
        Rules:
        - If it's a known medication, use the exact name
        - Meals: estimate calories in benefit field
        - Tasks: extract the action
        - Supplements/meds: include typical benefit
        - Always include appropriate emoji
        """

        do {
            let response = try await complete(
                messages: [Message(role: "user", content: prompt)],
                temperature: 0.3,
                maxTokens: 500
            )

            return parseAIResults(response)
        } catch {
            return []
        }
    }

    /// Generate insight about a supplement/medication
    func generateProductInsight(name: String, category: String, userProtocol: [String]) async -> ProductInsight? {
        let prompt = """
        You are a health supplement expert AI. Provide concise info about this product.
        
        Product: \(name) (Category: \(category))
        User's current protocol: \(userProtocol.joined(separator: ", "))
        
        Respond ONLY in this JSON format:
        {"benefit": "primary benefit in 10 words", "mechanism": "how it works in 15 words", "timing": "when to take", "interactions": ["interaction with items in their protocol"], "warning": "any important warning or null"}
        """

        do {
            let response = try await complete(
                messages: [Message(role: "user", content: prompt)],
                temperature: 0.3,
                maxTokens: 300,
                jsonMode: true
            )
            return parseProductInsight(response)
        } catch {
            return nil
        }
    }

    /// AI-powered universal search across all user data
    func smartSearch(query: String, context: SearchContext) async -> [SearchResult] {
        let prompt = """
        You are PulseLoop's smart search. The user searched: "\(query)"
        
        Available data:
        - Medications: \(context.medications.joined(separator: ", "))
        - Notes: \(context.noteTitles.joined(separator: ", "))
        - Tasks: \(context.tasks.joined(separator: ", "))
        - Meals (recent): \(context.recentMeals.joined(separator: ", "))
        
        Respond ONLY in JSON:
        [{"title": "result title", "subtitle": "why this matches", "type": "medication|note|task|meal|action", "action": "what tapping would do", "relevance": 0.9}]
        
        Include up to 5 results. Also suggest AI actions (like "Log [item]", "Create note about [topic]", "Set reminder for [thing]") if relevant.
        """

        do {
            let response = try await complete(
                messages: [Message(role: "user", content: prompt)],
                temperature: 0.3,
                maxTokens: 500
            )
            return parseSearchResults(response)
        } catch {
            return []
        }
    }

    /// Generate a contextual AI response for the chat interface
    func chat(
        messages: [Message],
        userContext: UserContext
    ) -> AsyncThrowingStream<String, Error> {
        let protocolDesc = userContext.protocolDetails.map { item in
            "  • \(item.name)  -  \(item.dose) (\(item.category), \(item.timing))\(item.benefit.map { " → \($0)" } ?? "")"
        }.joined(separator: "\n")

        let takenDesc = userContext.todayMedsTaken.isEmpty ? "None yet" : userContext.todayMedsTaken.joined(separator: ", ")
        let missedDesc = userContext.todayMedsMissed.isEmpty ? "None" : userContext.todayMedsMissed.joined(separator: ", ")

        let systemPrompt = """
        You are PulseLoop AI  -  \(userContext.name)'s personal health & life operating system assistant. You know their full supplement/medication protocol, daily routine, and health goals.

        \(userContext.personalityModifier.isEmpty ? "" : "PERSONALITY (adopt this tone in every reply):\n\(userContext.personalityModifier)\n")
        \(userContext.primaryGoal.isEmpty ? "" : "\(userContext.name.uppercased())'S PRIMARY GOAL: \(userContext.primaryGoal)\nKeep this goal in mind and steer advice toward it.\n")
        CURRENT STATE:
        - Time: \(userContext.timeOfDay) (\(userContext.currentHour):00)
        - Streak: \(userContext.streakDays) days consistent
        - Calories today: \(userContext.caloriesToday) kcal
        - Recent meals: \(userContext.recentMeals.joined(separator: ", ").isEmpty ? "Nothing logged yet" : userContext.recentMeals.joined(separator: ", "))
        
        \(userContext.name.uppercased())'S FULL PROTOCOL:
        \(protocolDesc.isEmpty ? "  No medications/supplements set up yet" : protocolDesc)
        
        TODAY'S ADHERENCE:
        - Taken: \(takenDesc)
        - Not yet taken: \(missedDesc)
        
        PENDING TASKS:
        \(userContext.pendingTasks.isEmpty ? "  None" : userContext.pendingTasks.map { "  • \($0)" }.joined(separator: "\n"))
        
        RULES:
        - You know \(userContext.name) personally. Reference their specific protocol items by name.
        - Give dosing, timing, and interaction advice based on their actual stack.
        - If they ask "what should I take next?" check the time and what they haven't taken yet.
        - For timing: AM items should be taken in the morning, PM items in the evening.
        - Be concise (2-4 sentences max unless they ask for detail).
        - Never say "I don't have access to your data"  -  you DO have it above.
        - If they want to log something, confirm what you'll log and the dose.
        
        MEMORY (things you've learned about \(userContext.name)):
        \(userContext.memories.isEmpty ? "No memories yet  -  this is your first interaction." : userContext.memories.joined(separator: "\n"))
        
        LIFE ORGANIZATION:
        - If they explicitly ask you to create a task, reminder, or note  -  confirm and say "Done, I've added [X] to your tasks."
        - If they share a preference or routine, you'll remember it automatically (no need to mention it).
        - Suggest optimizations when relevant: "Since you take X in the morning, you could stack Y with it."
        - Only offer to create tasks/notes when the user clearly wants something organized  -  don't auto-create things.
        """

        return stream(
            messages: messages,
            systemPrompt: systemPrompt,
            model: AIModel.smart.resolvedSlug,
            temperature: 0.7,
            maxTokens: 800
        )
    }

    /// Extract memories from a conversation turn
    func extractMemories(userMessage: String, aiResponse: String, existingMemories: [String]) async -> [ExtractedMemory] {
        let prompt = """
        Analyze this conversation and extract any facts worth remembering about the user for future interactions.
        
        User said: "\(userMessage)"
        AI responded: "\(aiResponse.prefix(500))"
        
        Already known: \(existingMemories.prefix(10).joined(separator: "; "))
        
        Extract NEW facts only (don't repeat known ones). Respond ONLY in JSON:
        [{"content": "what to remember", "category": "preference|fact|goal|routine|health|relationship|pattern|dislike", "importance": 7}]
        
        Return [] if nothing new worth remembering. Only save durable facts (preferences, goals, routines, health conditions, relationships)  -  not transient things.
        """

        do {
            let response = try await complete(
                messages: [Message(role: "user", content: prompt)],
                temperature: 0.2,
                maxTokens: 300
            )
            return parseMemories(response)
        } catch {
            return []
        }
    }

    /// Suggest organizational actions based on conversation
    func suggestActions(userMessage: String, aiResponse: String) async -> [SuggestedAction] {
        let prompt = """
        Based on this conversation, suggest any actions that would help organize the user's life.
        
        User: "\(userMessage)"
        AI: "\(aiResponse.prefix(300))"
        
        Respond ONLY in JSON (or [] if no actions needed):
        [{"type": "task|reminder|note|log", "title": "action title", "details": "specifics"}]
        
        Only suggest if the conversation implies something actionable (a to-do, a follow-up, a habit to track).
        """

        do {
            let response = try await complete(
                messages: [Message(role: "user", content: prompt)],
                temperature: 0.2,
                maxTokens: 200
            )
            return parseActions(response)
        } catch {
            return []
        }
    }

    struct ExtractedMemory {
        let content: String
        let category: String
        let importance: Int
    }

    struct SuggestedAction {
        let type: String
        let title: String
        let details: String
    }

    private func parseMemories(_ text: String) -> [ExtractedMemory] {
        guard let data = extractJSON(from: text),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return array.compactMap { dict in
            guard let content = dict["content"] as? String,
                  let category = dict["category"] as? String else { return nil }
            return ExtractedMemory(
                content: content,
                category: category,
                importance: dict["importance"] as? Int ?? 5
            )
        }
    }

    private func parseActions(_ text: String) -> [SuggestedAction] {
        guard let data = extractJSON(from: text),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return array.compactMap { dict in
            guard let type = dict["type"] as? String,
                  let title = dict["title"] as? String else { return nil }
            return SuggestedAction(
                type: type,
                title: title,
                details: dict["details"] as? String ?? ""
            )
        }
    }

    struct HealthScore {
        let score: Int
        let label: String
        let breakdown: String
    }

    func rateHealthScore(item: String, type: String) async -> HealthScore? {
        let prompt = """
        Rate the health score of this \(type) from 1-100. Be concise.
        Item: \(item)
        
        Respond in EXACTLY this format (no markdown):
        SCORE: [number 1-100]
        LABEL: [one word: Excellent/Good/Fair/Poor]
        BREAKDOWN: [one line summary of key ingredients/macros and why this score]
        """

        guard let result = try? await complete(
            messages: [Message(role: "user", content: prompt)],
            systemPrompt: "You are a nutritionist AI. Rate food and beverages based on ingredients, macros, sugar content, preservatives, and overall nutritional value. Be honest and direct.",
            temperature: 0.3,
            maxTokens: 150
        ) else { return nil }

        var score = 50
        var label = "Fair"
        var breakdown = "Could not analyze"

        for line in result.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SCORE:") {
                let val = trimmed.replacingOccurrences(of: "SCORE:", with: "").trimmingCharacters(in: .whitespaces)
                score = Int(val) ?? 50
            } else if trimmed.hasPrefix("LABEL:") {
                label = trimmed.replacingOccurrences(of: "LABEL:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("BREAKDOWN:") {
                breakdown = trimmed.replacingOccurrences(of: "BREAKDOWN:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        return HealthScore(score: score, label: label, breakdown: breakdown)
    }

    /// Summarize a note
    func summarizeNote(content: String) async -> String? {
        let prompt = """
        Summarize this note in 1-2 sentences. Be concise and capture the key point:
        
        \(content.prefix(2000))
        """

        return try? await complete(
            messages: [Message(role: "user", content: prompt)],
            temperature: 0.3,
            maxTokens: 100
        )
    }

    /// Generate AI tags for a note
    func generateNoteTags(title: String, content: String) async -> [String] {
        let prompt = """
        Generate 2-4 short tags for this note. Respond ONLY as a JSON array of strings.
        
        Title: \(title)
        Content: \(content.prefix(500))
        
        Example: ["health", "morning-routine", "supplements"]
        """

        do {
            let response = try await complete(
                messages: [Message(role: "user", content: prompt)],
                temperature: 0.3,
                maxTokens: 50
            )
            if let data = response.data(using: .utf8),
               let tags = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return tags
            }
        } catch {}
        return []
    }

    /// AI auto-file suggestion for a note: picks the best-fitting collection from
    /// `existingCollections` (or proposes a new short name) plus a few tags.
    struct NoteFiling {
        var collection: String?
        var tags: [String]
    }

    func autoFileNote(title: String, content: String, existingCollections: [String]) async -> NoteFiling {
        let collectionList = existingCollections.isEmpty ? "(none yet)" : existingCollections.joined(separator: ", ")
        let prompt = """
        File this note. Choose the single best collection for it and 2–4 short tags.
        Prefer an existing collection when it fits; otherwise propose a concise new \
        collection name (1–2 words). Respond ONLY as JSON.

        Existing collections: \(collectionList)
        Title: \(title)
        Content: \(content.prefix(600))

        Format: {"collection":"Work","tags":["project","q3"]}
        """
        do {
            let response = try await complete(
                messages: [Message(role: "user", content: prompt)],
                temperature: 0.2,
                maxTokens: 80,
                jsonMode: true
            )
            let cleaned = response
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
            if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"),
               let data = String(cleaned[start...end]).data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let collection = (json["collection"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let tags = (json["tags"] as? [String])?.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? []
                return NoteFiling(collection: (collection?.isEmpty ?? true) ? nil : collection, tags: tags)
            }
        } catch {}
        return NoteFiling(collection: nil, tags: [])
    }

    /// Prioritize inbox items
    func triageInbox(items: [(title: String, source: String, preview: String)]) async -> [InboxPriority] {
        let itemsDesc = items.enumerated().map { "\($0.offset): [\($0.element.source)] \($0.element.title)  -  \($0.element.preview.prefix(50))" }.joined(separator: "\n")

        let prompt = """
        Triage these inbox items by priority. Respond ONLY in JSON.
        
        Items:
        \(itemsDesc)
        
        Format: [{"index": 0, "priority": "high|medium|low", "reason": "why", "suggested_action": "reply|archive|defer|review"}]
        """

        do {
            let response = try await complete(
                messages: [Message(role: "user", content: prompt)],
                temperature: 0.2,
                maxTokens: 400
            )
            return parseInboxPriorities(response)
        } catch {
            return []
        }
    }

    /// Generate a smart reply suggestion
    func suggestReply(subject: String, body: String, from: String) async -> String? {
        let prompt = """
        Write a brief, professional reply to this email. Keep it under 3 sentences.
        
        From: \(from)
        Subject: \(subject)
        Body: \(body.prefix(500))
        
        Reply (just the body text, no greeting needed):
        """

        return try? await complete(
            messages: [Message(role: "user", content: prompt)],
            temperature: 0.7,
            maxTokens: 150
        )
    }

    /// Analyze protocol interactions
    func analyzeProtocolInteractions(medications: [(name: String, dose: String, timing: String)]) async -> ProtocolAnalysis? {
        let medsDesc = medications.map { "\($0.name) \($0.dose) (\($0.timing))" }.joined(separator: ", ")

        let prompt = """
        Analyze this supplement/medication protocol for interactions and optimization.
        
        Protocol: \(medsDesc)
        
        Respond ONLY in JSON:
        {"synergies": [{"items": ["item1", "item2"], "note": "why they work together"}], "conflicts": [{"items": ["item1", "item2"], "note": "why and how to fix"}], "timing_suggestions": [{"item": "name", "suggestion": "better timing and why"}], "overall_score": 8, "summary": "2 sentence overview"}
        """

        do {
            let response = try await complete(
                messages: [Message(role: "user", content: prompt)],
                model: AIModel.reasoning.resolvedSlug,
                temperature: 0.3,
                maxTokens: 600,
                jsonMode: true
            )
            return parseProtocolAnalysis(response)
        } catch {
            return nil
        }
    }

    // MARK: - Context Types

    struct UserContext {
        var name: String = "there"
        var timeOfDay: String = "morning"
        var currentHour: Int = 8
        var medicationsDue: [String] = []
        var protocolDetails: [ProtocolItem] = []
        var pendingTasks: [String] = []
        var recentMeals: [String] = []
        var caloriesToday: Int = 0
        var streakDays: Int = 0
        var todayMedsTaken: [String] = []
        var todayMedsMissed: [String] = []
        var memories: [String] = []
        var personalityModifier: String = ""
        var primaryGoal: String = ""
    }

    struct ProtocolItem {
        let name: String
        let dose: String
        let category: String
        let timing: String
        let benefit: String?
        let mechanism: String?
    }

    struct SearchContext {
        var medications: [String] = []
        var noteTitles: [String] = []
        var tasks: [String] = []
        var recentMeals: [String] = []
    }

    // MARK: - Response Types

    struct AIParseResult: Identifiable {
        let id = UUID()
        let title: String
        let category: String
        let emoji: String
        let dose: String?
        let benefit: String?
        let confidence: Double
    }

    struct ProductInsight {
        let benefit: String
        let mechanism: String
        let timing: String
        let interactions: [String]
        let warning: String?
    }

    struct SearchResult: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let type: String
        let action: String
        let relevance: Double
    }

    struct InboxPriority {
        let index: Int
        let priority: String
        let reason: String
        let suggestedAction: String
    }

    struct ProtocolAnalysis {
        let synergies: [(items: [String], note: String)]
        let conflicts: [(items: [String], note: String)]
        let timingSuggestions: [(item: String, suggestion: String)]
        let overallScore: Int
        let summary: String
    }

    // MARK: - Parsing Helpers

    private func parseAIResults(_ text: String) -> [AIParseResult] {
        guard let data = extractJSON(from: text),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return array.compactMap { dict in
            guard let title = dict["title"] as? String,
                  let category = dict["category"] as? String,
                  let emoji = dict["emoji"] as? String else { return nil }
            return AIParseResult(
                title: title,
                category: category,
                emoji: emoji,
                dose: dict["dose"] as? String,
                benefit: dict["benefit"] as? String,
                confidence: dict["confidence"] as? Double ?? 0.5
            )
        }
    }

    private func parseProductInsight(_ text: String) -> ProductInsight? {
        guard let data = extractJSON(from: text),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let benefit = dict["benefit"] as? String,
              let mechanism = dict["mechanism"] as? String,
              let timing = dict["timing"] as? String else { return nil }

        return ProductInsight(
            benefit: benefit,
            mechanism: mechanism,
            timing: timing,
            interactions: dict["interactions"] as? [String] ?? [],
            warning: dict["warning"] as? String
        )
    }

    private func parseSearchResults(_ text: String) -> [SearchResult] {
        guard let data = extractJSON(from: text),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return array.compactMap { dict in
            guard let title = dict["title"] as? String,
                  let subtitle = dict["subtitle"] as? String else { return nil }
            return SearchResult(
                title: title,
                subtitle: subtitle,
                type: dict["type"] as? String ?? "action",
                action: dict["action"] as? String ?? "",
                relevance: dict["relevance"] as? Double ?? 0.5
            )
        }
    }

    private func parseInboxPriorities(_ text: String) -> [InboxPriority] {
        guard let data = extractJSON(from: text),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return array.compactMap { dict in
            guard let index = dict["index"] as? Int,
                  let priority = dict["priority"] as? String else { return nil }
            return InboxPriority(
                index: index,
                priority: priority,
                reason: dict["reason"] as? String ?? "",
                suggestedAction: dict["suggested_action"] as? String ?? "review"
            )
        }
    }

    private func parseProtocolAnalysis(_ text: String) -> ProtocolAnalysis? {
        guard let data = extractJSON(from: text),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let synergies = (dict["synergies"] as? [[String: Any]] ?? []).compactMap { s -> (items: [String], note: String)? in
            guard let items = s["items"] as? [String], let note = s["note"] as? String else { return nil }
            return (items: items, note: note)
        }

        let conflicts = (dict["conflicts"] as? [[String: Any]] ?? []).compactMap { s -> (items: [String], note: String)? in
            guard let items = s["items"] as? [String], let note = s["note"] as? String else { return nil }
            return (items: items, note: note)
        }

        let timingSuggestions = (dict["timing_suggestions"] as? [[String: Any]] ?? []).compactMap { s -> (item: String, suggestion: String)? in
            guard let item = s["item"] as? String, let suggestion = s["suggestion"] as? String else { return nil }
            return (item: item, suggestion: suggestion)
        }

        return ProtocolAnalysis(
            synergies: synergies,
            conflicts: conflicts,
            timingSuggestions: timingSuggestions,
            overallScore: dict["overall_score"] as? Int ?? 7,
            summary: dict["summary"] as? String ?? ""
        )
    }

    private func extractJSON(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]") {
            let json = String(trimmed[start...end])
            return json.data(using: .utf8)
        }
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            let json = String(trimmed[start...end])
            return json.data(using: .utf8)
        }
        return nil
    }

    private func fallbackDailyBrief(context: UserContext) -> String {
        if !context.medicationsDue.isEmpty {
            return "You have \(context.medicationsDue.count) items in your morning protocol. \(context.pendingTasks.count) tasks waiting for you today."
        }
        return "Ready to start your day. \(context.pendingTasks.count) tasks on your plate."
    }

    enum AIError: Error {
        case httpError(status: Int, body: String)
        case parseError
        case noResponse
        case missingAPIKey
    }
}
