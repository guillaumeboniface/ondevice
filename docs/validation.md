# Validation record

Validated on 2026-10-21 with Xcode 27.1 / Swift 6.4 on an Apple-silicon Mac. App deployment target is iOS 18.0; intended hardware is iPhone 15 Pro or newer.

| Check | Result |
| --- | --- |
| Physical-iOS Release compile and link, unsigned | PASS (`generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO`) |
| Produced app contains all models, llama dynamic runtime and notices | PASS — 60 model files |
| Provisioned model SHA-256 verification | PASS |
| History length/input limits, orphaned/interrupted history, prompt delimiter isolation | PASS — 3 unit tests |
| Actual Phonon → Moonshine → Qwen → Phonon host loop | PASS — 1 integration test |
| Pre-cancelled LLM request and subsequent fresh generation | PASS, included in host integration test |
| Physical-iPhone launch / audio capture and playback | NOT RUN — no available physical iPhone reported by CoreDevice |
| Fresh-install offline operation on iPhone | NOT RUN |
| Accent/noise/name/number accuracy corpus | NOT RUN |
| Automatic EOU and voice barge-in | NOT IMPLEMENTED in push-to-talk baseline |
| Last-word-to-useful-speech, thermal, battery and 15-minute run | NOT RUN |
| Simulator launch | NOT RUN — pinned llama.cpp XCFramework has no simulator slice |

All 4 tests passed with no skips in the final run. The host audio sentence “The train leaves at nine thirty” was transcribed as “The train leaves at 9.30.” Qwen generated “Hello! How can I help you today?” and Phonon synthesized that answer. This establishes an integration path using the exact bundled model artifacts on the host. It does not establish accuracy, latency or memory on an iPhone.

The produced unsigned app has 1,752,021,407 logical file bytes on this Mac. Model files total 1,708,812,850 bytes. These are build artifacts, not measured installed iPhone footprint. Phonon copies its bundle to writable Application Support and locally compiles it on first use, so total installed storage is larger.

The local dependency preparation verifies official binary archive hashes and wraps Phonon's unchanged static archives as frameworks to prevent both speech packages from producing the same `include/module.modulemap` output. Its script is repeatable and uses the pinned upstream manifests on every run. Runtime source remains unchanged. The packaged llama framework is dynamic and embedded in the app. The Xcode build's remaining App Intents metadata message is informational; this app has no App Intents dependency.

Reproduction commands are in the [README](../README.md). Logs are in `.build/ios-build.log` and `.build/final-tests.log`; large artifacts and build logs are intentionally excluded from version control. Follow [device-benchmark.md](device-benchmark.md) to fill the remaining rows before calling the prototype physically validated.

## Incremental speech update — 2026-10-21

The controller now queues sentence/clause text for Phonon while the LLM continues generating. Playback uses one session across phrases, and interruption cancels the generation and synthesis tasks. Old playback cancellation callbacks are guarded from stopping a newer session.

Six selected host tests passed (three conversation-policy tests and three incremental phrase-buffer tests), including emitting a sentence before response completion, split decimals/closing quotes, and long unpunctuated text without loss. These were run directly with `xcrun xctest` after SwiftPM compiled the test bundle; SwiftPM's final dSYM step was blocked by the session sandbox. All app core, audio and inference sources passed a physical-iOS Swift type check against the existing dependency modules. A complete Xcode build was blocked during package resolution by denied access to the user manifest cache. The user reports that the updated app works on the tablet. This is a user-reported functional check; concurrent inference speed, pauses between phrases and sustained performance have not been measured.
