import Foundation
import SwiftData
import Observation

/// Drives a **hands-free, continuous voice conversation** — the voice-native core
/// of the assistant. The user just talks; the controller listens, decides when an
/// utterance is finished (silence-based endpointing), routes the transcript
/// through the existing Coach pipeline (`CoachViewModel.send`, which runs the full
/// tool stack — tasks, notes, mood/meals/habits, memory, navigation), speaks the
/// reply, then automatically resumes listening for the next thing.
///
/// It reuses `VoiceServices` for STT/TTS and `CoachViewModel` for orchestration, so
/// nothing about the model/tool layer changes — this is purely the conversational
/// loop that ties capture → reasoning → action → speech into one fluid surface.
@MainActor
@Observable
final class VoiceSessionController {
    /// Where the loop currently is. Drives the orb + caption in the UI.
    enum Phase: Equatable {
        case idle       // not started yet
        case listening  // mic open, capturing the user's speech
        case thinking   // utterance sent to the Coach, awaiting the reply + actions
        case speaking   // reading the reply aloud
        case paused     // user paused the session; mic closed
        case denied     // mic / speech permission refused
    }

    /// One exchange in the session, shown as a card and used to confirm out loud
    /// what was organized.
    struct Turn: Identifiable, Equatable {
        let id = UUID()
        var userText: String
        var assistantSummary: String = ""
        var actionsTaken: [String] = []
        var followUps: [String] = []
        var isError: Bool = false
        var isPending: Bool = true
    }

    // MARK: Observable state (read by the view)

    private(set) var phase: Phase = .idle
    private(set) var partialTranscript: String = ""
    private(set) var turns: [Turn] = []
    /// The STT engine actually driving capture this session (resolved at `start`).
    private(set) var activeEngine: STTEngineID = .apple
    /// Live audio level (0...1) for the waveform/orb. Mirrors `VoiceServices`.
    var audioLevel: Float { voice.audioLevel }
    var isSpeaking: Bool { voice.isSpeaking }

    /// Friendly name of the engine in use, shown in the UI so the user can see
    /// Whisper is really running.
    var engineLabel: String {
        switch activeEngine {
        case .whisper: return "Whisper"
        case .moonshine: return "Moonshine"
        case .apple: return "Apple"
        }
    }

    // MARK: Endpointing tuning

    /// End the utterance after this much continuous quiet once speech was heard.
    private let silenceWindow: TimeInterval = 1.2
    /// Audio level above this counts as the user actively talking.
    private let voiceThreshold: Float = 0.06
    /// Ignore sub-threshold blips so a cough/typo doesn't trigger a turn.
    private let minUtteranceChars = 2
    /// Hard cap so a never-ending monologue still gets processed.
    private let maxUtterance: TimeInterval = 45
    private let tickInterval: TimeInterval = 0.1

    // MARK: Dependencies

    private let voice: VoiceServices
    private let viewModel: CoachViewModel
    private let conversationId: UUID
    private let context: ModelContext
    private let coordinator: RingSyncCoordinator?

    // MARK: Loop bookkeeping

    private var tickTimer: Timer?
    private var lastVoiceAt = Date()
    private var utteranceStart = Date()
    private var heardSpeech = false
    private var isActive = false
    private var processing = false

    init(
        voice: VoiceServices,
        conversationId: UUID,
        context: ModelContext,
        coordinator: RingSyncCoordinator?,
        viewModel: CoachViewModel? = nil
    ) {
        self.voice = voice
        self.conversationId = conversationId
        self.context = context
        self.coordinator = coordinator
        // Created here (inside the main-actor init) rather than as a default arg,
        // which would evaluate in a nonisolated context.
        self.viewModel = viewModel ?? CoachViewModel()
    }

    // MARK: - Lifecycle

    /// Requests permission and opens the loop. Safe to call once per presentation.
    func start() async {
        guard !isActive else { return }
        let authorized = await voice.requestSpeechAuthorization()
        guard authorized else { phase = .denied; return }
        // Load the selected engine (e.g. Whisper) before opening the mic so the
        // session actually uses it instead of falling back to Apple mid-load.
        activeEngine = await voice.prepareSTTForSession()
        isActive = true
        startTicking()
        // Opt-in: greet with a once-a-day spoken brief, then fall into listening
        // (the tick loop resumes the mic once the brief finishes speaking).
        if speakBriefIfDue() { return }
        beginListening()
    }

    /// Speaks the proactive daily brief when the user has opted in and it hasn't
    /// played yet today. Returns true if it started speaking (so `start` skips the
    /// immediate listen; `tick` will resume once speech ends).
    @discardableResult
    private func speakBriefIfDue() -> Bool {
        let today = VoiceBriefComposer.dayKey(for: Date())
        guard VoiceBriefComposer.shouldSpeak(
            enabled: VoicePreferences.voiceBriefEnabled,
            lastSpokenDay: VoicePreferences.voiceBriefLastDay,
            today: today
        ) else { return false }

        let items = fetchBriefItems()
        let script = VoiceBriefComposer.script(learnings: items)
        guard !script.isEmpty else { return false }

        VoicePreferences.voiceBriefLastDay = today
        Analytics.track("voice_brief_spoken")
        phase = .speaking
        voice.speak(script)
        return true
    }

    /// Pulls the user's strongest active learnings for the brief, mapped to the
    /// composer's persistence-free `Item`.
    private func fetchBriefItems() -> [VoiceBriefComposer.Item] {
        var descriptor = FetchDescriptor<DailyLearning>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.importance, order: .reverse),
                     SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 6
        let learnings = (try? context.fetch(descriptor)) ?? []
        return learnings.map {
            VoiceBriefComposer.Item(title: $0.title, detail: $0.detail, importance: $0.importance)
        }
    }

    /// Tears everything down (mic, TTS, timer). Call on dismiss.
    func stop() {
        isActive = false
        processing = false
        voice.stopListening()
        voice.stopSpeaking()
        tickTimer?.invalidate()
        tickTimer = nil
        phase = .idle
    }

    /// Pause/resume the hands-free loop without leaving the screen.
    func togglePause() {
        if phase == .paused {
            beginListening()
        } else {
            voice.stopListening()
            voice.stopSpeaking()
            phase = .paused
        }
    }

    /// The orb is the one control the user needs: barge in while it's talking,
    /// send immediately while listening, or (re)start when idle/paused.
    func tapOrb() {
        switch phase {
        case .speaking:
            voice.stopSpeaking()
            beginListening()
        case .listening:
            finalizeUtterance(force: true)
        case .paused, .idle, .denied:
            Task { if !isActive { await start() } else { beginListening() } }
        case .thinking:
            break // don't interrupt an in-flight turn
        }
    }

    // MARK: - Listening

    private func beginListening() {
        guard isActive else { return }
        partialTranscript = ""
        heardSpeech = false
        lastVoiceAt = Date()
        utteranceStart = Date()
        voice.startListening()
        // Reflect the engine that actually started (in case of a fallback), so the
        // header label stays truthful across the session.
        if let id = voice.activeSTTID { activeEngine = id }
        phase = .listening
    }

    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    /// The heartbeat: detects end-of-utterance while listening and auto-resumes
    /// after the reply finishes speaking.
    private func tick() {
        guard isActive else { return }
        switch phase {
        case .listening:
            let partial = voice.transcribedText
            let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)

            // Treat *either* a rising audio level *or* a growing transcript as
            // activity, so endpointing works regardless of which STT engine is
            // active (some report level, all report partials).
            if partial != partialTranscript {
                partialTranscript = partial
                lastVoiceAt = Date()
            }
            // Count *either* a rising audio level *or* a growing transcript as
            // activity. The level path matters for Whisper, which only emits a
            // transcript every ~1.5s — without it, short phrases would never be
            // recognized as speech and the turn would never end.
            if voice.audioLevel > voiceThreshold {
                lastVoiceAt = Date()
                heardSpeech = true
            }
            if !trimmed.isEmpty {
                heardSpeech = true
            }

            let quietFor = Date().timeIntervalSince(lastVoiceAt)
            let runningFor = Date().timeIntervalSince(utteranceStart)
            if heardSpeech && (quietFor >= silenceWindow || runningFor >= maxUtterance) {
                finalizeUtterance(force: false)
            }

        case .speaking:
            // The reply finished reading → pick the conversation back up. (To
            // interrupt mid-confirmation the user taps the orb, which routes
            // through `tapOrb` → stop speaking → listen; we don't auto-detect
            // barge-in from the mic here because the mic is closed during TTS,
            // so its level would be stale.)
            if !voice.isSpeaking {
                beginListening()
            }

        default:
            break
        }
    }

    // MARK: - Turn handoff

    /// Closes the mic, resolves the *final* transcript (awaiting Whisper's
    /// full-buffer pass when needed), sends it through the Coach (which executes
    /// any tools), then speaks the result and loops back to listening.
    private func finalizeUtterance(force: Bool) {
        guard phase == .listening, !processing else { return }
        processing = true
        phase = .thinking

        // Show what we have immediately (the live partial); it's replaced by the
        // accurate final once the engine returns it.
        let provisional = voice.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let turn = Turn(userText: provisional)
        turns.append(turn)
        let turnId = turn.id

        Task { [weak self] in
            guard let self else { return }
            let finalText = await self.voice.stopListeningAndFinalize()
            let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard text.count >= self.minUtteranceChars else {
                // False trigger (noise / silence) — drop the empty turn and keep going.
                self.turns.removeAll { $0.id == turnId }
                self.processing = false
                self.beginListening()
                return
            }

            if let idx = self.turns.firstIndex(where: { $0.id == turnId }) {
                self.turns[idx].userText = text
            }
            HapticService.selection()
            await self.viewModel.send(
                text,
                conversationId: self.conversationId,
                context: self.context,
                coordinator: self.coordinator
            )
            self.completeTurn(turnId: turnId)
        }
    }

    /// Reads the assistant reply the Coach just persisted, updates the on-screen
    /// turn, and speaks a concise confirmation.
    private func completeTurn(turnId: UUID) {
        processing = false
        guard isActive else { return }

        let response = latestAssistantResponse()
        let spoken = Self.spokenSummary(from: response)

        if let idx = turns.firstIndex(where: { $0.id == turnId }) {
            turns[idx].isPending = false
            turns[idx].assistantSummary = response?.summary ?? spoken
            turns[idx].actionsTaken = response?.actionsTaken ?? []
            turns[idx].followUps = response?.followUpChips ?? []
            turns[idx].isError = viewModel.errorBanner != nil
        }

        if spoken.isEmpty {
            // Nothing to say — resume immediately.
            beginListening()
            return
        }

        phase = .speaking
        voice.speak(spoken)
        // `tick()` resumes listening once `voice.isSpeaking` flips back to false.
    }

    /// The Coach persists its structured reply on the latest assistant message;
    /// pull it back so we can both render and read it.
    private func latestAssistantResponse() -> CoachResponse? {
        let convo = conversationId
        var descriptor = FetchDescriptor<CoachMessage>(
            predicate: #Predicate { $0.conversationId == convo && $0.role == "assistant" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let message = (try? context.fetch(descriptor))?.first else { return nil }
        if let structured = CoachResponse.decode(fromJSON: message.cardsJSON) {
            return structured
        }
        // No structured payload (e.g. an out-of-credits notice) → wrap the plain body.
        guard !message.body.isEmpty else { return nil }
        return CoachResponse(responseType: .insight, title: "", summary: message.body)
    }

    /// Builds a short, speakable confirmation. For a multi-intent turn it reads
    /// back each thing that got done as a natural list ("Done: logged a run, added
    /// eggs to breakfast, and set a reminder to call mom at 6.") so the user hears
    /// every part of their request land, then adds the one-line summary. Pure and
    /// static so it can be unit-tested without a live session.
    static func spokenSummary(from response: CoachResponse?) -> String {
        guard let response else { return "" }
        var parts: [String] = []

        let actions = response.actionsTaken
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !actions.isEmpty {
            parts.append("Done: \(naturalList(actions)).")
        }

        let body = response.summary.isEmpty ? response.title : response.summary
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // Avoid repeating the summary when it's just echoing the single action.
        if !trimmedBody.isEmpty && !(actions.count == 1 && trimmedBody.caseInsensitiveCompare(actions[0]) == .orderedSame) {
            parts.append(trimmedBody)
        }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Joins items into a spoken-friendly list: "a", "a and b", "a, b, and c".
    /// Lower-cases the first letter of each follow-on item so it flows after
    /// "Done:" without sounding like a list of headlines.
    static func naturalList(_ items: [String]) -> String {
        let cleaned = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        let lowered = cleaned.map { lowerFirst($0) }
        switch lowered.count {
        case 1: return lowered[0]
        case 2: return "\(lowered[0]) and \(lowered[1])"
        default:
            let head = lowered.dropLast().joined(separator: ", ")
            return "\(head), and \(lowered.last!)"
        }
    }

    private static func lowerFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        // Keep acronyms/proper-ish all-caps starts intact (e.g. "PR", "Tahoe").
        if first.isUppercase, s.dropFirst().first?.isUppercase == true { return s }
        return first.lowercased() + s.dropFirst()
    }
}
