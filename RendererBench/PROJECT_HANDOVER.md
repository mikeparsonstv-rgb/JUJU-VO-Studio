# Renderer Bench — Project Handover

Last updated: 2026-08-09  
Completed milestone: **RB-007 Timing Repair Control**  
Current state: nine guarded, oracle-timed post-generation derivatives and paired identified bundles are complete. Operator listening is required to decide whether timing alone improves performance; no later milestone has begun.

## Purpose and governing philosophy

This is an evidence-gathering bench, not the TalkBack/CuePitch product. Generated voice is editable source material, never authority. Renderer-neutral requests, results, validation, and provenance permit fair comparison; renderer-native behavior stays isolated in adapters. Performance, identity, accent, intelligibility, timing, acoustic presence, and subjective editorial fit remain separate questions. Engineering measurements support listening but do not replace it.

Private production media stays local and ignored. Every authoritative output retains the exact model/runtime/backend, input identities and hashes, settings, lifecycle, timing, validation, and run ID. Unsupported measurements are explicit rather than fabricated. No aggregate winner exists.

## Architecture now

The Xcode 26-compatible Swift 6.2 package targets macOS 26 and contains:

- `RendererBenchCore`: renderer-neutral request/result models, registry, evidence store/runner, and common WAV validation.
- Qwen3, VoxCPM2, and Chatterbox adapters plus persistent JSON-lines Python workers in separate locked environments.
- `RB006Qualification`: neutral qualification manifest validation, SHA-256 provenance, cross-holdout leakage protection, measurement-unavailable state, and audition gain metadata.
- `rb006-qualification`: opt-in real-render harness. It opens one persistent session per renderer, performs health/load, then exactly three BHM-XH-01 and three BHM-XH-02 calls.
- `Analysis/RB006`: isolated Whisper/signal-analysis project and scripts for signal metrics, ASR, audition derivatives, and report construction.
- `RB007TimingRepair`: additive renderer-neutral performed-span, eligibility, provenance, and listening-pair models.
- `rb007-time-repair`: macOS `AVAudioUnitTimePitch` offline processor that stretches only a supplied performed region, preserves head/tail, fixes pitch at zero cents, and refuses overwrite/out-of-range work.
- `Analysis/RB007`: performed-span planning, completeness/ratio gating, Core Audio orchestration, paired measurement/ASR, identified bundle construction, frozen-source verification, and reports.

RB-006 and RB-007 required no changes under `Sources/RendererBenchCore`. Qualification/timing logic is additive. Active renderer IDs remain `qwen3`, `voxcpm2`, `chatterbox`, `moss`, and `microsoft`; only the first three are operational. RB-007 called none of them.

## Exact operational identities

Qwen remains `Qwen/Qwen3-TTS-12Hz-0.6B-Base@5d83992436eae1d760afd27aff78a71d676296fc`, tokenizer `Qwen/Qwen3-TTS-Tokenizer-12Hz@7dd38ad4e9bad454aae9cd937d0cd577604fe229`, qwen-tts 0.1.1, adapter `1.1.0-rb003`, Python 3.12.13 and actual MPS.

VoxCPM2 remains upstream `openbmb/VoxCPM2@bffb3df5a29440629464e5e839f4d214c8714c3d`, conversion `mlx-community/VoxCPM2-bf16@a7fb80d9056983135a54ca3f71fcc5a637ccddf5`, mlx-audio 0.4.6 revision `d28d68c6ac4e28f7d2d66007f640b06cf3fd8ceb`, adapter `1.0.0-rb004`, and MLX Metal.

Chatterbox remains official source `resemble-ai/chatterbox@5de7a54aa4e5e2baadb0182dde554908b48b85c2`, official model `ResembleAI/chatterbox@5bb1f6ee58e50c3b8d408bc82a6d3740c2db6e18`, explicit Multilingual V3 / `t3_model=v3`, adapter `1.0.0-rb005`, actual MPS, with PerTh watermarking retained.

## RB-006 authority and design

BHM-XH-01 conditions only on BHM01 human audio/transcript and generates the withheld BHM02 words for comparison with evaluation-only BHM02 human audio. BHM-XH-02 reverses those roles. Tests and runtime validation prevent the ground-truth target from entering renderer conditioning.

The operator confirmed the recommended transcripts and retained opening/final `Hah!` where performed. Human hashes are:

- BHM01 `ead6baecac68910aff1254bc2d368b4dd4b750f3cb4705e88ece03fd55a511c4`
- BHM02 `1a46eccf382b352a3ab7dcd16a6533021cc7bde78a8dc0b0d948b0ded166a696`

Authoritative transcript hashes are BHM01 `3e9e7ba2eb9f23d7bbba4db82e7010f2abff616e2a4d21727a05f836c4b3a79c` and BHM02 `af1c9689b57a32372a837e4f35156a603bdcc879e0861bcc7392bbc2a2d9d1ad`.

The three renderer sessions produced all 18 expected calls, each with normal run evidence and common WAV validation. Qwen used its established seed 1003/settings, VoxCPM2 its established native baseline, and Chatterbox its native defaults with PerTh enabled. Nothing was optimized, cropped, denoised, selected, or rerun to improve results.

## Headline evidence

Qwen produced 25.84–26.24-second outputs with mean WER 0.090/0.029 by direction. Its fixed seed produced byte/feature-identical calls within each direction; interpret this as repeatability, not stochastic diversity.

VoxCPM2 produced 0.80–13.76-second BHM-XH-01 and 6.72–10.56-second BHM-XH-02 files, with mean WER 0.950/0.676. It severely truncated all six long-form calls. Valid WAV structure is therefore necessary but not sufficient evidence of a usable render. The untuned failures are preserved.

Chatterbox produced 23.80–25.96-second BHM-XH-01 and 18.08–20.28-second BHM-XH-02 files, with mean WER 0.090/0.103. It showed real run-to-run acoustic variation and very large generation-time variance, especially 67.66–333.62 seconds in BHM-XH-01.

Whisper is assistive only. The separate evaluator gate records official OpenAI Whisper 20250625 `turbo`, model SHA-256 `aff26ae408abcba5fbf8813c21e62b0941638c5f6eebfb145be0c9839262a19a`, PyTorch 2.13.0, CPU, and MIT provenance. No speaker verifier passed a separate gate, so speaker similarity is unavailable. No accent score or subjective winner was generated.

Human context: BHM01/BHM02 durations are 28.88/30.00 seconds, active speech 21.77/22.61 seconds, pause proportions both approximately 0.246, median F0 179.8/182.9 Hz, and MFCC mean-vector distance 12.80. This is same-speaker variation, not an identity ceiling.

## RB-007 timing repair control

Operator listening after RB-006 found all three open systems recognisable as the original talent, Qwen the clear subjective leader, and shared reads too fast and pushed. Chatterbox could start convincingly then lose coherence; VoxCPM2 remained weakest/truncated. The common `Hah!` failure sounded like an external exclamation rather than internal amusement. RB-007 isolates only the first question: does overall timing repair improve perceived performance?

The entire 212-file RB-006 evidence tree was hashed before work and remains byte-for-byte unchanged. The withheld human target contributed only post-generation diagnostic timing labelled `oracle_target_performed_span`; it never entered renderer conditioning and no new render request occurred.

Performed span uses first meaningful speech onset through last meaningful offset, excluding head/tail silence while retaining internal pauses. BHM01 is 28.773 seconds and BHM02 29.589 seconds under the shared detector. Eligibility requires transcript coverage at least 0.80, assistive WER at most 0.35, and a fixed time scale from 0.85 through 1.20.

Nine files qualify: all six Qwen calls, Chatterbox BHM-XH-01 run 2, and both BHM02-target ElevenLabs generations. All six VoxCPM2 calls are excluded as incomplete. Five Chatterbox and both BHM01-target ElevenLabs calls are outside the ratio guardrail. No threshold was widened.

The system `AVAudioUnitTimePitch` path runs with pitch 0 cents through offline `AVAudioEngine`. It stretches only the detected performed region, keeps original head/tail, and proportionally scales internal pauses. No gain, normalization, EQ, compression, limiting, denoise, dereverb, formant, breath, pause, phrase, or spectral processing is requested. Every accepted repaired span is within 50 ms of its oracle target. Active-RMS movement ranges approximately −0.102 to −0.016 dB; median-F0 movement ranges −2.47 to +1.07 Hz. Whisper WER is unchanged for every Qwen and ElevenLabs pair and moves 0.090 to 0.104 for the one Chatterbox pair.

Direct AVFoundation decoding of the MP3 market files caused approximately −3 dB at unity rate. Those attempts were rejected and recoverably preserved. Accepted ElevenLabs processing starts from the frozen RB-006 resample/channel-only 48 kHz mono PCM copies while retaining exact MP3 identities/hashes as source provenance.

This engineering evidence does not answer whether pace, push, identity, Birmingham character, naturalness, or performance improved, nor whether time-stretch artefacts are audible. The paired identified bundles exist specifically for that operator decision. `Hah!` is expected to remain wrong because its semantic intent was not changed.

## Evidence and audition locations

Private ignored evidence root:

`BenchData/qualifications/RB006-Birmingham-Baseline`

Key descendants:

- `authoritative/renders`: 18 normal renderer run trees
- `measurements`: 24 signal records (two humans, 18 generated, four ElevenLabs) plus 18 ASR records
- `audition_raw_pcm`: resampling/channel-conversion-only 48 kHz mono PCM-16 copies
- `audition_level_matched`: attenuation-only gain-matched copies; no limiting, EQ, denoising, or dynamics processing
- `listening-bundle/BHM01_target` and `BHM02_target`: identified raw/matched audition sets with manifests
- `report/report.json` and `report/report.md`: detailed local authority

RB-007 private ignored evidence root is `BenchData/qualifications/RB007-Timing-Repair`, containing:

- `source_manifest`: all frozen RB-006 hashes plus timing plan, eligibility, oracle labels, and exclusions
- `repaired`: nine WAV derivatives with per-pair provenance and measurements
- `measurements`: original-market and repaired Whisper evidence
- `listening-bundle/BHM01_target` and `BHM02_target`: paired identified raw-level and attenuation-only level-matched bundles
- `report/report.json` and `report/report.md`: full timing-control report
- `rejected-artifacts`: preserved direct-MP3 level-mismatch and incomplete bundle-construction attempts, excluded from primary listening evidence

Each target bundle contains human ground truth, three calls from each open renderer, and two supplied ElevenLabs generations. ElevenLabs provenance/settings/conditioning parity are unknown; files are untouched external market context and were never used for conditioning or tuning.

## Verification

RB-007 began from the completed 79-test RB-006 suite. One pre-change run exposed the existing `timeoutTerminatesAndNextRequestRestarts` test's 0.2-second process-launch margin as flaky under concurrent load; its timeout is now 0.5 seconds while the scripted hang remains 2 seconds. Final regression passed 85/85 tests and the release build. RB-007 adds six model-free tests covering the 12 required concerns through combined cases. Ordinary tests download no model. Python compilation, JSON/bundle validation, nine repaired-duration tolerances, source/run provenance, zero renderer requests, and byte comparison of all 212 RB-006 files also pass.

## Known issues and honest edges

- Identified human audition is pending; engineering evidence cannot decide identity, Birmingham fidelity, naturalness, or editorial preference.
- VoxCPM2's long-form baseline truncates badly. The cause has not been tuned or diagnosed beyond the preserved measurements because RB-006 forbids optimization.
- Qwen's three same-seed calls are independent invocations but not independent stochastic samples.
- Whisper can misrecognize regional delivery and brand terms; WER/CER is not listening authority.
- No licence-gated speaker verifier was selected, so there is no embedding/cosine similarity.
- Signal measures and MFCC distance are descriptive, not accent or speaker-identity scores.
- Chatterbox latency is highly variable and non-streaming; no first-audio measurement exists.
- PerTh enabled metadata does not independently prove watermark detectability in every file.
- ElevenLabs comparison is uncontrolled because its conditioning and settings are unknown.
- Complete distributable third-party notices for all locked dependency graphs remain outstanding.
- This supplied folder is not a Git repository, so no commit history protects the work.
- Operator audition of RB-007 raw and level-matched pairs is outstanding; engineering checks cannot certify audible stretch quality or performance improvement.
- Oracle target seconds are deliberately contaminated evaluation information and must never be mistaken for production new-copy timing behavior.
- Overall time stretch scales internal pauses with speech; it does not reproduce target phrase cadence or pause placement.
- Most Chatterbox examples and both BHM01 ElevenLabs examples exceed the conservative ratio guardrail, limiting the systems represented in primary repaired listening.
- Rejected direct-MP3 attempts and an incomplete bundle attempt are retained under `rejected-artifacts` for audit, not listening.

## Roadmap

1. Operator auditions both RB-007 target bundles, comparing adjacent original/repaired files at raw and matched level. Record pace, remaining push, identity, Birmingham character, naturalness, artefacts, performance improvement, and unchanged `Hah!` semantics.
2. Preserve RB-006 and RB-007 evidence unchanged after listening; record observations as new annotations rather than rewriting measurements.
3. In a separately authorized milestone, prefer renderer-native/source-derived timing: same-copy defaults to original performed duration; new-copy inherits active-speech rate, pause proportion, cadence, and breath tendency.
4. After timing is controlled, isolate energy/push, emphasis/restraint, and internal-versus-external reaction. Keep `Hah!` as the Actor Model intent benchmark.
5. Separately consider a licence/provenance-gated speaker verifier and better completeness diagnostics; neither is an accent score.

No renderer-native timing, self-tuning, Actor Model, energy control, semantic direction, phrase retiming, or later milestone has begun.
