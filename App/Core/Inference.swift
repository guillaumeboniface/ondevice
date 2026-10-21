import Foundation

struct Message: Identifiable, Sendable, Equatable {
    let id: UUID
    let role: Role
    var text: String
    enum Role: String, Sendable { case user, assistant }
    init(role: Role, text: String) {
        self.id = UUID()
        self.role = role
        self.text = text
    }
}

protocol SpeechRecognizing: Actor {
    func load(from directory: URL) throws
    func transcribe(_ samples: [Float]) throws -> String
}

protocol TextGenerating: Actor {
    func load(from file: URL) throws
    func generate(messages: [Message], onToken: @Sendable (String) -> Void) throws -> String
}

@MainActor protocol SpeechSynthesizing: AnyObject {
    func load(from directory: URL) async throws
    func speak(_ phrases: AsyncThrowingStream<String, Error>, onFirstAudio: @escaping () -> Void) async throws
    func stop()
}

struct InferenceError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// Each generation is rebuilt from at most three completed exchanges plus the new question.
// The runtime additionally trims whole exchanges to fit the exact token budget.
enum ConversationPolicy {
    static let maxUserCharacters = 1_200
    static let maxOutputTokens = 160
    static let contextTokens: UInt32 = 2_048
    static let system = "You are a helpful voice assistant. Answer directly in one or two short sentences. Use plain spoken English. Avoid markdown, lists, and lengthy preambles. If uncertain, say so."

    static func bounded(_ messages: [Message]) -> [Message] {
        var exchanges = [Message]()
        var pendingUser: Message?
        for message in messages {
            if message.role == .user {
                pendingUser = message
            } else if let user = pendingUser {
                exchanges.append(contentsOf: [user, message])
                pendingUser = nil
            }
        }
        // An interrupted user-only turn stays visible but is not a completed exchange.
        var selected = Array(exchanges.suffix(6))
        if let pendingUser { selected.append(pendingUser) }
        return selected.map { message in
            var copy = message
            copy.text = String(message.text.prefix(maxUserCharacters))
            return copy
        }
    }

    // Text-only form of Qwen3.5's official template with enable_thinking=false.
    // A replacement checkpoint should provide its own template in its adapter.
    static func prompt(_ messages: [Message]) -> String {
        func safe(_ text: String) -> String {
            text.replacingOccurrences(of: "<|", with: "< |")
                .replacingOccurrences(of: "|>", with: "| >")
        }
        return "<|im_start|>system\n\(system)<|im_end|>\n"
            + messages.map { "<|im_start|>\($0.role.rawValue)\n\(safe($0.text))<|im_end|>\n" }.joined()
            + "<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }
}

// Wait for a word boundary after punctuation so decimals and split tokens stay intact.
struct SpeechPhraseBuffer {
    private var pending = ""

    mutating func append(_ token: String) -> [String] {
        pending += token
        var phrases = [String]()
        while let boundary = boundary() {
            let phrase = String(pending[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
            pending = String(pending[boundary...])
            if !phrase.isEmpty { phrases.append(phrase) }
        }
        return phrases
    }

    mutating func finish() -> String? {
        let tail = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = ""
        return tail.isEmpty ? nil : tail
    }

    private func boundary() -> String.Index? {
        var count = 0
        var previous: Character?
        for index in pending.indices {
            let character = pending[index]
            if character.isWhitespace, let previous {
                if ".!?".contains(previous) || (count >= 60 && ",;:".contains(previous)) || count >= 160 {
                    return index
                }
            }
            // Include closing quotation marks in the sentence being spoken.
            if !"\"”’)]".contains(character) { previous = character }
            count += 1
        }
        return nil
    }
}
