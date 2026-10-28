# TalkBack / CuePitch Renderer Bench — Project Docs

Working project name: **TalkBack / CuePitch Renderer Bench**  
Status: **v0.1 planning package**  
Purpose: Build a small, rigorous test bed for comparing a maximum of five voice renderers against real production requirements.

This folder is intended to be the shared source of truth between:
- Product / editorial direction
- Architecture and benchmark design
- Codex implementation

## Read order for Codex
1. `BUILD_BRIEF.md`
2. `DECISIONS.md`
3. `BENCHMARK_PLAN.md`
4. `TASK_RB-001.md`
5. `CODEX_LOG.md`

## Ground rule
This is **not yet the product**. It is the evidence-gathering bench that will tell us which renderer architectures deserve to underpin the future performance-direction system.

Do not add models simply because they are interesting. The active bench is capped at five.

## RB-001 implementation

The bench skeleton is an Xcode 26-compatible Swift 6.2 package targeting macOS 26. It contains a reusable core library, a deliberately plain command-line interface, and automated tests. Open `Package.swift` in Xcode 26 or use Swift Package Manager from Terminal.

```sh
swift test
swift run renderer-bench list
swift run renderer-bench render --test-id A01 --language en-GB \
  --direction "Neutral commercial read" \
  --script "A deterministic renderer bench check."
```

The working RB-001 adapter is `mock`; it is marked as a test fixture and does not consume one of the five active renderer slots. By default, run artifacts are written beneath `BenchData/runs/<test-id>/<run-id>/<renderer-id>/`. Override the root with `--data <path>`.

Play a generated fixture with:

```sh
swift run renderer-bench play BenchData/runs/<test-id>/<run-id>/mock/output.wav
```

## RB-002 Qwen3-TTS setup

RB-002 integrates only `Qwen/Qwen3-TTS-12Hz-0.6B-Base` at revision `5d83992436eae1d760afd27aff78a71d676296fc`. Its isolated Python worker and model cache are ignored by source control.

```sh
scripts/setup-qwen3.sh
swift run renderer-bench health qwen3

swift run renderer-bench render \
  --renderer qwen3 \
  --test-id C01 \
  --language en-GB \
  --script "New speech to render." \
  --reference-audio /absolute/path/reference.wav \
  --reference-text "Exact transcript of the reference." \
  --data BenchData
```

The transcript enables Qwen's preferred ICL clone path. Omitting it uses speaker-embedding-only cloning and records a warning. Set `QWEN3_DEVICE=mps` or `QWEN3_DEVICE=cpu` to force a backend; `auto` prefers MPS when PyTorch can access it. No model is downloaded during ordinary `swift test`.

See `docs/renderers/qwen3.md` for the tested environment and `docs/licensing/QWEN3_TTS_LICENSE_CHECK.md` for the licence gate.

## RB-003 persistent Qwen sessions

RB-003 keeps one Python process and one loaded Qwen model alive across a benchmark session. Stable A01 and C01 definitions live in `BenchAssets/benchmarks`. Because no suitably rights-cleared redistributable human recording was available, `BenchAssets/references/catalogue.json` records an explicit blocker and the real-model scripts continue to require an operator-supplied local reference and exact transcript.

Run one persistent smoke session:

```sh
scripts/smoke-qwen3.sh \
  /absolute/path/reference.wav \
  "Exact transcript of the reference." \
  /tmp/RendererBench-Smoke \
  mps
```

Run the controlled explicit MPS-then-CPU comparison:

```sh
scripts/benchmark-qwen3-backends.sh \
  /absolute/path/reference.wav \
  "Exact transcript of the reference." \
  /tmp/RendererBench-Backends
```

Each backend performs health, explicit load, A01, C01, two additional warm A01 renders, WAV validation, and graceful shutdown. Raw requests/results/audio and a session log are retained under the supplied data directory. Backend values are `auto`, `mps`, or `cpu`; persisted results contain both requested and actual backend.

## RB-004 VoxCPM2 MLX BF16

RB-004 adds VoxCPM2 as the second operational renderer through its own isolated environment and persistent worker. It uses only `mlx-community/VoxCPM2-bf16` revision `a7fb80d9056983135a54ca3f71fcc5a637ccddf5`, records the upstream `openbmb/VoxCPM2` lineage, and runs through pinned `mlx-audio 0.4.6` on MLX Metal.

```sh
scripts/setup-voxcpm2.sh
scripts/smoke-voxcpm2.sh \
  /absolute/path/reference.wav \
  "Exact transcript." \
  reference-001 \
  /tmp/RendererBench-VoxCPM2
```

For the controlled two-renderer comparison, copy `BenchAssets/local-assets.example.json` to the gitignored `BenchAssets/local-assets.json`, map `reference-001` to a lawfully authorised local WAV, then run:

```sh
scripts/compare-qwen-voxcpm2.sh reference-001 /tmp/RendererBench-Comparison
```

The comparison uses the stable A01/C01 text and identical reference identity/transcript/language for both renderers, while retaining each engine's meaningful native settings. See `docs/renderers/voxcpm2.md` and `docs/benchmarks/RB004_QWEN_VOXCPM2.md`.

## RB-005 Chatterbox Multilingual V3

RB-005 adds the exact official Chatterbox Multilingual V3 path as the third operational renderer. It uses an independent locked Python environment, an exact local model snapshot, a persistent JSON-lines worker, PyTorch MPS, reference-audio-only zero-shot cloning, and retained PerTh watermarking. V2, Turbo, Nano, CPU fallback, and unofficial conversions are rejected.

```sh
scripts/setup-chatterbox.sh
scripts/smoke-chatterbox.sh reference-001 /tmp/RendererBench-Chatterbox
scripts/compare-qwen-voxcpm2-chatterbox.sh reference-001 /tmp/RendererBench-ThreeWay
```

The comparison creates A01/C01 outputs for all three engines plus a self-contained, non-blind listening bundle. `reference-001` remains a temporary synthetic integration reference; it cannot support clone-fidelity conclusions. See `docs/renderers/chatterbox.md`, `docs/licensing/CHATTERBOX_V3_LICENSE_CHECK.md`, and `docs/benchmarks/RB005_THREE_WAY.md`.

## RB-006 Birmingham untuned baseline

RB-006 is the first private human cross-holdout qualification. BHM01 conditions generation of the withheld BHM02 words, and BHM02 conditions generation of the withheld BHM01 words. Qwen3-TTS, VoxCPM2, and Chatterbox V3 each produced three untuned calls in each direction: 18 authoritative renderer outputs in total.

The operator-confirmed transcripts retain the performed opening/final `Hah!` where present. Private human, ElevenLabs, screenshot, transcript, generated-audio, and measurement evidence remains ignored under `BenchData/qualifications/RB006-Birmingham-Baseline`; only neutral manifests, tooling, tests, and reports are project documents.

```sh
swift test
swift build -c release
```

The authoritative compact report is `docs/benchmarks/RB006_BIRMINGHAM_BASELINE.md`. Detailed local evidence is in `BenchData/qualifications/RB006-Birmingham-Baseline/report`, and identified raw plus gain-only level-matched listening bundles are in its `listening-bundle` directory. Whisper results are assistive intelligibility measurements only; no automated accent score, speaker-verifier result, subjective rating, or winner is claimed. VoxCPM2's severe long-form truncation and Qwen's fixed-seed repeatability are preserved as baseline findings rather than tuned away. This evidence is frozen as the RB-007 source authority.

## RB-007 timing repair control

RB-007 leaves the entire RB-006 tree frozen and creates only post-generation diagnostic derivatives under `BenchData/qualifications/RB007-Timing-Repair`. It measures each target human's performed span—excluding arbitrary head/tail silence—and labels its use everywhere as `oracle_target_performed_span`. No renderer was called or conditioned with target-human timing.

The fixed completeness and 0.85–1.20 time-scale gates admit six Qwen calls, one Chatterbox call, and two supplied ElevenLabs calls. All VoxCPM2 calls remain excluded as incomplete. Five Chatterbox and two ElevenLabs calls are preserved as out-of-range rather than stretched absurdly. The system `AVAudioUnitTimePitch` path changes the performed region only, at zero pitch shift, with no requested gain, EQ, dynamics, denoise, dereverb, formant, pause, phrase, or spectral processing.

See `docs/benchmarks/RB007_TIMING_REPAIR.md`. Identified raw-level and attenuation-only level-matched original/repaired bundles are under `BenchData/qualifications/RB007-Timing-Repair/listening-bundle`. Operator listening must determine whether pace, push, identity, Birmingham character, naturalness, or the overall read improves; RB-007 creates no winner and does not address the semantic intent of `Hah!`.
