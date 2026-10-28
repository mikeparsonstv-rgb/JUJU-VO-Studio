# TASK_RB-006 — Birmingham Cross-Holdout Baseline Qualification

## Milestone

**RB-006**

## Objective

Run the first real human voice-cloning qualification across the three operational open renderers:

```text
Qwen3-TTS
VoxCPM2
Chatterbox Multilingual V3
```

Use the supplied Birmingham commercial voice as a **cross-holdout test**:

```text
BHM01 human recording
    ↓ conditioning only
generate BHM02 words
    ↓
compare with actual BHM02 human recording

BHM02 human recording
    ↓ conditioning only
generate BHM01 words
    ↓
compare with actual BHM01 human recording
```

Run **three independent generations per renderer per direction**.

Total generated open-renderer outputs:

```text
3 renderers × 2 directions × 3 runs = 18
```

This milestone establishes the **untuned baseline**.

Do not optimize renderer parameters in RB-006.

---

## 1. Authority and read order

RB-005 is complete. Qwen3-TTS, VoxCPM2, and Chatterbox Multilingual V3 are operational persistent renderers. The previous synthetic `reference-001` is not a valid clone-fidelity benchmark.

Read, in this order:

1. `README.md`
2. `BUILD_BRIEF.md`
3. `DECISIONS.md`
4. `BENCHMARK_PLAN.md`
5. current `PROJECT_HANDOVER.md`
6. `KEY_FINDINGS.md`
7. `CODEX_LOG.md`
8. renderer records for Qwen, VoxCPM2, Chatterbox
9. licence records for Qwen, VoxCPM2, Chatterbox
10. `docs/benchmarks/RB005_THREE_WAY.md`
11. `RB006_BIRMINGHAM_ASSETS.json`
12. this task

Do not begin RB-007.

---

## 2. Scientific question

RB-006 asks:

> How well does each renderer generalize the supplied speaker identity and regional accent to words it was not conditioned on?

This is more important than reproducing material already present in the reference.

Do not score a renderer primarily on phrases present in its conditioning audio.

---

## 3. Input assets

Operator-supplied local/private assets:

```text
birmingham 1 training 1(1).wav
birmingham 1 training 2.wav

ElevenLabs_birming 1 sample 1 generation 1(1).mp3
ElevenLabs_birming 1 sample 1 generation 2(1).mp3

ElevenLabs_birming 1 sample 2 generation 1.mp3
ElevenLabs_birming 1 sample 2 generation 2.mp3
```

Copy-source screenshots:

```text
text input brief.jpg
text input brief 2.jpg
```

Candidate transcript files in the RB-006 pack:

```text
BHM01_transcript_candidate.txt
BHM02_transcript_candidate.txt
```

The asset manifest contains SHA-256 hashes and observed container/audio metadata.

### Privacy rule

These are private production benchmark assets.

Do not commit the human audio, ElevenLabs audio, screenshots, client-identifying metadata, or derived voice embeddings into source control unless explicitly authorized.

Use the existing private/local asset mapping pattern.

Commit only neutral metadata/transcripts if appropriate and lawful.

---

## 4. Transcript verification gate

The supplied transcript text was transcribed from the screenshots and is a **candidate**, not yet authoritative human-audio transcription.

This matters because Qwen and VoxCPM use transcript-conditioned reference paths.

Before the authoritative cross-holdout run:

1. compare each candidate transcript against the corresponding human WAV;
2. identify any mismatch in wording, contraction, repeated word, omitted word, or obvious copy typo;
3. do **not** silently correct the transcript;
4. write any proposed correction into a verification report;
5. if the mismatch can materially alter reference conditioning, stop before the authoritative run and request operator confirmation.

A disposable technical smoke render may occur before confirmation.

The authoritative evidence must record the exact reference transcript actually used.

---

## 5. Benchmark identities

Create stable benchmark identities:

```text
BHM01
BHM02
```

Description:

```text
Language: en-GB
Accent: strong Birmingham / West Midlands
Domain: commercial VO
Speaker: private operator-supplied benchmark identity
```

Create cross-holdout cases:

```text
BHM-XH-01
condition: BHM01
target text: BHM02
ground truth: BHM02 human

BHM-XH-02
condition: BHM02
target text: BHM01
ground truth: BHM01 human
```

---

## 6. Renderer policy

Operational renderers:

```text
qwen3
voxcpm2
chatterbox
```

Do not add MOSS, Microsoft, ElevenLabs integration, or another renderer.

Use the exact pinned runtime/model identities already established by RB-005.

Do not upgrade packages or model revisions merely for RB-006.

---

## 7. Baseline settings only

RB-006 is the **untuned control experiment**.

Use the established/default renderer-native clone settings already documented for each renderer.

Do not:

- search parameter space
- optimize reference crops
- tune CFG
- tune exaggeration
- tune temperature/top-p/top-k
- tune inference steps
- denoise the reference to improve cloning
- select a hand-picked “best” reference subsection
- use the human target recording in any way as renderer conditioning

If a renderer has unavoidable stochasticity, simply record that fact.

Do not invent deterministic seed control where the adapter does not support it.

---

## 8. Persistent-run design

Prefer one persistent loaded-model session per renderer.

Within that session:

```text
health
load once

BHM01 → BHM02 run 1
BHM01 → BHM02 run 2
BHM01 → BHM02 run 3

BHM02 → BHM01 run 1
BHM02 → BHM01 run 2
BHM02 → BHM01 run 3

shutdown
```

The reference may change per render request; the model must not reload merely because the reference changed.

Persist lifecycle and timing truth exactly.

---

## 9. Ground-truth separation

For each direction, distinguish:

```text
conditioning reference
target text
human ground-truth target recording
generated candidate
```

The human ground-truth target recording is **evaluation-only**.

It must never be passed to the renderer or used to derive conditioning.

This prevents data leakage.

---

## 10. ElevenLabs benchmark policy

The supplied ElevenLabs renders are a **closed external market benchmark**.

Preserve them untouched.

Do not:

- integrate ElevenLabs API
- use ElevenLabs outputs as conditioning
- tune Qwen/Vox/Chatterbox against ElevenLabs
- infer that ElevenLabs used the same conditioning architecture
- claim a fair conditioning-parity comparison unless provenance proves it

For human audition, place the supplied ElevenLabs generations beside the open-renderer outputs for the corresponding target text.

Record clearly:

```text
closed benchmark
operator supplied
conditioning parity unknown unless explicitly documented
```

---

## 11. Mandatory automatic measurements

The automatic system should do as much objective pre-analysis as is technically defensible.

### 11.1 Mandatory model-free / signal measurements

For every human ground truth and generated output record at least:

- duration
- sample rate/channels/codec
- active-speech duration where robust
- silence/pause proportion
- basic level statistics
- voiced fraction
- F0 median
- F0 lower/upper robust percentiles
- F0 range in semitones
- basic spectral/timbral descriptors
- MFCC summary statistics
- run-to-run variation for the three generations

Do not treat any one acoustic statistic as “speaker identity”.

### 11.2 Text/intelligibility measurement

If a licence-compatible, local ASR dependency can be added without destabilizing the renderer environments:

- transcribe each generated result
- compare with exact intended target text
- report WER/CER or equivalent
- preserve actual hypothesis text

Any new ASR code/model/weights must have a documented licence/provenance gate before use.

If that gate cannot be completed cleanly, mark this metric unavailable rather than blocking the entire milestone.

### 11.3 Speaker-similarity measurement

If a suitable local speaker-embedding/verifier can be used:

- compare every generated result with the **withheld human target recording**
- also compare BHM01 human vs BHM02 human to establish a same-speaker reference ceiling/context
- report raw model score/cosine similarity
- record exact model, version, weights, preprocessing, and licence

Any speaker-analysis model is an evaluator, not authority.

Do not call its output “percent the same person”.

Again, any code/weights added here require explicit licence/provenance documentation.

### 11.4 Accent

Do **not** invent a single automated “Birmingham accent score”.

Accent fidelity remains primarily a human listening judgement.

You may preserve phonetic/acoustic observations that could later support accent analysis, but do not turn them into a false authoritative number.

---

## 12. No aggregate magic score

Do not collapse all measurements into one winner score.

Keep dimensions separate.

For example:

```text
identity similarity
text accuracy
pitch behavior
timing/pause behavior
timbre descriptors
run consistency
```

A renderer may lead one dimension and lose another.

Human listening remains final authority.

---

## 13. Derived audition copies

Never modify originals.

Create derived audition copies in a separate folder.

Create at least:

### `audition_raw_pcm`

- 48 kHz
- mono
- PCM WAV
- simple format conversion/resampling only
- no loudness processing

### `audition_level_matched`

- derived from the raw audition copies
- 48 kHz mono PCM WAV
- gain-only loudness matching
- no compression/limiting/EQ/noise reduction
- record the exact gain applied to every file

Do not use level-matched copies as authoritative source evidence.

Their purpose is only to reduce loudness bias during human comparison.

---

## 14. Listening bundle

Create an identified listening bundle for each target.

Example:

```text
BHM01_target/
  HUMAN_ground_truth.wav
  QWEN_run1.wav
  QWEN_run2.wav
  QWEN_run3.wav
  VOXCPM_run1.wav
  VOXCPM_run2.wav
  VOXCPM_run3.wav
  CHATTERBOX_run1.wav
  CHATTERBOX_run2.wav
  CHATTERBOX_run3.wav
  ELEVENLABS_gen1.wav
  ELEVENLABS_gen2.wav
  manifest.json

BHM02_target/
  ...
```

This milestone is **identified listening**, not blind mode.

Do not ask the machine to invent subjective ratings.

---

## 15. Evidence layout

Suggested root:

```text
BenchData/qualifications/RB006-Birmingham-Baseline/<run-id>/
```

Within it preserve:

```text
inputs/
metadata/
renders/
measurements/
audition_raw_pcm/
audition_level_matched/
listening-bundle/
report/
```

Use symlinks/manifests where possible rather than duplicating private originals unnecessarily.

Every generated render must retain the normal authoritative RendererBench run evidence and run ID.

The qualification layer may reference those run IDs; it must not replace normal evidence storage.

---

## 16. Report

Produce both:

```text
report.json
report.md
```

Report by cross-holdout direction and renderer.

Include:

- exact human input identity/hash
- exact transcript used
- exact target text/hash
- renderer/model/runtime/backend identity
- native settings
- generation run IDs
- durations/timings/RTFs
- automatic measurements
- run-to-run consistency
- ElevenLabs benchmark file references
- limitations
- no subjective winner

Include a compact comparison table, but preserve raw measurements separately.

---

## 17. Human-vs-human reference context

Because BHM01 and BHM02 are real recordings of the same speaker, compute the same available acoustic/speaker measurements between:

```text
BHM01 human ↔ BHM02 human
```

This is valuable context.

It demonstrates how much the same real speaker naturally differs across two performances.

Do not treat human-vs-human similarity as an absolute mathematical ceiling unless the evaluator specifically justifies that interpretation.

---

## 18. Regression protection

Before real rendering:

```sh
swift test
swift build -c release
```

After RB-006 changes:

```sh
swift test
swift build -c release
```

All existing RB-005 tests must remain green.

New qualification-analysis tests must be model-free unless explicitly opt-in.

Do not make ordinary `swift test` download analysis models.

---

## 19. New tests

Add model-free coverage for at least:

1. qualification manifest parsing
2. cross-holdout direction validation
3. conditioning and ground-truth assets cannot be the same asset
4. target human file cannot enter renderer request conditioning
5. three-run evidence remains distinct
6. three renderer IDs coexist without collisions
7. SHA-256 provenance persists
8. exact transcript hash persists
9. baseline/native-settings policy is recorded
10. ElevenLabs external-benchmark flag persists
11. raw audition conversion does not overwrite originals
12. level-match metadata records applied gain
13. measurement unavailable states are explicit
14. no aggregate subjective winner is synthesized

If implementation remains script-only, provide equivalent automated checks.

---

## 20. Do not do

Do not:

- optimize renderer settings
- build the self-tuning loop
- use final human target audio as conditioning
- add a fourth renderer
- integrate ElevenLabs API
- build blind mode
- build scoring UI
- build Brand Master
- build Teach Pronunciation
- build brand-style learning
- build Actor Model
- implement Exact/Adjust/Interpret
- build session matching
- build presence synthesis
- fine-tune any model
- alter original human or ElevenLabs files
- claim accent fidelity from an automated metric
- declare a subjective winner

---

## 21. Acceptance criteria

RB-006 is complete when:

1. BHM01 and BHM02 are stable private benchmark identities.
2. Asset hashes/metadata are recorded.
3. Candidate transcripts have been checked and authoritative reference transcripts recorded.
4. Qwen, VoxCPM2, and Chatterbox remain on the exact pinned RB-005 identities.
5. Each renderer conditions only on the designated source recording.
6. Each renderer generates the opposite/withheld target text.
7. Three independent outputs exist per renderer per direction.
8. All 18 open-renderer outputs pass common WAV validation.
9. Human target recordings remain evaluation-only.
10. Mandatory model-free measurements are complete.
11. Optional ASR/speaker-verifier metrics are present only if licence/provenance gates pass.
12. Human-vs-human context measurements are present.
13. Supplied ElevenLabs outputs are preserved as external benchmarks.
14. Raw and level-matched listening copies are created without modifying originals.
15. Identified listening bundles are ready for operator audition.
16. `report.json` and `report.md` exist.
17. All pre-existing tests remain green.
18. New qualification checks/tests pass.
19. No renderer was tuned.
20. No subjective winner was invented.
21. RB-007 has not begun.

---

## 22. Deliver back

When finished report:

1. transcript-verification result
2. exact BHM01/BHM02 asset hashes
3. exact renderer identities confirmed
4. exact run IDs for all 18 renders
5. generation/timing summary
6. automatic measurement summary by renderer and direction
7. human-vs-human measurement context
8. any ASR/speaker-evaluator models added, with licence/provenance
9. listening-bundle locations
10. raw vs level-matched audition locations
11. ElevenLabs benchmark mapping/limitations
12. regression-test result
13. known limitations
14. architecture changes, if any
15. proposed RB-007 only — do not begin it

---

## 23. RB-007 boundary

RB-007 is intentionally not authorized here.

The likely next experiment is:

```text
same Birmingham cross-holdout
+
automatic renderer-native optimization loop
```

The scientific comparison will then be:

```text
RB-006 untuned baseline
vs
RB-007 self-tuned optimum
```

That delta measures the value added by the optimization layer rather than merely the underlying renderer.
