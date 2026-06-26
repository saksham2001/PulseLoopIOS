import Foundation
import AVFoundation
import OSLog

/// A bundled sherpa-onnx TTS model. Each entry maps a user-facing voice to the
/// on-disk files sherpa-onnx needs. Raw `id` values are persisted in
/// `VoicePreferences`, so don't rename them.
struct SherpaModel: Identifiable, Equatable {
    enum Kind { case vits, kitten, kokoro, matcha }

    let id: String
    let label: String
    /// Folder name under `Resources/Models/`.
    let folder: String
    let kind: Kind
    /// Speaker ids available for multi-speaker models (label keyed by sid).
    let speakers: [Int: String]

    var defaultSpeaker: Int { speakers.keys.min() ?? 0 }
}

extension SherpaModel {
    /// The on-device models bundled in the app, smallest/fastest first.
    static let bundled: [SherpaModel] = [
        SherpaModel(
            id: "piper-amy",
            label: "Amy (US, female)",
            folder: "vits-piper-en_US-amy-low-int8",
            kind: .vits,
            speakers: [0: "Amy"]
        ),
        SherpaModel(
            id: "piper-joe",
            label: "Joe (US, male)",
            folder: "vits-piper-en_US-joe-medium",
            kind: .vits,
            speakers: [0: "Joe"]
        ),
        SherpaModel(
            id: "piper-cori",
            label: "Cori (UK, female)",
            folder: "vits-piper-en_GB-cori-medium",
            kind: .vits,
            speakers: [0: "Cori"]
        ),
        SherpaModel(
            id: "piper-alan",
            label: "Alan (UK, male)",
            folder: "vits-piper-en_GB-alan-low",
            kind: .vits,
            speakers: [0: "Alan"]
        ),
        SherpaModel(
            id: "piper-libritts",
            label: "LibriTTS (US, multi-voice)",
            folder: "vits-piper-en_US-libritts_r-medium",
            kind: .vits,
            // A curated subset of the 904 LibriTTS speakers that sound distinct.
            speakers: [
                0: "Voice 1", 10: "Voice 2", 40: "Voice 3", 90: "Voice 4",
                200: "Voice 5", 500: "Voice 6", 700: "Voice 7", 900: "Voice 8",
            ]
        ),
        SherpaModel(
            id: "kitten-nano",
            label: "Kitten Nano (US, 8 voices)",
            folder: "kitten-nano-en-v0_1-fp16",
            kind: .kitten,
            speakers: [
                0: "Voice 1", 1: "Voice 2", 2: "Voice 3", 3: "Voice 4",
                4: "Voice 5", 5: "Voice 6", 6: "Voice 7", 7: "Voice 8",
            ]
        ),
    ]

    static func model(withID id: String?) -> SherpaModel {
        bundled.first { $0.id == id } ?? bundled[0]
    }

    /// Deterministic FNV-1a hash so voice→speaker mapping is stable across app
    /// launches (Swift's built-in String.hashValue is seeded per process).
    static func stableHash(_ s: String) -> Int {
        var hash: UInt64 = 1469598103934665603
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int(hash & 0x7fff_ffff)
    }

    /// Translates a Kokoro voice id (e.g. `af_heart`, `am_michael`) into the
    /// nearest bundled sherpa model + speaker, preserving gender and accent. Used
    /// only on the simulator, where Kokoro's Core ML graph emits static and is
    /// transparently routed through sherpa-onnx. On a real device Kokoro plays its
    /// own voices, so this mapping never runs there.
    ///
    /// Kokoro ids encode language+gender in the prefix: first char = language
    /// (`a`=US, `b`=UK, …), second char = gender (`f`=female, `m`=male). Same-
    /// gender voices are spread across distinct sherpa speakers (via LibriTTS /
    /// Kitten multi-speaker models) so two Kokoro voices never sound identical.
    static func target(forKokoroVoice voiceID: String) -> (model: SherpaModel, speaker: Int) {
        let parts = voiceID.split(separator: "_", maxSplits: 1)
        let prefix = parts.first.map(String.init) ?? ""
        let lang = prefix.first
        let gender = prefix.dropFirst().first   // "f" or "m"
        let isMale = gender == "m"

        // Build an ordered list of distinct (model, speaker) "voice slots" for the
        // requested gender. The single-speaker gendered Piper models guarantee the
        // gender is right; the multi-speaker LibriTTS speakers add within-gender
        // variety so two same-gender Kokoro voices map to different-sounding slots.
        let libritts = model(withID: "piper-libritts")
        let allLibri = libritts.speakers.keys.sorted()
        let half = allLibri.count / 2
        let libriMale = Array(allLibri.prefix(half))
        let libriFemale = Array(allLibri.suffix(from: half))

        var slots: [(SherpaModel, Int)]
        let kitten = model(withID: "kitten-nano")
        let kittenSpk = kitten.speakers.keys.sorted()
        let kHalf = kittenSpk.count / 2
        if isMale {
            slots = [(model(withID: "piper-joe"), 0), (model(withID: "piper-alan"), 0)]
            slots += libriMale.map { (libritts, $0) }
            slots += Array(kittenSpk.prefix(kHalf)).map { (kitten, $0) }
        } else {
            slots = [(model(withID: "piper-amy"), 0), (model(withID: "piper-cori"), 0)]
            slots += libriFemale.map { (libritts, $0) }
            slots += Array(kittenSpk.suffix(from: kHalf)).map { (kitten, $0) }
        }

        // UK accent (lang "b"): preserve the British accent by always mapping to
        // the UK Piper voice for that gender. There are only a few UK Kokoro
        // voices, so accent fidelity matters more than per-voice distinctness here.
        if lang == "b" {
            return isMale ? (model(withID: "piper-alan"), 0)
                          : (model(withID: "piper-cori"), 0)
        }

        // US + other languages: assign a UNIQUE slot per Kokoro voice by its
        // stable rank among the bundled voices that share its language+gender
        // prefix. Ranking (not hashing) guarantees distinct voices never collapse
        // to the same slot until the group is larger than the slot list.
        let peers = bundledKokoroVoices(withPrefix: prefix)
        let rank = peers.firstIndex(of: voiceID) ?? stableHash(voiceID) % slots.count
        let pick = slots[rank % slots.count]
        return (pick.0, pick.1)
    }

    /// The bundled Kokoro voice ids that share a language+gender `prefix`
    /// (e.g. `af`), sorted for a stable rank. Reads the bundle directly (no main-
    /// actor hop) so it's callable from any context; returns [] if unreadable.
    static func bundledKokoroVoices(withPrefix prefix: String) -> [String] {
        guard let dir = Bundle.main.resourceURL?
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("kokoro", isDirectory: true)
            .appendingPathComponent("voices", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files
            .filter { $0.hasSuffix(".bin") }
            .map { String($0.dropLast(4)) }
            .filter { $0.hasPrefix(prefix + "_") }
            .sorted()
    }
}

/// On-device text-to-speech via sherpa-onnx (ONNX Runtime). Unlike Core ML, ONNX
/// Runtime runs correctly on the iOS Simulator, so this is the default offline
/// engine. Hosts several bundled models (Piper, KittenTTS) the user can A/B test
/// in Settings. Fully offline — models are bundled, no API key, no server.
@MainActor
final class SherpaTTSEngine: NSObject, TextToSpeechEngine {
    static let shared = SherpaTTSEngine()

    let id: TTSEngineID = .sherpa

    private static let log = Logger(subsystem: "PulseLoop", category: "SherpaTTS")

    private var tts: SherpaOnnxOfflineTtsWrapper?
    /// The model the loaded `tts` was built for, so we can rebuild on change.
    private var loadedModelID: String?
    /// Built sessions kept alive for reuse. Repeatedly destroying and recreating
    /// onnxruntime/espeak sessions in one process corrupts the native heap, so each
    /// bundled model is built once and switched to instantly thereafter. The set is
    /// bounded by the (small, fixed) number of bundled models.
    private var modelCache: [String: SherpaOnnxOfflineTtsWrapper] = [:]
    private enum State { case idle, preparing, ready, failed }
    private var state: State = .idle

    var isAvailable: Bool { state == .ready && tts != nil }
    private(set) var isSpeaking = false
    var onFinish: (() -> Void)?

    private let player = PCMAudioPlayer()
    private var synthesisTask: Task<Void, Never>?
    /// Serializes off-actor synthesis. sherpa-onnx `generate` is not safe to call
    /// concurrently on a single instance, so each call waits for the previous one
    /// to finish before starting. Without this, an in-flight synthesis (e.g. a
    /// queued `speak`, or another caller of the shared engine) racing a new one on
    /// the same instance can corrupt state or crash under load.
    private var pendingGenerate: Task<(samples: [Float], rate: Double), Never>?

    override init() {
        super.init()
        player.onFinish = { [weak self] in self?.handleFinished() }
    }

    func prepareModelIfNeeded() async {
        let desired = VoicePreferences.sherpaModelID
        // Already loaded the desired model.
        if state == .ready, loadedModelID == desired, tts != nil { return }
        guard state != .preparing else { return }
        state = .preparing
        await loadModel(SherpaModel.model(withID: desired))
    }

    /// Switches to a specific bundled model, loading it off the main actor. Also
    /// persists the choice so `prepareModelIfNeeded()` (called by `speak`) doesn't
    /// later revert to a stale preference and clobber the selection.
    func selectModel(_ model: SherpaModel) async {
        VoicePreferences.sherpaModelID = model.id
        if model.speakers[VoicePreferences.sherpaSpeaker] == nil {
            VoicePreferences.sherpaSpeaker = model.defaultSpeaker
        }
        guard loadedModelID != model.id || tts == nil else { state = .ready; return }
        state = .preparing
        await loadModel(model)
    }

    /// Loads `model` for an ephemeral request (e.g. a Kokoro→sherpa redirect)
    /// WITHOUT persisting it as the user's sherpa preference, so the A/B model
    /// chosen in Settings isn't clobbered. No-op if it's already loaded.
    private func loadModelIfNeeded(_ model: SherpaModel) async {
        guard loadedModelID != model.id || tts == nil else { state = .ready; return }
        state = .preparing
        await loadModel(model)
    }

    /// True for Kokoro-style voice ids like `af_heart` / `am_michael`: a 2-letter
    /// language+gender prefix, an underscore, then a name. Plain sherpa speaker
    /// ids are pure integers and never match.
    static func isKokoroVoiceID(_ id: String) -> Bool {
        let parts = id.split(separator: "_", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 2 else { return false }
        return parts[0].allSatisfy { $0.isLetter }
    }

    private func loadModel(_ model: SherpaModel) async {
        // Don't swap the live instance out from under an in-flight synthesis.
        _ = await pendingGenerate?.value
        // Reuse an already-built session instead of recreating it: destroy+recreate
        // churn of native sessions corrupts the heap under repeated switches.
        if let cached = modelCache[model.id] {
            tts = cached
            loadedModelID = model.id
            state = .ready
            return
        }
        guard let dir = Self.bundledModelDirectory(model.folder) else {
            Self.log.error("model folder missing: \(model.folder, privacy: .public)")
            state = .failed
            tts = nil
            return
        }
        let built = await Task.detached(priority: .userInitiated) {
            Self.buildTTS(model: model, dir: dir)
        }.value
        if let built {
            modelCache[model.id] = built
            tts = built
            loadedModelID = model.id
            state = .ready
        } else {
            tts = nil
            state = .failed
        }
    }

    /// Builds the sherpa-onnx TTS instance for a model. Runs off the main actor.
    private nonisolated static func buildTTS(model: SherpaModel, dir: URL) -> SherpaOnnxOfflineTtsWrapper? {
        // espeak-ng-data is identical across models, so it's bundled once at the
        // Models root and shared by every espeak-based model (Piper/Kitten/VITS).
        let espeak = Bundle.main.resourceURL?
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("espeak-ng-data", isDirectory: true).path ?? ""
        let tokens = dir.appendingPathComponent("tokens.txt").path

        var modelConfig: SherpaOnnxOfflineTtsModelConfig
        switch model.kind {
        case .vits:
            let onnx = Self.firstFile(in: dir, ext: "onnx")?.path ?? ""
            let vits = sherpaOnnxOfflineTtsVitsModelConfig(
                model: onnx, lexicon: "", tokens: tokens, dataDir: espeak)
            modelConfig = sherpaOnnxOfflineTtsModelConfig(vits: vits, numThreads: 2, provider: "cpu")
        case .kitten:
            let onnx = dir.appendingPathComponent("model.fp16.onnx").path
            let voices = dir.appendingPathComponent("voices.bin").path
            let kitten = sherpaOnnxOfflineTtsKittenModelConfig(
                model: onnx, voices: voices, tokens: tokens, dataDir: espeak)
            modelConfig = sherpaOnnxOfflineTtsModelConfig(numThreads: 2, provider: "cpu", kitten: kitten)
        case .kokoro:
            let onnx = Self.firstFile(in: dir, ext: "onnx")?.path ?? ""
            let voices = dir.appendingPathComponent("voices.bin").path
            let kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
                model: onnx, voices: voices, tokens: tokens, dataDir: espeak)
            modelConfig = sherpaOnnxOfflineTtsModelConfig(kokoro: kokoro, numThreads: 2, provider: "cpu")
        case .matcha:
            let acoustic = Self.firstFile(in: dir, ext: "onnx")?.path ?? ""
            let matcha = sherpaOnnxOfflineTtsMatchaModelConfig(
                acousticModel: acoustic, tokens: tokens, dataDir: espeak)
            modelConfig = sherpaOnnxOfflineTtsModelConfig(matcha: matcha, numThreads: 2, provider: "cpu")
        }

        var config = sherpaOnnxOfflineTtsConfig(model: modelConfig)
        let wrapper = SherpaOnnxOfflineTtsWrapper(config: &config)
        return wrapper.tts != nil ? wrapper : nil
    }

    private nonisolated static func firstFile(in dir: URL, ext: String) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.pathExtension == ext }
    }

    private static func bundledModelDirectory(_ folder: String) -> URL? {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func speak(_ text: String, rate: Float, pitch: Float, voiceID: String?) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // A Kokoro-style id (e.g. "af_heart") arrives when the simulator redirects
        // Kokoro → sherpa. Translate it to a matching sherpa model + speaker so the
        // chosen voice's gender/accent is preserved and every voice sounds distinct.
        var requestedSpeaker: Int?
        if let voiceID, Self.isKokoroVoiceID(voiceID) {
            let t = SherpaModel.target(forKokoroVoice: voiceID)
            requestedSpeaker = t.speaker
            await loadModelIfNeeded(t.model)
        } else {
            // Make sure the model the user selected is the one loaded.
            await prepareModelIfNeeded()
        }
        guard !trimmed.isEmpty, let tts, state == .ready else {
            Self.log.error("speak skipped: ready=\(self.state == .ready, privacy: .public)")
            return
        }

        stop()
        let sid = requestedSpeaker ?? Int(voiceID ?? "") ?? VoicePreferences.sherpaSpeaker
        let speed = Self.mapRateToSpeed(rate)

        isSpeaking = true
        synthesisTask = Task { [weak self] in
            guard let self else { return }
            let generated = await self.generate(text: trimmed, sid: sid, speed: speed)

            guard !Task.isCancelled, !generated.samples.isEmpty else {
                await MainActor.run { self.handleFinished() }
                return
            }
            await MainActor.run {
                self.player.play(samples: generated.samples, sampleRate: generated.rate)
            }
        }
    }

    /// Runs `tts.generate` off the main actor, serialized after any prior
    /// synthesis on this instance. Returns empty samples when no model is loaded.
    private func generate(text: String, sid: Int, speed: Float) async -> (samples: [Float], rate: Double) {
        guard let tts else { return ([], 0) }
        let prior = pendingGenerate
        let task = Task.detached(priority: .userInitiated) { () -> (samples: [Float], rate: Double) in
            _ = await prior?.value   // never overlap two generations on one instance
            let audio = tts.generate(text: text, sid: sid, speed: speed)
            return (audio.samples, Double(audio.sampleRate))
        }
        pendingGenerate = task
        return await task.value
    }

    func stop() {
        synthesisTask?.cancel()
        synthesisTask = nil
        player.stop()
        // Only signal completion if speech was actually in progress. `speak()` calls
        // stop() up front to clear any prior utterance; firing onFinish there would
        // make the voice session reopen the mic and clip the start of the new reply.
        let wasSpeaking = isSpeaking
        isSpeaking = false
        if wasSpeaking { onFinish?() }
    }

    /// Synthesizes to raw float PCM without playback. Used by tests to verify the
    /// bundled model produces real (non-silent, non-static) audio.
    func debugSynthesize(_ text: String, sid: Int = 0) async -> [Float] {
        await prepareModelIfNeeded()
        guard state == .ready else { return [] }
        return await generate(text: text, sid: sid, speed: 1.0).samples
    }

    /// Test-only: synthesizes via the same Kokoro→sherpa translation the
    /// simulator redirect uses, so tests can prove each Kokoro voice maps to a
    /// distinct sherpa voice (model + speaker).
    func debugSynthesizeKokoro(_ text: String, kokoroVoiceID: String) async -> [Float] {
        let t = SherpaModel.target(forKokoroVoice: kokoroVoiceID)
        await loadModelIfNeeded(t.model)
        guard state == .ready else { return [] }
        return await generate(text: text, sid: t.speaker, speed: 1.0).samples
    }

    private func handleFinished() {
        guard isSpeaking else { return }
        isSpeaking = false
        onFinish?()
    }

    /// Maps the app's `AVSpeechUtterance` rate scale onto sherpa-onnx's speed
    /// (1.0 = normal). Apple's default rate maps to 1.0x.
    private static func mapRateToSpeed(_ rate: Float) -> Float {
        let normalized = rate / AVSpeechUtteranceDefaultSpeechRate
        return min(max(normalized, 0.5), 2.0)
    }
}
