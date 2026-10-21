import Foundation
import PhononTTS

@MainActor final class PhononSynthesizer: SpeechSynthesizing {
    private var phonon: Phonon?
    private var playback: PCMPlayback?
    private var session = UUID()

    func load(from directory: URL) async throws {
        // Only copy locally bundled files. Do not use the runtime's download API.
        let installed = try await Task.detached(priority: .userInitiated) {
            try PhononModels.install(bundled: directory)
        }.value
        try Task.checkCancellation()
        phonon = try await Phonon.load(models: installed, language: .english)
        if phonon?.voices.contains("Freya") == true { try await phonon?.setVoice("Freya") }
        playback = PCMPlayback()
    }

    func speak(_ phrases: AsyncThrowingStream<String, Error>, onFirstAudio: @escaping () -> Void) async throws {
        guard let phonon, let playback else { throw InferenceError("Phonon is not loaded.") }
        try Task.checkCancellation()
        let activeSession = UUID()
        session = activeSession
        try playback.start()
        var first = true
        do {
            for try await text in phrases {
                try Task.checkCancellation()
                for try await chunk in phonon.stream(text) {
                    try Task.checkCancellation()
                    guard !chunk.isEmpty else { continue }
                    try playback.enqueue(chunk)
                    if first {
                        first = false
                        // Host enqueue timestamp, not an acoustic measurement of useful speech.
                        onFirstAudio()
                    }
                }
            }
            try Task.checkCancellation()
            try await playback.drain()
        } catch {
            if session == activeSession { playback.stop() }
            throw error
        }
    }

    func stop() { session = UUID(); playback?.stop() }
}
