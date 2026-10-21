import Foundation
import XCTest
import PhononTTS
@testable import OfflineInference

final class RuntimeSmokeTests: XCTestCase {
    func testBundledModelsOnHost() async throws {
        guard let modelPath = ProcessInfo.processInfo.environment["OFFLINE_MODEL_ROOT"] else {
            throw XCTSkip("Set OFFLINE_MODEL_ROOT to run the real-model host smoke test. This is not an iPhone benchmark.")
        }
        let root = URL(fileURLWithPath: modelPath)
        let installed = try PhononModels.install(bundled: root.appendingPathComponent("phonon"),
                                                to: root.deletingLastPathComponent().appendingPathComponent("HostPhonon"))
        let tts = try await Phonon.load(models: installed, language: .english, computeUnit: .cpu)
        let samples = try await tts.synthesize("The train leaves at nine thirty.")
        XCTAssertGreaterThan(samples.count, 24_000)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        // STT accepts arbitrary input sample rates through the runtime; this adapter consumes 16 kHz.
        let ratio = 24_000.0 / 16_000.0
        let resampled = (0..<Int(Double(samples.count) / ratio)).map { index -> Float in
            let position = Double(index) * ratio
            let low = Int(position)
            let high = min(low + 1, samples.count - 1)
            let fraction = Float(position - Double(low))
            return samples[low] * (1 - fraction) + samples[high] * fraction
        }
        let recognizer = MoonshineRecognizer()
        try await recognizer.load(from: root.appendingPathComponent("moonshine"))
        let transcript = try await recognizer.transcribe(resampled)
        print("HOST STT:", transcript)
        XCTAssertTrue(transcript.lowercased().contains("train"))
        let llm = LlamaLanguageModel()
        try await llm.load(from: root.appendingPathComponent("llm/model.gguf"))
        let response = try await llm.generate(messages: [Message(role: .user, text: "Say hello in one short sentence.")], onToken: { _ in })
        print("HOST LLM:", response)
        XCTAssertFalse(response.isEmpty)
        XCTAssertFalse(response.contains("<think>"))
        let cancelled = Task {
            try await llm.generate(messages: [Message(role: .user, text: "Count to one hundred.")], onToken: { _ in })
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled generation should throw") }
        catch is CancellationError { }
        let following = try await llm.generate(messages: [Message(role: .user, text: "Say hello in one short sentence.")], onToken: { _ in })
        XCTAssertFalse(following.isEmpty)
        let reply = try await tts.synthesize(response)
        XCTAssertGreaterThan(reply.count, 1_000)
        print("HOST LOOP PASSED; final speech samples:", reply.count)
    }
}
