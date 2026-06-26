import Foundation
import AVFoundation

/// Apple's `AVSpeechSynthesizer`-backed TTS. The guaranteed, always-available
/// engine and the fallback for the open-source engines. Logic lifted from
/// `VoiceServices` so behavior is identical.
@MainActor
final class AppleTTSEngine: NSObject, TextToSpeechEngine, AVSpeechSynthesizerDelegate {
    let id: TTSEngineID = .apple
    var isAvailable: Bool { true }
    private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    /// Notified when speech naturally finishes or is cancelled, so the
    /// coordinator can clear its `isSpeaking` flag.
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, rate: Float, pitch: Float, voiceID: String?) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = rate
        utterance.pitchMultiplier = pitch

        if let voiceID, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "en-US")
                ?? AVSpeechSynthesisVoice(language: "en-US")
        }

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func prepareModelIfNeeded() async { /* Apple needs no model download. */ }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.onFinish?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.onFinish?()
        }
    }
}
