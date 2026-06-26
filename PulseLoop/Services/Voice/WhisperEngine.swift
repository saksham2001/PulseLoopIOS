import Foundation
import AVFoundation
import WhisperKit

/// On-device speech-to-text via WhisperKit (`argmaxinc/argmax-oss-swift`, MIT).
/// Runs Whisper on the Apple Neural Engine / GPU via Core ML, fully offline once
/// the model is downloaded. No API key, no server.
///
/// Capture model: WhisperKit transcribes a buffer of 16 kHz mono Float samples,
/// not a live recognition request. So we tap the mic with `AVAudioEngine`,
/// down-convert to 16 kHz mono, accumulate, and run periodic partial transcripts
/// plus a final transcript on `stop()`. Until the pipeline is ready (model
/// downloaded + loaded), `isAvailable` is false so `VoiceServices` falls back to
/// `AppleSpeechEngine`.
@MainActor
final class WhisperEngine: NSObject, SpeechToTextEngine {
    /// Shared instance so every `VoiceServices` (Coach, Notes, capture sheet…)
    /// reuses one loaded Core ML pipeline instead of loading the model per view.
    static let shared = WhisperEngine()

    let id: STTEngineID = .whisper

    /// WhisperKit's expected input sample rate.
    private static let targetSampleRate: Double = 16_000
    /// Re-transcribe the accumulated buffer at most this often for partials.
    private static let partialInterval: TimeInterval = 1.5

    /// Default model. `base` (~80 MB) balances size and accuracy; `small`
    /// improves domain-vocabulary coverage at a larger download.
    private let modelName: String

    private var pipe: WhisperKit?
    private enum State { case idle, preparing, ready, failed }
    private var state: State = .idle

    /// Ready only once the WhisperKit pipeline has initialized (model downloaded
    /// + loaded). Apple remains the fallback until then.
    var isAvailable: Bool { state == .ready && pipe != nil }

    // Capture plumbing. The audio engine is recreated per session (see
    // startStreaming) — the shared singleton would otherwise carry a stale
    // AVAudioEngine across sessions.
    private var audioEngine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var captureBuffer: [Float] = []
    private var onPartial: ((String) -> Void)?
    private var onLevel: ((Float) -> Void)?
    private var latestTranscript = ""
    private var isRunning = false
    private var lastPartialAt = Date.distantPast
    private var isTranscribing = false
    /// Bumped each session so a late partial transcription from a prior capture
    /// can't clobber the current one.
    private var captureGeneration = 0

    init(modelName: String = "base") {
        self.modelName = modelName
        super.init()
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Initializes the WhisperKit pipeline off the main thread. The model and
    /// tokenizer are bundled in the app (`Models/whisper-base`), so this loads
    /// fully offline with no download. Safe to call repeatedly; only the first
    /// call does work.
    func prepareModelIfNeeded() async {
        guard state == .idle || state == .failed else { return }
        state = .preparing
        do {
            let config: WhisperKitConfig
            if let bundled = Self.bundledModelFolder {
                // Offline: point WhisperKit at the bundled model folder. The
                // tokenizer.json shipped alongside is picked up automatically
                // because WhisperKit adds `modelFolder` to its search paths.
                config = WhisperKitConfig(modelFolder: bundled.path, download: false)
            } else {
                // Fallback (should not happen in shipping builds): download.
                config = WhisperKitConfig(model: modelName)
            }
            let pipe = try await WhisperKit(config)
            self.pipe = pipe
            state = .ready
        } catch {
            state = .failed
            self.pipe = nil
        }
    }

    /// Location of the bundled Whisper model folder, if present.
    private static var bundledModelFolder: URL? {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("whisper-base", isDirectory: true),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func startStreaming(onPartial: @escaping (String) -> Void,
                        onLevel: @escaping (Float) -> Void) throws {
        guard !isRunning else { return }
        guard isAvailable else { throw VoiceEngineError.recognizerUnavailable }

        self.onPartial = onPartial
        self.onLevel = onLevel
        captureBuffer = []
        latestTranscript = ""
        lastPartialAt = Date.distantPast
        isTranscribing = false
        captureGeneration &+= 1

        // Use a fresh capture engine each session. Reusing the singleton's prior
        // AVAudioEngine across sessions left it with a stale/zero input format
        // after the audio session was deactivated (between TTS playback and the
        // next listen, or when the voice screen was reopened) — which made Whisper
        // work only on the first session and then silently fail to start. The
        // expensive WhisperKit pipeline (`pipe`) stays loaded; only this
        // lightweight capture graph is rebuilt.
        audioEngine = AVAudioEngine()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw VoiceEngineError.audioSessionFailed
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: Self.targetSampleRate,
                                         channels: 1,
                                         interleaved: false) else {
            throw VoiceEngineError.audioSessionFailed
        }
        targetFormat = target
        converter = AVAudioConverter(from: inputFormat, to: target)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handleTap(buffer)
        }

        do {
            try audioEngine.start()
            isRunning = true
        } catch {
            teardown()
            throw VoiceEngineError.audioSessionFailed
        }
    }

    @discardableResult
    func stop() -> String {
        guard isRunning else { return latestTranscript }
        teardown()
        // Final transcription of the full buffer, performed asynchronously so we
        // never block the main actor (a synchronous DispatchGroup.wait() here
        // deadlocks: the transcribe Task also needs the main actor). The final,
        // most-accurate text is delivered through `onPartial` when ready; the
        // value returned now is the last live partial.
        let samples = captureBuffer
        if !samples.isEmpty, let pipe {
            let finalCallback = onPartial
            Task { [weak self] in
                let results = try? await pipe.transcribe(audioArray: samples)
                let text = (results?.map(\.text).joined(separator: " ") ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                await MainActor.run {
                    self?.latestTranscript = text
                    finalCallback?(text)
                }
            }
        }
        return latestTranscript
    }

    // MARK: - Private

    private nonisolated func handleTap(_ buffer: AVAudioPCMBuffer) {
        // Compute a quick level for the waveform.
        if let channelData = buffer.floatChannelData?[0] {
            let frameLength = Int(buffer.frameLength)
            if frameLength > 0 {
                var sum: Float = 0
                for i in 0..<frameLength { sum += abs(channelData[i]) }
                let level = min(max((sum / Float(frameLength)) * 4, 0), 1)
                Task { @MainActor [weak self] in self?.onLevel?(level) }
            }
        }
        // Down-convert to 16 kHz mono and append. Copy the buffer synchronously on
        // the render thread first: the audio engine recycles `buffer` once this tap
        // returns, so reading it later on the main actor is a use-after-free.
        guard let owned = Self.copyBuffer(buffer) else { return }
        Task { @MainActor [weak self] in self?.appendConverted(owned) }
    }

    /// Deep-copies a render-thread PCM buffer so it can be safely read after the
    /// tap callback returns (the engine reuses the original's backing storage).
    private nonisolated static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else { return nil }
        copy.frameLength = buffer.frameLength
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<channels { memcpy(dst[ch], src[ch], frames * MemoryLayout<Float>.size) }
        } else if let src = buffer.int16ChannelData, let dst = copy.int16ChannelData {
            for ch in 0..<channels { memcpy(dst[ch], src[ch], frames * MemoryLayout<Int16>.size) }
        } else {
            return nil
        }
        return copy
    }

    private func appendConverted(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if error != nil { return }

        if let channel = out.floatChannelData?[0] {
            let n = Int(out.frameLength)
            captureBuffer.append(contentsOf: UnsafeBufferPointer(start: channel, count: n))
        }
        maybeEmitPartial()
    }

    private func maybeEmitPartial() {
        guard isRunning, !isTranscribing, let pipe else { return }
        guard Date().timeIntervalSince(lastPartialAt) >= Self.partialInterval else { return }
        // Need at least ~1s of audio to be useful.
        guard captureBuffer.count >= Int(Self.targetSampleRate) else { return }
        lastPartialAt = Date()
        isTranscribing = true
        let snapshot = captureBuffer
        let gen = captureGeneration
        Task { [weak self] in
            let results = try? await pipe.transcribe(audioArray: snapshot)
            let text = (results?.map(\.text).joined(separator: " ") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                guard let self else { return }
                self.isTranscribing = false
                // Ignore a result that arrived after this capture session ended.
                guard gen == self.captureGeneration else { return }
                if !text.isEmpty {
                    self.latestTranscript = text
                    self.onPartial?(text)
                }
            }
        }
    }

    private func teardown() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        isRunning = false
        isTranscribing = false
        converter = nil
        onLevel?(0)
    }
}
