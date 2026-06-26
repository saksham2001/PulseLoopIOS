import Foundation

/// Stable identifiers for the available speech-to-text engines. Raw values are
/// persisted (via `VoicePreferences`) so they must not change.
enum STTEngineID: String, Codable, CaseIterable {
    case apple
    case whisper
    case moonshine
}

/// Stable identifiers for the available text-to-speech engines.
enum TTSEngineID: String, Codable, CaseIterable {
    case apple
    case kokoro
    case sherpa
    case openai
}

/// A single speech-to-text backend. `VoiceServices` owns the active engine and
/// delegates to it, so all callers keep using the same `VoiceServices` surface.
///
/// Implementations must be safe to use on the main actor. The Apple engine is
/// always available and is the guaranteed fallback; open-source engines report
/// `isAvailable == false` until their model is downloaded and the device/OS is
/// supported, at which point the coordinator routes to them.
@MainActor
protocol SpeechToTextEngine: AnyObject {
    var id: STTEngineID { get }

    /// True when this engine can run right now: package present, OS supported,
    /// and any required model already downloaded. Apple is always `true`.
    var isAvailable: Bool { get }

    /// Requests microphone/recognition permission. Returns `true` if granted.
    func requestAuthorization() async -> Bool

    /// Begins live capture. `onPartial` delivers the best transcript so far;
    /// `onLevel` delivers a 0...1 audio level for waveform UI. Throws if the
    /// audio session or recognizer cannot start.
    func startStreaming(onPartial: @escaping (String) -> Void,
                        onLevel: @escaping (Float) -> Void) throws

    /// Stops capture and returns the final transcript.
    func stop() -> String

    /// Triggers any one-time model download/initialization. No-op for Apple.
    /// Safe to call repeatedly; should not block the main thread internally.
    func prepareModelIfNeeded() async
}

/// A single text-to-speech backend. `VoiceServices` owns the active engine and
/// delegates `speak`/`stop` to it. Apple is always available and is the
/// guaranteed fallback.
@MainActor
protocol TextToSpeechEngine: AnyObject {
    var id: TTSEngineID { get }

    /// True when this engine can speak right now (package + OS + model ready).
    var isAvailable: Bool { get }

    /// Whether the engine is currently producing audio.
    var isSpeaking: Bool { get }

    /// Speaks `text`. `rate`/`pitch` use Apple's `AVSpeechUtterance` scale; an
    /// engine that doesn't support a parameter ignores it. `voiceID` is the
    /// engine-specific voice identifier (nil = engine default).
    func speak(_ text: String, rate: Float, pitch: Float, voiceID: String?) async

    /// Stops any current speech immediately.
    func stop()

    /// Triggers any one-time model download/initialization. No-op for Apple.
    func prepareModelIfNeeded() async
}
