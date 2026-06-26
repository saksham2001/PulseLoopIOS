import Foundation

/// The coach agent loop: context → model → tools → structured final. Ports
/// `_run_openai` from the web orchestrator, with the same caps, per-tool
/// arg-retry guard, JSON repair, and graceful fallbacks. Runs on the main actor
/// (tools read SwiftData); the network awaits hop off-main inside the client.
@MainActor
struct CoachOrchestrator {
    let client: ResponsesClient
    let registry: ToolRegistry
    let flags: CoachFeatureFlags
    let toolContext: ToolExecutionContext

    /// Per-(role) feedback/telemetry stats used for feedback-weighted model selection
    /// (Life OS T4). Defaults to empty so routing degrades to the capability prior.
    /// The view model populates this from `CoachFeedbackStore.outcomeStats`.
    var routingStats: [String: ModelOutcomeStats] = [:]
    /// A user-forced model slug for this turn (transparency "use a different model").
    /// When set, it overrides auto routing for the model (the role still classifies).
    var forcedModel: String? = nil

    private let maxFinalAttempts = 3
    private let maxToolArgRetries = 2

    struct TurnResult {
        let assistant: CoachResponse
        let trace: [CoachToolCallTrace]
        var pendingActions: [PendingAction] = []
        /// True when the real LLM ran this turn (vs a scripted fallback). Drives
        /// credit metering (E1) — scripted fallbacks are free.
        var usedLLM: Bool = false
        /// Accumulated token usage across the turn's API rounds, when reported.
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        /// Set when the turn failed at the transport/parse level and the assistant
        /// body is a canned fallback. The UI surfaces this so failures aren't silent.
        var errorMessage: String? = nil
        /// Decision-log fields (Life OS T0): which specialist handled the turn, the
        /// resolved model slug, how many tool rounds ran, and whether the answer had
        /// to be recovered on the JSON-reliability anchor. Used to make routing
        /// data-driven (T4) and to surface a quality dashboard (T6).
        var roleLabel: String = AgentRole.generalist.label
        var model: String = ""
        var rounds: Int = 0
        var recovered: Bool = false
    }

    struct PriorMessage { let role: String; let text: String }

    func runTurn(
        userText: String,
        packet: CoachContextPacket,
        recentMessages: [PriorMessage],
        personality: CoachPersonality = .dataNerd,
        primaryGoal: String = "",
        imageDataURLs: [String] = [],
        onTrace: @escaping (CoachTraceEvent) -> Void = { _ in }
    ) async -> TurnResult {
        guard flags.coachEnabled else {
            return TurnResult(assistant: CoachFallbacks.scripted(packet: packet, userText: userText), trace: [])
        }
        do {
            return try await runOpenAI(userText: userText, packet: packet, recentMessages: recentMessages, personality: personality, primaryGoal: primaryGoal, imageDataURLs: imageDataURLs, onTrace: onTrace)
        } catch {
            NSLog("[OpenRouterCoach] turn failed: %@", String(describing: error))
            onTrace(CoachTraceEvent(label: "Something went wrong", status: .failedTool))
            return TurnResult(
                assistant: CoachFallbacks.fallback(),
                trace: [],
                errorMessage: Self.userFacingError(error)
            )
        }
    }

    /// Maps a transport error to a short, user-facing reason for the chat error banner.
    private static func userFacingError(_ error: Error) -> String {
        if let responsesError = error as? ResponsesError {
            switch responsesError {
            case .insufficientCredits:
                return "You're out of AI credits. Add more in your provider account, then try again."
            case .missingAPIKey:
                return "No AI key configured. Add one in Settings → AI Assistant."
            default:
                break
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline — check your connection and try again."
            case .timedOut:
                return "The request timed out. Try again in a moment."
            default:
                return "Couldn't reach the AI service. Try again."
            }
        }
        return "The AI hit an error and couldn't finish that. Try again."
    }

    /// Parse `CoachSource`s out of a `search_web` tool result JSON string.
    static func sources(fromSearchResult json: String) -> [CoachSource] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            guard let url = r["url"] as? String, !url.isEmpty else { return nil }
            let title = (r["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? url
            let publisher = (r["publisher"] as? String) ?? WebSearchResult.host(of: url)
            return CoachSource(title: title, url: url, publisher: publisher)
        }
    }

    /// De-duplicate sources by URL, preserving order, capped to `limit`.
    static func dedupedSources(_ sources: [CoachSource], limit: Int) -> [CoachSource] {
        var seen = Set<String>()
        var out: [CoachSource] = []
        for s in sources where !seen.contains(s.url) {
            seen.insert(s.url)
            out.append(s)
            if out.count >= limit { break }
        }
        return out
    }

    private func runOpenAI(
        userText: String,
        packet: CoachContextPacket,
        recentMessages: [PriorMessage],
        personality: CoachPersonality = .dataNerd,
        primaryGoal: String = "",
        imageDataURLs: [String] = [],
        onTrace: @escaping (CoachTraceEvent) -> Void
    ) async throws -> TurnResult {
        let toolSpecs = registry.toolSpecs
        let textFormat = CoachResponseSchema.textFormat
        // Multi-agent routing (Sakana-style): classify the turn and dispatch it to
        // the best specialist model. Photo turns must use a multimodal model, so the
        // router returns `.vision` for them — preserving the prior photo behavior.
        // The generalist (gpt-4o-mini) is the safe default and the reliability anchor.
        let role = AgentRouter.route(
            userText: userText,
            hasImage: !imageDataURLs.isEmpty,
            recentMessages: recentMessages.map(\.text))
        // Vision turns always force the vision slug (a chosen "smart" slug may not be
        // multimodal). Other roles resolve their model via the capability registry +
        // feedback-weighted ranking (auto mode), unless the user pinned a model — and
        // the generalist's reliability-anchor coercion is always applied. A per-turn
        // `forcedModel` (transparency "use a different model") wins when set.
        let autoPicked = forcedModel == nil
            && AgentRouter.autoModelEnabled
            && !AgentRouter.hasExplicitOverride(for: role)
        let modelOverride: String? = {
            if let forced = forcedModel, !forced.isEmpty { return forced }
            if !imageDataURLs.isEmpty { return AIModel.vision.toolCapableResolvedSlug }
            if role != .generalist { return AgentRouter.bestModel(for: role, stats: routingStats) }
            // Generalist: auto-pick from the registry, else honor flags.model with the
            // anchor coercion for known JSON-unreliable slugs.
            if autoPicked { return AgentRouter.bestModel(for: role, stats: routingStats) }
            return AIModel.jsonUnreliableSlugs.contains(flags.model) ? AIModel.jsonReliableAnchor : nil
        }()
        let resolvedModel = modelOverride ?? flags.model
        NSLog("[OpenRouterCoach] routed role=%@ model=%@", role.label, resolvedModel)
        onTrace(CoachTraceEvent(
            label: "Routing to \(role.label) · \(AgentRouter.shortModelName(resolvedModel))",
            status: .thinking,
            toolName: nil))
        // A second, human-readable "why" line for the transparency strip.
        onTrace(CoachTraceEvent(
            label: AgentRouter.routingRationale(role: role, slug: resolvedModel, autoPicked: autoPicked && forcedModel == nil),
            status: .thinking,
            toolName: nil))

        // Specialists like Nemotron need `detailed thinking on` to reason and may emit
        // reasoning tokens; the role hint shapes tone/depth without weakening the JSON
        // contract (the parser strips any leaked reasoning before decoding — T3).
        let systemPrompt = CoachPromptBuilder.systemPrompt(
            personality: personality, goal: primaryGoal, roleHint: role.promptHint)
        let systemContent = role.needsDetailedThinking ? "detailed thinking on\n\n\(systemPrompt)" : systemPrompt

        // Initial input: system + developer + recent turns + the new user message.
        var input: [[String: Any]] = [
            OpenAIRequestBuilder.message(role: "system", content: systemContent),
            OpenAIRequestBuilder.message(role: "developer", content: CoachPromptBuilder.developerMessage(packet: packet)),
        ]
        for m in recentMessages {
            input.append(OpenAIRequestBuilder.message(role: m.role == "user" ? "user" : "assistant", content: m.text))
        }
        input.append(OpenAIRequestBuilder.message(role: "user", content: userText, imageDataURLs: imageDataURLs))

        onTrace(CoachTraceEvent(label: imageDataURLs.isEmpty ? "Planning the approach…" : "Looking at your photo…", status: .thinking))

        var totalInput = 0
        var totalOutput = 0
        func accumulate(_ r: OpenAIResponse) {
            if let u = r.usage { totalInput += u.inputTokens; totalOutput += u.outputTokens }
        }

        var response = try await send(input: input, tools: toolSpecs, textFormat: textFormat, previousResponseId: nil, modelOverride: modelOverride)
        accumulate(response)
        noteWebSearch(response, onTrace: onTrace)

        var trace: [CoachToolCallTrace] = []
        var toolCalls = 0
        var rounds = 0
        var argFailures: [String: Int] = [:]
        // Citations safety net: gather sources from search_web results so we can
        // backfill the reply if the model forgets to populate `sources` (T2).
        var collectedSources: [CoachSource] = []

        while rounds < flags.maxRounds {
            let functionCalls = response.functionCalls
            if functionCalls.isEmpty { break }

            var outputs: [[String: Any]] = []
            for fc in functionCalls {
                if toolCalls >= flags.maxToolCalls {
                    outputs.append(OpenAIRequestBuilder.functionCallOutput(
                        callID: fc.callID, output: "{\"error\":\"tool-call budget exceeded\"}"))
                    continue
                }
                if (argFailures[fc.name] ?? 0) > maxToolArgRetries {
                    outputs.append(OpenAIRequestBuilder.functionCallOutput(
                        callID: fc.callID, output: "{\"error\":\"stop calling \(fc.name); arguments kept failing\"}"))
                    continue
                }
                toolCalls += 1
                let label = registry.tool(named: fc.name)?.publicLabel ?? "Working"
                onTrace(CoachTraceEvent(label: label, status: .runningTool, toolName: fc.name))

                let startedAt = Date()
                let result = await ToolCallExecutor.execute(fc, registry: registry, context: toolContext)
                let finishedAt = Date()

                if result.isError, result.jsonString.contains("invalid arguments") {
                    argFailures[fc.name, default: 0] += 1
                }
                onTrace(CoachTraceEvent(
                    label: label, status: result.isError ? .failedTool : .completedTool, toolName: fc.name))
                trace.append(CoachToolCallTrace(
                    toolName: fc.name, label: label,
                    status: result.isError ? "error" : "success",
                    argsRedacted: ToolCallExecutor.redactArgs(fc.arguments),
                    resultSummary: result.summary,
                    startedAt: startedAt, finishedAt: finishedAt))
                outputs.append(OpenAIRequestBuilder.functionCallOutput(callID: fc.callID, output: result.jsonString))
                if fc.name == "search_web", !result.isError {
                    collectedSources.append(contentsOf: Self.sources(fromSearchResult: result.jsonString))
                }
            }

            rounds += 1
            onTrace(CoachTraceEvent(label: "Putting it together…", status: .writingAnswer))
            response = try await send(input: outputs, tools: toolSpecs, textFormat: textFormat, previousResponseId: response.id, modelOverride: modelOverride)
            accumulate(response)
            noteWebSearch(response, onTrace: onTrace)
        }

        // The round budget may be exhausted while the model still wants to call
        // tools. Leaving those calls unanswered corrupts the chat history (a stateful
        // backend like OpenRouter requires every assistant `tool_calls` to be followed
        // by matching `tool` outputs), which throws on the next request. Close them out
        // with a stub so we can ask cleanly for the final answer.
        if !response.functionCalls.isEmpty {
            let closeouts = response.functionCalls.map {
                OpenAIRequestBuilder.functionCallOutput(
                    callID: $0.callID, output: "{\"error\":\"tool-call budget exceeded; answer with what you have\"}")
            }
            response = try await send(input: closeouts, tools: toolSpecs, textFormat: textFormat, previousResponseId: response.id, modelOverride: modelOverride)
            accumulate(response)
        }

        let finalResult = try await finalAnswer(
            from: response, textFormat: textFormat, modelOverride: modelOverride,
            role: role, onTrace: onTrace)
        let assistant = finalResult.answer
        // If the model cited sources, trust them. Otherwise backfill from the live
        // search results so a searched answer always shows where it came from.
        let finalAssistant: CoachResponse = {
            guard assistant.sources.isEmpty, !collectedSources.isEmpty else { return assistant }
            var withSources = assistant
            withSources.sources = Self.dedupedSources(collectedSources, limit: 6)
            return withSources
        }()
        onTrace(CoachTraceEvent(label: "", status: .done))
        return TurnResult(
            assistant: finalAssistant,
            trace: trace,
            pendingActions: toolContext.pendingActions,
            usedLLM: true,
            inputTokens: totalInput,
            outputTokens: totalOutput,
            roleLabel: role.label,
            model: finalResult.recovered ? AIModel.jsonReliableAnchor : resolvedModel,
            rounds: rounds,
            recovered: finalResult.recovered
        )
    }

    // MARK: - Final parse + repair

    /// Resolve the turn's final answer. Runs the parse/repair loop on the routed
    /// model; if a *specialist* (non-generalist) model still can't produce a usable
    /// structured answer, retry once on the generalist (gpt-4o-mini) — the
    /// reliability anchor — before giving up. This keeps the JSON-apology bug fixed
    /// even when a specialist misbehaves.
    private func finalAnswer(
        from response: OpenAIResponse, textFormat: [String: Any], modelOverride: String?,
        role: AgentRole, onTrace: @escaping (CoachTraceEvent) -> Void
    ) async throws -> (answer: CoachResponse, recovered: Bool) {
        if let parsed = try await parseFinal(response, textFormat: textFormat, modelOverride: modelOverride) {
            return (parsed, false)
        }
        // The routed model couldn't deliver a usable structured answer. Recover on
        // the JSON-reliability anchor (gpt-4o-mini) when the failing model was either
        // a specialist *or* a generalist running a model that's known to loop on
        // JSON-apology replies (e.g. the user picked Gemini Flash). This guarantees a
        // real answer instead of surfacing the apology / a canned fallback.
        let runningModel = modelOverride ?? flags.model
        let isAnchor = runningModel == AIModel.jsonReliableAnchor
        let shouldRecover = role != .generalist
            || AIModel.jsonUnreliableSlugs.contains(runningModel)
            || !isAnchor
        if shouldRecover, !isAnchor {
            let anchor = AIModel.jsonReliableAnchor
            NSLog("[OpenRouterCoach] %@ (%@) parse-failed; recovering on anchor %@", role.label, runningModel, anchor)
            onTrace(CoachTraceEvent(
                label: "Handing off to \(AgentRouter.shortModelName(anchor))",
                status: .thinking, toolName: nil))
            let nudge = OpenAIRequestBuilder.message(
                role: "user",
                content: "Reply now with ONLY a single valid JSON object matching the coach_response schema. Put your actual answer in the \"summary\" field. Do NOT apologize or mention JSON — just output the object.")
            let retry = try await send(input: [nudge], tools: [], textFormat: textFormat, previousResponseId: nil, modelOverride: anchor)
            if let parsed = try await parseFinal(retry, textFormat: textFormat, modelOverride: anchor) {
                return (parsed, true)
            }
        }
        return (CoachFallbacks.fallback(), false)
    }

    /// Runs the JSON parse + repair loop. Returns `nil` (not a canned fallback) when
    /// it exhausts attempts, so the caller can decide whether to fall back to the
    /// generalist or surface a canned response.
    private func parseFinal(_ response: OpenAIResponse, textFormat: [String: Any], modelOverride: String?) async throws -> CoachResponse? {
        var current = response
        var attempts = 1
        while true {
            if let parsed = CoachResponseParser.parse(current.outputText) {
                // Reject a "sorry, I'll fix the JSON" meta-reply that happens to be
                // valid JSON — it carries no real answer. Treat it as unusable so we
                // either retry or salvage prior prose, never surface the apology.
                if !Self.isMetaApology(parsed.summary) && !Self.isMetaApology(parsed.title) {
                    return parsed.adaptiveShaped()
                }
            }
            // If the model produced a genuine prose answer (not JSON, not an
            // apology), wrap it verbatim rather than nagging it into a JSON loop.
            let text = CoachResponseParser.stripReasoningTokens(current.outputText).trimmingCharacters(in: .whitespacesAndNewlines)
            if attempts >= 2, !text.isEmpty, !Self.isMetaApology(text), !text.hasPrefix("{") {
                return Self.wrapProse(text)
            }
            attempts += 1
            if attempts > maxFinalAttempts { return nil }
            let repair = OpenAIRequestBuilder.message(
                role: "user",
                content: "Reply now with ONLY a single valid JSON object matching the coach_response schema. Put your actual answer in the \"summary\" field. Do NOT apologize or mention JSON — just output the object.")
            current = try await send(input: [repair], tools: [], textFormat: textFormat, previousResponseId: current.id, modelOverride: modelOverride)
        }
    }

    /// Detects the model's "you're right, my apologies, I'll stick to the JSON
    /// schema" meta-reply, which is never a real answer.
    static func isMetaApology(_ text: String) -> Bool {
        let t = text.lowercased()
        guard !t.isEmpty else { return false }
        let mentionsJSONorSchema = t.contains("json") || t.contains("schema") || t.contains("format")
        let apologizes = t.contains("apolog") || t.contains("you are absolutely right")
            || t.contains("you're absolutely right") || t.contains("my mistake")
            || t.contains("i clearly missed")
        return mentionsJSONorSchema && apologizes
    }

    /// Wraps a plain-text model answer into a minimal valid `CoachResponse` so a
    /// good answer isn't lost just because the model skipped the JSON envelope.
    static func wrapProse(_ text: String) -> CoachResponse {
        let summary = String(text.prefix(900))
        return CoachResponse(
            responseType: .insight,
            title: "",
            summary: summary,
            followUpChips: [],
            confidence: .medium
        ).textSanitized()
    }

    // MARK: - Helpers

    private func send(
        input: [[String: Any]], tools: [[String: Any]], textFormat: [String: Any], previousResponseId: String?, modelOverride: String? = nil
    ) async throws -> OpenAIResponse {
        let body = try OpenAIRequestBuilder.data(
            model: modelOverride ?? flags.model, input: input, tools: tools, textFormat: textFormat,
            previousResponseId: previousResponseId, reasoningEffort: flags.settings.reasoningEffort)
        return try await client.send(requestBody: body)
    }

    private func noteWebSearch(_ response: OpenAIResponse, onTrace: (CoachTraceEvent) -> Void) {
        if !response.webSearchCallIDs.isEmpty {
            onTrace(CoachTraceEvent(label: "Searching reliable sources", status: .completedTool, toolName: "web_search"))
        }
    }
}
