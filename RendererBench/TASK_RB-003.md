# TASK_RB-003 — Stabilise Qwen Real-Render Operations

## Milestone

**RB-003**

## Objective

Turn the working Qwen3-TTS integration from RB-002 into a dependable, measurable renderer path.

RB-002 proved that:

- Qwen3-TTS can run on the target Apple Silicon Mac
- the Base checkpoint can render real cloned speech
- the Swift/Python worker boundary is sound
- success/failure persistence works
- output WAV validation works
- both MPS and CPU can execute

RB-003 should now remove avoidable one-shot overhead and make the Qwen path useful as a repeatable benchmark instrument.

The focus is:

1. **persistent worker lifecycle / model reuse**
2. **clean separation of load time vs generation time**
3. **controlled identical-input MPS-versus-CPU measurements**
4. **approved non-private reference assets for repeatable tests**
5. **stronger opt-in smoke/integration automation**

Do **not** add a second real renderer in this milestone.

---

## Before coding

Read, in this order:

1. `README.md`
2. `BUILD_BRIEF.md`
3. `DECISIONS.md`
4. `BENCHMARK_PLAN.md`
5. `PROJECT_HANDOVER.md`
6. `KEY_FINDINGS.md`
7. `CODEX_LOG.md`
8. `docs/licensing/QWEN3_TTS_LICENSE_CHECK.md`
9. `docs/renderers/qwen3.md`
10. this task

Preserve all RB-001 and RB-002 architectural boundaries.

In particular:

- Swift core remains renderer-neutral
- Qwen remains behind the adapter/worker boundary
- Qwen/Python/PyTorch dependencies remain isolated from Swift
- five active renderer slots remain unchanged
- mock remains a test fixture, not an active candidate
- no model-specific conditionals may leak into the common runner
- ordinary `swift test` must not download or load model weights

---

# 1. Persistent worker lifecycle

RB-002 uses a one-shot worker that reloads dependencies/model for every render.

RB-003 should add a **persistent Qwen worker mode** so that:

- Python process can remain alive across multiple renders
- Qwen model can remain loaded in memory
- tokenizer can remain loaded
- repeated benchmark runs avoid full setup/model-load cost
- health/state can be queried while the worker is alive

The worker protocol should remain simple and inspectable.

Preferred shape:

```text
Swift adapter/client
      ↓
persistent child process
      ↓
versioned JSON messages over stdin/stdout
      ↓
Qwen model stays loaded
```

Do not add a network server unless a local child-process protocol proves inadequate.

---

# 2. Worker protocol extension

Extend the protocol cleanly rather than inventing ad hoc commands.

At minimum support:

```text
health
load
render
shutdown
```

A reasonable lifecycle:

```text
launch worker
↓
health
↓
load model
↓
render
↓
render
↓
render
↓
shutdown
```

The worker must still:

- write diagnostics only to stderr
- reserve stdout for machine-readable protocol messages
- validate protocol version
- validate request IDs
- reject unsupported operations explicitly
- avoid silently switching model/checkpoint
- remain pinned to the exact RB-002 model IDs/revisions unless a new brief changes them

---

# 3. Worker states

Expose an explicit renderer-worker state.

Suggested conceptual states:

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

Exact enum naming is up to the implementation.

The Swift client should be able to distinguish:

- Python environment unavailable
- worker process unavailable
- worker alive but model not loaded
- model loaded and ready
- worker failed
- worker timed out

Do not collapse all failures into “renderer unavailable.”

---

# 4. Model reuse

Once loaded, the model should be reused for subsequent renders.

Acceptance behaviour:

- first real render may incur model-load cost
- second and later renders in the same worker lifetime should not reload the checkpoint
- model ID/revision/tokenizer remain identical across renders
- per-run metadata still records the exact model/checkpoint used
- failure of one render should not automatically destroy the worker unless recovery is unsafe

If an unrecoverable exception leaves model state uncertain, terminate and restart cleanly rather than pretending the worker is healthy.

---

# 5. Timing instrumentation

RB-003 must distinguish timing categories honestly.

Capture where possible:

```text
worker_startup_seconds
python_import_seconds
model_load_seconds
render_generation_seconds
adapter_total_seconds
output_duration_seconds
realtime_factor
```

If some categories cannot be isolated reliably, leave them absent/null and document why.

Do not:

- label total elapsed time as model load time
- label generation time as first-audio latency
- invent streaming latency
- mix cold-start and warm-render numbers without marking them

Persist a cold/warm indicator where useful.

Suggested:

```text
render_context:
  worker_reused: true/false
  model_reused: true/false
  cold_start: true/false
```

---

# 6. Controlled MPS-versus-CPU benchmark

RB-002 proved both MPS and CPU execute, but the two observed runs used different text/output durations.

RB-003 should create a **controlled identical-input comparison**.

Use:

- exact same script
- exact same reference audio
- exact same reference transcript
- exact same language
- exact same generation settings
- same checkpoint/tokenizer
- same test machine
- separate explicit backend selection

Run at minimum:

```text
MPS cold render
MPS warm render
CPU cold render
CPU warm render
```

Prefer multiple warm runs if inexpensive enough to expose variance.

Store raw timing evidence.

Do not claim quality equivalence from timing tests.

Do not claim deterministic output equivalence unless proven.

---

# 7. Backend selection

Expose backend selection explicitly for Qwen integration testing.

Suggested values:

```text
auto
mps
cpu
```

Rules:

- `auto` should report what backend was actually selected
- `mps` must fail clearly if MPS is unavailable
- `cpu` must not silently use MPS
- persisted results record requested backend and actual backend

Do not introduce CUDA-specific logic on macOS.

---

# 8. Reference asset catalogue

RB-002 used temporary architecture-only reference audio.

RB-003 should create a small **approved non-private reference asset catalogue** for repeatable engineering tests.

Requirements:

- no celebrity/talent/private production recordings
- no client-confidential assets
- redistribution/use rights must be clear
- reference transcript must be known
- asset provenance/licence must be documented
- audio characteristics must be documented

Create:

```text
BenchAssets/
  references/
    <asset-id>/
      reference.wav
      metadata.json
```

Suggested metadata:

```text
asset_id
display_name
source
licence
redistribution_permitted
language
speaker_description
transcript
sample_rate
channels
duration
notes
date_added
```

If no suitable redistributable human reference asset is available, do not fabricate one.

In that case:

- keep an operator-supplied local reference path
- create the catalogue structure/schema
- document the missing approved asset as an explicit blocker
- do not commit private audio

The project may later add multiple reference voices, but RB-003 needs only one dependable engineering reference.

---

# 9. Benchmark case materialisation

Materialise only what RB-003 needs.

Create stable machine-readable definitions for:

### A01 — Neutral commercial read

Purpose:
- baseline real speech generation
- timing/render throughput

### C01 — Clone / neutral

Purpose:
- baseline clone path
- identity-listening reference later

Keep benchmark text stable once established.

Do not add the full 12-test corpus yet.

A01 and C01 may still share the same Base clone mechanism, but retain distinct benchmark intent.

---

# 10. Smoke / integration automation

Strengthen the opt-in real-model path.

Provide a repeatable command/script that can:

1. health-check Qwen
2. launch worker
3. load model
4. render A01
5. render C01
6. optionally run controlled backend timing comparison
7. validate outputs
8. print concise result locations and timings
9. shut worker down cleanly

Suggested:

```text
scripts/smoke-qwen3.sh
```

and optionally:

```text
scripts/benchmark-qwen3-backends.sh
```

Do not make normal unit tests invoke the model.

---

# 11. Persistent worker safety

Because the worker now remains alive:

- guard against protocol desynchronisation
- handle malformed worker responses
- handle EOF cleanly
- capture stderr without deadlocking
- ensure child process termination on app exit/test teardown
- add configurable idle timeout if useful
- add configurable per-render timeout
- make `shutdown` graceful where possible
- force-kill only as fallback
- do not leak zombie processes

A stuck worker must not wedge the bench permanently.

---

# 12. Reference prompt caching

If Qwen supports reusable clone prompt state or speaker embedding extraction for repeated renders with the same reference, investigate whether it can be safely reused.

If implemented:

- key cached prompt state by reference identity + transcript + model revision
- do not reuse across incompatible checkpoints
- make reuse visible in metadata
- preserve the ability to disable caching for controlled tests

This is **optional** in RB-003.

Persistent model reuse is required.
Prompt/embedding reuse is not.

Do not compromise correctness merely to gain speed.

---

# 13. Result metadata additions

Extend Qwen-specific environment/timing metadata where necessary to preserve:

```text
worker_protocol_version
worker_reused
model_reused
cold_start
requested_backend
actual_backend
python_import_seconds
model_load_seconds
generation_seconds
adapter_total_seconds
reference_asset_id if catalogue asset used
reference_prompt_reused if implemented
```

Keep the common result model renderer-neutral.

Use structured settings/environment fields rather than adding Qwen-specific properties to shared Swift schemas unless they are genuinely general concepts.

---

# 14. Output validation

Retain RB-002 common WAV validation unchanged unless a defect is discovered.

Persistent-worker changes must not bypass:

- existence check
- non-empty check
- RIFF/WAVE validation
- valid PCM/float structure
- data presence
- positive finite duration
- persisted validated duration/sample rate

---

# 15. Tests

Retain all existing RB-001 and RB-002 tests.

Add automated tests covering at least:

1. persistent worker protocol request/response framing
2. worker state transitions
3. load followed by multiple renders does not logically reload model
4. shutdown terminates worker cleanly
5. malformed response fails safely
6. unexpected worker exit fails safely
7. render timeout terminates/restarts appropriately
8. requested backend and actual backend persist
9. cold/warm timing metadata serialises correctly
10. reference asset metadata serialisation
11. benchmark definition loading for A01/C01
12. repeated warm renders retain unique run IDs and do not overwrite evidence

Use fake/test workers for unit tests where appropriate.

Normal `swift test` must remain model-free.

---

# 16. Real integration checks

Run the real installed Qwen path on the target Mac.

Minimum evidence:

### Persistent MPS session
- launch
- load once
- render A01
- render C01
- render at least one additional warm sample
- shutdown

### Persistent CPU session
- same input(s)
- explicit CPU backend
- at least one cold and one warm render
- shutdown

Record:

- backend
- load time
- generation time
- output duration
- realtime factor
- any warnings/fallbacks

Do not over-interpret small sample counts.

---

# 17. Documentation updates

Update:

```text
docs/renderers/qwen3.md
KEY_FINDINGS.md
PROJECT_HANDOVER.md
CODEX_LOG.md
```

Only add reusable findings to `KEY_FINDINGS.md`.

Document:

- persistent worker architecture
- actual worker lifecycle
- measured cold/warm behaviour
- actual MPS/CPU backend behaviour
- reference asset status
- any Qwen quirks that future adapters should know about

Do not change the licensing record unless new licence facts emerge.

---

# 18. Do not do

Do not:

- add VoxCPM2
- add Chatterbox
- add MOSS
- configure Microsoft/Azure
- add ElevenLabs
- enlarge the five-renderer active set
- redesign the common renderer protocol unnecessarily
- add a database
- build UI polish
- build waveform display
- build blind mode
- add human scoring UI
- build Render All across five models
- implement performance pills
- implement Actor Model logic
- implement Exact / Adjust / Interpret
- implement session matching
- implement acoustic-presence synthesis
- fine-tune Qwen
- switch checkpoint
- add CustomVoice or VoiceDesign paths
- add a local HTTP server unless process protocol genuinely fails

---

# 19. Acceptance criteria

RB-003 is complete when:

1. Qwen can run through a persistent worker process.
2. The model is loaded once and reused for multiple renders.
3. Worker lifecycle/state is explicit and testable.
4. Shutdown and failure cleanup are reliable.
5. Cold-start/model-load/generation timing are separated honestly where measurable.
6. Explicit MPS and CPU backend selection works.
7. Requested and actual backend are persisted.
8. Controlled identical-input MPS-vs-CPU measurements have been run.
9. At least one approved non-private reference asset is catalogued **or** the absence of a suitable redistributable asset is explicitly documented without committing private material.
10. Stable A01/C01 benchmark definitions exist.
11. Real Qwen smoke automation uses the persistent path.
12. Existing WAV validation remains active.
13. Existing RB-001/RB-002 tests still pass.
14. New RB-003 unit tests pass.
15. Real persistent MPS and CPU sessions have been exercised on the target Mac.
16. `CODEX_LOG.md` contains an RB-003 entry.
17. `KEY_FINDINGS.md` and `PROJECT_HANDOVER.md` are updated.
18. No second real renderer has been integrated.
19. RB-004 has not begun.

---

# 20. Deliver back

When finished, report:

1. concise summary
2. project tree changes
3. persistent worker lifecycle
4. worker protocol changes
5. model load/reuse behaviour
6. exact reference asset used or why none was committed
7. A01/C01 benchmark definitions
8. test command + result summary
9. MPS cold/warm measurements
10. CPU cold/warm measurements
11. backend/fallback observations
12. generated audio format/sample rate
13. BenchData result locations
14. known limitations
15. any reusable architectural findings
16. proposed RB-004

Do not begin RB-004 without instruction.
