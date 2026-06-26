import Foundation
import AVFoundation
import Speech

/// Apple's on-device speech recognizer (`SFSpeechRecognizer` + `AVAudioEngine`).
/// This is the guaranteed, always-available STT engine and the fallback for the
/// open-source engines. The logic here was lifted from `VoiceServices` so the
/// behavior is identical; `VoiceServices` now delegates to it.
@MainActor
final class AppleSpeechEngine: NSObject, SpeechToTextEngine {
    let id: STTEngineID = .apple

    /// Apple's recognizer ships with the OS — always available.
    var isAvailable: Bool { true }

    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onPartial: ((String) -> Void)?
    private var onLevel: ((Float) -> Void)?
    private var latestTranscript = ""
    private var isRunning = false

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startStreaming(onPartial: @escaping (String) -> Void,
                        onLevel: @escaping (Float) -> Void) throws {
        guard !isRunning else { return }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw VoiceEngineError.recognizerUnavailable
        }

        self.onPartial = onPartial
        self.onLevel = onLevel
        latestTranscript = ""

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw VoiceEngineError.audioSessionFailed
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw VoiceEngineError.audioSessionFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            if let data = channelData, frameLength > 0 {
                var sum: Float = 0
                for i in 0..<frameLength { sum += abs(data[i]) }
                let avg = sum / Float(frameLength)
                let level = min(max(avg * 4, 0), 1)
                Task { @MainActor [weak self] in self?.onLevel?(level) }
            }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.latestTranscript = result.bestTranscription.formattedString
                    self.onPartial?(self.latestTranscript)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in self.teardown() }
            }
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
        teardown()
        return latestTranscript
    }

    func prepareModelIfNeeded() async { /* Apple needs no model download. */ }

    private func teardown() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        isRunning = false
        onLevel?(0)
    }
}

enum VoiceEngineError: Error {
    case recognizerUnavailable
    case audioSessionFailed
}
