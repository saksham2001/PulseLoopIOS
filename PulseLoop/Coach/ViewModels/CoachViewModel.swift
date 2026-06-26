import Foundation
import SwiftData
import UIKit

/// Owns one coach turn end-to-end: persist the user message, build flags +
/// context, run the orchestrator off the SwiftData reads it needs, persist the
/// assistant message (+ tool-call trace), and surface live progress. The iOS
/// analogue of the web `coach_service.send_message`.
@MainActor
@Observable
final class CoachViewModel {
    var traceEvents: [CoachTraceEvent] = []
    var isSending = false
    var errorBanner: String?
    /// Set when a turn was refused for lack of credits. CoachView observes this to
    /// offer an in-place "Add credits" path to the paywall (`CreditsView`).
    var outOfCredits = false
    /// The in-flight turn, so the UI can cancel it (AIN-6).
    private var currentTask: Task<Void, Never>?

    /// A model slug the user picked via the transparency "use a different model"
    /// affordance. Applied to the next turn only, then cleared (Life OS T4).
    var pendingForcedModel: String?

    /// Re-run the most recent user message on a specific model (transparency action).
    func retry(_ text: String, on modelSlug: String, conversationId: UUID, context: ModelContext) {
        pendingForcedModel = modelSlug
        startTurn(text, conversationId: conversationId, context: context)
    }

    /// Cancel the in-flight turn. The orchestrator's `try await` network hops throw
    /// `CancellationError`, which the catch path turns into a (suppressed) error.
    func cancel() {
        currentTask?.cancel()
    }

    /// Start a turn as a tracked, cancellable task. The view calls this (rather than
    /// awaiting `send` directly) so `cancel()` can stop it.
    func startTurn(
        _ text: String,
        conversationId: UUID,
        context: ModelContext,
        coordinator: RingSyncCoordinator? = nil,
        images: [Data] = []
    ) {
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.send(text, conversationId: conversationId, context: context, coordinator: coordinator, images: images)
        }
    }

    private let keyStore: APIKeyStore
    private let settingsStore: CoachSettingsStore
    private let clientFactory: (String) -> ResponsesClient
    private let ledger: CreditsLedger
    /// Resolves the paired device token used to authenticate the backend proxy.
    /// Injectable for tests; defaults to the Keychain store written at pairing.
    private let deviceTokenProvider: () -> String?

    init(
        keyStore: APIKeyStore = OpenAIKeychainStore(),
        settingsStore: CoachSettingsStore = .shared,
        clientFactory: @escaping (String) -> ResponsesClient = { OpenRouterResponsesClient(apiKey: $0) },
        ledger: CreditsLedger = .shared,
        deviceTokenProvider: @escaping () -> String? = { (try? CloudSyncKeychainStore().readKey()) ?? nil }
    ) {
        self.keyStore = keyStore
        self.settingsStore = settingsStore
        self.clientFactory = clientFactory
        self.ledger = ledger
        self.deviceTokenProvider = deviceTokenProvider
    }

    func send(
        _ text: String,
        conversationId: UUID,
        context: ModelContext,
        coordinator: RingSyncCoordinator? = nil,
        images: [Data] = []
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow an image-only message (no text) as long as something was sent.
        guard !(trimmed.isEmpty && images.isEmpty), !isSending else { return }
        isSending = true
        traceEvents = []
        errorBanner = nil
        outOfCredits = false
        defer { isSending = false }

        // Build base64 data URLs for the model, and keep a compressed copy of the
        // first image to render in the transcript.
        let imageDataURLs = images.map { Self.dataURL(for: $0) }
        let effectiveText = trimmed.isEmpty ? "Here's an image — take a look and help me with it." : trimmed

        // Optimistically persist the user message so the UI shows it immediately.
        let userMessage = CoachMessage(
            conversationId: conversationId,
            role: "user",
            body: trimmed,
            attachmentData: images.first
        )
        context.insert(userMessage)
        context.saveOrLog("coach", surface: true)

        let apiKey = AIService.shared.currentAPIKey
        let flags = CoachFeatureFlags(settings: settingsStore.settings, hasAPIKey: apiKey != nil)
        NSLog("[OpenRouterCoach] sendDiag coachEnabled=%@ hasKey=%@ provider=%@ canAffordTurn=%@",
              String(flags.coachEnabled), String(apiKey != nil),
              settingsStore.settings.providerMode.rawValue, String(ledger.canAfford(.coachTurn)))

        // Credit enforcement (E3). When a real LLM turn would run, refuse it up
        // front if the balance can't cover a coach turn. In backend-proxy mode the
        // server is authoritative and will also enforce (HTTP 402), but blocking
        // here avoids a wasted round-trip and gives an immediate, clear message.
        if flags.coachEnabled, !ledger.canAfford(.coachTurn) {
            let assistant = CoachMessage(
                conversationId: conversationId,
                role: "assistant",
                body: "You're out of AI credits. Add more in Settings → AI Credits to keep chatting with the assistant."
            )
            context.insert(assistant)
            context.saveOrLog("coach")
            errorBanner = "Out of AI credits."
            outOfCredits = true
            return
        }

        let packet = CoachContextBuilder.build(context: context)
        let recent = recentMessages(conversationId: conversationId, excluding: userMessage.id, context: context)

        var orchestrator = CoachOrchestrator(
            client: makeClient(apiKey: apiKey, settings: settingsStore.settings),
            registry: ToolRegistry(flags: flags),
            flags: flags,
            toolContext: ToolExecutionContext(modelContext: context, flags: flags, coordinator: coordinator)
        )
        // Feedback-weighted routing (Life OS T4): feed recent on-device outcomes so
        // the router can prefer models that work well for this user. Empty on day one
        // ⇒ routing falls back to the declarative capability prior.
        orchestrator.routingStats = CoachFeedbackStore.outcomeStats(in: context)
        orchestrator.forcedModel = pendingForcedModel
        pendingForcedModel = nil

        let turnStartedAt = Date()
        let result = await orchestrator.runTurn(
            userText: effectiveText,
            packet: packet,
            recentMessages: recent,
            personality: settingsStore.settings.personality,
            primaryGoal: settingsStore.settings.primaryGoal,
            imageDataURLs: imageDataURLs
        ) { [weak self] event in
            self?.traceEvents.append(event)
        }
        let turnLatencyMs = Int(Date().timeIntervalSince(turnStartedAt) * 1000)

        // If the user cancelled mid-turn (AIN-6), don't persist a fallback/error
        // bubble — just note that it stopped, and skip metering.
        if Task.isCancelled {
            context.insert(CoachMessage(conversationId: conversationId, role: "assistant", body: "Stopped."))
            context.saveOrLog("coach")
            return
        }

        persist(result, conversationId: conversationId, context: context, latencyMs: turnLatencyMs)
        NSLog("[OpenRouterCoach] turnDone usedLLM=%@ tools=%d in=%d out=%d err=%@",
              String(result.usedLLM), result.trace.count, result.inputTokens, result.outputTokens,
              result.errorMessage ?? "nil")

        // Surface a transport/parse failure so it isn't silent (BUG-2). The assistant
        // bubble already holds a canned fallback; the banner explains why.
        if let message = result.errorMessage {
            errorBanner = message
        }

        // Meter the AI call against the credits ledger (E1). Scripted fallbacks
        // (no LLM) are free. Sub-app generation turns are metered as such.
        //
        // In backend-proxy mode the *server* is the authoritative ledger: it already
        // debited the turn and synced the balance back via the response's
        // `pulseloop_credits` field, so metering locally here would double-count.
        let serverAuthoritative = settingsStore.settings.providerMode == .backendProxy
        if result.usedLLM, !serverAuthoritative {
            let kind: AIUsageKind = result.trace.contains {
                $0.toolName == "generate_subapp_spec" || $0.toolName == "refine_subapp_spec"
            } ? .subAppGeneration : .coachTurn
            let usage = OpenAIResponse.TokenUsage(inputTokens: result.inputTokens, outputTokens: result.outputTokens)
            ledger.meter(kind, usage: usage)
        }
    }

    /// Builds the transport for this turn, honoring the configured provider mode,
    /// but always degrading to a transport that actually works rather than to a
    /// guaranteed failure.
    ///
    /// Order of preference:
    /// 1. `.backendProxy` with a valid URL → `BackendProxyResponsesClient` (server holds the key).
    /// 2. `.bedrock` *when fully configured* (IAM creds + region + model) → `BedrockResponsesClient`.
    /// 3. A usable on-device OpenRouter key → `OpenRouterResponsesClient` (BYO key).
    /// 4. Paired device (token) + web URL → `BackendProxyResponsesClient` (zero-config fallback).
    /// 5. Last resort → the injected `clientFactory` (lets tests stub; otherwise an
    ///    empty-key client whose failure surfaces a clear "set up AI" path).
    ///
    /// Crucially, an experimental/misconfigured `providerMode` (e.g. `.bedrock`
    /// selected with no AWS credentials — which has shipped on some devices) no
    /// longer dead-ends into an empty-key OpenRouter call. It falls through to the
    /// paired proxy, so the coach keeps working.
    private func makeClient(apiKey: String?, settings: CoachSettings) -> ResponsesClient {
        // 1. Explicit backend proxy URL.
        if settings.providerMode == .backendProxy {
            let trimmed = settings.backendProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http" {
                return BackendProxyResponsesClient(baseURL: url, sessionToken: deviceTokenProvider())
            }
        }

        // 2. Bedrock — only when actually configured with on-device IAM credentials.
        if settings.providerMode == .bedrock, let bedrock = makeBedrockClient(settings: settings) {
            return bedrock
        }

        // 3. A real on-device OpenRouter key (BYO-key path).
        if let key = apiKey, !key.isEmpty {
            return clientFactory(key)
        }

        // 4. Zero-config: paired device → route through the proxy (server holds the key).
        // The proxy client appends `v1/coach/responses`, so the base must include `/api`.
        if let token = deviceTokenProvider(), !token.isEmpty,
           let webURL = CoachFeatureFlags.appWebBaseURL {
            return BackendProxyResponsesClient(baseURL: webURL.appendingPathComponent("api"), sessionToken: token)
        }

        // 5. Nothing usable — return the default client. Its call will fail cleanly
        // and the orchestrator's fallback explains how to enable AI.
        return clientFactory(apiKey ?? "")
    }

    /// Builds a `BedrockResponsesClient` only when complete IAM credentials, a
    /// region, and a model id are all present; otherwise nil so the caller falls
    /// back to a working transport.
    private func makeBedrockClient(settings: CoachSettings) -> ResponsesClient? {
        guard let creds = BedrockCredentialsStore().read() else { return nil }
        let region = settings.bedrockRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.bedrockModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !creds.accessKeyID.isEmpty, !creds.secretAccessKey.isEmpty,
              !region.isEmpty, !model.isEmpty else { return nil }
        return BedrockResponsesClient(
            accessKeyID: creds.accessKeyID,
            secretAccessKey: creds.secretAccessKey,
            sessionToken: creds.sessionToken,
            region: region,
            modelID: model
        )
    }

    // MARK: - Confirmation cards

    /// Execute the pending action at `index` after the user taps Confirm. Any other
    /// proposed actions on the same message remain as live cards so none are lost.
    func confirmPendingAction(_ message: CoachMessage, at index: Int, context: ModelContext) {
        var actions = PendingAction.decodeArray(fromJSON: message.pendingActionJSON)
        guard actions.indices.contains(index) else { return }
        let action = actions.remove(at: index)
        let resultText = PendingActionExecutor.execute(action, context: context)
        message.pendingActionJSON = PendingAction.encodedJSONArray(actions)
        context.insert(CoachMessage(conversationId: message.conversationId, role: "assistant", body: resultText))
        context.saveOrLog("coach")
    }

    /// Dismiss the pending action at `index` after the user taps Cancel, leaving the
    /// other proposed actions intact.
    func cancelPendingAction(_ message: CoachMessage, at index: Int, context: ModelContext) {
        var actions = PendingAction.decodeArray(fromJSON: message.pendingActionJSON)
        guard actions.indices.contains(index) else { return }
        actions.remove(at: index)
        message.pendingActionJSON = PendingAction.encodedJSONArray(actions)
        context.insert(CoachMessage(conversationId: message.conversationId, role: "assistant", body: "Okay, I won't make that change."))
        context.saveOrLog("coach")
    }

    /// Persist an inline travel card (from chat) as a `TripItem` on the most recent
    /// active trip, creating a trip if none exists yet. "One shape, two surfaces":
    /// the saved item then appears on the Travel screen.
    func saveTravelCard(_ card: CoachTravelCard, context: ModelContext) {
        func clean(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        let trip: Trip
        let existing = (try? context.fetch(FetchDescriptor<Trip>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )))?.first { $0.status == .planning || $0.status == .booked }
        if let existing {
            trip = existing
        } else {
            let destination = clean(card.location) ?? "My trip"
            trip = Trip(destination: destination)
            context.insert(trip)
        }
        let kind = TripItemKind(rawValue: card.kind.tripItemKindRaw) ?? .activity
        let nextOrder = (trip.items.map(\.order).max() ?? -1) + 1
        let item = TripItem(
            tripId: trip.id,
            kind: kind,
            title: card.title,
            details: clean(card.subtitle),
            location: clean(card.location),
            url: clean(card.bookingURL),
            price: card.price,
            currency: clean(card.currency),
            rating: card.rating,
            latitude: card.latitude,
            longitude: card.longitude,
            order: nextOrder
        )
        context.insert(item)
        trip.items.append(item)
        trip.updatedAt = Date()
        context.saveOrLog("coach.travel.save")
        HapticService.success()
    }

    // MARK: - Persistence

    private func persist(_ result: CoachOrchestrator.TurnResult, conversationId: UUID, context: ModelContext, latencyMs: Int = 0) {
        let assistant = CoachMessage(
            conversationId: conversationId,
            role: "assistant",
            body: result.assistant.plainText,
            cardsJSON: result.assistant.encodedJSON(),
            pendingActionJSON: PendingAction.encodedJSONArray(result.pendingActions)
        )
        context.insert(assistant)

        for entry in result.trace {
            context.insert(CoachToolCall(
                conversationId: conversationId,
                messageId: assistant.id,
                toolName: entry.toolName,
                inputJSON: entry.argsRedacted,
                outputJSON: entry.resultSummary
            ))
        }

        // Decision log (Life OS T0): one telemetry row per turn, linked to the
        // assistant message so feedback can be sliced by role/model. Only LLM turns
        // are logged (scripted fallbacks carry no routing decision).
        if result.usedLLM {
            let telemetry = Self.makeTelemetry(result, messageId: assistant.id, conversationId: conversationId, latencyMs: latencyMs)
            context.insert(telemetry)
            // Content-free usage event through the existing opt-in seam.
            Analytics.track("coach_turn_completed", [
                "role": telemetry.roleLabel,
                "model": AgentRouter.shortModelName(telemetry.model),
                "rounds": String(telemetry.rounds),
                "recovered": String(telemetry.recovered),
                "had_error": String(!telemetry.errorReason.isEmpty),
            ])
        }

        if let convo = fetchConversation(conversationId, context: context) {
            convo.updatedAt = Date()
        }
        context.saveOrLog("coach")
    }

    /// Builds the per-turn `TurnTelemetry` row from a turn result. Pure + static so
    /// it's unit-testable without a model context. Tool names are de-duplicated,
    /// ordered by first use, and joined low-cardinality (no arguments).
    static func makeTelemetry(
        _ result: CoachOrchestrator.TurnResult, messageId: UUID, conversationId: UUID, latencyMs: Int
    ) -> TurnTelemetry {
        var seen = Set<String>()
        var orderedTools: [String] = []
        for entry in result.trace where seen.insert(entry.toolName).inserted {
            orderedTools.append(entry.toolName)
        }
        return TurnTelemetry(
            messageId: messageId,
            conversationId: conversationId,
            roleLabel: result.roleLabel,
            model: result.model,
            rounds: result.rounds,
            toolNames: orderedTools.joined(separator: ","),
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens,
            latencyMs: latencyMs,
            recovered: result.recovered,
            errorReason: result.errorMessage ?? ""
        )
    }

    private func recentMessages(
        conversationId: UUID, excluding excludedId: UUID, context: ModelContext, limit: Int = 10
    ) -> [CoachOrchestrator.PriorMessage] {
        var descriptor = FetchDescriptor<CoachMessage>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 40
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows
            .filter { $0.id != excludedId }
            .suffix(limit)
            .map { CoachOrchestrator.PriorMessage(role: $0.role, text: $0.body) }
    }

    private func fetchConversation(_ id: UUID, context: ModelContext) -> CoachConversation? {
        let descriptor = FetchDescriptor<CoachConversation>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    /// Builds a `data:` URL (base64 JPEG) for a model `image_url` content part,
    /// downscaling/compressing so requests stay within sane payload sizes.
    static func dataURL(for imageData: Data) -> String {
        let prepared = downscaledJPEG(imageData) ?? imageData
        return "data:image/jpeg;base64,\(prepared.base64EncodedString())"
    }

    /// Downscales to a max dimension and re-encodes as JPEG to cap upload size.
    private static func downscaledJPEG(_ data: Data, maxDimension: CGFloat = 1024, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
