import Foundation
import AVFoundation
import Speech

/// Voice services: Speech-to-Text (dictation) and Text-to-Speech (read-aloud).
///
/// `VoiceServices` is the single **coordinator** for all voice in the app. It
/// owns a set of pluggable engines (`SpeechToTextEngine` / `TextToSpeechEngine`)
/// and delegates to the one the user selected in `VoicePreferences`, falling back
/// to Apple's always-available engines whenever the selected engine isn't ready
/// (model still downloading, OS too old, etc.). Its public surface is unchanged
/// from the original single-engine implementation, so every caller keeps working.
@MainActor @Observable
final class VoiceServices: NSObject {
    var isListening = false
    var transcribedText = ""
    var isSpeaking = false
    var audioLevel: Float = 0
    var elapsedSeconds: Int = 0

    /// Observable per-engine readiness, refreshed as models finish preparing so
    /// Settings can reflect Download → Downloading → Ready without polling.
    var sttReady: [STTEngineID: Bool] = [:]
    var ttsReady: [TTSEngineID: Bool] = [:]
    /// Engines currently downloading/initializing their model.
    var preparingSTT: Set<STTEngineID> = []
    var preparingTTS: Set<TTSEngineID> = []

    // MARK: Engines

    private let appleSTT = AppleSpeechEngine()
    private let appleTTS = AppleTTSEngine()
    private let whisperSTT = WhisperEngine.shared
    private let kokoroTTS = KokoroTTSEngine.shared
    private let sherpaTTS = SherpaTTSEngine.shared
    private let openAITTS = OpenAITTSEngine.shared

    /// Optional open-source engines registered as they land (B2 Whisper, C1
    /// Kokoro). Keyed by id so the coordinator can resolve the user's choice.
    private var sttEngines: [STTEngineID: SpeechToTextEngine] = [:]
    private var ttsEngines: [TTSEngineID: TextToSpeechEngine] = [:]

    /// The STT engine currently driving capture (cleared on stop).
    private var activeSTT: SpeechToTextEngine?
    /// The TTS engine currently speaking (cleared on finish/stop).
    private var activeTTS: TextToSpeechEngine?

    private var levelTimer: Timer?

    override init() {
        super.init()
        sttEngines[.apple] = appleSTT
        ttsEngines[.apple] = appleTTS
        appleTTS.onFinish = { [weak self] in self?.handleSpeechFinished() }
        // Register the on-device open-source STT engine. It reports
        // `isAvailable == false` until its model is prepared, so the coordinator
        // keeps using Apple until Whisper is ready (see prepareSelectedEngines()).
        sttEngines[.whisper] = whisperSTT
        // On-device open-source TTS (Kokoro). Same lazy-availability contract.
        kokoroTTS.onFinish = { [weak self] in self?.handleSpeechFinished() }
        ttsEngines[.kokoro] = kokoroTTS
        // On-device neural TTS via sherpa-onnx (ONNX Runtime). The default
        // engine: it works on both simulator and device and hosts several models.
        sherpaTTS.onFinish = { [weak self] in self?.handleSpeechFinished() }
        ttsEngines[.sherpa] = sherpaTTS
        // Cloud TTS via OpenAI (gpt-4o-mini-tts). Reports unavailable until an
        // OpenAI API key is saved, so the coordinator falls back to on-device.
        openAITTS.onFinish = { [weak self] in self?.handleSpeechFinished() }
        ttsEngines[.openai] = openAITTS

        // Stop voice cleanly on audio interruptions (calls, Siri, other apps) so
        // we never leave a stuck mic or a dead playback graph.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        // Warm up the user's selected engines from their bundled models so the
        // first dictation/utterance uses the chosen engine instead of falling
        // back to Apple while a model loads. Loading is local (no network).
        prepareSelectedEngines()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private nonisolated func handleInterruption(_ note: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // On any interruption begin, abandon the current session safely.
            if self.isListening { self.stopListening() }
            if self.isSpeaking { self.stopSpeaking() }
        }
    }

    private func handleSpeechFinished() {
        isSpeaking = false
        deactivateSessionIfIdle()
    }

    /// Releases the shared audio session when nothing is actively using it, so
    /// other apps' audio resumes and the mic indicator clears.
    private func deactivateSessionIfIdle() {
        guard !isListening, !isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Kicks off model download/initialization for the user's selected engines if
    /// they need it. Call from app start or when the user picks an engine in
    /// Settings. Safe to call repeatedly; Apple is a no-op.
    func prepareSelectedEngines() {
        let stt = VoicePreferences.sttEngine.engineID
        if let engine = sttEngines[stt] {
            Task { await engine.prepareModelIfNeeded() }
        }
        let tts = VoicePreferences.ttsEngine.engineID
        if let engine = ttsEngines[tts] {
            Task { await engine.prepareModelIfNeeded() }
        }
        // On the simulator Kokoro is redirected to sherpa (see resolvedTTS), so
        // warm sherpa too whenever Kokoro is the selection.
        #if targetEnvironment(simulator)
        if tts == .kokoro, let sherpa = ttsEngines[.sherpa] {
            Task { await sherpa.prepareModelIfNeeded() }
        }
        #endif
    }

    /// Whether the given STT engine is ready to run right now (model present).
    func isReady(stt id: STTEngineID) -> Bool { sttEngines[id]?.isAvailable ?? false }
    /// Whether the given TTS engine is ready to run right now.
    func isReady(tts id: TTSEngineID) -> Bool { ttsEngines[id]?.isAvailable ?? false }

    /// Triggers model preparation for a specific STT engine (used by Settings to
    /// download on demand), updating observable status flags.
    func prepare(stt id: STTEngineID) {
        guard let engine = sttEngines[id], !preparingSTT.contains(id) else { return }
        if engine.isAvailable { sttReady[id] = true; return }
        preparingSTT.insert(id)
        Task { [weak self] in
            await engine.prepareModelIfNeeded()
            await MainActor.run {
                self?.preparingSTT.remove(id)
                self?.sttReady[id] = engine.isAvailable
            }
        }
    }

    /// Triggers model preparation for a specific TTS engine.
    func prepare(tts id: TTSEngineID) {
        guard let engine = ttsEngines[id], !preparingTTS.contains(id) else { return }
        if engine.isAvailable { ttsReady[id] = true; return }
        preparingTTS.insert(id)
        Task { [weak self] in
            await engine.prepareModelIfNeeded()
            await MainActor.run {
                self?.preparingTTS.remove(id)
                self?.ttsReady[id] = engine.isAvailable
            }
        }
    }

    /// Refreshes the observable readiness flags from the engines' current state.
    func refreshReadiness() {
        for (id, engine) in sttEngines { sttReady[id] = engine.isAvailable }
        for (id, engine) in ttsEngines { ttsReady[id] = engine.isAvailable }
    }

    /// Registers an additional STT engine (called when an open-source engine is
    /// available). Re-registering replaces the prior instance for that id.
    func register(stt engine: SpeechToTextEngine) { sttEngines[engine.id] = engine }

    /// Registers an additional TTS engine.
    func register(tts engine: TextToSpeechEngine) {
        ttsEngines[engine.id] = engine
        if let apple = engine as? AppleTTSEngine { apple.onFinish = { [weak self] in self?.handleSpeechFinished() } }
    }

    /// Resolves the STT engine to use: the user's selection if available, else
    /// Apple. Falling back here is what keeps voice from ever fully breaking. If
    /// the selection exists but isn't ready yet, kick off its model preparation
    /// so a later capture can use it.
    private func resolvedSTT() -> SpeechToTextEngine {
        let selected = VoicePreferences.sttEngine.engineID
        if let engine = sttEngines[selected] {
            if engine.isAvailable { return engine }
            Task { await engine.prepareModelIfNeeded() }
        }
        return appleSTT
    }

    private func resolvedTTS() -> TextToSpeechEngine {
        var selected = VoicePreferences.ttsEngine.engineID
        // Kokoro's Core ML graph emits static on the iOS Simulator (no real ANE).
        // Transparently route to the sherpa-onnx neural engine there so the user
        // never hears noise; on a real device Kokoro is used as selected.
        #if targetEnvironment(simulator)
        if selected == .kokoro { selected = .sherpa }
        #endif
        if let engine = ttsEngines[selected] {
            if engine.isAvailable { return engine }
            Task { await engine.prepareModelIfNeeded() }
        }
        // If the (possibly redirected) selection isn't ready, prefer sherpa over
        // Apple so users still get a neural voice when one is loaded.
        if selected != .sherpa, let sherpa = ttsEngines[.sherpa], sherpa.isAvailable {
            return sherpa
        }
        return appleTTS
    }

    // MARK: - Speech-to-Text

    func requestSpeechAuthorization() async -> Bool {
        await resolvedSTT().requestAuthorization()
    }

    /// The engine currently driving capture, if listening (e.g. `.whisper`).
    var activeSTTID: STTEngineID? { activeSTT?.id }

    func startListening() {
        guard !isListening else { return }

        transcribedText = ""
        elapsedSeconds = 0
        audioLevel = 0

        let engine = resolvedSTT()
        if tryStartStreaming(engine) {
            activeSTT = engine
        } else if engine.id != .apple, tryStartStreaming(appleSTT) {
            // Resilience: never leave the user with a dead mic. If the selected
            // engine fails to start this session, fall back to Apple so capture
            // keeps working (e.g. a transient audio-session hiccup on Whisper).
            activeSTT = appleSTT
        } else {
            activeSTT = nil
            return
        }

        isListening = true
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.elapsedSeconds += 1 }
        }
    }

    /// Attempts to start a given STT engine, wiring its partial/level callbacks.
    /// Returns whether it started successfully.
    private func tryStartStreaming(_ engine: SpeechToTextEngine) -> Bool {
        do {
            try engine.startStreaming(
                onPartial: { [weak self] text in self?.transcribedText = text },
                onLevel: { [weak self] level in self?.audioLevel = level }
            )
            return true
        } catch {
            return false
        }
    }

    func stopListening() {
        if let engine = activeSTT {
            let final = engine.stop()
            if !final.isEmpty { transcribedText = final }
        }
        activeSTT = nil
        isListening = false
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0
        deactivateSessionIfIdle()
    }

    /// Ensures the user's selected STT engine is actually loaded *before* a
    /// continuous/hands-free session opens the mic, so it uses the chosen engine
    /// (e.g. Whisper) instead of silently falling back to Apple because the model
    /// hadn't finished initializing yet. Returns the engine id that capture will
    /// use (the selection if it became ready, otherwise `.apple`).
    @discardableResult
    func prepareSTTForSession() async -> STTEngineID {
        let selected = VoicePreferences.sttEngine.engineID
        guard selected != .apple, let engine = sttEngines[selected] else { return .apple }
        if !engine.isAvailable {
            await engine.prepareModelIfNeeded()
        }
        refreshReadiness()
        return engine.isAvailable ? selected : .apple
    }

    /// Stops capture and returns the *most accurate* final transcript. Streaming
    /// engines (Apple) finalize synchronously; chunked engines (Whisper) transcribe
    /// the full buffer only after the mic stops and deliver it via their partial
    /// callback. For those we await a short grace window so the hands-free loop
    /// never drops the tail of an utterance (and so sub-1s phrases, which produce
    /// no live partial, still yield text).
    func stopListeningAndFinalize(grace: TimeInterval = 1.6) async -> String {
        let chunked = (activeSTT?.id == .whisper)
        let before = transcribedText
        stopListening()
        guard chunked else { return transcribedText }
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 120_000_000)
            // The async full-buffer transcript overwrites `transcribedText`;
            // take it as soon as it differs from the last live partial.
            if transcribedText != before { break }
        }
        return transcribedText
    }

    // MARK: - Text-to-Speech

    /// Speaks `text` using the configured TTS engine, voice, rate, and pitch
    /// (`VoicePreferences`). Pass explicit values to override the stored
    /// preferences (e.g. for a settings preview). Interrupts any current speech.
    func speak(_ text: String, rate: Float? = nil, pitch: Float? = nil, voiceID: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Stop whatever is currently speaking before starting anew.
        activeTTS?.stop()

        let engine = resolvedTTS()
        activeTTS = engine
        let resolvedRate = rate ?? VoicePreferences.ttsRate
        let resolvedPitch = pitch ?? VoicePreferences.ttsPitch
        let resolvedVoice = voiceID ?? VoicePreferences.ttsVoiceID

        isSpeaking = true
        Task { [weak self] in
            await engine.speak(trimmed, rate: resolvedRate, pitch: resolvedPitch, voiceID: resolvedVoice)
            // For engines that complete synchronously within `speak`, reflect the
            // finished state if the engine reports it is no longer speaking.
            await MainActor.run {
                guard let self else { return }
                if !engine.isSpeaking {
                    self.isSpeaking = false
                    self.deactivateSessionIfIdle()
                }
            }
        }
    }

    func stopSpeaking() {
        activeTTS?.stop()
        isSpeaking = false
        deactivateSessionIfIdle()
    }

    #if DEBUG
    /// Test-only: the TTS engine id that `resolvedTTS()` would pick right now.
    func resolvedTTSEngineIDForTesting() -> TTSEngineID { resolvedTTS().id }
    #endif

    /// Toggles speech for `text`: starts speaking if idle, stops if already
    /// speaking. Returns the resulting speaking state. Used by the chat bubble's
    /// speaker button.
    @discardableResult
    func toggleSpeaking(_ text: String) -> Bool {
        if isSpeaking {
            stopSpeaking()
            return false
        }
        speak(text)
        return true
    }
}
