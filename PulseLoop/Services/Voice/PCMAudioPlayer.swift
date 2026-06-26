import Foundation
import AVFoundation
import OSLog

/// Shared audio player for on-device TTS engines that produce raw mono float PCM.
///
/// Plays samples through an `AVAudioEngine` graph, converting the source sample
/// rate to the hardware output format with `AVAudioConverter` (implicit mixer
/// conversion produced static on the simulator). One instance owns at most one
/// active playback; starting a new clip stops the previous one.
@MainActor
final class PCMAudioPlayer {
    private static let log = Logger(subsystem: "PulseLoop", category: "PCMAudioPlayer")

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?

    /// Called on the main actor when the current clip finishes or is stopped.
    var onFinish: (() -> Void)?

    var isPlaying: Bool { node?.isPlaying ?? false }

    /// Plays `samples` (mono float, `-1...1`) at `sampleRate`. Stops any current
    /// playback first. `onFinish` fires when the clip completes.
    func play(samples: [Float], sampleRate: Double) {
        stop()
        guard !samples.isEmpty,
              let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat,
                                                  frameCapacity: AVAudioFrameCount(samples.count)) else {
            onFinish?()
            return
        }
        sourceBuffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = sourceBuffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                channel.update(from: src.baseAddress!, count: samples.count)
            }
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])

            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            engine.attach(node)

            let playbackFormat = engine.outputNode.outputFormat(forBus: 0)
            let bufferToPlay = Self.convert(sourceBuffer, from: sourceFormat, to: playbackFormat) ?? sourceBuffer
            engine.connect(node, to: engine.mainMixerNode, format: bufferToPlay.format)
            engine.prepare()
            try engine.start()

            self.engine = engine
            self.node = node

            node.scheduleBuffer(bufferToPlay, at: nil, options: []) { [weak self] in
                Task { @MainActor [weak self] in self?.finish() }
            }
            node.play()
            Self.log.log("playing src=\(sampleRate, privacy: .public) out=\(playbackFormat.sampleRate, privacy: .public) frames=\(bufferToPlay.frameLength, privacy: .public)")
        } catch {
            Self.log.error("play failed: \(error.localizedDescription, privacy: .public)")
            cleanup()
            onFinish?()
        }
    }

    func stop() {
        let wasPlaying = node != nil
        cleanup()
        if wasPlaying {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    private func finish() {
        cleanup()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        onFinish?()
    }

    private func cleanup() {
        node?.stop()
        engine?.stop()
        node = nil
        engine = nil
    }

    /// Converts a PCM buffer between formats (sample rate / layout) with
    /// `AVAudioConverter`. Returns `nil` if conversion can't be set up.
    private static func convert(_ buffer: AVAudioPCMBuffer,
                                from sourceFormat: AVAudioFormat,
                                to destFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        if sourceFormat.sampleRate == destFormat.sampleRate,
           sourceFormat.channelCount == destFormat.channelCount,
           sourceFormat.commonFormat == destFormat.commonFormat {
            return buffer
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: destFormat) else { return nil }
        let ratio = destFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: destFormat, frameCapacity: capacity) else { return nil }

        var fed = false
        let status = converter.convert(to: out, error: nil) { _, inStatus in
            if fed {
                inStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : out
    }
}
