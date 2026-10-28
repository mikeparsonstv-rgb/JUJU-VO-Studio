# TASK_RB-004 — Integrate VoxCPM2 as the Second Real Renderer

## Milestone

**RB-004**

## Objective

Integrate **VoxCPM2** as the second operational renderer and use it to prove that the renderer-bench architecture created in RB-001 through RB-003 is genuinely renderer-independent.

The central question is not merely:

> Can VoxCPM2 render speech?

It is:

> Can a substantially different TTS architecture be integrated, measured, persisted and compared without changing the common bench design built around Qwen?

RB-004 should end with the first genuine same-input, same-reference **Qwen3-TTS vs VoxCPM2** evidence.

Do **not** add a third real renderer in this milestone.

---

# 1. Read before coding

Read, in this order:

1. `README.md`
2. `BUILD_BRIEF.md`
3. `DECISIONS.md`
4. `BENCHMARK_PLAN.md`
5. current `PROJECT_HANDOVER.md`
6. `KEY_FINDINGS.md`
7. `CODEX_LOG.md`
8. `docs/licensing/QWEN3_TTS_LICENSE_CHECK.md`
9. `docs/renderers/qwen3.md`
10. `docs/benchmarks/RB003_CONTROLLED_BACKENDS.md`
11. this task

Preserve all governing decisions from RB-001 to RB-003.

In particular:

- maximum five active renderer slots remains unchanged
- active IDs remain `qwen3`, `voxcpm2`, `chatterbox`, `moss`, `microsoft`
- `mock` remains test-only
- Swift core remains renderer-neutral
- engine-specific runtime logic remains behind adapters/workers
- no renderer-specific branches may be added to the common runner
- common WAV validation remains mandatory
- ordinary `swift test` must remain model-free and download-free

---

# 2. Current primary-source expectations

Treat these as starting facts to verify, not as permission to skip the licence/runtime checks.

Official VoxCPM2 currently documents:

- official repository: `OpenBMB/VoxCPM`
- official model: `openbmb/VoxCPM2`
- model size: approximately 2B parameters
- 30 supported languages
- voice cloning
- controllable cloning
- continuation / “Ultimate Cloning” using reference audio + transcript
- voice design
- streaming API
- 48 kHz output
- Apache-2.0 code and model licensing

Official upstream documentation is CUDA-oriented.

For Apple Silicon, a current MLX conversion exists:

- `mlx-community/VoxCPM2-bf16`
- Apache-2.0 metadata
- full-precision BF16 conversion of `openbmb/VoxCPM2`
- MLX / `mlx-audio` runtime
- voice cloning and voice-design support
- 48 kHz output

RB-004 should prefer the **BF16 MLX conversion** for the production comparison on the Mac, because the goal is quality-faithful Apple-Silicon execution rather than minimum model size.

Do not use the 8-bit or 4-bit conversion as the primary RB-004 renderer unless the BF16 path is genuinely blocked and the change is explicitly documented for review.

---

# 3. Licence gate — required before installation

Verify exact terms for all components actually used:

1. `OpenBMB/VoxCPM` source
2. official `openbmb/VoxCPM2` weights/model card
3. `mlx-community/VoxCPM2-bf16`
4. `mlx-audio`
5. any other required model/runtime asset

Create:

```text
docs/licensing/VOXCPM2_LICENSE_CHECK.md
```

Record at minimum:

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
relationship to upstream model
date checked
```

### Gate

If the actual runtime/model combination fails the project's open-core rule:

**STOP RB-004.**

Do not silently substitute a different model or closed service.

---

# 4. Renderer identity versus runtime identity

The active renderer remains:

```text
renderer_id = voxcpm2
display_name = VoxCPM2
```

But results must record the exact runtime flavour.

For the preferred path this should make clear that the tested renderer is conceptually:

```text
upstream model:
openbmb/VoxCPM2

Apple Silicon runtime/model conversion:
mlx-community/VoxCPM2-bf16

runtime:
mlx-audio / MLX
```

Do not pretend the MLX conversion is byte-identical execution of the upstream PyTorch/CUDA implementation.

Historical evidence must preserve both:

- **model lineage**
- **runtime/conversion identity**

---

# 5. Apple Silicon runtime strategy

Primary target:

```text
Mac Studio M1 Ultra
macOS 26
Apple Silicon
MLX
BF16 VoxCPM2 conversion
```

Preferred architecture:

```text
RendererBenchCore
      ↓
VoxCPM2RendererAdapter
      ↓
persistent VoxCPM2 worker
      ↓
isolated Python environment
      ↓
mlx-audio + MLX
      ↓
mlx-community/VoxCPM2-bf16
```

Do not import Python/MLX directly into the Swift core.

Do not share Qwen's Python environment.

Suggested isolated locations:

```text
.renderer-envs/voxcpm2
.renderer-models/voxcpm2
```

Both should remain ignored and configurable.

---

# 6. Prove renderer independence

This milestone must actively test the existing abstractions.

Before adding or changing a common type, ask:

> Is this genuinely a renderer-neutral concept, or am I changing the core merely because VoxCPM works differently from Qwen?

Preferred outcome:

- new adapter
- new worker
- new setup/smoke scripts
- renderer-specific metadata stored through existing structured settings/environment fields
- minimal or zero changes to common runner logic

Any required common-core change must be documented in `DECISIONS.md` and justified as a general need for future renderers, not a VoxCPM convenience.

---

# 7. Persistent worker

Implement VoxCPM2 using the persistent lifecycle pattern proven in RB-003.

At minimum:

```text
launch
health
load
render
render
...
shutdown
```

Use the same conceptual worker states where applicable:

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

The protocol does not need to be source-identical to the Qwen worker, but equivalent concepts should behave consistently.

Do not copy Qwen implementation blindly where MLX requires different behaviour.

---

# 8. Worker protocol

Use versioned JSON messaging over stdin/stdout unless a genuine technical blocker is discovered.

At minimum support:

### `health`

Return:

- Python version
- MLX version
- mlx-audio version
- model presence
- exact model revision
- architecture/backend
- whether Apple GPU/Metal execution is available
- worker state
- whether render can be attempted

### `load`

Load the exact BF16 model once and return:

- load success/failure
- model ID/revision
- upstream model lineage
- load duration
- memory evidence where practical
- actual backend/runtime

### `render`

Inputs should support:

- text
- reference audio
- exact reference transcript where available
- renderer settings
- output path
- optional seed if the implementation genuinely supports it

Output should report:

- success
- output path
- sample rate
- audio duration
- generation duration
- model/runtime metadata
- warnings
- actual settings used

### `shutdown`

Graceful process termination.

stdout remains protocol-only.
Diagnostics go to stderr.

---

# 9. Clone mode for fair comparison

For the first Qwen/VoxCPM comparison, use VoxCPM2's highest-fidelity reference-audio-plus-transcript path where the runtime exposes it correctly.

Upstream terminology may describe this as continuation or “Ultimate Cloning.”

Conceptually, for C01:

```text
reference audio
+
exact reference transcript
+
new text
↓
VoxCPM2 cloned speech
```

This is the closest comparison to the Qwen Base ICL clone path established in RB-002/RB-003.

Do not use voice design as the primary C01 path.

Do not add style instructions to the baseline C01 render.

---

# 10. Capability declaration

Update the `voxcpm2` descriptor only after the exact runtime is verified.

Capabilities that upstream VoxCPM2 currently claims include:

- multilingual TTS
- voice cloning
- reference-audio + transcript cloning/continuation
- controllable cloning / style guidance
- voice design
- streaming

However:

**declare only what the installed MLX runtime actually exposes and what RB-004 verifies.**

Family-level capability claims are not enough.

If `mlx-audio` does not expose an upstream feature, mark that capability false for this tested runtime.

Keep renderer capability truth more important than marketing completeness.

---

# 11. Stable local benchmark reference identity

RB-003 intentionally did not commit ambiguous/private voice material.

RB-004 should establish a repeatable **local benchmark reference identity** without weakening rights discipline.

Create support for a local reference asset such as:

```text
reference-001
```

Preferred structure:

```text
BenchAssets/references/reference-001/
  metadata.json
```

The actual WAV may remain outside the repository if it is private/operator-owned.

Use a gitignored local mapping/config, for example:

```text
BenchAssets/local-assets.json
```

or another clean solution.

Committed metadata should be able to preserve:

```text
asset_id
display_name
language
speaker_description
transcript
rights_status
redistribution_permitted
audio_committed
notes
```

Local/private mapping can provide:

```text
asset_id
absolute/local path
```

Rules:

- never commit client/talent/celebrity/private recordings accidentally
- do not weaken the catalogue's rights checks
- Qwen and VoxCPM must use the **same reference audio and exact transcript** for comparison
- result metadata should preserve `reference_asset_id`
- result metadata may preserve source path according to existing project privacy rules

---

# 12. Benchmark cases

Use the stable RB-003 definitions:

### A01 — Neutral commercial read

Use exactly the existing stable text.

Purpose:
- baseline speech generation
- throughput/timing

### C01 — Clone / neutral

Use exactly the existing stable text.

Purpose:
- baseline cloning comparison
- later identity/naturalness listening

Do not casually edit either benchmark definition.

For RB-004, both Qwen and VoxCPM2 should render these cases from the same reference identity.

---

# 13. First genuine renderer comparison

Produce the first controlled two-renderer evidence:

```text
Qwen3-TTS
vs
VoxCPM2
```

Keep constant:

- A01/C01 text
- reference asset
- exact transcript
- language
- test machine
- output validation rules

Record each renderer's own appropriate/default generation settings rather than forcing meaningless parameter equivalence.

The comparison should clearly distinguish:

### Comparable
- successful generation
- output validity
- output duration
- generation time
- real-time factor
- clone/reference usage
- language
- sample rate
- subjective listening later

### Not directly equivalent
- model-specific guidance values
- diffusion steps vs Qwen generation internals
- seeds unless determinism semantics are proven equivalent
- cold-load architecture details

Do not manufacture a fake apples-to-apples parameter mapping.

---

# 14. Timing

For VoxCPM2 capture, where measurable:

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
```

Do not mislabel streaming/first-audio latency if not explicitly measured.

Because VoxCPM2 outputs 48 kHz according to upstream documentation, persist the actual validated output sample rate rather than assuming it.

---

# 15. Quality-first BF16 policy

RB-004 is establishing a quality benchmark, not optimising deployment size.

Primary model:

```text
mlx-community/VoxCPM2-bf16
```

Do not automatically move to:

```text
VoxCPM2-8bit
VoxCPM2-4bit
```

If BF16 is too slow or fails technically, report measured evidence.

A later milestone may compare quantisation quality/speed if that becomes useful.

---

# 16. Setup

Create a reproducible setup path, for example:

```text
scripts/setup-voxcpm2.sh
```

Requirements:

- isolated environment
- no global Python installs
- exact package versions/revisions recorded
- exact model revision pinned
- configurable model/cache location
- no silent fallback to a different model
- repeated setup is sensible/non-destructive
- model weights are not bundled into Swift package
- setup makes network/download actions obvious

Do not modify Qwen's environment.

---

# 17. Smoke automation

Add an opt-in real-model path such as:

```text
scripts/smoke-voxcpm2.sh
```

It should:

1. verify environment
2. health-check worker
3. launch persistent worker
4. load model once
5. render A01
6. render C01
7. validate outputs
8. report result paths/timings
9. shut down cleanly

Then add a controlled comparison script/harness, for example:

```text
scripts/compare-qwen-voxcpm2.sh
```

It should use the same local reference asset for both.

Do not add generic five-renderer Render All yet.

---

# 18. Output handling

Final benchmark audio must be written under bench-controlled run directories:

```text
BenchData/runs/<test-id>/<run-id>/<renderer-id>/
```

Do not leave the authoritative result only in a worker cache/output folder.

Common runner validation must independently verify VoxCPM2 output.

Do not bypass common validation because MLX returns an in-memory waveform.

---

# 19. Tests

Retain all existing tests.

Add model-free unit tests covering at least:

1. VoxCPM worker request encoding
2. VoxCPM worker response decoding
3. worker protocol framing
4. persistent state transitions
5. health unavailable state
6. model load state
7. multiple renders reuse one loaded model logically
8. graceful shutdown
9. malformed response handling
10. unexpected worker exit handling
11. timeout handling
12. model/runtime lineage metadata persistence
13. VoxCPM descriptor/capability snapshot persistence
14. reference asset ID persistence
15. common WAV validation on 48 kHz VoxCPM fixture/output
16. two VoxCPM runs do not overwrite one another
17. two different renderer IDs can store results under the same canonical benchmark without collision
18. comparison harness definition/load test if appropriate

Use fake workers/fixtures for ordinary unit tests.

`swift test` must not load MLX or model weights.

---

# 20. Real integration evidence

On the target Mac, run at minimum:

### VoxCPM2 persistent session

- health
- load once
- A01
- C01
- one additional warm render
- shutdown

Record:

- Python/runtime versions
- MLX version
- mlx-audio version
- exact BF16 model revision
- model load time
- generation time
- validated output duration
- validated sample rate
- real-time factor
- warnings/errors
- actual backend

### Qwen/VoxCPM comparison

Using the exact same reference asset/transcript:

- Qwen A01
- VoxCPM2 A01
- Qwen C01
- VoxCPM2 C01

Preserve all four results.

Do not yet assign winner scores from one listening pass.

---

# 21. Architecture audit

At the end of RB-004 explicitly report:

### Common-core changes required for VoxCPM2
List them.

Ideal result:

```text
none
```

If changes were required:

- state each change
- explain why it is renderer-neutral
- identify whether it benefits future Chatterbox/MOSS/Microsoft integration
- update `DECISIONS.md` only if it is a genuine architectural decision

This audit is a major acceptance condition because RB-004 is testing renderer independence.

---

# 22. Documentation

Create/update:

```text
docs/licensing/VOXCPM2_LICENSE_CHECK.md
docs/renderers/voxcpm2.md
docs/benchmarks/RB004_QWEN_VOXCPM2.md
KEY_FINDINGS.md
PROJECT_HANDOVER.md
CODEX_LOG.md
```

Only reusable architectural discoveries belong in `KEY_FINDINGS.md`.

Document MLX conversion/runtime identity clearly.

---

# 23. Do not do

Do not:

- integrate Chatterbox
- integrate MOSS
- configure Microsoft/Azure
- add ElevenLabs
- add a sixth renderer
- replace Qwen
- add VoxCPM quantised variants to the active renderer list
- fine-tune VoxCPM2
- implement LoRA
- build voice-design UI
- build controllable-cloning pills/UI
- implement Actor Model logic
- implement Exact / Adjust / Interpret
- implement session matching
- implement acoustic-presence synthesis
- build waveform UI
- build blind mode
- add ratings UI
- add a database
- implement generic Render All across all five
- introduce a local HTTP service unless child-process IPC genuinely fails
- modify stable A01/C01 text without reporting

---

# 24. Acceptance criteria

RB-004 is complete when:

1. Exact licences/revisions for the actual VoxCPM2 runtime stack are documented and pass the open-core gate.
2. VoxCPM2 exists behind its own isolated adapter/worker environment.
3. The preferred BF16 MLX VoxCPM2 model runs on the target Apple Silicon Mac.
4. The model loads once and is reused for multiple renders.
5. `health`, `load`, `render`, and `shutdown` operate cleanly.
6. A01 and C01 produce real valid speech through the common runner.
7. VoxCPM2 output is independently validated by the existing common WAV validator.
8. Exact model lineage and runtime conversion identity are persisted.
9. A stable local benchmark reference identity exists without committing unapproved voice material.
10. Qwen and VoxCPM2 render A01/C01 using the same reference audio/transcript.
11. First controlled two-renderer evidence is persisted.
12. Timing metadata is honest and interpretable.
13. Existing Qwen path still operates.
14. All previous unit tests still pass.
15. New RB-004 unit tests pass.
16. The architecture audit explicitly reports common-core changes.
17. No third real renderer has been integrated.
18. `PROJECT_HANDOVER.md`, `CODEX_LOG.md`, renderer docs and benchmark evidence are updated.
19. RB-005 has not begun.

---

# 25. Deliver back

When finished, report:

1. concise summary
2. licence-gate result
3. exact upstream VoxCPM2 revision
4. exact MLX BF16 revision
5. exact runtime/package versions
6. project tree changes
7. worker lifecycle/protocol summary
8. reference asset identity/status
9. test command + result summary
10. VoxCPM2 load/generation timings
11. output format/sample rate
12. Qwen A01/C01 result locations
13. VoxCPM2 A01/C01 result locations
14. first listening observations, clearly labelled subjective
15. common-core changes required
16. capability corrections discovered
17. known limitations
18. proposed RB-005

Do not begin RB-005 without instruction.
