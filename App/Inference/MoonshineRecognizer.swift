import Foundation
import MoonshineVoice

actor MoonshineRecognizer: SpeechRecognizing {
    private var transcriber: Transcriber?

    func load(from directory: URL) throws {
        transcriber = try Transcriber(modelPath: directory.path, modelArch: .smallStreaming)
    }

    func transcribe(_ samples: [Float]) throws -> String {
        try Task.checkCancellation()
        guard let transcriber else { throw InferenceError("Speech recognizer is not loaded.") }
        // Milestone 1 deliberately finalizes only when the user releases push-to-talk.
        let result = try transcriber.transcribeWithoutStreaming(audioData: samples, sampleRate: 16_000)
        try Task.checkCancellation()
        return result.lines.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
