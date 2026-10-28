# DECISIONS.md

This file records decisions that should not be casually re-litigated by implementation agents.

---

## D-001 — Active renderer count
**Decision:** Maximum of five active renderer slots.

**Why:** Enough contrast to learn while keeping testing rigorous.

**Current five:**
1. Qwen3-TTS
2. VoxCPM2
3. Chatterbox Multilingual V3
4. MOSS-TTS
5. Microsoft / Azure Speech

**Rule:** A new renderer must replace an existing active renderer rather than enlarging the bench.

---

## D-002 — ElevenLabs role
**Decision:** ElevenLabs is an external benchmark, not a core renderer dependency.

**Why:** It represents current premium generative voice quality/control but is closed.

---

## D-003 — Open-core licensing
**Decision:** Core renderer candidates should use permissively usable code and weights.

**Preferred:** MIT / Apache-2.0 / BSD-style.

**Reject from core unless explicitly reconsidered:**
- non-commercial weights
- research-only weights
- separate permission requirements
- ambiguous checkpoint rights

Code licence and weight licence must be checked separately.

---

## D-004 — Renderer-independent architecture
**Decision:** All engine-specific behaviour belongs in renderer adapters.

The benchmark runner and persistent test schema remain renderer-neutral.

---

## D-005 — Three primary jobs
The benchmark is designed around:
1. supplied voice → new speech
2. cloned voice → new speech
3. guide speech → target-voice performance transfer

Generic TTS quality alone is not enough.

---

## D-006 — Exact means preserve performance
**Decision:** Exact mode means the guide performance is already correct.

The system should preserve:
- timing
- pause placement
- emphasis
- pitch movement
- energy contour
- phrase rhythm
- hesitation / micro-rhythm where possible

while allowing:
- voice restoration
- voice identity transfer
- session continuity
- recording-condition replacement

Exact is not “AI interpretation.”

---

## D-007 — Adjust and Interpret
**Decision:**
- Exact = mimic/preserve performance
- Adjust = extract performance into editable representation
- Interpret = future Actor Model re-performance informed by the guide

Do not collapse these into a single control.

---

## D-008 — Performance graph is renderer-independent
**Decision:** The eventual performance representation must not be tied to one model’s tags or latent controls.

Adapters translate common intent into renderer-specific mechanisms.

---

## D-009 — Session identity is separate from voice identity
**Decision:** Treat at least these concepts separately:
- performance
- voice identity
- session/acoustic signature
- ambient/presence signature

A recording can be a perfect performance and still fail because it belongs to the wrong studio/session.

---

## D-010 — Presence is a research target
**Decision:** Do not assume “room tone” means reverb or a noise loop.

Investigate the low-level physical continuity of an occupied recording space, including pre-utterance behaviour and non-stationary floor statistics.

No synthesis implementation in v0.1.

---

## D-011 — Surgical-control benchmark
**Decision:** A core benchmark is the ability to change one requested dimension without unwanted collateral change.

This matters more than headline naturalness scores.

---

## D-012 — Store everything needed for comparison
**Decision:** Preserve request parameters, renderer settings, versions, outputs and timing for every run.

No ephemeral “listen and forget” testing.

---

## D-013 — UI restraint
**Decision:** The first bench is functional, calm and unpolished.

Do not spend engineering time on production UI before benchmark reliability exists.

---

## D-014 — Separate renderer environments
**Decision:** Do not force all local TTS engines into a single dependency environment.

Each adapter may use an isolated worker/environment.

---

## D-015 — Source material philosophy
**Decision:** Generated speech is treated like rushes.

The human editor/director remains the final judge.
