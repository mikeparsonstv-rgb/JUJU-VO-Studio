# Renderer Bench — Key Findings

Last updated: 2026-08-08

## Renderer boundary

Keep requests, results, capabilities, descriptors, and health renderer-neutral. The controller chooses an adapter by ID and never branches on Qwen, VoxCPM, Chatterbox, MOSS, or Microsoft. This keeps model dependencies replaceable and makes unavailable engines ordinary bench state.

## Historical interpretability

Do not store only a renderer ID. Snapshot the descriptor, declared capabilities, version/checkpoint, settings, environment, and timing inside each result. Today's registry will change; old evidence must remain understandable without reconstructing old code.

## Non-overwriting run identity

A test ID identifies the canonical test, not one execution. Insert a unique run ID between test ID and renderer ID:

```text
runs/<test-id>/<run-id>/<renderer-id>/
```

This permits fair reruns while preventing accidental loss of prior outputs.

## Failure isolation

Persist the request before calling an adapter. Catch adapter errors at the runner boundary and serialize them into a normal unsuccessful `RendererResult`. The error path should not fabricate an audio path. Unknown registry IDs remain caller/configuration errors; known-but-unavailable renderers are recorded benchmark outcomes.

## Deterministic WAV fixture

A dependency-free architecture fixture can be produced as PCM RIFF/WAVE: 48 kHz, mono, signed 16-bit little-endian samples, with a 44-byte header. A one-second fixture contains 48,000 samples and is 96,044 bytes. A short fade at both ends avoids clicks. This proves file creation and playback plumbing without confusing synthetic audio with a real candidate renderer.

## Swift date persistence

The default JSON `Date` Codable representation round-trips the runner's sub-second timestamps exactly. Basic ISO-8601 encoding can discard fractional seconds and caused equality failure during the first persistence test. Any future human-readable timestamp format must explicitly retain adequate fractional precision and be migration-tested.

## Test fixture versus active renderer

The deterministic mock must be visibly marked `isTestFixture` and filtered out of the active renderer list. Test infrastructure should never silently become a sixth candidate or distort the five-renderer policy.

## External worker protocol hygiene

Pass arbitrary text and paths as JSON over stdin, never through shell-concatenated command strings. Reserve stdout for one versioned machine-readable response and route diagnostic output to stderr. Invoke the executable directly with an argument array, impose a timeout, terminate a hung process, and verify response/request IDs. This boundary is reusable for every local model worker.

## Success requires independent artifact validation

An adapter's success claim is not sufficient. The common runner must independently require the promised output to exist, be non-empty, parse as the expected audio container, contain actual audio data, and have a finite positive duration. Use the validated container duration/sample rate in persisted results. This prevents a renderer-specific worker bug from creating false-positive benchmark evidence.

## Failure metadata must survive exceptions

Renderer errors should be able to carry a renderer-neutral environment snapshot. The runner can then persist package, revision, device and timing evidence even when generation fails, without understanding the engine that produced it.

## Capability claims belong to the exact exposed path

Family-level features are not adapter capabilities. A family may support streaming or instruction control while a selected checkpoint or current integration does not. Declare only the operations actually exposed and tested, and reject unsupported direction/settings rather than silently ignoring them.

## GPU availability can be sandbox-dependent

Hardware backend probes must be run in the same execution context as the renderer. On the RB-002 Mac, PyTorch MPS was built and available outside the file sandbox but reported unavailable inside it. Treat a sandboxed negative probe as contextual evidence, not automatically as an upstream Apple Silicon blocker.

## Persistent child-process protocols need nonblocking framing

For a long-lived JSON-lines worker, poll the stdout file descriptor and then use the underlying POSIX `read`; Foundation's `FileHandle.read(upToCount:)` can wait for the full requested length on a still-open pipe even after `poll` reports readable data. Keep a byte buffer, split only at newline boundaries, validate protocol version and request ID, and treat malformed JSON, EOF, timeout, or uncertain model state as a reason to terminate and restart. Graceful `shutdown` is the normal path; terminate and kill are fallbacks.

## Separate lifecycle timings by what they actually measure

Worker launch, Python imports, model deserialization, generation, adapter round-trip, output duration, and realtime factor are different measurements. Process age is not startup time, model-cache inspection is not import time, generation time is not first-audio latency, and a first render after an explicit load can be `cold_start=true` while still reporting `model_reused=true`. Persist those distinctions instead of compressing them into one ambiguous duration.

## Backend comparisons require identical persisted requests

Compare accelerators only when script, reference audio, reference transcript, language, checkpoint, tokenizer, seed, and settings match. Persist requested and actual backend separately and fail forced backends rather than silently falling back. Matching inputs and seeds do not prove deterministic cross-backend output; different output durations in the RB-003 MPS and CPU runs demonstrate why timing evidence must not be misreported as output equivalence.

## Reference assets need a rights gate as well as a schema

A technically convenient voice sample is not automatically a benchmark asset. A reusable catalogue entry needs known provenance, licence, redistribution permission, exact transcript, language, speaker description, and audio characteristics. If those facts are unavailable, preserve the schema and blocker, accept an operator-supplied local path, and commit no private or ambiguously licensed audio.

## Preserve model lineage separately from runtime conversion

An accelerator conversion is not the same historical identity as its upstream checkpoint. Persist the upstream model/revision, conversion repository/revision, runtime package/revision, and actual backend separately. This lets evidence say “VoxCPM2 through this BF16 MLX conversion” without implying byte-identical PyTorch/CUDA execution.

## Verify the runtime path, not just its API names

An argument can exist without affecting generation. In pinned mlx-audio 0.4.6, VoxCPM2 accepts `ref_text` but the generator does not use it; transcript-conditioned generation actually uses `prompt_text + prompt_audio` continuation. Adapter design must follow inspected and exercised implementation behavior, and metadata should name the real mode used.

## Persistent model load and first-generation warmup are distinct

Loading weights can complete before an accelerator has compiled or warmed its execution graph. The first VoxCPM2 generation was materially slower than later renders despite `model_reused=true`. Keep explicit model-load time separate from cold-generation time, and do not treat a fast deserialization number as full cold-start cost.

## Fair comparisons preserve inputs, not meaningless controls

Two renderers can share script, reference identity, transcript, language, machine, validation, and evidence layout while retaining different native generation controls. Do not force diffusion steps/CFG into a fake mapping with sampling temperature/top-k, or claim equivalent seed semantics. Persist each renderer's requested and actual settings and compare only genuinely shared outcomes.

## Stable local asset identity can coexist with private storage

Commit non-sensitive reference metadata under a stable asset ID and resolve the actual WAV through a gitignored local mapping. Persist the asset ID in every result. This makes repeated local comparisons traceable without placing private or ambiguously licensed recordings in source control; rights status remains explicit and the mapping can be replaced only through an intentional operator action.

## Variant identity must be enforced when upstream defaults are historical

An upstream family loader can expose a new model while retaining an older default for compatibility. Chatterbox's multilingual loader still selects V2 if `t3_model` is omitted. Pinning a repository is therefore insufficient: pass the intended variant explicitly, verify the resolver's exact filename, persist both, and reject incompatible requests.

## Transitive runtime data belongs in the provenance and isolation gate

Python package locks do not capture every model-like runtime download. Chatterbox's multilingual tokenizer triggered spaCy-pkuseg to fetch a segmentation archive during first load. Treat transitive data assets like weights: identify their licence/source/version, route their cache into the renderer-owned model directory, prefetch during setup, hash known artifacts, and include them in health readiness.

## Official convenience loaders still need backend assertions

A documented accelerator option can coexist with silent fallback behavior. If a benchmark requires MPS, persist requested and actual backend, verify framework availability, inspect the loaded model's device after construction, and fail rather than accepting CPU.

## Reference transcript availability and consumption are separate facts

A controlled comparison may supply a common transcript even when one renderer's clone API uses reference audio alone. Persist whether the transcript was available and whether the renderer actually consumed it. Manufacturing a fake transcript argument obscures architectural differences; dropping availability obscures input comparability.

## Provenance behavior includes output watermarking

If an official generator applies a watermark as part of inference, preserve and record that behavior rather than removing it for convenience. Expected/enabled/system/version metadata makes results interpretable, but it is not the same as independently detecting the watermark in finished audio.

## Listening bundles should carry portable result metadata

Copied WAV files are not self-explanatory. Place each selected result JSON beside its audition file and have the manifest use relative links while retaining original source-result locations. This keeps a local bundle intelligible if a source run moves or a temporary directory is cleared.

## Copy text and spoken reference transcript are different evidence

A UI screenshot can prove intended copy but not the exact words actually spoken. Transcript-conditioned cloning must use a transcript verified against the reference recording, especially when copy contains typos, articles differ, or performers pluralize and add interjections. ASR can locate high-confidence discrepancies and timestamps, but it must not silently become authority; material differences require an explicit operator decision and a new authoritative transcript hash.

## Performed interjections belong to transcript authority

Do not automatically strip laughter-like lexical interjections as noise. If the operator confirms an opening or closing `Hah!` as part of the performed reference, retain it in the authoritative transcript and hash. Whether ASR lexicalises an interjection is assistive evidence, not a reason to erase performance material.

## Cross-holdout prevents memorized-word evidence from dominating

Condition on recording A while generating the verified words from recording B, then reverse the direction. Keep the withheld human target evaluation-only and validate that its asset path never enters the renderer request. This tests generalization of voice characteristics to unseen copy instead of rewarding reproduction of phrases already heard in conditioning.

## A valid WAV is not necessarily a complete render

Container validation proves decodability, format, data presence, and duration—not that all requested words were spoken. RB-006 VoxCPM2 outputs all passed WAV validation while truncating severely. Long-form qualification therefore also needs expected-text ASR, hypothesis word counts, duration context, and human listening.

## Fixed-seed repetition and stochastic sampling are different experiments

Three separate renderer calls with the same supported seed can prove lifecycle independence and exact repeatability, but identical results must not be described as three independent stochastic samples. Record both the call count and seed policy so later analysis distinguishes stability from diversity.

## Preserve failures in an untuned control

When a baseline renderer truncates, varies, or performs slowly, do not rerun until a favorable sample appears. Retain every planned output, report the failure mode, and leave diagnosis or optimization to a separately authorized milestone. Otherwise the control becomes silently selected evidence.

## Level matching should remain a reversible audition derivative

Keep raw authority untouched. For comparative listening, create a separate gain-only copy using attenuation to the quietest active-speech RMS in each target group. Record every applied gain and avoid limiting, compression, EQ, denoising, or enhancement; those processes can change the very voice qualities under evaluation.

## Optional evaluators require their own gate and unavailable state

An analysis model is another dependency and provenance surface. Install it in an isolated locked environment, record source/licence/version/model hash/device, and state its limited role. If no suitable speaker verifier passes that process, record `unavailable` with a reason instead of substituting MFCC distance or inventing an identity score.

## Performed span is not file duration

Timing comparisons should use first meaningful speech onset through last meaningful speech offset. This excludes arbitrary head/tail silence while retaining internal pauses. Persist onset, offset, active speech, internal-pause duration/proportion, and the exact detector parameters; otherwise “match duration” can mean incompatible things.

## Oracle timing must be labelled as evaluation leakage

In cross-holdout work, withheld human timing cannot become an ordinary generation input. It can answer a diagnostic question only as a post-generation derivative labelled `oracle_target_performed_span`. Keep renderer request count at zero and distinguish this experiment from production new-copy behavior, which must inherit normalized source pace rather than target seconds.

## Completeness precedes time repair

Never stretch truncated speech to look duration-correct. Apply transcript coverage and intelligibility gates before the ratio calculation, persist every exclusion, and keep incomplete originals as failure evidence. A 6-second fragment expanded to 30 seconds is not a repaired read.

## Ratio guardrails preserve diagnostic validity

Time stretch is not harmless at arbitrary ratios. Fix a defensible range before listening and do not widen it to increase sample count. RB-007 retained 0.85–1.20, admitting six Qwen, one Chatterbox, and two ElevenLabs derivatives while excluding five Chatterbox and two ElevenLabs calls as out of range.

## Decoder paths can violate a gain-neutral experiment

Container decoding is part of the signal path. Direct AVFoundation MP3 decoding attenuated the supplied market benchmarks by about 3 dB even at unity time scale, while PCM inputs remained neutral. A preservation experiment must run a unity control per source type; use a frozen, provenance-linked resample/channel-only PCM copy when container decoding itself changes level, and retain the rejected attempt outside primary evidence.

## Timing tolerance and collateral descriptors are engineering gates, not listening results

Verify target-span error, active RMS, F0 median/range, spectral centroid, MFCC distance, pause proportion, and ASR before audition. These checks can expose unintended movement but cannot prove identity retention, regional authenticity, naturalness, or improvement. RB-007 holds all repaired spans within 50 ms; audible stretch artefacts still require a human.
