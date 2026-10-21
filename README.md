# OnDevice

Native SwiftUI prototype for an English voice conversation that runs entirely on an iPhone. Target: iPhone 15 Pro or newer, iOS 18+. All model weights and voices are bundled in the installed app. No cloud inference, Apple Intelligence, speech-recognition service or first-launch model download is used.

**Stack:** Moonshine Small Streaming → Qwen3.5-2B Q4_K_M via llama.cpp → Gradium Phonon 31M English via Core ML. This is a provisional integration baseline; the other candidates are assessed in [model-evaluation.md](docs/model-evaluation.md).

## Build and run

Requires Xcode 16+ with the iOS SDK, Python 3.11+, Git, curl, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Development setup downloads large files; allow several GB of storage for archives, extracted models, frameworks and build products.

```sh
cd /Users/guillaume/projects/ondevice
./scripts/bootstrap.sh
open OnDevice.xcodeproj
```

The pinned llama.cpp release includes physical-iOS and macOS slices, **not an iOS Simulator slice**. Select a physical iPhone; simulator support requires a separate llama.cpp source build.

Choose your signing team under Signing & Capabilities, select a physical iPhone, and run the **OnDevice** scheme in **Release**. No signing identity is committed. A missing/incomplete model asset fails the build. First launch locally copies and compiles Phonon's Core ML models; keep the app foregrounded until ready. A model-ready time is shown under Measurements.

Hold the microphone button, speak, and release to send. The recording is capped at 30 seconds. The transcript appears, text generates locally, then Phonon speaks the reply. Hold again to stop the reply and record a new turn, or use Stop. VoiceOver users can double-tap to start and double-tap again to send. New Conversation clears the in-memory history. Backgrounding stops active capture/playback and cancels the turn.

The application starts from explicit local paths, never the runtimes' auto-download helpers. `bootstrap.sh` pins sources and verifies binary checksums, then materializes local Swift binary dependencies. A reproducible Phonon framework wrapper avoids a module-map collision with Moonshine; it changes packaging, not runtime code or archive bytes. After provisioning, building and running require no model network access. Full model hashes live in `bundled-models.lock.json`; the application includes its copy as `Models/assets.json`. The bundled model files total **1.71 GB decimal** before runtime binaries and installed Core ML compilation/copy overhead. Model files, archives, vendor checkouts and generated build products are excluded from Git because of their size; the provisioned workspace contains the actual files.

## Implemented scope

- Native microphone capture at 16 kHz and 24 kHz streamed PCM playback with playback-completion tracking.
- Replaceable `SpeechRecognizing`, `TextGenerating` and `SpeechSynthesizing` adapters.
- Finalized push-to-talk STT, visible streaming LLM tokens, streamed Phonon PCM playback.
- 2,048-token LLM context, at most three previous exchanges, 160-token response cap, non-thinking text template.
- Manual interruption, cancellation checks between inference batches/tokens/chunks, and stale-turn callback protection. A native STT call already in progress finishes before its actor handles another call.
- Session measurements and user-initiated JSON export containing timings and device state, without conversation text. Recordings are temporary and deleted after capture; transcripts live only in memory.

Live STT partials, automatic EOU and voice-activated barge-in are follow-on work. LLM tokens feed a phrase queue: speech begins at sentence boundaries while the rest of the reply generates. Long sentences can split at a clause or word boundary. One playback session spans queued phrases; pauses depend on device synthesis speed. [The device protocol](docs/device-benchmark.md) covers accuracy, endpointing, acoustic latency, installed size, memory and a 15-minute sustained run.

## Verification

```sh
python3 scripts/verify_assets.py --hash
swift test -c release
OFFLINE_MODEL_ROOT="$PWD/App/Resources/Models" swift test -c release --filter RuntimeSmokeTests
xcodebuild -project OnDevice.xcodeproj -scheme OnDevice \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath .build/iOS CODE_SIGNING_ALLOWED=NO build
python3 scripts/verify_app_bundle.py .build/iOS/Build/Products/Release-iphoneos/OnDevice.app
```

The optional host smoke test loads the real Phonon bundle, synthesizes a sentence, transcribes it with Moonshine, generates a Qwen reply, and synthesizes that reply. It creates a local writable Phonon copy under `App/Resources/HostPhonon`; remove that generated folder after the test. This is a host integration check, not an accuracy benchmark or proof of physical-iPhone performance.

Build/test outcomes and remaining validation are recorded in [validation.md](docs/validation.md). No physical-device performance figures are claimed. Published weight sizes and vendor latency figures are not runtime RAM requirements or measured end-to-end latency for this app.

## Layout

- `App/` — native UI, audio, orchestration and inference adapters.
- `App/Resources/Models/` — provisioned files copied into the app as a folder reference.
- `App/Resources/Licenses/` — redistribution notices.
- `scripts/` — developer-only provisioning, local dependency preparation and asset verification.
- `Tests/` — context/template invariants and optional real-model host smoke test.
- `project.yml` — reproducible XcodeGen project definition.

Intended tasks, languages beyond English and maximum installed size still need product decisions. The initial model selection should be revisited after the first device measurements.
