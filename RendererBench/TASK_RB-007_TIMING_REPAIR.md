# TASK_RB-007 — Timing Repair Control

**Project:** TalkBack / CuePitch Renderer Bench  
**Milestone:** RB-007  
**Status:** Authorized  
**Purpose:** Isolate how much of the current subjective performance failure is caused by pace/timing before broader performance-direction work.

## Background

RB-006 is the frozen untuned Birmingham cross-holdout baseline. Do not alter, overwrite, rerun selectively, or reinterpret its evidence.

Operator listening after RB-006 produced these important observations:

- All three open renderers are recognisably the original voice talent.
- All three are broadly in the quality territory ElevenLabs occupied before its newer hinting/direction controls.
- Qwen is currently the clear subjective winner.
- Chatterbox can begin convincingly and then lose coherence/performance.
- VoxCPM2 is subjectively the weakest and also has the already-recorded long-form truncation failures.
- Across the usable systems, the most obvious shared performance issues are:
  - read pace too fast
  - energy too high / too pushed
- The performed `Hah!` is a shared semantic/performance failure, including in the supplied ElevenLabs outputs: systems tend to render an external exclamation / “gotcha” rather than internal amusement / discovery. This is NOT part of RB-007 timing repair; preserve it as a future Actor Model benchmark.

The immediate hypothesis for RB-007 is deliberately narrow:

> If we repair overall performed duration without changing identity, pitch, copy, EQ, dynamics, or spectral character, does the read become materially more convincing?

This is a diagnostic timing control, not yet the full self-tuning milestone.

---

# Governing rule

> **Change one thing: timing. Preserve everything else.**

RB-007 must not become an unofficial performance-remix pass.

---

# Important distinction: product default vs benchmark diagnostic

The intended product rule is:

### Same-copy cloning / repair

The first cloned render should default to the **performed duration of the original reference performance**.

Do not use file duration including arbitrary head/tail silence. Use the spoken/performed span.

### New-copy cloning

Do NOT force the new script to the raw total seconds of an unrelated reference recording.

Instead inherit the source performer’s normalized pace behaviour:

- active-speech rate
- pause proportion
- phrase cadence
- breath/pause tendency

Hard commercial-duration constraints remain a separate production layer.

## Current Birmingham cross-holdout caveat

RB-006 is intentionally cross-holdout:

- BHM01 conditions generation of BHM02 copy.
- BHM02 conditions generation of BHM01 copy.
- Withheld target human audio is evaluation-only.

Therefore exact target-human duration must **not** be fed back into renderer generation and then described as ordinary cross-holdout cloning.

For RB-007, exact target timing may be used only in an explicitly labelled **post-generation diagnostic derivative**. This keeps RB-006 renderer generation uncontaminated while allowing us to answer the narrow question: “What happens if the pacing is repaired?”

---

# RB-007 scope

Create timing-repaired audition derivatives from the existing RB-006 outputs.

Do **not** replace the RB-006 authoritative renders.

Do **not** perform new renderer tuning in this milestone.

Do **not** alter renderer settings.

Do **not** modify RendererBenchCore unless a strictly additive renderer-neutral schema is genuinely necessary. Prefer the qualification/analysis layer because this is a derived evaluation experiment.

---

# Inputs

Use the existing RB-006 authority:

`BenchData/qualifications/RB006-Birmingham-Baseline`

Use:

- existing human BHM01/BHM02 ground truth
- existing Qwen outputs
- existing Chatterbox outputs
- existing VoxCPM2 outputs only where completeness permits meaningful timing repair
- supplied ElevenLabs generations as external market context

No source audio should be modified.

No new conditioning is permitted.

---

# Timing target

For each target bundle, measure the human target’s **performed span** using the same speech/onset methodology across all files.

Definition:

```text
performed_span =
last meaningful speech offset
-
first meaningful speech onset
```

This deliberately excludes arbitrary leading/trailing file silence while retaining the pauses inside the performance.

Persist:

- source file duration
- performed-span duration
- active-speech duration
- internal-pause duration/proportion
- first speech onset
- last speech offset
- method/version used to determine them

For this RB-007 diagnostic only:

```text
timing target = withheld human target performed span
```

Label this everywhere as:

`oracle_target_performed_span`

or equivalent unmistakable wording.

It is an evaluation diagnostic, not a production-realistic source of timing information.

---

# Eligibility gate

Do not stretch obviously incomplete speech to fill the target duration.

Before timing repair, each generated file must pass a completeness gate using existing RB-006 ASR/text evidence.

Suggested rule:

- expected target transcript coverage must be sufficient to represent a complete read
- any severe truncation remains `ineligible_for_timing_repair`

VoxCPM2's known truncated outputs should therefore normally be skipped and reported, not expanded from e.g. 6 seconds to ~30 seconds.

Persist the exclusion reason.

---

# Timing repair

Create a new derived tree, for example:

```text
BenchData/qualifications/RB007-Timing-Repair/
├── source_manifest/
├── measurements/
├── repaired/
│   ├── BHM01_target/
│   └── BHM02_target/
├── listening-bundle/
│   ├── BHM01_target/
│   └── BHM02_target/
└── report/
```

Every repaired file must preserve the RB-006 source result identity.

## DSP constraints

Timing repair must be:

- pitch-preserving
- gain-neutral except unavoidable tiny numerical differences
- no EQ
- no compression
- no limiting
- no denoise
- no dereverb
- no formant shift
- no added breath
- no pause editing
- no phrase-level rearrangement
- no spectral enhancement
- no loudness normalization as part of timing repair

Prefer a system-provided macOS/Core Audio time/pitch path for this diagnostic so no new licence-sensitive DSP dependency is introduced. `AVAudioUnitTimePitch` is acceptable as a first implementation candidate.

If the selected implementation produces audible artefacts that would invalidate listening, stop and report rather than silently substitute an unreviewed dependency.

Persist:

- algorithm/backend
- version/platform
- requested target performed span
- original performed span
- stretch ratio
- repaired performed span
- duration error in milliseconds and percent

---

# Processing behaviour

Only stretch the performed region.

Do not let arbitrary head/tail silence determine the stretch factor.

Preserve head/tail silence separately where practical.

First version may scale all internal pauses proportionally with the spoken region. Phrase-level/pause-aware retiming is explicitly out of scope for RB-007.

This is intentionally the simplest timing repair.

---

# Stretch-ratio guardrail

Do not create absurd derivatives.

Persist and flag all ratios.

Suggested initial guardrail:

```text
0.85 <= time_scale <= 1.20
```

If a file lies outside that range, mark `timing_repair_out_of_range` and do not include it in the primary listening set without an explicit note.

The exact threshold may be adjusted if the existing RB-006 evidence demonstrates a better justified value, but any change must be documented before listening.

---

# Listening bundle

For each target, create an identified listening bundle containing:

1. human target
2. RB-006 original Qwen calls
3. RB-007 timing-repaired Qwen calls
4. RB-006 original Chatterbox calls
5. RB-007 timing-repaired Chatterbox calls
6. eligible Vox originals + repaired derivatives, if any
7. ElevenLabs originals
8. ElevenLabs timing-repaired derivatives

Where possible, present original/repaired pairs adjacent to one another.

Create both:

- raw-level original/repaired comparison
- gain-only level-matched comparison using the already-established RB-006 audition policy

Do not level-match the authoritative source files.

---

# Primary listening questions

RB-007 does not ask “which renderer wins?”

It asks:

### Pace
- Does the repaired version feel less rushed?
- Does it sit closer to the human performer’s natural pace?
- Does it reduce the sense that the model is pushing the copy?

### Energy interaction
- Does simply slowing the performance reduce perceived “push”?
- Or is high energy still clearly present after timing is corrected?

### Identity
- Does time repair leave the voice recognisably the same person?
- Does Birmingham character survive?

### Naturalness
- Does the stretch introduce audible artefacts?
- Does it make breaths, consonants, or pauses sound artificial?

### Performance
- Does timing repair improve the read even though interpretation is unchanged?
- Does the `Hah!` remain wrong in the same semantic way? It should: that failure is expected to survive a pure timing fix.

This last point is important. If `Hah!` remains a “gotcha” after timing repair, that supports the hypothesis that it is an Actor Model/intent problem rather than a pace problem.

---

# Measurements

For every eligible original/repaired pair persist:

- file duration
- performed span
- active speech duration
- pause proportion
- median F0
- F0 range
- RMS / loudness descriptors already used by RB-006
- spectral/MFCC descriptors already used by RB-006
- ASR hypothesis / WER / CER where available
- exact stretch ratio
- post-repair timing error
- source RB-006 run/result IDs

The purpose is to verify that timing changed while unrelated properties did not move unexpectedly.

Do not invent a single aggregate score.

---

# Acceptance criteria

RB-007 is complete when:

1. RB-006 remains byte-for-byte untouched.
2. Every derivative points back to its exact RB-006 source result.
3. Human target audio is never used as renderer conditioning.
4. Any use of target-human duration is explicitly labelled diagnostic/oracle timing information.
5. Known incomplete Vox outputs are not misleadingly stretched to full duration.
6. Timing repair changes only the performed timing dimension to the practical extent of the chosen DSP method.
7. Original/repaired identified listening bundles exist for BHM01_target and BHM02_target.
8. ElevenLabs receives the same timing-repair treatment where eligible, so the comparison is not biased toward open renderers.
9. Report JSON + Markdown summarize measurements and exclusions.
10. Existing tests/build remain green.
11. New tests cover provenance, eligibility, target-span calculation, ratio guardrail, no overwrite, and repaired-duration tolerance.

---

# Required tests

At minimum add model-free tests for:

- performed-span measurement on known fixture
- target span excludes head/tail silence
- internal pause remains inside performed span
- stretch ratio calculation
- ratio guardrail
- incomplete render exclusion
- provenance link to RB-006 source
- RB-006 source not modified
- human target path never enters a renderer request
- repaired duration within tolerance
- metadata records diagnostic/oracle target source
- listening manifest original/repaired pairing

No renderer/model download should be required by ordinary unit tests.

---

# Report headline

The report should make the scientific question explicit:

> **RB-007 tests whether correcting overall timing alone materially improves perceived performance. It does not test Actor Model direction, semantic intent, phrase-level timing, energy control, or renderer-native performance steering.**

---

# What comes after RB-007

Do not implement these yet, but preserve the roadmap:

### Next: renderer-native/source-derived timing

Move from diagnostic post timing repair to production behaviour:

```text
same-copy clone
→ default to original performed duration

new-copy clone
→ inherit source speaking rate + pause behaviour
```

Prefer generation at the desired pace over post time-stretch. Post-stretch remains fallback/repair.

### Then: performance direction

Once timing is controlled, isolate:

- energy / push
- emphasis
- restraint
- internal vs external reaction
- especially the `Hah!` benchmark

The central future test remains:

> **Can we change one thing without damaging everything else?**
