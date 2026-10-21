import Foundation
import llama

actor LlamaLanguageModel: TextGenerating {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?

    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }

    func load(from file: URL) throws {
        guard model == nil else { return }
        llama_backend_init()
        var parameters = llama_model_default_params()
        parameters.load_mode = LLAMA_LOAD_MODE_MMAP
        #if targetEnvironment(simulator)
        parameters.n_gpu_layers = 0
        #else
        parameters.n_gpu_layers = 99
        #endif
        guard let loaded = llama_model_load_from_file(file.path, parameters) else {
            throw InferenceError("llama.cpp could not load the bundled Qwen GGUF.")
        }
        var options = llama_context_default_params()
        options.n_ctx = ConversationPolicy.contextTokens
        options.n_batch = 256
        options.n_ubatch = 256
        options.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.processorCount - 2)))
        options.n_threads_batch = options.n_threads
        guard let ctx = llama_init_from_model(loaded, options) else {
            llama_model_free(loaded)
            throw InferenceError("Could not allocate the language model context. Try a smaller checkpoint.")
        }
        model = loaded
        context = ctx
        vocab = llama_model_get_vocab(loaded)
    }

    private func tokenize(_ text: String, vocab: OpaquePointer) throws -> [llama_token] {
        let count = text.withCString { llama_tokenize(vocab, $0, Int32(text.utf8.count), nil, 0, true, true) }
        guard count < 0, count != Int32.min else { throw InferenceError("Invalid tokenization size.") }
        var tokens = [llama_token](repeating: 0, count: Int(-count))
        let written = text.withCString { llama_tokenize(vocab, $0, Int32(text.utf8.count), &tokens, Int32(tokens.count), true, true) }
        guard written > 0 else { throw InferenceError("Prompt tokenization failed.") }
        return Array(tokens.prefix(Int(written)))
    }

    func generate(messages: [Message], onToken: @Sendable (String) -> Void) throws -> String {
        guard let context, let vocab else { throw InferenceError("Language model is not loaded.") }
        try Task.checkCancellation()
        var history = ConversationPolicy.bounded(messages)
        var tokens = try tokenize(ConversationPolicy.prompt(history), vocab: vocab)
        let limit = Int(ConversationPolicy.contextTokens) - ConversationPolicy.maxOutputTokens
        while tokens.count > limit && history.count > 1 {
            history.removeFirst(min(2, history.count - 1))
            tokens = try tokenize(ConversationPolicy.prompt(history), vocab: vocab)
        }
        guard tokens.count < limit else { throw InferenceError("Please ask a shorter question.") }
        llama_memory_clear(llama_get_memory(context), true)
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw InferenceError("Could not create a token sampler.")
        }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(20))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.8, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))

        var batch = llama_batch_init(256, 0, 1)
        defer { llama_batch_free(batch) }
        func decode(_ input: ArraySlice<llama_token>, at position: Int) throws {
            batch.n_tokens = Int32(input.count)
            for (index, token) in input.enumerated() {
                batch.token[index] = token
                batch.pos[index] = Int32(position + index)
                batch.n_seq_id[index] = 1
                batch.seq_id[index]![0] = 0
                batch.logits[index] = index == input.count - 1 ? 1 : 0
            }
            guard llama_decode(context, batch) == 0 else {
                throw InferenceError("Local text generation failed to decode a batch.")
            }
        }
        for offset in stride(from: 0, to: tokens.count, by: 256) {
            try Task.checkCancellation()
            try decode(tokens[offset..<min(offset + 256, tokens.count)], at: offset)
        }
        var output = ""
        var pending = [UInt8]()
        for index in 0..<ConversationPolicy.maxOutputTokens {
            try Task.checkCancellation()
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            var piece = [CChar](repeating: 0, count: 256)
            var count = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if count < 0 {
                piece = [CChar](repeating: 0, count: Int(-count))
                count = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            }
            guard count >= 0 else { throw InferenceError("Could not decode a token.") }
            pending.append(contentsOf: piece.prefix(Int(count)).map { UInt8(bitPattern: $0) })
            if let text = String(bytes: pending, encoding: .utf8) {
                output += text
                pending.removeAll(keepingCapacity: true)
                onToken(text)
            }
            try decode([token][...], at: tokens.count + index)
        }
        try Task.checkCancellation()
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
