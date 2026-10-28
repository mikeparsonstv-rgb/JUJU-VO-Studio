# CODEX_LOG.md

Codex should append one entry after every completed task.

Use this template:

---

## YYYY-MM-DD — TASK_ID — Short task name

### Summary
What changed.

### Files changed
- path
- path

### Tests run
- command
- result

### Manual verification
What was checked manually.

### Known limitations
Anything incomplete or model/environment dependent.

### Architecture notes
Any implementation decision that may matter later.

### Suggested next task
One concise recommendation.

---

---

## 2026-08-08 — RB-001 — Renderer Bench skeleton

### Summary
Created an Xcode 26-compatible Swift 6.2 package with a renderer-neutral core, CLI, five active placeholder descriptors, a separate deterministic mock adapter, transparent JSON/WAV persistence, and failure isolation.

### Files changed
- `Package.swift`
- `.gitignore`
- `README.md`
- `Sources/RendererBenchCore/Models.swift`
- `Sources/RendererBenchCore/Adapters.swift`
- `Sources/RendererBenchCore/Registry.swift`
- `Sources/RendererBenchCore/Persistence.swift`
- `Sources/RendererBenchCore/Runner.swift`
- `Sources/RendererBenchCLI/main.swift`
- `Tests/RendererBenchCoreTests/RendererBenchCoreTests.swift`
- `PROJECT_HANDOVER.md`
- `KEY_FINDINGS.md`
- `CODEX_LOG.md`

### Tests run
- `swift test`
- Result: 8 tests passed, 0 failed.
- Manual mock CLI render produced a valid RIFF/WAVE PCM file: mono, 16-bit, 48 kHz.
- Manual unavailable `qwen3` render returned a controlled error and exit status 1.

### Manual verification
Listed all five active placeholders plus the clearly labelled mock fixture. Rendered A01 through the mock, inspected the persisted tree, and verified the output with the macOS `file` utility.

### Known limitations
- No actual speech engine is integrated; the mock emits a fixed one-second 440 Hz tone.
- The interface is CLI-only and playback delegates to macOS `afplay`.
- Candidate capabilities are declarations for bench routing/history, not yet runtime-verified engine claims.
- There is no batch/render-all command, visual interface, corpus loader, ratings, or blind mode.
- SwiftPM may emit harmless user-cache warnings in restricted sandboxes.

### Architecture notes
The repository was empty, so RB-001 uses a Swift package that Xcode 26 opens natively. `RendererBenchCore` is independent of the CLI. Model-specific work is confined to adapters. Runs add a UUID level beneath the test ID so reruns cannot overwrite one another. Default Codable date representation is retained in stored JSON because it round-trips sub-second timing exactly.

### Suggested next task
Define RB-002 explicitly before selecting and integrating the first real renderer worker; do not infer the renderer or installation plan from RB-001.

---

## 2026-08-08 — RB-002 — Qwen3-TTS first real renderer

### Summary
Passed the Apache-2.0 licence gate, integrated the pinned Qwen3-TTS 12 Hz 0.6B Base model through a separate Swift adapter and isolated Python worker, added real health/render CLI paths, validated successful audio independently in the common runner, and completed real MPS and CPU voice-clone renders on the target Mac.

### Files changed
- `Package.swift`
- `.gitignore`
- `README.md`
- `Sources/RendererBenchCore/Models.swift`
- `Sources/RendererBenchCore/Adapters.swift`
- `Sources/RendererBenchCore/Registry.swift`
- `Sources/RendererBenchCore/Runner.swift`
- `Sources/RendererBenchCore/AudioFileValidator.swift`
- `Sources/Qwen3RendererAdapter/Qwen3RendererAdapter.swift`
- `Sources/Qwen3RendererAdapter/QwenWorkerClient.swift`
- `Sources/Qwen3RendererAdapter/QwenWorkerProtocol.swift`
- `Sources/RendererBenchCLI/main.swift`
- `Workers/Qwen3/pyproject.toml`
- `Workers/Qwen3/uv.lock`
- `Workers/Qwen3/qwen_worker.py`
- `scripts/setup-qwen3.sh`
- `scripts/smoke-qwen3.sh`
- `Tests/RendererBenchCoreTests/RB002Tests.swift`
- `docs/licensing/QWEN3_TTS_LICENSE_CHECK.md`
- `docs/renderers/qwen3.md`
- `docs/benchmarks/RB002_QWEN_CASES.md`
- `PROJECT_HANDOVER.md`
- `KEY_FINDINGS.md`
- `CODEX_LOG.md`

### Tests run
- `swift test` — 16 tests passed, 0 failed, including retained RB-001 coverage and all requested RB-002 cases.
- `swift build -c release` — succeeded.
- `scripts/smoke-qwen3.sh <temporary-reference> <transcript> /tmp/RendererBench-RB002-MPS` with `QWEN3_DEVICE=mps` — succeeded.
- Direct A01 render with `QWEN3_DEVICE=cpu` — succeeded.
- `afinfo` validated both real outputs as 24 kHz mono Int16 WAV.

### Manual verification
Installed locked managed Python 3.12.13 and the exact 0.6B Base snapshot. Confirmed MPS is built/available outside the restrictive file sandbox, health reports exact package/model/tokenizer/device state, a real C01 MPS clone persists complete evidence, CPU fallback renders successfully, and unsupported direction persists a controlled unsuccessful result.

### Known limitations
- The one-shot worker reloads dependencies/model for every render.
- MPS/CPU observations are not a controlled comparative benchmark.
- The temporary macOS system-voice reference is not an approved benchmark voice or clone-quality test.
- Only Base voice cloning is implemented; no Qwen instruction, streaming, VoiceDesign, or CustomVoice path is exposed.
- The other four active renderer slots remain unavailable placeholders.
- Distribution still requires a generated third-party-notices inventory for the locked Python graph.

### Architecture notes
Qwen-specific code is isolated in its own Swift target and Python environment. JSON travels over stdin/stdout with version/request-ID checks; logs stay on stderr; a timeout terminates hung workers. The common runner now validates WAV existence, size, structure, audio data, and duration, and renderer failures may carry neutral environment metadata into persisted results. The model and tokenizer revisions are pinned, and rendering is local-files-only.

### Suggested next task
Define RB-003 explicitly; a reasonable focus is persistent worker/model reuse plus controlled repeated backend measurements and an approved reference-asset catalogue before another renderer integration.

---

## 2026-08-08 — RB-003 — Stabilise Qwen real-render operations

### Summary
Replaced the live one-shot Qwen path with a persistent JSON-lines child process, explicit health/load/render/shutdown lifecycle, resident model reuse, explicit auto/MPS/CPU selection, separated timing metadata, stable A01/C01 definitions, a reference-catalogue schema/blocker, and repeatable smoke/backend scripts. Completed controlled identical-request persistent MPS and CPU sessions on the target Mac.

### Files changed
- `Package.swift`
- `README.md`
- `Sources/RendererBenchCore/BenchCatalog.swift`
- `Sources/Qwen3RendererAdapter/QwenWorkerProtocol.swift`
- `Sources/Qwen3RendererAdapter/QwenWorkerClient.swift`
- `Sources/Qwen3RendererAdapter/PersistentQwenWorkerClient.swift`
- `Sources/Qwen3RendererAdapter/Qwen3RendererAdapter.swift`
- `Sources/QwenSessionBench/main.swift`
- `Workers/Qwen3/qwen_worker.py`
- `scripts/smoke-qwen3.sh`
- `scripts/benchmark-qwen3-backends.sh`
- `BenchAssets/benchmarks/A01.json`
- `BenchAssets/benchmarks/C01.json`
- `BenchAssets/references/catalogue.json`
- `BenchAssets/references/README.md`
- `Tests/RendererBenchCoreTests/RB003Tests.swift`
- `docs/renderers/qwen3.md`
- `docs/benchmarks/RB003_CONTROLLED_BACKENDS.md`
- `PROJECT_HANDOVER.md`
- `KEY_FINDINGS.md`
- `CODEX_LOG.md`

### Tests run
- `swift test` — 28 tests passed, 0 failed; ordinary tests used fake workers and loaded no model weights.
- `.renderer-envs/qwen3/bin/python -m py_compile Workers/Qwen3/qwen_worker.py` — passed.
- `scripts/benchmark-qwen3-backends.sh ... /tmp/RendererBench-RB003-Controlled-20260808` — explicit persistent MPS and CPU sessions both passed.

### Manual verification
Verified four validated renders per backend, one worker session ID per backend, render indices 0–3, model reuse after one explicit load, requested/actual backend agreement, graceful shutdown with no remaining worker, unique evidence directories, and 24 kHz mono PCM-16 RIFF/WAVE outputs. MPS warm A01 generation was 22.670/22.840 seconds; CPU warm A01 was 59.376/57.437 seconds. These are small-sample timing observations, not quality or deterministic-equivalence claims.

### Known limitations
- No approved redistributable human reference was available; the catalogue is empty with an explicit blocker, and real scripts require a local rights-cleared reference.
- Prompt/embedding caching is not implemented; metadata reports `reference_prompt_reused=false`.
- The worker is process-persistent only for the lifetime of the owning adapter/session; there is no daemon, cross-process sharing, or idle timeout.
- First-audio/streaming latency is not measured because generation is non-streaming.
- The controlled evidence used a temporary macOS system-voice architecture reference and cannot assess human clone fidelity.
- Only Qwen is operational; no second renderer was added.

### Architecture notes
The Swift core remains renderer-neutral. Qwen lifecycle fields stay in the adapter's environment snapshot. The client serializes access with a lock, frames newline-delimited JSON using `poll` plus POSIX `read`, captures stderr separately, validates protocol/request identity, restarts after failed/uncertain state, and shuts down gracefully before termination fallbacks. Model/checkpoint/tokenizer pins remain unchanged from RB-002.

### Suggested next task
Define RB-004 explicitly before any further work; do not infer or begin it from this handover.

---

## 2026-08-08 — RB-004 — VoxCPM2 second real renderer

### Summary
Passed the VoxCPM2 open-core licence gate, integrated the exact full-precision BF16 MLX conversion behind its own persistent adapter/worker and isolated environment, established local `reference-001`, retained the stable A01/C01 corpus, and produced the first controlled Qwen3-TTS versus VoxCPM2 evidence using identical reference inputs.

### Files changed
- `Package.swift`
- `.gitignore`
- `README.md`
- `Sources/VoxCPM2RendererAdapter/*`
- `Sources/VoxCPM2SessionBench/main.swift`
- `Sources/RendererBenchCLI/main.swift`
- `Sources/QwenSessionBench/main.swift`
- `Sources/Qwen3RendererAdapter/Qwen3RendererAdapter.swift`
- `Workers/VoxCPM2/pyproject.toml`
- `Workers/VoxCPM2/uv.lock`
- `Workers/VoxCPM2/voxcpm2_worker.py`
- `scripts/setup-voxcpm2.sh`
- `scripts/smoke-voxcpm2.sh`
- `scripts/compare-qwen-voxcpm2.sh`
- `BenchAssets/references/catalogue.json`
- `BenchAssets/references/reference-001/metadata.json`
- `BenchAssets/local-assets.example.json`
- `Tests/RendererBenchCoreTests/RB004Tests.swift`
- `docs/licensing/VOXCPM2_LICENSE_CHECK.md`
- `docs/renderers/voxcpm2.md`
- `docs/benchmarks/RB004_QWEN_VOXCPM2.md`
- `PROJECT_HANDOVER.md`
- `KEY_FINDINGS.md`
- `CODEX_LOG.md`

### Tests run
- `swift test` — 45 tests passed, 0 failed; all ordinary tests remained model-free and download-free.
- `swift build -c release` — passed.
- Python compilation, shell syntax, JSON validation, and locked setup checks — passed.
- `scripts/smoke-voxcpm2.sh ...` — persistent health/load/A01/C01/warm A01/shutdown passed.
- `scripts/compare-qwen-voxcpm2.sh reference-001 /tmp/RendererBench-RB004-Comparison-20260808` — controlled persistent Qwen MPS and VoxCPM2 MLX Metal comparison passed.

### Manual verification
Verified exact upstream/conversion/runtime lineage in results, MLX Metal availability, one worker/model load per renderer session, unique render indices and run IDs, common input equivalence, reference asset ID persistence, graceful shutdown with no worker leak, and common validation of Qwen 24 kHz and VoxCPM2 48 kHz mono PCM-16 WAV. No subjective listening score was fabricated; outputs remain for human audition.

### Known limitations
- `reference-001` maps to a temporary synthetic system voice and is not suitable for human clone-fidelity conclusions.
- VoxCPM2's pinned `ref_text` parameter is unused; RB-004 uses its actual transcript-conditioned continuation path.
- First generation includes MLX graph warmup beyond model load.
- Voice design, controllable style guidance, streaming, and deterministic seed are not exposed by this adapter.
- No prompt cache, cross-process model sharing, concurrency, or idle timeout exists.
- Product distribution still needs complete transitive third-party notices.

### Architecture notes
Common-core changes required: none. The common request/result schema, runner, store, registry mechanics, and WAV validator were unchanged. VoxCPM2-specific behavior is confined to its target and Python environment. Model lineage, conversion identity, runtime, settings, timing, and local asset identity fit the existing structured snapshots. Qwen gained only adapter-level `reference_asset_id` propagation.

### Suggested next task
Obtain and read an explicit RB-005 brief before any further renderer or product work; do not infer its scope from this entry.

---

## 2026-08-08 — RB-005 — Chatterbox Multilingual V3 third renderer

### Summary
Passed the exact Chatterbox V3 open-core gate, installed its pinned official source/model/PerTh/tokenizer stack independently, proved the official PyTorch MPS route, implemented a persistent adapter/worker, and produced controlled Qwen/VoxCPM2/Chatterbox A01/C01 evidence plus a portable listening bundle. No common-core, MOSS, Microsoft, or RB-006 work was performed.

### Files changed
- `Package.swift`, `README.md`
- `Sources/ChatterboxRendererAdapter/*`, `Sources/ChatterboxSessionBench/main.swift`, `Sources/RendererBenchCLI/main.swift`
- `Workers/Chatterbox/pyproject.toml`, `uv.lock`, `chatterbox_worker.py`
- `scripts/setup-chatterbox.sh`, `smoke-chatterbox.sh`, `compare-qwen-voxcpm2-chatterbox.sh`
- `Tests/RendererBenchCoreTests/RB005Tests.swift`
- Chatterbox licence/renderer/benchmark docs, handover, findings, and this log

### Tests and real verification
- `swift test` — 65 passed, 0 failed; ordinary tests remained model/download-free.
- `swift build` — passed before the real run.
- Repeated locked setup passed and isolated the newly discovered official spaCy-pkuseg asset.
- Chatterbox smoke health/load/A01/C01/warm-A01/shutdown passed on MPS.
- The controlled three-way script completed nine renders (six selected plus three warm A01), common validation, graceful shutdown, and bundle creation.

### Evidence summary
Chatterbox identity was source `5de7a54...`, model `5bb1f6e...`, `t3_model=v3`, Chatterbox 0.1.7, PyTorch/torchaudio 2.6.0, and PerTh 1.0.1 on actual MPS. Its controlled session imported in 4.575 s, loaded in 10.806 s, generated A01 cold in 36.391 s, C01 warm in 34.284 s, and A01 warm in 30.671 s. Outputs are validated mono 24 kHz PCM-16 with PerTh enabled. The self-contained bundle and full 11 MB run were preserved under ignored `BenchData/runs/RB005-ThreeWay-20260808`.

### Known limitations
- `reference-001` remains a temporary synthetic integration reference; no human clone-quality conclusion is valid.
- No human audition or subjective ranking was performed.
- The first load exposed a user-cache tokenizer download before it was isolated; that cache was not deleted.
- Watermark application is reported by the official generator but not independently detected from the files.
- Timings are small-sample, cache-sensitive elapsed generation, not first-audio latency.
- Complete third-party notices remain required for distribution.

### Architecture notes
Common-core changes required: none. Chatterbox-specific variant, language, settings, clone mode, watermark, and lifecycle metadata remain inside adapter snapshots. V2 and non-MPS fallback are explicitly rejected. Qwen and VoxCPM2 remained operational.

### Suggested next task
Do not begin RB-006 without its explicit brief. A future milestone may prioritise a rights-cleared human reference and structured listening before more renderer breadth, but that choice remains with the project owner.

---

## 2026-08-08 — RB-006 — Birmingham transcript gate (authoritative run blocked)

### Work completed
Read the RB-006 authority chain, extracted only neutral manifest/transcript files from the supplied pack, found all private media in the already-local ignored folder, and verified all eight asset hashes. Added privacy ignore rules, a separate locked analysis environment, official Whisper licence gate, transcript evaluator, and verification report. Pre-change `swift test` passed 65/65 and the release build passed.

### Gate result
Official Whisper `turbo` assistive ASR found material candidate/audio discrepancies, most clearly BHM02 singular `prediction` versus spoken `predictions`, screenshot typo `does` versus spoken `dose`, likely inserted `you`, and a possible spoken `The`. BHM01 has lower-confidence `thick/fit` and article ambiguity. The authoritative render is stopped pending operator confirmation as TASK_RB-006 requires.

### Safety state
No renderer request was made, no human target was used as conditioning, no model/settings were tuned, no renderer environment or identity changed, private assets remain uncommitted/ignored, and RB-007 was not begun.

---

## 2026-08-08 — RB-006 — Birmingham untuned baseline completed

### Summary
Applied the operator-confirmed authoritative transcript decisions, including performed opening/final `Hah!`; implemented the neutral qualification manifest/harness and model-free leakage/provenance tests; made 18 persistent-session cross-holdout calls; measured all human, generated, and supplied external-benchmark audio; and created identified raw plus gain-only level-matched audition bundles and JSON/Markdown reports. No renderer was tuned and RB-007 was not begun.

### Evidence result
All 18 renderer files pass common WAV validation. Qwen produced full-duration low-ASR-error fixed-seed-repeatable output. Chatterbox produced complete-looking, variable outputs with substantial latency variance. VoxCPM2 severely truncated all six long-form calls; the planned outputs were preserved rather than rerun or selected. Official licence-gated Whisper supplied assistive WER/CER only. Speaker similarity and automated accent score are explicitly unavailable, and no subjective winner was created.

### Architecture
Added `RB006Qualification` and `rb006-qualification` without changing `RendererBenchCore` or any pinned renderer identity. The harness validates hashes and cross-holdout roles, opens one persistent model session per renderer, and writes normal authoritative run evidence. The isolated `Analysis/RB006` project performs signal/ASR analysis and derived audition/report construction without entering ordinary Swift tests.

### Verification and handoff
Pre-change regression was 65/65 tests plus release build. Final regression passed 79/79 tests and the release build; Python compilation and the 18-request/result/bundle acceptance audit also passed. RB-006 adds all 14 required model-free test concerns. Detailed evidence is ignored beneath `BenchData/qualifications/RB006-Birmingham-Baseline`; the project-facing record is `docs/benchmarks/RB006_BIRMINGHAM_BASELINE.md`, with current design, issues, and roadmap in `PROJECT_HANDOVER.md` and reusable techniques in `KEY_FINDINGS.md`.

---

## 2026-08-09 — RB-007 — Timing Repair Control

### Summary
Froze and hashed all 212 RB-006 evidence files, implemented additive performed-span/eligibility/provenance models and a system Core Audio time-stretch executable, created nine guarded post-generation timing derivatives, measured and transcribed original/repaired pairs, and built paired identified raw-level plus attenuation-only level-matched bundles. No renderer request, model setting change, new conditioning, winner, Actor Model, or later milestone occurred.

### Eligibility and evidence
The shared method measured BHM01/BHM02 oracle performed spans at 28.773/29.589 seconds. Fixed gates were transcript coverage ≥0.80, WER ≤0.35, and time scale 0.85–1.20. All six Qwen calls, one Chatterbox call, and two BHM02-target ElevenLabs calls qualified. All six VoxCPM2 calls failed completeness; five Chatterbox and two BHM01-target ElevenLabs calls were out of range. Every accepted repair landed within 50 ms. Qwen and ElevenLabs WER remained unchanged; the Chatterbox pair moved from 0.090 to 0.104.

### DSP and rejected path
`AVAudioUnitTimePitch` ran through `AVAudioEngine` offline manual rendering on macOS 26.5.1, pitch 0 cents, performed region only, preserved head/tail, with no requested gain, EQ, dynamics, denoise, dereverb, formant, pause, phrase, or spectral change. A unity-rate control found direct AVFoundation MP3 decoding attenuated the supplied market files by about 3 dB. Those two attempts were rejected and retained; accepted ElevenLabs repairs use frozen RB-006 resample/channel-only PCM copies with original MP3 hashes retained as authority.

### Architecture and tests
Added `RB007TimingRepair`, `rb007-time-repair`, `Analysis/RB007`, six combined model-free tests covering all required concerns, `docs/benchmarks/RB007_TIMING_REPAIR.md`, and updated project documentation. `RendererBenchCore` and all renderers remain unchanged. One pre-change full-suite run exposed the existing timeout-restart test's 0.2-second process-launch margin as flaky under concurrent load; raising it to 0.5 seconds still remains far below its scripted 2-second hang. Final regression passed 85/85 tests and the release build; Python compilation, JSON/bundle checks, duration tolerances, provenance, and the 212-file RB-006 frozen-source audit passed.

### Interpretation boundary
The operator must judge whether repaired files feel less rushed, whether push remains, whether identity/Birmingham character survive, whether stretch artefacts are audible, whether performance improves, and whether `Hah!` remains semantically wrong. The engineering report does not answer these or select a winner.
