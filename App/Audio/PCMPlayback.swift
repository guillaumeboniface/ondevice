import AVFoundation

// Retain the engine through the last rendered buffer. Generation finishing is not playback finishing.
@MainActor final class PCMPlayback {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private var completion: CheckedContinuation<Void, Error>?
    private var generation = UUID()

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        if !engine.isRunning { try engine.start() }
        player.play()
    }

    func enqueue(_ samples: [Float]) throws {
        guard !samples.isEmpty else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw InferenceError("Could not allocate a playback buffer.")
        }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        player.scheduleBuffer(buffer)
    }

    func drain() async throws {
        let current = generation
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                completion = continuation
                let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
                silence.frameLength = 1
                silence.floatChannelData![0][0] = 0
                player.scheduleBuffer(silence, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.generation == current else { return }
                        self.completion?.resume()
                        self.completion = nil
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                self.stop()
            }
        }
    }

    func stop() {
        generation = UUID()
        player.stop()
        engine.stop()
        completion?.resume(throwing: CancellationError())
        completion = nil
    }
}
