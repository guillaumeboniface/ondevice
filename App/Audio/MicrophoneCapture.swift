import AVFoundation
import Foundation

@MainActor final class MicrophoneCapture: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("ondevice-turn.wav")
    var onLimit: (() -> Void)?
    private(set) var startedAt: TimeInterval = 0

    func start() async throws {
        let permitted = await AVAudioApplication.requestRecordPermission()
        try Task.checkCancellation()
        guard permitted else { throw InferenceError("Enable microphone access in Settings to talk.") }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        self.recorder = recorder
        startedAt = ProcessInfo.processInfo.systemUptime
        guard recorder.record(forDuration: 30) else { throw InferenceError("Microphone recording could not start.") }
    }

    func stop() throws -> [Float] {
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.length <= 16_000 * 31,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { throw InferenceError("No audio was captured.") }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw InferenceError("Unsupported microphone format.") }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    func discard() {
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identity = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, let active = self.recorder, ObjectIdentifier(active) == identity else { return }
            self.onLimit?()
        }
    }
}
