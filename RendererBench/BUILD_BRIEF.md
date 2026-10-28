# BUILD_BRIEF.md

## 1. Project

Working name: **TalkBack / CuePitch Renderer Bench**

This repository is the first engineering stage of a larger computational performance-direction system for generated voice.

The eventual system is not intended to be merely another TTS front end. Its durable value will be a renderer-independent performance model that can convert creative direction into structured performance intent and then translate that intent into whatever voice engine is currently best.

The renderer bench exists to discover what current engines can and cannot do before the higher-level Actor / Performance Model is built.

---

## 2. Core philosophy

### AI voice is source material, not authority
Generated speech should be treated like rushes: generate, compare, select, edit, regenerate and repair.

### Performance and editorial fit are separate problems
Do not force every generated read to hit final commercial duration at the cost of acting quality.

Future workflow:
1. Performance pass
2. Editorial pass
3. Compliance pass

### The critical benchmark is surgical control
A strong renderer must be able to alter one thing without damaging everything else.

Example:
> Make the word “boosters” more clearly articulated.

A pass means:
- articulation changes as requested
- speaker identity remains stable
- emotional read remains stable
- timing remains stable unless deliberately changed
- surrounding words remain effectively unchanged

---

## 3. Active renderer limit

**Maximum active renderers: 5.**

The initial bench should support:

1. **Qwen3-TTS**
2. **VoxCPM2**
3. **Chatterbox Multilingual V3**
4. **MOSS-TTS**
5. **Microsoft speech renderer / Azure Speech** — industrial control reference

### ElevenLabs
ElevenLabs is **not one of the five active open-core candidates**.

It is retained as an **external quality and control benchmark**. The bench should allow an ElevenLabs reference render to be attached or compared later, but the initial architecture must not depend on ElevenLabs.

---

## 4. Open-model policy

For a model to qualify as a core renderer candidate, verify the **exact code licence and exact model-weight licence**.

Preferred:
- MIT
- Apache-2.0
- BSD-style permissive terms

Core candidate requirements:
- source code available
- weights available
- commercial use permitted
- modification permitted
- no separate licensing negotiation required
- no non-commercial restriction
- no research-only restriction

Copyleft licences such as GPL/AGPL should not be promoted into the core product without an explicit architecture/legal decision.

A permissive code repository does not automatically make restricted model weights acceptable.

---

## 5. The three primary renderer jobs

### Job A — Supplied voice → new speech

Input:
- text
- supplied / existing target voice
- performance direction

Output:
- new speech in that supplied voice

Measure:
- naturalness
- direction obedience
- identity stability
- diction
- accent
- timing
- repeatability
- multilingual behaviour

---

### Job B — Voice clone → new speech

Input:
- one or more reference recordings
- new text
- performance direction

Output:
- new speech in the cloned identity

Measure separately:
- clone fidelity
- performance freedom
- identity stability under strong direction
- pickup consistency
- cross-language identity
- isolated word / phrase replacement quality

---

### Job C — Speech → speech performance transfer

Input:
- guide performance
- target supplied or cloned voice

Output:
- target voice carrying the guide performance

This eventually supports three conceptual modes:

#### Exact
Preserve the actual guide performance as precisely as possible while changing voice identity / session condition.

Real production examples:
- an actress sends a perfect pickup while she has a cold
- an actress sends a low-fidelity phone pickup
- a pickup is recorded a year later in a different studio
- preserve timing, stress, intent and rhythm while restoring the approved voice/session identity

#### Adjust
Extract the guide into an editable performance representation.

#### Interpret
Future mode: use the guide as inspiration, then allow the higher-level Actor Model to reinterpret it.

**RB v0.1 should not implement the full Adjust or Interpret model.**
It should keep the data model extensible enough to support them later.

---

## 6. Secondary production benchmarks

### D — Session continuity

Question:
> Can a pickup recorded in a different studio be made to disappear into the original session?

Separate conceptual components:
- performance
- voice identity
- session signature
- ambient / presence signature

Do not reduce session matching to EQ alone.

---

### E — Acoustic presence

Generated voices often reveal themselves in the negative space around speech.

Future research areas:
- occupied-booth silence
- non-stationary noise floor
- pre-utterance micro-behaviour
- room/mic statistical texture
- performer-correlated micro-events
- session noise-field continuity

This is **research only in v0.1**, but the bench must preserve unprocessed audio and allow future acoustic analysis.

---

## 7. Architecture principles

### Renderer-independent core

Use a common adapter interface.

Conceptually:

```text
Benchmark Request
      ↓
Renderer Adapter
      ↓
Renderer-specific translation
      ↓
Engine/API
      ↓
Audio + metadata
```

The benchmark runner must not contain Qwen-, VoxCPM-, Chatterbox-, MOSS- or Microsoft-specific logic outside the relevant adapter.

### Common request object

At minimum:

```text
RendererRequest
- test_id
- script
- language
- direction_text
- reference_audio_paths[]
- guide_audio_path?
- seed?
- target_duration?
- renderer_settings{}
```

### Common result object

At minimum:

```text
RendererResult
- test_id
- renderer_id
- renderer_version
- model_checkpoint
- settings_snapshot
- output_audio_path
- output_duration
- render_started_at
- render_completed_at
- render_time
- first_audio_latency? 
- realtime_factor?
- success
- error?
- environment_snapshot
```

Keep the result schema forward-compatible.

---

## 8. Renderer capabilities

Each adapter should declare capabilities rather than forcing the UI to guess.

Suggested structure:

```text
RendererCapabilities
- text_to_speech
- supplied_voice
- voice_cloning
- guide_performance_transfer
- natural_language_direction
- structured_direction
- pronunciation_control
- pause_control
- speed_control
- pitch_control
- duration_control
- streaming
- deterministic_seed
- multilingual
- local
- cloud
```

Capabilities should be stored with benchmark results so historical tests remain interpretable if model behaviour changes later.

---

## 9. Bench UI — v0.1

Keep it intentionally plain.

Required:
- script text field
- language field
- direction field
- optional reference audio selector
- optional guide performance audio selector
- renderer selector
- Render button
- Render All button
- result list
- audio playback
- visible duration
- render time
- success/error state
- settings/metadata disclosure

Useful but not required in first milestone:
- waveform
- blind comparison
- star/rating controls
- notes
- A/B loop
- lock/vary controls

No visual polish work until the benchmark path is reliable.

---

## 10. Persistence

Every run must be reproducible as far as the renderer permits.

Store:
- request
- renderer/version
- settings
- seed if supported
- references used
- output paths
- timing
- errors
- capability snapshot
- human notes/ratings later

Prefer simple transparent storage first:
- JSON or JSONL metadata
- deterministic folder structure
- WAV outputs where possible

Example:

```text
BenchData/
  tests/
    RB001/
      request.json
      qwen3/
        result.json
        output.wav
      voxcpm2/
        result.json
        output.wav
```

Do not introduce a database until benchmark volume justifies it.

---

## 11. Platform / implementation assumptions

Primary development target:
- macOS
- Apple Silicon

However many research renderers are Python/PyTorch and may initially require:
- Python virtual environments
- local subprocess workers
- model-specific dependencies
- remote/API adapters where local execution is impractical

Do not force every renderer into a single Python environment.

Preferred shape:
- lightweight bench controller
- isolated renderer workers/adapters
- explicit health/status checks
- clean stdout/stderr capture

The bench must tolerate one renderer being unavailable without breaking the others.

---

## 12. What not to build yet

Do **not** build:
- final product branding
- final product UI
- full Actor Model
- performance pills UI
- automatic screenplay analysis
- full session matching
- acoustic-presence synthesis
- DAW/NLE integration
- fine-tuning infrastructure
- unlimited renderer discovery
- cloud orchestration platform
- user accounts / subscriptions

The bench exists to produce evidence.

---

## 13. Definition of success for Renderer Bench v0.1

We can say v0.1 works when:

1. The application/repo has a clean common renderer protocol.
2. At least one renderer adapter can generate speech end-to-end.
3. The remaining four adapters can exist as clean stubs with explicit availability/health status.
4. A benchmark request is persisted.
5. A renderer result is persisted.
6. Output audio can be played.
7. Renderer failures do not crash the bench.
8. The same test can be rerun.
9. Adding another renderer does not require rewriting the runner.
10. Tests cover the common schemas and adapter boundary.

The first milestone is architectural correctness, not model quality.
