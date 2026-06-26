import Foundation
import AVFoundation

/// User-configurable speech-to-text engine. Apple's on-device recognizer is the
/// only engine wired up today; the open-source engines are listed so the choice
/// persists and the UI is ready for when their runtimes land (see
/// `VOICE_LOOP_PROMPT.md`). Selecting a not-yet-available engine falls back to
/// Apple at runtime.
enum STTEngine: String, CaseIterable, Identifiable {
    case appleOnDevice
    case whisper
    case moonshine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appleOnDevice: return "Apple (on-device)"
        case .whisper: return "Whisper (open source)"
        case .moonshine: return "Moonshine (open source)"
        }
    }

    var detail: String {
        switch self {
        case .appleOnDevice: return "Built-in dictation. Fast, private, no download."
        case .whisper: return "High accuracy, on-device (Core ML). Built in — no download."
        case .moonshine: return "Tiny & fast on-device model. Coming soon."
        }
    }

    /// True when the engine can be selected in Settings. Whisper ships via
    /// WhisperKit (downloads its model on first use); Moonshine is not yet wired.
    /// Apple is always available. At runtime the coordinator still falls back to
    /// Apple if a selected engine's model isn't ready yet.
    var isAvailable: Bool { self == .appleOnDevice || self == .whisper }

    /// Maps the persisted preference case to the engine coordinator's id.
    var engineID: STTEngineID {
        switch self {
        case .appleOnDevice: return .apple
        case .whisper: return .whisper
        case .moonshine: return .moonshine
        }
    }
}

/// User-configurable text-to-speech engine.
/// - `sherpa` (sherpa-onnx / ONNX Runtime) is the default on-device engine: it
///   runs correctly on both simulator and device and hosts several bundled models.
/// - `kokoro` (Core ML) is offered too but is device-only in practice (its Core ML
///   graph emits noise on the simulator).
/// - `appleOnDevice` (`AVSpeechSynthesizer`) is the always-available fallback.
enum TTSEngine: String, CaseIterable, Identifiable {
    case appleOnDevice
    case kokoro
    case sherpa
    case openai

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appleOnDevice: return "Apple (on-device)"
        case .kokoro: return "Kokoro (Core ML)"
        case .sherpa: return "Neural (on-device)"
        case .openai: return "OpenAI (cloud)"
        }
    }

    var detail: String {
        switch self {
        case .appleOnDevice: return "System voices. Configurable speed & pitch."
        case .kokoro: return "Kokoro neural voice (Core ML). Best on a real device."
        case .sherpa: return "Natural neural voices (Piper, Kitten) — US & UK, male & female. Built in, no download."
        case .openai: return "Highest-quality cloud voices (gpt-4o-mini-tts). Uses your OpenRouter key (or an OpenAI key) & network."
        }
    }

    /// True when the engine can be selected in Settings. The on-device engines are
    /// always wired; OpenAI is only selectable once a cloud key (OpenRouter or a
    /// dedicated OpenAI key) is available. At runtime the coordinator falls back
    /// to Apple if a selected engine isn't ready.
    var isAvailable: Bool {
        switch self {
        case .appleOnDevice, .kokoro, .sherpa: return true
        case .openai: return OpenRouterKeychainStore().hasKey || OpenAIKeychainStore().hasKey
        }
    }

    /// Maps the persisted preference case to the engine coordinator's id.
    var engineID: TTSEngineID {
        switch self {
        case .appleOnDevice: return .apple
        case .kokoro: return .kokoro
        case .sherpa: return .sherpa
        case .openai: return .openai
        }
    }
}

/// Central store for voice (STT/TTS) preferences, persisted in `UserDefaults` so
/// both `VoiceServices` and the settings UI read the same source of truth.
/// Values are resolved at call time, so changes take effect on the next
/// dictation/utterance without restarting.
enum VoicePreferences {
    enum Keys {
        static let sttEngine = "voice.sttEngine"
        static let ttsEngine = "voice.ttsEngine"
        static let ttsVoiceID = "voice.tts.voiceIdentifier"
        static let ttsRate = "voice.tts.rate"
        static let ttsPitch = "voice.tts.pitch"
        static let autoSpeakReplies = "voice.tts.autoSpeakReplies"
        static let voiceBriefEnabled = "voice.brief.enabled"
        static let voiceBriefLastDay = "voice.brief.lastDay"
        static let sherpaModelID = "voice.tts.sherpaModelID"
        static let sherpaSpeaker = "voice.tts.sherpaSpeaker"
        static let openAIVoice = "voice.tts.openAIVoice"
        static let openAIModel = "voice.tts.openAIModel"
    }

    /// Default speaking rate. `AVSpeechUtterance.rate` ranges 0...1 where the
    /// natural default is ~0.5 (`AVSpeechUtteranceDefaultSpeechRate`).
    static let defaultRate: Float = AVSpeechUtteranceDefaultSpeechRate
    static let minRate: Float = AVSpeechUtteranceMinimumSpeechRate
    static let maxRate: Float = AVSpeechUtteranceMaximumSpeechRate
    static let defaultPitch: Float = 1.0
    static let minPitch: Float = 0.5
    static let maxPitch: Float = 2.0

    private static var defaults: UserDefaults { .standard }

    static var sttEngine: STTEngine {
        get { STTEngine(rawValue: defaults.string(forKey: Keys.sttEngine) ?? "") ?? .whisper }
        set { defaults.set(newValue.rawValue, forKey: Keys.sttEngine) }
    }

    static var ttsEngine: TTSEngine {
        get { TTSEngine(rawValue: defaults.string(forKey: Keys.ttsEngine) ?? "") ?? .sherpa }
        set { defaults.set(newValue.rawValue, forKey: Keys.ttsEngine) }
    }

    /// The selected sherpa-onnx bundled model id (e.g. `piper-amy`).
    static var sherpaModelID: String {
        get { defaults.string(forKey: Keys.sherpaModelID) ?? SherpaModel.bundled[0].id }
        set { defaults.set(newValue, forKey: Keys.sherpaModelID) }
    }

    /// The selected speaker id (sid) for multi-speaker sherpa models.
    static var sherpaSpeaker: Int {
        get { defaults.integer(forKey: Keys.sherpaSpeaker) }
        set { defaults.set(newValue, forKey: Keys.sherpaSpeaker) }
    }

    /// The selected OpenAI TTS voice (e.g. `alloy`, `nova`). Defaults to `alloy`.
    static var openAIVoice: String {
        get { defaults.string(forKey: Keys.openAIVoice) ?? OpenAITTSEngine.defaultVoice }
        set { defaults.set(newValue, forKey: Keys.openAIVoice) }
    }

    /// The selected OpenAI TTS model (e.g. `gpt-4o-mini-tts`, `tts-1`, `tts-1-hd`).
    static var openAIModel: String {
        get { defaults.string(forKey: Keys.openAIModel) ?? OpenAITTSEngine.defaultModel }
        set { defaults.set(newValue, forKey: Keys.openAIModel) }
    }

    /// The selected `AVSpeechSynthesisVoice` identifier, or nil to use the system
    /// default for the device locale.
    static var ttsVoiceID: String? {
        get {
            let stored = defaults.string(forKey: Keys.ttsVoiceID)
            return (stored?.isEmpty ?? true) ? nil : stored
        }
        set { defaults.set(newValue ?? "", forKey: Keys.ttsVoiceID) }
    }

    static var ttsRate: Float {
        get {
            guard defaults.object(forKey: Keys.ttsRate) != nil else { return defaultRate }
            return min(max(defaults.float(forKey: Keys.ttsRate), minRate), maxRate)
        }
        set { defaults.set(min(max(newValue, minRate), maxRate), forKey: Keys.ttsRate) }
    }

    static var ttsPitch: Float {
        get {
            guard defaults.object(forKey: Keys.ttsPitch) != nil else { return defaultPitch }
            return min(max(defaults.float(forKey: Keys.ttsPitch), minPitch), maxPitch)
        }
        set { defaults.set(min(max(newValue, minPitch), maxPitch), forKey: Keys.ttsPitch) }
    }

    /// When true, the Coach automatically reads each new assistant reply aloud.
    static var autoSpeakReplies: Bool {
        get { defaults.bool(forKey: Keys.autoSpeakReplies) }
        set { defaults.set(newValue, forKey: Keys.autoSpeakReplies) }
    }

    /// Opt-in: when true, opening hands-free voice mode greets the user with a
    /// short spoken daily brief (built from their durable learnings) once per day
    /// before listening. Off by default so voice mode stays silent unless asked.
    static var voiceBriefEnabled: Bool {
        get { defaults.bool(forKey: Keys.voiceBriefEnabled) }
        set { defaults.set(newValue, forKey: Keys.voiceBriefEnabled) }
    }

    /// The `yyyy-MM-dd` (local) day we last spoke the brief, so it plays at most
    /// once per calendar day even across multiple voice sessions.
    static var voiceBriefLastDay: String? {
        get {
            let stored = defaults.string(forKey: Keys.voiceBriefLastDay)
            return (stored?.isEmpty ?? true) ? nil : stored
        }
        set { defaults.set(newValue ?? "", forKey: Keys.voiceBriefLastDay) }
    }

    /// English voices available on this device, sorted by language then name, for
    /// the settings picker. Other locales are appended after English ones.
    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted { lhs, rhs in
            let lhsEnglish = lhs.language.hasPrefix("en")
            let rhsEnglish = rhs.language.hasPrefix("en")
            if lhsEnglish != rhsEnglish { return lhsEnglish }
            if lhs.language != rhs.language { return lhs.language < rhs.language }
            return lhs.name < rhs.name
        }
    }
}
