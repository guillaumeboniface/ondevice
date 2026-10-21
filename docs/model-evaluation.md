# Runtime and model evaluation

Verified against primary sources on 2026-10-21. This is integration triage, not a measured ranking. No iPhone latency, accuracy, RAM or thermal results have been established.

## Initial implementation

English, foreground operation, iOS 18+, iPhone 15 Pro or newer (user-confirmed hardware target). The app uses Moonshine Small Streaming through the official Swift package, Qwen3.5-2B text GGUF Q4_K_M through llama.cpp, and Gradium Phonon 31M English through the official Swift/Core ML runtime. All model files are copied into the application bundle at build time. Development provisioning uses the network; app inference does not.

The recognizer runs a finalized push-to-talk recording in the initial milestone. The streaming-capable model name does not imply live transcription in this implementation. The LLM displays tokens as generated. TTS streams PCM after completion of the short text response; text generation and speech synthesis are sequential. This creates a clear baseline for later sentence streaming.

The Qwen adapter implements the text-only official Qwen3.5 chat template with thinking disabled. It limits generation to 160 tokens, context to 2,048 tokens, history to three exchanges plus the current question, and trims older whole exchanges again if tokenization exceeds the prompt budget. A checkpoint swap requires a matching chat template, tokenizer and architecture smoke test, not just a file rename.

## STT candidates

| Candidate | Integration evidence and next test | Decision |
| --- | --- | --- |
| Moonshine Small Streaming, 123M | Official Swift `MoonshineVoice`; explicit `Transcriber(modelPath:modelArch:)` prevents auto-download. Streaming models are MIT. | Initial adapter. Test accents and names on device; no accuracy preference established. |
| Moonshine Medium Streaming, 245M | Same runtime and file layout; `.mediumStreaming`. Larger models must be separately bundled. | First same-runtime accuracy comparison; measure all three stages resident together. |
| Parakeet Realtime EOU, 120M | English streaming with end-of-utterance output. FluidAudio provides Core ML speech integrations; weights use NVIDIA Open Model License. | First endpointing comparison. Verify exact converted bundle, versioned local-loading API and license before an adapter is accepted. |
| Parakeet TDT v3, 600M | 25 European languages; FluidAudio/Core ML path. Do not equate chunked decoding with native streaming. | Multilingual candidate if the language requirement expands; higher model footprint. |
| Nemotron 3.5 ASR Streaming, 600M | Official card documents native streaming and multiple language tiers; not all listed locales are production-ready. Current card lists OpenMDW 1.1. | Exact iOS runtime, conversion, language quality and total memory remain unvalidated here. |
| Qwen3-ASR | Official model card supports multilingual ASR. Python/Transformers support alone does not prove an iOS path. | Defer until a pinned iOS runtime and export are demonstrated. |

Sources: [Moonshine Swift](https://github.com/moonshine-ai/moonshine-swift), [Moonshine model catalog](https://github.com/moonshine-ai/moonshine/blob/main/core/moonshine-model-catalog.cpp), [Moonshine license](https://github.com/moonshine-ai/moonshine/blob/main/LICENSE), [FluidAudio](https://github.com/FluidInference/FluidAudio), [Parakeet EOU](https://huggingface.co/nvidia/parakeet_realtime_eou_120m-v1), [Parakeet TDT v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), [Nemotron 3.5](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b), [Qwen3-ASR](https://huggingface.co/Qwen/Qwen3-ASR-0.6B).

## LLM candidates

| Candidate | Packaging / integration decision |
| --- | --- |
| Qwen3.5-2B | Apache 2.0. Initial text-only Q4_K_M GGUF; no vision projector. llama.cpp's pinned source recognizes `qwen35`; its official XCFramework contains iOS device slices. Device linking and real-model host execution are separate gates from device performance. The b11786 release artifact has iOS-device and macOS slices but no iOS Simulator slice; simulator use requires a separate source build. |
| MiniCPM5-1B | Official GGUF and Apache 2.0. Strong smaller comparison candidate; verify the exact architecture and chat template in the selected llama.cpp revision before substituting. Not integrated or benchmarked. |
| LFM2.5-1.2B-Instruct | Compact edge candidate. The QAD Q4_0 artifact is a different quantization from Q4_K_M; validate its runtime explicitly. Custom commercial terms remain a selection consideration. Not integrated or benchmarked. |
| LFM2.5-2.6B | Larger Liquid comparison under the applicable Liquid license. Recheck the precise checkpoint and commercial conditions. Not integrated or benchmarked. |
| Qwen3.5-4B | Apache 2.0 quality comparison, requiring a separate memory and sustained-performance evaluation. Not integrated or benchmarked. |

**llama.cpp versus MLX Swift:** llama.cpp was chosen because the requested initial artifact is a GGUF Q4_K_M file and the project provides an official Apple XCFramework plus a native Swift example. MLX Swift LM is a credible replacement runtime but uses its own model representation and quantization path: a GGUF artifact is not a drop-in MLX model. Exact Qwen3.5 checkpoint support, Metal operation on iOS, tokenizer, local-only loading and conversion integrity need a separate prototype. No conclusion about which runtime is faster on an iPhone is justified here.

Sources: [Qwen3.5-2B](https://huggingface.co/Qwen/Qwen3.5-2B), [GGUF artifact](https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF), [official Qwen chat template](https://huggingface.co/Qwen/Qwen3.5-2B/blob/main/chat_template.jinja), [llama.cpp](https://github.com/ggml-org/llama.cpp), [MiniCPM5 official GGUF](https://huggingface.co/openbmb/MiniCPM5-1B-GGUF), [Liquid model and terms](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct), [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm).

## TTS and storage

Phonon 31M English weights are Apache 2.0. The official v0.4.0 Swift runtime requires iOS 18+ and uses an exported Core ML bundle, not the roughly 64 MB Rust Q8 GGUF artifact. The downloaded release archive, extracted bundle, writable installed copy and compiled models are distinct storage costs. `PhononModels.install(bundled:)` copies bundled files into Application Support without a network request; Core ML compilation happens locally. Preparation time includes installation, compilation, loading and voice conditioning. The app explicitly selects Freya.

Phonon 40M variants carry CC BY-NC terms with separate commercial licensing; they are not included. Do not silently substitute them for the English 31M release.

Sources: [Phonon release](https://github.com/gradium-ai/xn-ptts/releases/tag/v0.4.0), [Swift runtime guide](https://github.com/gradium-ai/xn-ptts/blob/v0.4.0/ios/PhononTTS/README.md), [model announcement](https://gradium.ai/blog/release-phonon-open-weight).

## Next implementation order

1. Complete the physical-device baseline and compare checkpoints using the same corpus, microphone, context and settings.
2. Feed 16 kHz capture into Moonshine streams and publish partial/final line revisions off the audio render thread. Use a bounded PCM queue with explicit overload handling.
3. Speak completed LLM sentences while later tokens generate, with bounded queues and one cancellation token across all stages. Preserve punctuation and avoid speaking partial numbers or names.
4. Compare explicit EOU with a configurable silence/VAD policy. Include hesitation and self-correction cases before enabling automatic turn submission.
5. Add listening during playback, echo cancellation and true voice barge-in. The initial app only provides manual interruption through push-to-talk or Stop.
