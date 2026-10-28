# TASK_RB-005 — Integrate Chatterbox Multilingual V3 as the Third Real Renderer

## Milestone

**RB-005**

## Objective

Integrate **Chatterbox Multilingual V3** as the third operational renderer and produce the first controlled three-way renderer comparison:

```text
Qwen3-TTS
vs
VoxCPM2
vs
Chatterbox Multilingual V3
```

RB-005 is about completing the first meaningful three-renderer shootout while preserving the renderer-neutral architecture proven by RB-004.

Do **not** add MOSS or Microsoft in this milestone.

---

## 1. Read before coding

Read, in this order:

1. `README.md`
2. `BUILD_BRIEF.md`
3. `DECISIONS.md`
4. `BENCHMARK_PLAN.md`
5. current `PROJECT_HANDOVER.md`
6. `KEY_FINDINGS.md`
7. `CODEX_LOG.md`
8. Qwen licence/renderer docs
9. VoxCPM2 licence/renderer docs
10. `docs/benchmarks/RB003_CONTROLLED_BACKENDS.md`
11. `docs/benchmarks/RB004_QWEN_VOXCPM2.md`
12. this task

Preserve all RB-001 through RB-004 architecture.

The five active renderer IDs remain:

```text
qwen3
voxcpm2
chatterbox
moss
microsoft
```

After RB-005:

- qwen3 = operational
- voxcpm2 = operational
- chatterbox = operational
- moss = unavailable placeholder
- microsoft = unavailable placeholder

`mock` remains test-only and outside the five active slots.

---

## 2. Target Chatterbox model

Primary renderer for RB-005:

```text
Chatterbox Multilingual V3
```

Official upstream currently describes it as:

- 500M parameters
- 23+ languages
- zero-shot voice cloning
- improved speaker similarity versus earlier multilingual releases
- reduced hallucination/repetition
- improved natural/conversational delivery
- cross-language voice cloning
- MIT licensed
- built-in PerTh watermarking
- loadable through `ChatterboxMultilingualTTS.from_pretrained(..., t3_model="v3")`
- upstream code documents `cuda`, `cpu`, and `mps` as device choices

Do not integrate Chatterbox Turbo, Nano, the legacy multilingual V2 checkpoint, or a Single Language Pack as the primary RB-005 renderer.

Those can remain future research options.

---

## 3. Licence/provenance gate

Before installing or integrating, verify exact licences and revisions for all actual components used:

1. official `resemble-ai/chatterbox` source
2. exact `ResembleAI/chatterbox` model snapshot/assets used by Multilingual V3
3. PerTh/watermark dependency/assets
4. any required tokenizer/voice encoder/decoder checkpoints
5. any other runtime asset required by the pinned V3 path

Create:

```text
docs/licensing/CHATTERBOX_V3_LICENSE_CHECK.md
```

Record:

```text
component
repository/model ID
exact revision/commit
source URL
licence
commercial use permitted?
modification permitted?
redistribution permitted?
attribution / notice obligations
date checked
```

If any required code/weight component does not satisfy the project's open-core commercial-use rule, **STOP RB-005**.

Do not silently fall back to another Chatterbox variant.

---

## 4. Exact runtime identity

Persist the tested identity clearly.

At minimum capture:

```text
renderer_id = chatterbox
renderer_family = Chatterbox
variant = Multilingual V3
source commit
model repository
model revision
t3_model = v3
Python version
PyTorch version
torchaudio version
Chatterbox package/source version
PerTh version
actual device/backend
```

Do not allow historical evidence to become ambiguous between original English Chatterbox, Multilingual V2, Multilingual V3, Turbo, Nano, or Single Language Pack.

---

## 5. Apple Silicon path

Primary target:

```text
Mac Studio M1 Ultra
macOS 26
Apple Silicon
PyTorch MPS
```

The current official upstream README explicitly documents `mps` as a supported device option for the Chatterbox/Multilingual path.

Use the official V3 PyTorch path first.

Preferred architecture:

```text
RendererBenchCore
      ↓
ChatterboxRendererAdapter
      ↓
persistent Chatterbox worker
      ↓
isolated Python environment
      ↓
Chatterbox Multilingual V3
      ↓
PyTorch MPS
```

Do not share Qwen or VoxCPM environments.

Suggested paths:

```text
.renderer-envs/chatterbox
.renderer-models/chatterbox
```

Do not add an MLX conversion unless the official MPS path is genuinely blocked and a later explicit decision authorizes it.

---

## 6. Prove architecture remains renderer-independent

RB-004 required zero changes under `Sources/RendererBenchCore`.

RB-005 should aim for the same.

Before changing common code, ask:

> Is this genuinely a general renderer-neutral need, or am I changing the core because Chatterbox has a different API?

Ideal architecture audit result:

```text
Common-core changes required: none
```

If a common change is genuinely necessary:

- document it
- justify why it benefits future MOSS/Microsoft integration
- do not add Chatterbox-specific fields to shared schemas

---

## 7. Persistent worker lifecycle

Use the established persistent pattern:

```text
launch
health
load
render
render
...
shutdown
```

Use equivalent lifecycle states to Qwen/VoxCPM2 where appropriate:

```text
starting
ready_unloaded
loading
ready_loaded
rendering
failed
shutting_down
stopped
```

Model and conditioning components should load once per worker session and be reused.

Do not reload the model for each render.

---

## 8. Worker protocol

Use versioned newline-delimited JSON over stdin/stdout.

Support at minimum `health`, `load`, `render`, and `shutdown`.

`health` should report environment/model presence, exact V3 identity, PerTh availability, requested/actual backend, MPS availability, worker state, and render readiness.

`load` should load Chatterbox Multilingual V3 once and report exact model identity, load duration, actual backend/device, sample rate if known, watermarking state, and warnings.

`render` should accept text, language/language_id, reference audio, renderer-native settings, and output path; return output path, generation duration, actual sample rate, model/version metadata, actual settings, watermarking state, and warnings/errors.

stdout remains protocol-only. Diagnostics remain on stderr.

---

## 9. Voice-clone baseline

For A01/C01 use the V3 multilingual zero-shot voice-cloning path with the same reference asset already used for Qwen and VoxCPM2.

Conceptually:

```text
reference audio
+
new text
+
language_id
↓
Chatterbox Multilingual V3
```

Chatterbox does not require the same transcript-conditioned clone mechanism as Qwen/VoxCPM2, so do not manufacture a fake transcript parameter if the API does not use one.

Persist:

```text
reference_asset_id
reference_audio used
reference transcript available? yes/no
reference transcript used by renderer? yes/no
clone mode
```

---

## 10. Chatterbox controls

The Chatterbox family exposes renderer-native controls including CFG and exaggeration/intensity.

For the baseline three-way shootout:

- use official/default V3 settings unless there is a clear technical reason not to
- record exact values
- do not map Qwen/Vox settings into Chatterbox concepts
- do not yet treat `exaggeration` as our renderer-independent performance control

---

## 11. Watermarking

Chatterbox V3 embeds PerTh watermarking in generated audio.

Treat this as renderer behaviour that must be documented, not removed.

Persist watermark expectation/system/enabled state/version where available.

If upstream allows watermark disabling, do not disable it merely for benchmark convenience unless necessary for a controlled technical test and explicitly recorded.

---

## 12. Language handling

Multilingual V3 supports 23+ languages including English, French, German, Dutch, Italian, Spanish, Portuguese, Danish, Finnish, Norwegian, Swedish, Polish, Greek, Turkish, Arabic, Hebrew, Hindi, Japanese, Korean, Malay, Russian, Swahili, and Chinese.

For RB-005, use the same English A01/C01 benchmark as Qwen and VoxCPM2.

Do not start broad multilingual evaluation yet.

---

## 13. Reference identity

Continue using the stable `reference-001` mechanism from RB-004 for architecture/timing comparison.

Do not delay Chatterbox integration waiting for the eventual rights-cleared human reference.

Preserve the warning that `reference-001` is not yet a valid human clone-quality benchmark.

---

## 14. Stable benchmark cases

Use the existing unchanged:

- A01 — Neutral commercial read
- C01 — Clone / neutral

Do not edit their texts.

Run all three operational renderers against the same cases.

---

## 15. Three-way comparison

Create the first controlled comparison:

```text
Qwen3-TTS
VoxCPM2
Chatterbox Multilingual V3
```

Keep constant where meaningful:

- benchmark text
- `reference-001`
- language
- test machine
- common persistence
- common WAV validation

Do not force equivalence where renderer architectures differ.

Record common evidence such as success/failure, output duration, sample rate, generation time, realtime factor, load time, reference identity, language, and cold/warm state.

Record renderer-native settings separately.

---

## 16. Timing

For Chatterbox capture:

```text
worker_startup_seconds
python_import_seconds
model_load_seconds
generation_seconds
adapter_total_seconds
output_duration_seconds
realtime_factor
cold_start
worker_reused
model_reused
requested_backend
actual_backend
```

Run at minimum:

- first/cold generation after load
- C01 warm generation
- one additional A01 warm generation

Do not call generation latency first-audio latency.

---

## 17. Setup

Create:

```text
scripts/setup-chatterbox.sh
```

Requirements:

- isolated environment
- no global Python installs
- exact source/model revisions pinned
- model cache configurable
- no silent V2/Turbo/Nano fallback
- repeated setup safe
- network/download actions understandable
- model weights not bundled into Swift package

Document any macOS-specific dependency fixes rather than hiding them.

---

## 18. Smoke automation

Create:

```text
scripts/smoke-chatterbox.sh
```

It should resolve the reference asset, health-check, launch worker, load V3, render A01, render C01, render one extra warm case, validate outputs, report timings/result paths, and shut down cleanly.

Also create or extend:

```text
scripts/compare-qwen-voxcpm2-chatterbox.sh
```

Do not implement a generic five-renderer Render All UI yet.

---

## 19. Output validation

Use existing common WAV validation.

Final authoritative outputs belong under:

```text
BenchData/runs/<test-id>/<run-id>/chatterbox/
```

Persist validated sample rate/duration from the actual container.

---

## 20. Tests

Retain all 45 existing tests.

Add model-free tests covering at least:

1. Chatterbox worker request encoding
2. worker response decoding
3. protocol framing
4. health unavailable state
5. persistent lifecycle transitions
6. load state
7. multiple renders reuse loaded model logically
8. graceful shutdown
9. malformed response handling
10. EOF/unexpected-exit handling
11. timeout handling
12. exact V3 identity persists
13. legacy V2 cannot be silently selected
14. Chatterbox capability snapshot persists
15. CFG/exaggeration settings persist
16. reference asset ID persists
17. language ID persists
18. watermark metadata persists
19. common WAV validation accepts valid Chatterbox output
20. repeated Chatterbox runs do not overwrite
21. three renderer IDs can store canonical benchmark evidence without collision
22. unsupported generic direction is rejected rather than silently ignored

`swift test` must remain model-free.

---

## 21. Real integration evidence

On the target M1 Ultra run a persistent Chatterbox session:

- health
- load once
- A01 cold
- C01 warm
- A01 warm
- shutdown

Then run the three-way comparison with the same `reference-001`:

- Qwen A01
- VoxCPM2 A01
- Chatterbox A01
- Qwen C01
- VoxCPM2 C01
- Chatterbox C01

Preserve all six outputs and result metadata.

No invented subjective ranking.

---

## 22. First listening bundle

Create a simple human-audition bundle or manifest containing the six controlled outputs:

```text
A01_qwen.wav
A01_voxcpm2.wav
A01_chatterbox.wav

C01_qwen.wav
C01_voxcpm2.wav
C01_chatterbox.wav
```

This is not blind mode yet.

Preserve provenance.

---

## 23. Architecture audit

Explicitly report:

```text
Common-core changes required for Chatterbox:
```

Ideal:

```text
none
```

If not none, justify each change as renderer-neutral.

---

## 24. Documentation

Create/update:

```text
docs/licensing/CHATTERBOX_V3_LICENSE_CHECK.md
docs/renderers/chatterbox.md
docs/benchmarks/RB005_THREE_WAY.md
KEY_FINDINGS.md
PROJECT_HANDOVER.md
CODEX_LOG.md
```

Only reusable findings go into `KEY_FINDINGS.md`.

---

## 25. Do not do

Do not:

- integrate MOSS
- configure Microsoft/Azure
- add ElevenLabs
- add Chatterbox Turbo/Nano as additional active renderers
- use Multilingual V2
- use a Single Language Pack as the primary renderer
- enlarge the five-renderer set
- fine-tune Chatterbox
- remove watermarking merely for convenience
- build Actor Model logic
- implement Exact/Adjust/Interpret
- build Brand Master
- build Teach Pronunciation
- build Brand Lexicon
- build brand-style learning
- build session matching
- build acoustic-presence synthesis
- build waveform UI
- build blind mode
- add ratings UI
- add database
- implement generic Render All across five engines
- change A01/C01 text

---

## 26. Acceptance criteria

RB-005 is complete when:

1. Chatterbox Multilingual V3 exact code/model/runtime licences and revisions are documented and pass the open-core gate.
2. Chatterbox has its own isolated environment.
3. The exact V3 path runs on the target M1 Ultra.
4. MPS is used if it works correctly; any fallback is explicit.
5. Persistent worker lifecycle works.
6. Model loads once and is reused.
7. A01 and C01 render real valid speech.
8. Common WAV validation remains the authority.
9. Renderer-native controls/settings are persisted honestly.
10. PerTh watermark behaviour is documented/persisted.
11. Qwen and VoxCPM2 remain operational.
12. All three renderers use the same `reference-001` for comparison.
13. Controlled A01/C01 three-way evidence exists.
14. A simple human-audition bundle/manifest exists.
15. All prior tests still pass.
16. New RB-005 tests pass.
17. Architecture audit explicitly reports common-core changes.
18. MOSS and Microsoft remain untouched placeholders.
19. `PROJECT_HANDOVER.md`, `KEY_FINDINGS.md`, renderer/licence docs and `CODEX_LOG.md` are updated.
20. RB-006 has not begun.

---

## 27. Deliver back

When finished, report:

1. concise summary
2. licence-gate result
3. exact Chatterbox source revision
4. exact V3 model revision/assets
5. runtime/package versions
6. actual Apple-Silicon backend
7. project tree changes
8. persistent worker lifecycle summary
9. Chatterbox capability truth
10. test command + result count
11. import/load/generation timings
12. output format/sample rate
13. watermark behaviour
14. A01 three-way result locations
15. C01 three-way result locations
16. human-audition bundle location
17. common-core changes required
18. known limitations
19. proposed RB-006

Do not begin RB-006 without instruction.
