import Foundation
import AVFoundation
import OSLog

/// Cloud text-to-speech for OpenAI voices (`gpt-4o-mini-tts`, `tts-1`,
/// `tts-1-hd`). Routes through OpenRouter's OpenAI-compatible
/// `/api/v1/audio/speech` endpoint when an OpenRouter key is configured (which
/// the rest of the app already uses), and falls back to calling OpenAI directly
/// when only a dedicated OpenAI key is saved. Reports `isAvailable == false`
/// when neither key is present, so the coordinator uses the on-device default.
///
/// Both providers return raw PCM (24 kHz, signed 16-bit LE, mono) which we
/// decode to float and play through the shared `PCMAudioPlayer`.
@MainActor
final class OpenAITTSEngine: NSObject, TextToSpeechEngine {
    static let shared = OpenAITTSEngine()

    let id: TTSEngineID = .openai

    private static let log = Logger(subsystem: "PulseLoop", category: "OpenAITTS")

    /// Which cloud endpoint a synthesis call should use. OpenRouter is preferred
    /// because the app already manages that key for chat; the direct OpenAI path
    /// is the fallback for users who only saved an OpenAI key.
    private enum Provider {
        case openRouter(key: String)
        case openAI(key: String)

        var endpoint: URL {
            switch self {
            case .openRouter: return URL(string: "https://openrouter.ai/api/v1/audio/speech")!
            case .openAI: return URL(string: "https://api.openai.com/v1/audio/speech")!
            }
        }

        var key: String {
            switch self {
            case .openRouter(let k), .openAI(let k): return k
            }
        }

        /// OpenRouter requires a provider-prefixed slug (`openai/gpt-4o-mini-tts`);
        /// the direct OpenAI API wants the bare id (`gpt-4o-mini-tts`).
        func modelSlug(_ model: String) -> String {
            switch self {
            case .openRouter: return model.contains("/") ? model : "openai/\(model)"
            case .openAI: return model
            }
        }
    }

    /// OpenAI TTS voices (gpt-4o-mini-tts / tts-1 family). Label is for the picker.
    static let voices: [(id: String, label: String)] = [
        ("alloy", "Alloy (neutral)"),
        ("ash", "Ash (male)"),
        ("ballad", "Ballad (male)"),
        ("coral", "Coral (female)"),
        ("echo", "Echo (male)"),
        ("fable", "Fable (British)"),
        ("nova", "Nova (female)"),
        ("onyx", "Onyx (deep male)"),
        ("sage", "Sage (female)"),
        ("shimmer", "Shimmer (female)"),
        ("verse", "Verse (expressive)"),
    ]

    /// Selectable OpenAI TTS models, best/most expressive first.
    static let models: [(id: String, label: String)] = [
        ("gpt-4o-mini-tts", "GPT-4o mini TTS (best)"),
        ("tts-1", "TTS-1 (fast)"),
        ("tts-1-hd", "TTS-1 HD (high quality)"),
    ]

    static let defaultVoice = "alloy"
    static let defaultModel = "gpt-4o-mini-tts"

    /// OpenAI returns PCM at 24 kHz, signed 16-bit little-endian, mono.
    private static let pcmSampleRate: Double = 24_000

    private let openAIKeyStore: APIKeyStore
    private let session: URLSession
    private let player = PCMAudioPlayer()
    private var speakTask: Task<Void, Never>?

    private(set) var isSpeaking = false
    var onFinish: (() -> Void)?

    /// Cloud engine: "available" whenever a usable key exists (OpenRouter or a
    /// dedicated OpenAI key). No model to download, so `prepareModelIfNeeded` is
    /// a no-op.
    var isAvailable: Bool { resolveProvider() != nil }

    init(
        openAIKeyStore: APIKeyStore = OpenAIKeychainStore(),
        session: URLSession = .shared
    ) {
        self.openAIKeyStore = openAIKeyStore
        self.session = session
        super.init()
        player.onFinish = { [weak self] in self?.handleFinished() }
    }

    /// Prefers OpenRouter (the app's primary key) and falls back to a direct
    /// OpenAI key. Returns nil when neither is configured.
    private func resolveProvider() -> Provider? {
        if let routerKey = AIService.shared.currentAPIKey, !routerKey.isEmpty {
            return .openRouter(key: routerKey)
        }
        if let openAIKey = (try? openAIKeyStore.readKey()) ?? nil, !openAIKey.isEmpty {
            return .openAI(key: openAIKey)
        }
        return nil
    }

    func prepareModelIfNeeded() async { /* cloud engine, nothing to prepare */ }

    func speak(_ text: String, rate: Float, pitch: Float, voiceID: String?) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let provider = resolveProvider() else {
            Self.log.error("speak skipped: no OpenRouter or OpenAI API key")
            return
        }

        stop()
        let voice = voiceID.flatMap { v in
            Self.voices.contains { $0.id == v } ? v : nil
        } ?? VoicePreferences.openAIVoice
        let model = VoicePreferences.openAIModel
        let speed = Self.mapRateToSpeed(rate)

        isSpeaking = true
        speakTask = Task { [weak self] in
            guard let self else { return }
            do {
                let samples = try await self.synthesize(text: trimmed, voice: voice, model: model, speed: speed, provider: provider)
                if Task.isCancelled { await MainActor.run { self.handleFinished() }; return }
                guard !samples.isEmpty else { await MainActor.run { self.handleFinished() }; return }
                await MainActor.run {
                    self.player.play(samples: samples, sampleRate: Self.pcmSampleRate)
                }
            } catch {
                Self.log.error("synthesize failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { self.handleFinished() }
            }
        }
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        player.stop()
        // Only signal completion if speech was actually playing; firing onFinish on
        // the pre-speak stop() would reopen the mic and clip the start of the reply.
        let wasSpeaking = isSpeaking
        isSpeaking = false
        if wasSpeaking { onFinish?() }
    }

    // MARK: - Networking

    /// Calls the provider's `/audio/speech` requesting raw PCM, returns mono
    /// float samples.
    private func synthesize(text: String, voice: String, model: String, speed: Float, provider: Provider) async throws -> [Float] {
        var request = URLRequest(url: provider.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(provider.key)", forHTTPHeaderField: "Authorization")
        if case .openRouter = provider {
            request.setValue("PulseLoop iOS", forHTTPHeaderField: "X-Title")
        }
        request.timeoutInterval = 60
        let body: [String: Any] = [
            "model": provider.modelSlug(model),
            "input": text,
            "voice": voice,
            "response_format": "pcm",
            "speed": Double(speed),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes])

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            Self.log.error("HTTP \(http.statusCode, privacy: .public): \(String(bodyText.prefix(400)), privacy: .public)")
            throw NSError(domain: "OpenAITTS", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: bodyText])
        }
        return Self.decodePCM16(data)
    }

    /// Decodes signed 16-bit little-endian PCM into normalized mono floats.
    private static func decodePCM16(_ data: Data) -> [Float] {
        let count = data.count / 2
        guard count > 0 else { return [] }
        var samples = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let scale: Float = 1.0 / 32768.0
            for i in 0..<count {
                let lo = Int16(raw[i * 2])
                let hi = Int16(raw[i * 2 + 1])
                let value = Int16(bitPattern: UInt16(bitPattern: lo) | (UInt16(bitPattern: hi) << 8))
                samples[i] = Float(value) * scale
            }
        }
        return samples
    }

    // MARK: - Private

    private func handleFinished() {
        guard isSpeaking else { return }
        isSpeaking = false
        onFinish?()
    }

    /// Maps the app's `AVSpeechUtterance` rate scale onto OpenAI's `speed`
    /// (0.25...4.0, 1.0 = normal). Apple's default rate maps to 1.0x.
    private static func mapRateToSpeed(_ rate: Float) -> Float {
        let normalized = rate / AVSpeechUtteranceDefaultSpeechRate
        return min(max(normalized, 0.25), 4.0)
    }
}
