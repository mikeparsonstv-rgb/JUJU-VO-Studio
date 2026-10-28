# TASK_RB-002 — Integrate Qwen3-TTS as the First Real Renderer

## Milestone

**RB-002**

## Objective

Integrate **Qwen3-TTS** as the first real renderer behind the renderer-neutral boundary created in RB-001.

This milestone is deliberately narrow:

> Prove that a real open model can be installed in an isolated environment, health-checked, invoked from the Swift bench, produce valid speech audio, and persist enough version/environment evidence for the result to remain interpretable later.

Do **not** expand the bench UI or begin the Actor Model.

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
8. this task

RB-001 is the governing architectural baseline.

Preserve these RB-001 decisions:

- renderer-neutral request/result/capability/descriptor/health schemas
- the controller never branches on model name
- `testID` identifies the canonical test; `runID` identifies one execution
- results snapshot descriptor, capabilities, version/checkpoint, settings, environment and timing
- known-but-unavailable renderers are normal persisted outcomes
- unknown renderer IDs remain caller/configuration errors
- the mock remains `isTestFixture` and is not one of the five active candidates
- do not force model dependencies into the Swift controller process

---

# 1. Licence gate — MUST HAPPEN FIRST

Before installing model weights or writing integration-specific production code, verify the exact licence of:

1. the **Qwen3-TTS source repository**
2. the **exact model checkpoint**
3. the **Qwen3-TTS tokenizer checkpoint**
4. any other required downloaded model assets

The current research expectation is Apache-2.0, but **do not rely on the brief alone**.

Record:

```text
component
repository / model ID
source URL
revision / commit if available
licence
commercial use permitted?
modification permitted?
redistribution permitted?
attribution / notice obligation
date checked
```

Create:

```text
docs/licensing/QWEN3_TTS_LICENSE_CHECK.md
```

### Gate

If the exact code **and all required weights/assets** are not permissively usable for commercial modification/use under the project's open-core policy:

**STOP RB-002.**

Do not substitute another model without instruction.

Report the licence problem and leave the qwen3 adapter unavailable.

This is an engineering documentation check, not legal advice.

---

# 2. Exact model for RB-002

Start with:

```text
Qwen/Qwen3-TTS-12Hz-0.6B-Base
```

and its required Qwen3-TTS 12 Hz tokenizer.

Reason:

- it is the smaller released Base checkpoint
- Base supports rapid voice cloning from reference audio
- it gives us a genuine supplied/cloned-voice path without making the first real integration unnecessarily heavy
- RB-002 is testing the adapter/worker architecture, not selecting the final winning Qwen checkpoint

Do not silently switch to 1.7B.

If 0.6B-Base cannot run correctly on the target Mac after reasonable investigation, document the blocker and stop for review rather than redesigning the milestone.

---

# 3. Do not misstate Qwen capabilities

For this exact Base checkpoint, declare only capabilities verified against the installed version.

In particular:

- voice cloning: expected
- multilingual speech: expected
- streaming: may be supported by the family, but declare it only if this integration actually exposes/tests it
- natural-language performance instruction: **do not assume the Base checkpoint supports the same instruction surface as CustomVoice / VoiceDesign**
- supplied voice / cloning and instruction control are separate capabilities

Update the qwen3 descriptor/capability snapshot with facts from the exact installed checkpoint.

Do not promote family-level marketing claims into checkpoint-level capabilities.

---

# 4. Isolated worker architecture

The Swift package remains the controller.

Create an isolated Qwen worker outside `RendererBenchCore`.

Preferred conceptual boundary:

```text
RendererBenchCore
      ↓
Qwen3RendererAdapter
      ↓
Qwen worker process
      ↓
isolated Python environment
      ↓
Qwen3-TTS package + checkpoint
```

Do not import Python or PyTorch directly into the core Swift target.

Do not put Qwen dependencies in the same environment as future VoxCPM, Chatterbox or MOSS dependencies.

---

# 5. Worker protocol

Use a simple, inspectable request/response contract.

JSON over stdin/stdout is preferred unless there is a compelling reason otherwise.

Example request shape:

```json
{
  "operation": "render",
  "request_id": "...",
  "text": "...",
  "language": "English",
  "reference_audio": "/absolute/path/reference.wav",
  "reference_text": "...",
  "settings": {}
}
```

Example response shape:

```json
{
  "success": true,
  "output_audio": "/absolute/path/output.wav",
  "sample_rate": 24000,
  "duration_seconds": 3.42,
  "model_id": "...",
  "model_revision": "...",
  "tokenizer_id": "...",
  "package_versions": {},
  "device": "...",
  "warnings": []
}
```

Exact field names may differ, but the protocol must be:

- versionable
- renderer-specific only at the adapter/worker boundary
- machine-readable
- testable without parsing human log text

### Logging

Worker logs/debug text must go to **stderr**.

stdout should contain only protocol output.

---

# 6. Worker operations

Implement at least:

### `health`

Report:

- worker runnable
- Python version
- qwen-tts version
- torch version
- model/checkpoint availability
- tokenizer availability
- selected compute device/backend
- whether a render can be attempted

Health checking must not require generating a full speech sample every time.

### `render`

For RB-002 implement the Base-model clone path:

Inputs:

- text
- language
- reference audio
- reference transcript when available
- renderer settings

Output:

- real generated speech audio
- structured metadata

Use the reference transcript / ICL path where supported and appropriate for best cloning quality.

Do not add speculative performance-control translation yet.

---

# 7. macOS / Apple Silicon investigation

Target system remains macOS 26 / Apple Silicon.

The official Qwen examples may favour CUDA. Do not fake Mac support.

Investigate and record what actually works on the development Mac:

- PyTorch MPS if supported by the required operations
- CPU fallback if viable
- unsupported operations / fallbacks
- memory footprint if easily measurable
- model load time
- first render time

Do **not** install CUDA-only dependencies such as FlashAttention merely because upstream recommends them for NVIDIA systems.

If upstream Qwen cannot currently execute correctly on Apple Silicon using its supported Python stack, return a clear unavailable health state and document the blocker.

Do not contaminate the Swift architecture to work around a model-specific limitation.

Create/update an environment note under:

```text
docs/renderers/qwen3.md
```

---

# 8. Environment snapshot

Every successful or failed Qwen result should preserve enough information to understand what was tested.

Capture where practical:

```text
renderer adapter version
worker protocol version
Qwen model ID
model revision / commit hash if available
tokenizer ID
tokenizer revision if available
qwen-tts package version / source commit
Python version
PyTorch version
Transformers version
OS version
machine architecture
compute backend/device
relevant generation settings
reference audio identity/path
reference transcript presence
output sample rate
```

Do not rely on today's registry to reconstruct these later.

Do not hash enormous model files merely for this milestone; revision identifiers are sufficient when available.

---

# 9. Output-file validation

RB-001 identified a missing guard:

> An adapter could theoretically report success without actually creating its promised output file.

Fix this at the appropriate common boundary.

A successful render must be rejected/converted into a failed result if:

- output path does not exist
- file is empty
- file cannot be read as the expected audio container
- reported duration is zero or nonsensical

Prefer validation that is renderer-neutral.

Do not make the runner understand Qwen-specific audio.

Add automated tests for this behaviour using test adapters/fixtures.

---

# 10. Reference audio handling

RB-002 introduces real reference audio into the operational path.

The core schema already contains reference-audio fields.

Extend the CLI only as much as needed to expose them.

Suggested flags:

```text
--reference-audio /path/to/reference.wav
--reference-text "Transcript of reference"
```

If the exact Qwen clone path requires a reference transcript for best quality, make that clear.

Do not fabricate a permanent benchmark voice.

For architecture/integration testing, an upstream official sample may be used only if its redistribution/use terms are verified. Otherwise require the operator to supply a local reference file.

Do not commit private production/talent recordings into the repository.

---

# 11. First real benchmark cases

Do not materialise all 12 canonical tests yet.

For RB-002 create only two Qwen-compatible test definitions / documentation entries:

### A01 — Neutral new speech

Purpose:
- prove intelligible real speech generation
- establish basic timing/output metadata

For Base cloning, run this using the supplied reference voice.

### C01 — Clone / neutral

Purpose:
- prove voice-clone path
- create the first real result we can later compare with other renderers

Persist the exact reference used outside private repository data as appropriate.

If A01 and C01 are operationally the same path at this stage, that is acceptable. Keep their benchmark intent distinct.

Do not score naturalness automatically.

---

# 12. CLI additions

Add only what RB-002 needs.

At minimum the CLI should be able to:

```text
renderer-bench health qwen3

renderer-bench render \
  --renderer qwen3 \
  --test-id C01 \
  --language en-GB \
  --script "..." \
  --reference-audio /path/reference.wav \
  --reference-text "..." \
  --data /path/BenchData
```

Use the existing command conventions where possible rather than redesigning the CLI.

A renderer with missing environment/model dependencies should report unavailable clearly.

---

# 13. Persistence behaviour

Preserve the RB-001 hierarchy:

```text
BenchData/
  runs/
    <test-id>/
      <run-id>/
        request.json
        <renderer-id>/
          result.json
          output.wav
```

The Qwen worker should write temporary/model output where instructed by the adapter.

The final benchmark audio should end up under the run directory controlled by the bench.

Do not let Qwen choose arbitrary permanent output locations.

---

# 14. Timing

Capture separately where possible:

- worker startup time
- model load time
- generation/render time
- total adapter elapsed time
- output duration
- realtime factor

First-audio latency is **not required** for RB-002 unless true streaming is implemented.

Do not label total render time as first-audio latency.

---

# 15. Tests

Retain all RB-001 tests.

Add automated tests covering at least:

1. Qwen worker request encoding
2. Qwen worker response decoding
3. Qwen unavailable health state
4. adapter maps worker success to `RendererResult`
5. adapter maps worker failure to persisted unsuccessful result
6. successful-result output file must exist
7. empty output file is rejected
8. invalid/non-audio output is rejected
9. Qwen descriptor/capability snapshot persists
10. two Qwen test runs cannot overwrite each other

### Integration test

Add one opt-in real-model integration test or smoke-test command.

It must be skippable when:
- model is not installed
- reference audio is not provided
- environment is unavailable

Do not make ordinary `swift test` download gigabytes of weights.

---

# 16. Installation / setup

Provide one reproducible setup path.

Prefer a script or documented command sequence under something like:

```text
scripts/setup-qwen3.sh
```

or an equivalent non-destructive setup mechanism.

Requirements:

- isolated environment
- no global Python package installation
- repeatable
- detects existing environment sensibly
- does not silently download a different model
- exact model ID documented
- model storage location understandable/configurable

Do not bundle model weights into the Swift package.

---

# 17. Security / process hygiene

Treat renderer workers as external processes.

- quote/escape paths safely
- do not shell-concatenate untrusted script text
- pass JSON through stdin or files rather than command-line embedding of arbitrary speech text
- capture stderr separately
- apply a reasonable process timeout/configurable timeout
- terminate failed/hung worker cleanly
- do not log API secrets or private audio contents

No network server is required for RB-002.

---

# 18. Do not do

Do not:

- integrate the other four real engines
- add ElevenLabs
- switch Qwen checkpoint without reporting
- implement VoiceDesign as a second Qwen product path
- implement CustomVoice as a second Qwen product path
- build performance pills
- build Exact / Adjust / Interpret UI
- build session matching
- build acoustic-presence synthesis
- add waveform UI
- add blind comparison
- add ratings
- add a database
- implement Render All
- perform fine-tuning
- redesign `RendererBenchCore`
- put Qwen/Python dependencies inside the Swift core process

---

# 19. Acceptance criteria

RB-002 is complete when:

1. Exact Qwen code/weight/tokenizer licensing is documented and passes the open-core gate.
2. Qwen uses an isolated worker/environment.
3. `renderer-bench health qwen3` reports meaningful real state.
4. A supplied reference voice can produce real cloned speech through the common adapter boundary.
5. The resulting audio is playable.
6. The bench validates the promised output before recording success.
7. Request/result metadata and environment/checkpoint evidence are persisted.
8. Failed Qwen execution is stored as a normal unsuccessful benchmark result.
9. Existing RB-001 tests still pass.
10. New RB-002 unit tests pass.
11. A real-model smoke test has been run successfully on the target machine, **or** a genuine upstream Apple-Silicon blocker has been clearly documented without architectural compromise.
12. `CODEX_LOG.md` contains an RB-002 entry.
13. `KEY_FINDINGS.md` is updated only with findings that are genuinely reusable beyond Qwen.
14. `PROJECT_HANDOVER.md` is updated to reflect the new state.
15. RB-003 has not begun.

---

# 20. Deliver back

When finished, report:

1. concise summary
2. licence-gate result
3. exact model/checkpoint/tokenizer tested
4. project tree changes
5. worker protocol summary
6. environment/backend used on the Mac
7. test command + result summary
8. smoke-test command + result
9. generated audio format/sample rate/duration
10. where BenchData was written
11. known Qwen limitations
12. any capability corrections discovered
13. proposed RB-003

Do not begin RB-003 without instruction.
