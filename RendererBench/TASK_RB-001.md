# TASK_RB-001 — Build the Renderer Bench Skeleton

## Before coding

Read, in this order:

1. `README.md`
2. `BUILD_BRIEF.md`
3. `DECISIONS.md`
4. `BENCHMARK_PLAN.md`
5. `CODEX_LOG.md`

Do not reinterpret the product beyond those documents.

---

## Objective

Create **Renderer Bench v0.1 skeleton** with a clean renderer-independent architecture and one working adapter path.

This first task is primarily about boundaries, persistence and failure isolation.

Do **not** attempt to integrate all five engines in this task.

---

## Choose implementation shape

Prefer the simplest architecture that works well on macOS/Apple Silicon and can later host Python/model-specific workers.

A good solution may be:

```text
Bench Controller / UI
        ↓
RendererProtocol
        ↓
Adapter
        ↓
Worker / API
```

Do not force all renderer dependencies into the controller process.

If the repository is empty, choose a pragmatic project structure and document the choice in `CODEX_LOG.md`.

---

## Implement

### 1. Common models

Create serializable models equivalent to:

```text
RendererRequest
RendererResult
RendererCapabilities
RendererDescriptor
RendererHealth
```

At minimum, support the fields described in `BUILD_BRIEF.md`.

Keep them renderer-neutral.

---

### 2. Renderer adapter protocol

Create a common interface with operations conceptually equivalent to:

```text
descriptor()
capabilities()
healthCheck()
render(request)
```

Exact language/API naming is up to you.

The runner must not need model-specific conditionals.

---

### 3. Five registered renderer descriptors

Register placeholders for:

- qwen3
- voxcpm2
- chatterbox
- moss
- microsoft

Each should expose:
- id
- display name
- local/cloud type
- availability
- declared capabilities

For this task, four may be unavailable/stub adapters.

---

### 4. One deterministic working adapter

Implement a **MockRendererAdapter** or equivalent test renderer first.

Purpose:
- prove the full request → render → persistence → playback/result path
- avoid model-installation problems masking architecture problems

It may generate:
- a short WAV tone
- silence plus a tone
- another deterministic synthetic audio fixture

It must create valid audio output and result metadata.

Do not pretend the mock is one of the five actual engines.

---

### 5. Persistence

For each test run, create a transparent filesystem structure similar to:

```text
BenchData/
  runs/
    <test-id>/
      request.json
      <renderer-id>/
        result.json
        output.wav
```

Persist:
- request
- result
- capability snapshot
- renderer descriptor/version info
- timing
- error information

Paths should be configurable and testable.

---

### 6. Failure isolation

A failed renderer must:
- return/store an error result
- not crash the bench
- not prevent other renderers from running

Add tests for this.

---

### 7. Minimal interface

If implementing a UI in this milestone, keep it extremely basic.

Required interaction:
- enter script
- enter language
- enter direction text
- choose renderer
- render
- see success/error
- play generated mock audio
- see duration/render time

If UI choice would meaningfully slow the architecture work, a CLI + tests is acceptable for RB-001, provided the code is structured so a macOS UI can be added cleanly next.

Document the decision.

---

## Tests

Add automated tests for at least:

1. `RendererRequest` serialization round-trip
2. `RendererResult` serialization round-trip
3. capability serialization
4. renderer registry lookup
5. mock render produces valid output file
6. request/result persistence
7. failed renderer does not throw through the runner
8. two sequential runs do not overwrite each other accidentally

Run all tests before completing the task.

---

## Do not do

Do not:
- install Qwen3-TTS yet
- install VoxCPM2 yet
- install Chatterbox yet
- install MOSS yet
- configure Azure credentials yet
- add ElevenLabs
- add a database
- build waveform rendering
- build blind comparison
- build performance pills
- build Actor Model logic
- build session matching
- add arbitrary extra renderers
- redesign the project brief

---

## Acceptance criteria

RB-001 is complete when:

- project builds/runs on the chosen macOS development path
- common renderer protocol exists
- five active renderer descriptors are registered
- mock renderer successfully generates playable audio
- metadata is persisted
- errors are persisted without crashing
- automated tests pass
- no engine-specific logic has leaked into the benchmark runner
- `CODEX_LOG.md` contains a new RB-001 entry
- any new architecture decision is added to `DECISIONS.md` only if genuinely necessary

---

## Deliver back

When finished, report:

1. concise summary
2. project tree
3. files changed
4. test command + output summary
5. how to run the bench
6. where BenchData is written
7. known limitations
8. proposed RB-002

Do not begin RB-002 without instruction.
