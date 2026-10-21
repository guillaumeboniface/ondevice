# Physical iPhone validation protocol

Status: NOT RUN. Target: iPhone 15 Pro or newer, iOS 18+. Record exact iPhone, OS build, battery health, free storage, app build, asset lock hash, ambient temperature and inference settings. A host or simulator result is never a device result.

## First-launch offline gate

1. Build Release with all assets included; choose the signing team and install over USB. Do not run the app yet.
2. Remove any prior installation and its local data before testing a clean first launch. Enable Airplane Mode and explicitly disable Wi-Fi and Bluetooth. Keep them off throughout preparation and the conversation.
3. Launch, allow local Core ML compilation, grant microphone permission, and complete ten push-to-talk exchanges. Include numbers and a follow-up referring to a previous turn.
4. Verify spoken output, visible transcript, bounded short replies, no missing-model errors and no network dependency. Repeat after force quitting and rebooting. Inspect network activity with Instruments in a separate online control run.
5. Record time to model-ready on a clean install, time on a second launch, app bundle size, Application Support before/after compilation, and total installed footprint in iPhone Storage. Compressed download bytes are a separate measure.

Pass only if a fresh installation speaks on its first launch with all radios off. The app build fails when provisioned model files are absent; it must never fetch substitutes.

## Accuracy corpus

Collect consented, locally stored recordings from at least five English speakers with varied accents. Use the same recordings and levels for each candidate. Include at least ten examples per category:

- Quiet natural speech and fast connected speech.
- Regional/non-native accents, soft speech and distance from the microphone.
- Cafe-like background noise, fan noise, and competing speech at documented SNR.
- Names and uncommon words (e.g. Siobhan, Niamh, Guillaume, Kubernetes).
- Phone numbers, decimals, dates, currency, addresses, spelled letters and times.
- Hesitations, 0.3/0.7/1.2/2 second within-turn pauses, restarts and corrections: “Set it for Tuesday ... actually, Thursday at three thirty.”
- Empty/silent recordings and noise without speech; assess hallucinations separately.

Keep the literal reference and normalized reference. Report WER = (substitutions + deletions + insertions) / reference words, plus exact-match rates for names and numeric fields. Do not hide a wrong number with punctuation/number normalization. Review each substitution and correction-retention failure. A synthetic Phonon recording is only an integration smoke test, not an accuracy corpus.

## Endpointing and latency

The initial app is push-to-talk: releasing the control is the endpoint. It does not run automatic end-of-speech detection, so automatic EOU delay and premature-ending rate are “not applicable” for this baseline.

For streaming/EOU candidates, replay the same annotated recordings in real time and compare the emitted turn-end event with the hand-labelled last-word boundary. Report missed turns, late turns, false endpoints during pauses, and lost corrections, including counts and denominator. Sweep thresholds rather than choosing one from a single example.

Use an external two-channel recording or synchronized acoustic markers to measure last-word-end to first *useful* spoken answer. Exclude filler (“Sure”) from useful-response onset. At least 30 turns per condition; report median, p90 and p95. Include endpoint wait, STT finalization, prompt prefill, generation, voice conditioning if needed, TTS and audio output latency. Separate first turn from warm turns.

The app JSON records release-to-first-token and release-to-first-PCM-enqueue timestamps. These are software diagnostics and do not include all acoustic delay. They are not equivalent to user-last-word-to-first-useful-speech. Model preparation is measured from loading requested to all stages ready, not process launch time; use Instruments for actual launch timing.

## Memory, heat and battery (15 minutes)

1. Start unplugged at a documented battery level, screen brightness and ambient temperature. Record Low Power Mode and thermal state. Avoid unrelated foreground/background workloads.
2. Run a fixed 15-minute script: 10–20 second questions and natural short replies, alternating normal turns with follow-ups. Log every turn and timestamp. Use the same script/cadence on every candidate.
3. Use Instruments Allocations/VM Tracker and Energy Log on a separate profiling run; monitor process physical footprint, system memory pressure and termination logs. App RSS sampled once per second is a lower-resolution supplement and can miss peaks.
4. Export JSON at the end, recording battery start/end, thermal transitions, total turns, timeouts, cancellations and errors. The app reports battery at completed/interrupted turns, not a calibrated energy estimate. Measure battery drain across repeated unplugged runs; profiling/USB changes power behavior.
5. Compare first, middle and final five-minute latency distributions and tokens/sec. Report thermal throttling, surface-temperature measurement method and any jetsam termination. Never infer runtime RAM from weight size.

## Functional stress cases

- Release the button before microphone permission resolves; then grant/deny permission and retry.
- Hold for 30 seconds; recording finalizes exactly once.
- Interrupt STT, LLM and TTS separately using Stop or a new push-to-talk turn. Old callbacks must not populate a new turn; audio must stop and later replies must still play.
- Background the app, lock the screen, accept an audio interruption and unplug/change the audio route. Foreground operation must recover without stale playback or a stuck recording state.
- Start a new conversation during generation. Confirm old context is absent from the next response.
- Ask enough questions to exceed the history bound and use an overlong/Unicode question; verify graceful token-budget handling.
- Repeat loading/launching and rejected permissions; check that temporary microphone audio is removed. Chat is memory-only and export contains timings, not conversation text.

## Results sheet

| Build / device / model variant | Clean model preparation | Warm preparation | WER / name exact / number exact | Last word → useful audio p50 / p95 | Peak physical footprint | Bundle / installed bytes | 15-min battery delta | Thermal / failures |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Pending device run | — | — | — | — | — | — | — | — |

Agree acceptable latency, accuracy, maximum installed size, tasks and required languages before declaring a model selection final.
