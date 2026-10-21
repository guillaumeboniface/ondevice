import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor final class ConversationController: ObservableObject {
    enum Phase: String {
        case loading = "Preparing models"
        case ready = "Ready when you are"
        case requestingMicrophone = "Opening microphone"
        case recording = "Listening"
        case transcribing = "Transcribing"
        case thinking = "Thinking"
        case speaking = "Speaking"
        case failed = "Something needs attention"
    }
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var detail = "Loading bundled models. First launch compiles Phonon locally."
    @Published private(set) var messages = [Message]()
    @Published private(set) var partial = ""
    @Published private(set) var measurements = [TurnMeasurement]()
    @Published private(set) var coldLoadSeconds: Double?
    @Published private(set) var peakRSS: UInt64 = 0
    @Published private(set) var assetBytes: Int64 = 0
    @Published var showDiagnostics = false
    private let recognizer: any SpeechRecognizing
    private let languageModel: any TextGenerating
    private let voice: any SpeechSynthesizing
    private let microphone = MicrophoneCapture()
    private var task: Task<Void, Never>?
    private var sampler: Task<Void, Never>?
    private var turnID = UUID()
    private var current: TurnMeasurement?
    private var releasedAt: TimeInterval = 0
    private var loaded = false
    private var interruptionObserver: NSObjectProtocol?

    init(recognizer: any SpeechRecognizing = MoonshineRecognizer(),
         languageModel: any TextGenerating = LlamaLanguageModel(),
         voice: (any SpeechSynthesizing)? = nil) {
        self.recognizer = recognizer
        self.languageModel = languageModel
        self.voice = voice ?? PhononSynthesizer()
        microphone.onLimit = { [weak self] in self?.finishRecording() }
        UIDevice.current.isBatteryMonitoringEnabled = true
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.interrupt() }
        }
    }

    var canTalk: Bool { loaded && phase != .requestingMicrophone }
    var isBusy: Bool { [.transcribing, .thinking, .speaking].contains(phase) }

    func prepare() {
        guard !loaded, task == nil else { return }
        phase = .loading
        sampler?.cancel()
        sampler = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.peakRSS = max(self.peakRSS, Diagnostics.residentBytes())
                try? await Task.sleep(for: .seconds(1))
            }
        }
        task = Task { [self] in
            let start = ProcessInfo.processInfo.systemUptime
            do {
                guard let root = Bundle.main.url(forResource: "Models", withExtension: nil) else {
                    throw InferenceError("The Models folder is missing from this build.")
                }
                struct Manifest: Decodable {
                    struct File: Decodable { let path: String; let bytes: Int64 }
                    let files: [File]
                }
                let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("assets.json")))
                guard !manifest.files.isEmpty else { throw InferenceError("Bundled model manifest is empty.") }
                for file in manifest.files {
                    let url = root.appendingPathComponent(file.path)
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                    guard Int64(size ?? -1) == file.bytes else { throw InferenceError("Incomplete bundled asset: \(file.path)") }
                }
                assetBytes = manifest.files.reduce(0) { $0 + $1.bytes }
                detail = "Loading Moonshine Small Streaming"
                try await recognizer.load(from: root.appendingPathComponent("moonshine"))
                try Task.checkCancellation()
                detail = "Loading Qwen3.5 · 2B · 4-bit"
                try await languageModel.load(from: root.appendingPathComponent("llm/model.gguf"))
                try Task.checkCancellation()
                detail = "Preparing Phonon · local Core ML compilation"
                try await voice.load(from: root.appendingPathComponent("phonon"))
                coldLoadSeconds = ProcessInfo.processInfo.systemUptime - start
                loaded = true
                phase = .ready
                detail = "Hold to talk. Release to send."
            } catch {
                phase = .failed
                detail = error.localizedDescription
            }
            task = nil
        }
    }

    func beginRecording() {
        guard canTalk, phase != .recording else { return }
        interrupt()
        let id = UUID()
        turnID = id
        phase = .requestingMicrophone
        task = Task { [self] in
            do {
                try await microphone.start()
                try Task.checkCancellation()
                guard turnID == id else { microphone.discard(); return }
                phase = .recording
                detail = "Release to send · 30 second limit"
            } catch is CancellationError {
                if turnID == id { microphone.discard() }
            } catch {
                guard turnID == id else { return }
                phase = .failed
                detail = error.localizedDescription
            }
            if turnID == id { task = nil }
        }
    }

    func finishRecording() {
        // A very quick release can precede completion of the permission request.
        if phase == .requestingMicrophone { interrupt(); return }
        guard phase == .recording else { return }
        releasedAt = ProcessInfo.processInfo.systemUptime
        let id = turnID
        current = TurnMeasurement(captureSeconds: releasedAt - microphone.startedAt)
        phase = .transcribing
        detail = "Recognizing your words on this iPhone"
        let samples: [Float]
        do { samples = try microphone.stop() }
        catch { fail(error, id: id); return }
        task = Task { [self] in
            do {
                let sttStart = ProcessInfo.processInfo.systemUptime
                let transcript = try await recognizer.transcribe(samples)
                try Task.checkCancellation()
                guard turnID == id else { return }
                current?.sttSeconds = ProcessInfo.processInfo.systemUptime - sttStart
                guard !transcript.isEmpty else { throw InferenceError("No speech was detected. Hold the button and try again.") }
                messages.append(Message(role: .user, text: String(transcript.prefix(ConversationPolicy.maxUserCharacters))))
                // Keep UI/history memory bounded as well as the prompt.
                if messages.count > 25 { messages.removeFirst(messages.count - 25) }
                phase = .thinking
                detail = "Generating a short reply locally"
                let generationStart = ProcessInfo.processInfo.systemUptime
                let tokens = AsyncThrowingStream<String, Error>.makeStream()
                let phrases = AsyncThrowingStream<String, Error>.makeStream()
                let history = messages
                let response = try await withThrowingTaskGroup(of: String?.self) { group in
                    defer {
                        group.cancelAll()
                        tokens.continuation.finish()
                        phrases.continuation.finish()
                    }
                    group.addTask { [languageModel] in
                        do {
                            let response = try await languageModel.generate(messages: history) { token in
                                tokens.continuation.yield(token)
                            }
                            tokens.continuation.finish()
                            return response
                        } catch {
                            tokens.continuation.finish(throwing: error)
                            throw error
                        }
                    }
                    group.addTask { @MainActor [voice] in
                        do {
                            try await voice.speak(phrases.stream) { [weak self] in
                                guard let self, self.turnID == id else { return }
                                if self.current?.firstPCMEnqueuedAfterRelease == nil {
                                    self.current?.firstPCMEnqueuedAfterRelease = ProcessInfo.processInfo.systemUptime - self.releasedAt
                                }
                                self.phase = .speaking
                                self.detail = "Hold to interrupt and start a new turn"
                            }
                            return nil
                        } catch {
                            // Wake the text consumer if synthesis fails while generation continues.
                            tokens.continuation.finish(throwing: error)
                            throw error
                        }
                    }
                    var buffer = SpeechPhraseBuffer()
                    for try await token in tokens.stream {
                        try Task.checkCancellation()
                        guard turnID == id else { throw CancellationError() }
                        if current?.firstTokenAfterRelease == nil {
                            current?.firstTokenAfterRelease = ProcessInfo.processInfo.systemUptime - releasedAt
                        }
                        partial += token
                        for phrase in buffer.append(token) { phrases.continuation.yield(phrase) }
                    }
                    current?.generationSeconds = ProcessInfo.processInfo.systemUptime - generationStart
                    if let tail = buffer.finish() { phrases.continuation.yield(tail) }
                    phrases.continuation.finish()
                    var response = ""
                    for try await result in group {
                        if let result { response = result }
                    }
                    return response
                }
                try Task.checkCancellation()
                guard turnID == id else { return }
                partial = ""
                guard !response.isEmpty else { throw InferenceError("The local model returned an empty reply.") }
                messages.append(Message(role: .assistant, text: response))
                current?.completedAfterRelease = ProcessInfo.processInfo.systemUptime - releasedAt
                finishMeasurement()
                phase = .ready
                detail = "Hold to talk. Release to send."
                task = nil
            } catch is CancellationError {
                // The action that cancelled this task already updates state.
            } catch { fail(error, id: id) }
        }
    }

    private func fail(_ error: Error, id: UUID) {
        guard turnID == id else { return }
        current?.failure = error.localizedDescription
        finishMeasurement()
        partial = ""
        phase = .failed
        detail = error.localizedDescription
        task = nil
    }

    func interrupt() {
        guard loaded else { return }
        turnID = UUID()
        task?.cancel()
        task = nil
        voice.stop()
        microphone.discard()
        if current != nil { current?.interrupted = true; finishMeasurement() }
        partial = ""
        phase = .ready
        detail = "Hold to talk. Release to send."
    }

    func clear() {
        interrupt()
        messages.removeAll()
    }

    private func finishMeasurement() {
        guard var current else { return }
        current.residentBytes = Diagnostics.residentBytes()
        peakRSS = max(peakRSS, current.residentBytes)
        current.peakSampledResidentBytes = peakRSS
        current.thermalState = Diagnostics.thermalState()
        current.batteryLevel = UIDevice.current.batteryLevel
        measurements.append(current)
        if measurements.count > 250 { measurements.removeFirst() }
        self.current = nil
    }

    func exportReport() throws -> URL {
        let report = DiagnosticReport(coldLoadSeconds: coldLoadSeconds, bundledAssetBytes: assetBytes,
                                      peakSampledResidentBytes: peakRSS, turns: measurements)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ondevice-benchmark.json")
        try encoder.encode(report).write(to: url, options: .atomic)
        return url
    }
}
