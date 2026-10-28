# BENCHMARK_PLAN.md

## Purpose

Define a small canonical corpus that lets us compare models repeatedly as releases change.

The first corpus should be deliberately compact and difficult rather than broad and generic.

Target: **12 canonical tests**.

---

## Group A — Plain supplied-voice speech

### A01 — Neutral commercial read
A clean, contemporary 15–20 second commercial-style sentence.

Tests:
- baseline naturalness
- diction
- rhythm
- voice stability

### A02 — Same copy, intimate
Direction:
> More intimate. One person, close to you. Do not become breathy or slow.

Tests:
- direction obedience
- control isolation

### A03 — Same copy, authoritative
Direction:
> More authoritative, but not louder and not announcer-like.

Tests:
- stance without crude volume substitution

---

## Group B — Surgical direction

### B01 — Single-word articulation
Baseline:
> ...with our new boosters...

Direction:
> Make only “boosters” more clearly articulated.

Pass:
- target word improves
- surrounding sentence remains effectively unchanged

### B02 — Single-word emphasis
Direction:
> Put the thought on “you”, not on “want”.

Tests:
- interpretive emphasis
- collateral change

### B03 — Pause insertion
Direction:
> Add a short thought pause before the final clause. Change nothing else.

Tests:
- timing locality
- repeatability

---

## Group C — Clone stability

### C01 — Clone / neutral
Create new speech from an approved studio reference.

Measure:
- identity
- intelligibility
- texture

### C02 — Clone / strong direction
Use the same identity under a strong performance instruction.

Measure:
- whether identity collapses under direction

### C03 — Cross-language identity
Same target identity in English and one European target language.

Initial language:
- French or German

Measure:
- identity continuity
- accent/native plausibility

---

## Group D — Exact performance transfer

### D01 — Clean guide → target voice
A guide read with deliberate timing and emphasis.

Goal:
- preserve the performance
- change the voice identity

### D02 — Phone pickup
Guide recorded on a phone but performed correctly.

Goal:
- preserve performance information
- reject phone-recording character

### D03 — Different-session pickup
Same human actor in an older approved studio recording and a later pickup recorded elsewhere.

Goal:
- eventually judge session continuity

For v0.1, merely preserve and catalogue the source/reference materials and support A/B listening.

---

## Human ratings

Later rating dimensions:

- Naturalness
- Speaker identity
- Direction accuracy
- Control isolation
- Timing fidelity
- Diction
- Emotional/intent fidelity
- Cross-language identity
- Pickup invisibility
- Session continuity

Use 1–5 initially. Do not invent an elaborate psychometric system yet.

---

## Blind mode

Planned for a later milestone.

When active:
- randomise renderer labels
- preserve hidden mapping
- reveal after rating
- do not show model name during first listen

---

## Golden rule

The corpus stays stable across renderer/model updates unless a test is proven defective.

That lets us rescore the rapidly changing model landscape rather than relying on memory.
