import Foundation
import AVFoundation
import OSLog
import KokoroCoreML

/// On-device text-to-speech via Kokoro Core ML (`jud/kokoro-coreml`, Apache-2.0).
/// Synthesizes 24 kHz mono PCM on the Neural Engine / GPU (CPU on the simulator),
/// encodes it to WAV, and plays it with `AVAudioPlayer`. Fully offline — the
/// model is bundled in the app. No API key, no server.
///
/// Until the bundled model loads and warms up, `isAvailable` is false so
/// `VoiceServices` falls back to `AppleTTSEngine`.
/// so `VoiceServices` falls back to `AppleTTSEngine`.
@MainActor
final class KokoroTTSEngine: NSObject, TextToSpeechEngine {
    /// Shared instance so every `VoiceServices` reuses one loaded Core ML model
    /// instead of loading ~100 MB of weights per view.
    static let shared = KokoroTTSEngine()

    let id: TTSEngineID = .kokoro

    private static let log = Logger(subsystem: "PulseLoop", category: "Kokoro")

    /// Default Kokoro voice. The Settings voice picker can override this for
    /// Kokoro-named voices; if a stored id isn't a Kokoro voice we fall back here.
    private let defaultVoice = "af_heart"

    /// Names of the bundled Kokoro voices (e.g. `af_heart`), read from the model
    /// folder so Settings can populate a picker without loading the Core ML model.
    static var bundledVoiceNames: [String] {
        guard let dir = bundledModelDirectory?.appendingPathComponent("voices", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files
            .filter { $0.hasSuffix(".bin") }
            .map { String($0.dropLast(4)) }
            .sorted()
    }

    /// Human-readable label for a Kokoro voice id like `af_heart` →
    /// "Heart (US, female)". Falls back to the raw id if the prefix is unknown.
    static func friendlyLabel(for voiceID: String) -> String {
        let parts = voiceID.split(separator: "_", maxSplits: 1)
        guard parts.count == 2, let prefix = parts.first.map(String.init) else { return voiceID }
        let name = String(parts[1]).replacingOccurrences(of: "_", with: " ").capitalized
        let region: String
        switch prefix.first {
        case "a": region = "US"
        case "b": region = "UK"
        case "e": region = "Spanish"
        case "f": region = "French"
        case "h": region = "Hindi"
        case "i": region = "Italian"
        case "j": region = "Japanese"
        case "p": region = "Portuguese"
        case "z": region = "Chinese"
        default: region = prefix.uppercased()
        }
        let gender = prefix.dropFirst().first == "f" ? "female" : (prefix.dropFirst().first == "m" ? "male" : "")
        let suffix = gender.isEmpty ? region : "\(region), \(gender)"
        return "\(name) (\(suffix))"
    }

    private var engine: KokoroEngine?
    private enum State { case idle, preparing, ready, failed }
    private var state: State = .idle

    var isAvailable: Bool { state == .ready && (engine?.isReady ?? false) }
    private(set) var isSpeaking = false

    /// Notified when speech finishes/cancels, so the coordinator clears its flag.
    var onFinish: (() -> Void)?

    private var playbackTask: Task<Void, Never>?
    private let player = PCMAudioPlayer()

    func prepareModelIfNeeded() async {
        guard state == .idle || state == .failed else { return }
        player.onFinish = { [weak self] in self?.handleFinished() }
        state = .preparing
        // Prefer the model bundled in the app (offline, no download). Kokoro's
        // own downloader is macOS-only, so on iOS the bundle is the only source.
        guard let dir = Self.bundledModelDirectory else {
            state = .failed
            self.engine = nil
            return
        }
        do {
            let engine = try KokoroEngine(modelDirectory: dir, forceCPU: Self.requiresCPUOnly)
            self.engine = engine
            // Warm-up runs on a background thread inside the engine; poll briefly
            // for readiness so the first `speak` doesn't stall the UI.
            for _ in 0..<40 {
                if engine.isReady { break }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            state = .ready
        } catch {
            state = .failed
            self.engine = nil
        }
    }

    /// Location of the bundled Kokoro model directory, if present and complete.
    private static var bundledModelDirectory: URL? {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("kokoro", isDirectory: true),
              KokoroEngine.isDownloaded(at: url) else { return nil }
        return url
    }

    /// Whether to force CPU-only Core ML inference. The CPU-only backend
    /// produces static on the iOS Simulator (Kokoro's quantized backend needs
    /// the GPU/ANE path), so we always allow the full `.all` compute units.
    private static var requiresCPUOnly: Bool { false }

    func speak(_ text: String, rate: Float, pitch: Float, voiceID: String?) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let engine, engine.isReady else {
            Self.log.error("speak skipped: engine ready=\(self.engine?.isReady ?? false, privacy: .public)")
            return
        }

        stop() // interrupt anything currently playing

        let voice = resolveVoice(voiceID, engine: engine)
        let speed = Self.mapRateToSpeed(rate)

        isSpeaking = true
        playbackTask = Task { [weak self] in
            guard let self else { return }
            let samples: [Float]
            do {
                let result = try engine.synthesize(text: trimmed, voice: voice, speed: speed)
                samples = result.samples
            } catch {
                Self.log.error("synthesize failed: \(error.localizedDescription, privacy: .public)")
                await self.finishSpeaking()
                return
            }
            if Task.isCancelled { await self.finishSpeaking(); return }
            guard !samples.isEmpty else {
                Self.log.error("empty audio samples=\(samples.count, privacy: .public)")
                await self.finishSpeaking()
                return
            }
            await MainActor.run {
                self.player.play(samples: samples, sampleRate: KokoroEngine.audioFormat.sampleRate)
            }
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        player.stop()
        // Only signal completion if speech was actually playing; firing onFinish on
        // the pre-speak stop() would reopen the mic and clip the start of the reply.
        let wasSpeaking = isSpeaking
        isSpeaking = false
        if wasSpeaking { onFinish?() }
    }

    /// Synthesizes `text` to raw 24 kHz PCM samples without playback. Used by
    /// tests to verify the bundled model produces real (non-silent) audio.
    func debugSynthesize(_ text: String, voiceID: String? = nil) throws -> [Float] {
        guard let engine, engine.isReady else { return [] }
        let voice = resolveVoice(voiceID, engine: engine)
        return try engine.synthesize(text: text, voice: voice, speed: 1.0).samples
    }

    // MARK: - Private

    private func resolveVoice(_ voiceID: String?, engine: KokoroEngine) -> String {
        if let voiceID, engine.availableVoices.contains(voiceID) { return voiceID }
        if engine.availableVoices.contains(defaultVoice) { return defaultVoice }
        return engine.availableVoices.first ?? defaultVoice
    }
    /// Maps the app's `AVSpeechUtterance` rate scale onto Kokoro's 0.5...2.0
    /// speed range, treating Apple's default rate as 1.0x.
    private static func mapRateToSpeed(_ rate: Float) -> Float {
        let normalized = rate / AVSpeechUtteranceDefaultSpeechRate
        return min(max(normalized, 0.5), 2.0)
    }

    /// Player completion → clear speaking state.
    private func handleFinished() {
        guard isSpeaking else { return }
        isSpeaking = false
        onFinish?()
    }

    /// Synthesis failure path (player not involved): clear state directly.
    private func finishSpeaking() {
        guard isSpeaking else { return }
        isSpeaking = false
        player.stop()
        onFinish?()
    }

    /// Encodes 24 kHz mono float PCM samples into a 16-bit WAV blob. Used by
    /// tests to dump a host-playable clip for audio validation.
    static func wavData(from samples: [Float], sampleRate: Int) -> Data? {
        guard !samples.isEmpty else { return nil }
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = samples.count * blockAlign

        var data = Data(capacity: 44 + dataSize)
        func appendUInt32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        func appendUInt16(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16)                              // PCM fmt chunk size
        appendUInt16(1)                               // PCM format
        appendUInt16(UInt16(channels))
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(byteRate))
        appendUInt16(UInt16(blockAlign))
        appendUInt16(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(UInt32(dataSize))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intVal = Int16(clamped * Float(Int16.max))
            appendUInt16(UInt16(bitPattern: intVal))
        }
        return data
    }
}
