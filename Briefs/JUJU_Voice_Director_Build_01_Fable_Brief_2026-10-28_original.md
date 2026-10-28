# JUJU Voice Director — BUILD 01: Connected Engineer

**Implementation handoff to Claude Fable 5.1**  
**Date:** 28 October 2026  
**Status:** Approved product direction; implementation specification, not a claim that features exist  
**Revision:** 1.1 — WAV-to-session recall, export-embedded Job/Take UUIDs, and complete per-job parameter persistence  
**Primary machine:** Apple Silicon Mac Studio M1 Ultra, 128 GB unified memory  
**Product philosophy:** A voice-over session, not a TTS interface. The director directs; the Engineer understands and operates; the actor performs.

## 0. The assignment — read before changing code

Build the first genuinely usable **JUJU Voice Director** macOS studio around the existing JUJU/TalkBack/CuePitch voice-work architecture. The first experience is job-centric and conversational: open the app, find a past job or create a new one, paste the script, **Connect to Engineer**, cast a named actor through natural speech, make takes through VoiceStudio / Voicebox / direct Qwen, and revisit client history without reconstructing settings. **Every exported WAV is also an entry point back to its exact JUJU job and take: drag it onto the JUJU icon and restore that read.** Run controlled shootouts. Add a limited but real voice-to-voice performance experiment.

**Use Claude Fable 5.1 as the coding/implementation agent, not as a required component of the finished app.** For the in-app Engineer, prototype a provider-independent interface, with OpenAI Realtime/GPT-Live as the primary conversational candidate and a local speech-recognition + instruction model + Gradium Phonon path as an alternative. Compare them in the actual app; do not weld the product to either. Phonon is the Engineer's optional spoken output, never a substitute for the high-quality actor renderer. A reported ~7 ms Phonon synthesis start is not an end-to-end conversation-time guarantee.

**Do not generate a greenfield replacement for the user's functioning renderer bench.** Start by inspecting the actual local repository, operating-system SDKs, available apps, model directories, and existing build/test status. Do not infer that historical paths still exist. Report discovered paths, checksums, available API contracts and limitations. Preserve existing working assets. Make additive, independently testable changes and keep the old benchmarks auditable. The user will conduct this work on their own Mac; no part of this brief implies those local files have been modified.

The core product and operating principles come from the existing `TALKBACK_END_GAME.md`: persistent Voice Master independent of the renderer; non-destructive takes; human direction compiled to a renderer-neutral performance representation; separate Exact / Adjust / Interpret operations; protected approved material; every take saved; natural shorthand; the technology disappearing during a session.

The authoritative **last accessible renderer handover** is `PROJECT_HANDOVER(6).md`, 9 August 2026, RB-007. It describes a Swift 6.2/Xcode 26-compatible package targeting macOS 26, `RendererBenchCore`, renderer-neutral requests/results, common WAV validation, isolated version-locked Python workers, provenance, operational adapters for Qwen3-TTS 0.6B Base / VoxCPM2 / Chatterbox, and placeholder IDs `moss` and `microsoft`. Preserve frozen evidence at `BenchData/qualifications/RB006-Birmingham-Baseline` and `BenchData/qualifications/RB007-Timing-Repair` unchanged. It reports 85 passing tests, VoxCPM2 long-form truncation, Chatterbox variability, and Qwen as the subjective baseline leader. It **does not** establish reliable performance-direction control. Inspect current reality before proceeding.

## 1. What the director should experience

The app should feel like entering a familiar recording studio. It has three participants:

- **Director:** the human user, speaking naturally, offering a performance example or using the ordinary UI.
- **Engineer:** a fast, polite AI assistant which recalls jobs, casts actors, interprets directions, operates deterministic tools, gives short truthful acknowledgements and returns the revised take.
- **Actor:** a named voice identity, rendered by whichever qualified voice model or service is appropriate. The Actor is not the Engineer.

### 1.1 First opening

Home presents **New Job** and **Recent Jobs**, sorted by last activity, newest first. A row shows job name, client/brand, market, currently selected or approved actor name, number of takes and last-used date. Search may be exposed unobtrusively; no forced wizard. All examples here are illustrative placeholders until real persisted data exists.

New Job displays only:

- Job Name
- Script paste/edit area
- **Connect to Engineer**

A small Settings affordance is available. The larger conventional UI—actor dropdowns, audition list, engine selector, take strip, script editing, playback, pronunciation and more—can grow progressively, but it must use exactly the same state and tools as spoken conversation. Never construct two separate truth stores for voice and UI.

After Connect, the Engineer greets briefly; it must not commence continuous microphone upload without prior user permission and a visible state indicator. On first connection request microphone permission and explain online/local processing. A disconnect/mute action must always be available.

### 1.2 Existing job

Director selects a recent job. Restore the actual saved script, cast, voice references, selected actor, take list, approvals, direction history, applicable pronunciation/brand profiles, engine settings and working context. If connected or when connection is established, Engineer says:

> “Welcome back. Are we continuing this job, or using these settings for a new one?”

**Continue** leaves the job intact. **New from settings** creates a distinct new job with a new identity, optionally copied script if asked, inherited reusable cast/voice profiles and suitable settings, but a fresh take sequence and independent approvals. Never relabel or move historical takes into the new job.

### 1.2A Return from an exported WAV — mandatory first-class entry point

The user may be sent an audio file they made months ago, or the client may provide only the exact filename. **That WAV is the shorthand for the entire job and take.** The director must not need to remember the client, job, actor, voice engine, original prompt, take number or other history.

Real-world interaction:

> Client: “We used `LenorGermany-Anna-2026-10-28-Line03-Take04.wav`. Could we change the last line?”  
> Director locates the WAV on the Mac, drags it onto JUJU Voice Director's application icon in Finder/Dock, or drops it into the app.  
> JUJU resolves its embedded immutable identifiers to the corresponding saved job and exact original take, opens that job, selects the read and shows its playback waveform.  
> Engineer (when connected): “Welcome back. I've got Anna's line three, take four, from Lenor Germany. Are we making changes to this today, or doing something new with the same settings?”

Two responses:

- **Continue/edit this job:** retain original job and selected take; new renders/pickups become *additional* takes or derivatives, never overwrite the original/client-approved file.
- **New job, same setup:** ask for a new job name; copy/reference reusable settings, approved actor/voice rights, market, language, pronunciation, performance direction and render profiles, creating new job UUID and new take identities. The source job and all its audio remain unchanged.

Engineer speech and microphone activation must follow the same explicit connection/permission rules as normal opening. The welcome state is visible as text regardless of connection; do not silently turn on remote voice services just because a WAV was dropped.

If the user possesses **only the filename**, they may search their Mac's disk/archive, find that WAV and drop it: **exactly the same process**. Optionally expose a small in-app filename search field against the saved local export index for convenience; it is not necessary to create a separate recovery mechanism or new project wizard. There is no requirement for a client to have JUJU installed.

**Success means the original read is immediately on the desk**, with the original job state and exact actor/take selected—not a blank script, a freshly created job, or a generic import screen.

### 1.3 New job with prior-client memory

On New Job, the Engineer can ask:

> “Is this completely new, or another job for a client we've worked with?”

Director says:

> “Another Lenor detergent commercial for Germany.”

Look up jobs by client, brand/product, market/locale and recency. Do not blindly choose the chronologically newest unrelated project. Show what was matched and ask succinctly:

> “Last time on Lenor Germany we used Anna with a warm, natural read and saved brand pronunciation. Shall I bring those settings over?”

On approval, create an independent job using the relevant *reusable* values. Preserve the previous project's script, audio, approvals and take numbering separately. When a brand has several locales, **Germany de-DE, Austria de-AT, Swiss Standard German de-CH and Swiss German dialects are distinct choices**; similarly French for Switzerland is separate from metropolitan French. Never silently substitute dialects.

A rights check is required before reusing a host-supplied/cloned voice on a new client, job, geography or purpose. If reuse is not authorised, offer suitable alternative auditioning, not a silent clone.

### 1.4 Conversational casting

> Director: “I'd like an English female voice, early 30s, from Manchester.”  
> Engineer: “Sure. I'll find a few Mancunian voices. Shall we try them on your script?”

Translate natural language into a casting brief. Keep gender **presentation**, approximate **perceived** age, language, accent/dialect, timbral character, performance style and rights/availability as separate fields. Search approved local actors first and then permitted synthesis/voice-design options. Offer two or three audition reads from the same script passage. Do not claim unverified regional authenticity. An English-speaking 'Northern' approximation is not guaranteed to be Mancunian.

> Director: “She's a little posh. Have we got someone more fun?”

Interpret this primarily as a **casting search**: retain female, approximately early 30s, Manchester unless corrected; seek less RP/polished and more approachable/playful alternatives. Do not change the current actor's identity and pretend that solves a casting request. Compare alternatives without deleting existing auditions.

> Director: “The first one's great. Can she be a little more mischievous?”

Interpret this as **keep actor; vary performance**. Names persist: Jane, Lucy, Anna, etc. Display **CURRENT ACTOR: Jane** prominently. A human-cloned voice is named by its supplying/authorising **voice host**, not by the Engineer. The host-supplied name is authoritative and cannot be silently renamed; keep immutable internal identifiers and permission provenance separately. Generated or licensed catalog voices can have human-friendly aliases, clearly distinct from real people.

### 1.5 Taking direction

> Director: “Right, let's go for a take.”  
> Engineer: “Okay, locking in Jane for this next read.”

This **locks the exact current actor binding for that one pending take**, with all engine-specific profile identities and versions captured. It is not a permanent job-wide casting approval. Render, validate, save, then play. The Engineer should never say “ready” until the output exists and has passed validation. Every generation is retained non-destructively even if disapproved.

> Director: “Can we make it more like this — today ONLY at our store?”

Detect the instruction and the spoken demonstration as different spans; save the actual guide recording. Analyse words/alignment and relevant pitch, stress, pause, energy, cadence and apparent emotional intention. Apply the best **supported** performance path (see Section 6); do not pass unspecific invented emotion values to an engine that ignores them. The Engineer returns a new take and preserves the previous one.

### 1.6 Spoken examples, pickups and protection

Commands to support or correctly defer:

- “Again, less salesy.”
- “Keep that first sentence.”
- “Try Jane instead of Lucy.”
- “Go back to the second take.”
- “Just the last two words, more conviction.”
- “That's the one.”
- “Try something completely different.”
- “Make it 30 seconds.”

For Build 01, implement the common full-line/full-read cases with correct state and best-effort direction; record unsupported surgical edits as an actionable request and tell the director what is possible. **Do not claim sample-accurate pickups, exact runtime or authentic emotion-transfer capabilities before they are tested.** The later end-game's Exact / Adjust / Interpret and intelligent infill remain explicit roadmap items.

## 2. First-build interface

### 2.1 Home

- Header: JUJU Voice Director; small Settings.
- New Job as a clear primary action.
- Scrollable recent jobs with metadata and search where appropriate.
- Sort by `lastOpenedAt`/`lastActivityAt`, stable newest first; reopen updates recency.
- Empty state: create first job, no dummy persisted projects.
- Opening a job restores state and triggers the conversational welcome when connected.

### 2.2 Studio

Calm 16-inch MacBook Pro-compatible layout, native SwiftUI, progressive disclosure. Default presentation:

```text
JUJU Voice Director               Job: Lenor Autumn DE         Settings

SCRIPT / CURRENT LINE                 CURRENT ACTOR
Today only at our store.             Anna
Discover something...                 German (Germany) · approved

[ waveform / play / transport ]       [ Engineer: Listening / Thinking /
                                        Rendering / Ready / Muted ]
TAKES
Line01: Take01  Take02  Take03 [approved]

[ Connect / Disconnect Engineer ]     [ text direction fallback ]
```

This is a hierarchy guide, not a demand for dense permanent columns. The app should stay legible during playback and hide secondary controls until requested. Preserve preferred JUJU design language: quiet native macOS affordances, no gratuitous animation, settings behind an affordance, 8-frame/approximately 320 ms fades where appropriate, no arbitrary sliders where numeric or natural-language control is better. Always provide manual alternatives to microphone operation.

Minimum controls: Create/Open job, save/paste script, Connect/Disconnect, microphone indicator/mute, actor display and auditions, engine selection in secondary controls, Play/Stop, take list and approval, manual Render, engine status, Settings.

### 2.3 Settings → Voice Engines

Show installed/available VoiceStudio, Voicebox, direct Qwen, status/health and model versions where detected; don't claim missing engines are installed. Reserve **ElevenLabs API Key**, masked and marked Future/Experimental. When wired, key material must live in macOS Keychain, never plaintext settings, logs, job archives or crash reports. **A full ElevenLabs v4 TTS integration is not a Build 01 prerequisite.** A small opt-in Voice Changer/speech-to-speech feasibility test may use that key if available and permitted.

### 2.4 Accessibility

Full keyboard operation, VoiceOver labels, readable status, text direction fallback, manually selected actor/line/take. Spoken interaction is a choice, not a gate to professional use. Maintain useful visibility of the current job/actor/take even when Engineer voice is disabled.

## 3. Data model — canonical JUJU ownership

Use GRDB/SQLite if it fits the repository's existing native database strategy; otherwise justify the persistence layer. Store media on disk and references in the database. Use stable UUIDs, schema versions, transactions, migrations, checksums and append-only events for critical actions. Everything below needs stable IDs distinct from display text:

- `Client(id, displayName, aliases, notes)`
- `Brand(id, clientID, displayName, aliases)`
- `Market(id, countryCode, languageTag, dialectTag?, notes)`
- `Job(id [UUID], name, clientID?, brandID?, marketID?, createdAt, lastOpenedAt, scriptRevisionID, sourceJobID?, status, settingsSchemaVersion, currentSettingsRevisionID)`
- `ScriptRevision(id, jobID, rawText, createdAt)` and `ScriptSegment(id, revisionID, stableLineNumber, text, order, character?)`; line numbers are logical segments, not UI line wraps.
- `VoiceMaster(id, displayName, origin: hostCloned|generated|licensed, hostID?, ownership/consent evidence, language/accent, reference media, rights restrictions)`
- `RendererProfile(id, voiceMasterID, engineID, backendVoiceID, modelVersion, conditioning, state, compatibility)`
- `JobActorBinding(id, jobID, voiceMasterID, selectedRendererProfileID?, audition/approved, jobSpecificNotes)`
- `CastingBrief(id, jobID, requestedVoiceAttributes, preservedConstraints, createdAt)` and `Audition(id, jobID, castingBriefID, actorID, takeID, rank/notes)`
- `EngineerSession(id, jobID, mode, provider, startedAt, lastStatus)` and `DirectionEvent(id, sessionID, targetSegmentIDs, transcript, intent, rawAudioAssetID?, proposedAction, confirmedAction, createdAt)`
- `PerformanceGuide(id, jobID, directorAudioAssetID, transcript, alignedSegments, timing/pitch/energy features, consent/cloud flags, provenance)`
- `Take(id [UUID], jobID, segmentID|fullRead, perLineTakeNumber, actorBindingSnapshot, rendererSnapshot, directionEventIDs, guideID?, inputHash, outputAssetID, status, createdAt, approvalState, immutableTakeSettingsSnapshotID)`
- `AudioAsset(id [UUID], kind, relativePath, checksum, codec, sampleRate, channels, duration, captureSource)`
- `PronunciationEntry(id, brandID?, marketID, writtenForm, approvedPhoneticForm, referenceAudioID?, evidence)`
- `EngineRun(id, engineID, version, inputHash, start/finish, settings, warnings, errors, executionEnvironment, timing, outputHash)`
- `ReusablePreset(id, sourceJobID, scope: client|brand|market|actor|job, version, includedFields, provenance)`
- `JobSettingsRevision(id [UUID], jobID, schemaVersion, canonicalSettingsJSON, createdAt, sourceJobSettingsRevisionID?, authoredBy)` — every setting required to resume/edit or clone a setup; immutable revisions not mutable-only blobs.
- `TakeSettingsSnapshot(id [UUID], takeID, jobSettingsRevisionID, resolvedCompleteSettingsJSON, scriptRevisionID, voiceMasterID, rendererProfileID, engineBuild/modelRevision, prompt/conditioning, guideReferencesAndHashes, randomSeedIfSupported, timingAndPerformanceConstraints, pronunciationRevisionID?, outputFormat, creationTimestamp)` — captures *resolved values actually sent* to renderer. Do not claim deterministic reproduction if engine or service does not support it.
- `WAVExport(id [UUID], jobID, takeID, sourceAudioAssetID, exportedPathOrName, exportedFileChecksum, exportTimestamp, exportSettingsSnapshotID, metadataSchemaVersion, byteFormat, sampleRate, bitDepth, channelCount)` — export is a distinct entity so a later sample-rate derivative still traces to the same take.
- `WAVRecallIndex(jobID, takeID, wavExportID, canonicalExportFilename, candidateAudioChecksum?, metadataVersion)` — SQLite indices for exact IDs and filename fallback; no sidecar should be required for the normal WAV-drop journey.

Persist **all resolved parameters**, including ones the user never saw in the UI: job-level preferences in versioned job revisions, and the exact actor/profile/engine/conditioning/output settings in immutable take snapshots. Capture application/build/version and backend feature availability for diagnosis. Separate reproducibility evidence from reproducibility guarantee. Persist a **snapshot of the actor/profile/engine on each take**: later changing to Lucy must never relabel Jane's earlier WAV. Reusing a preset should copy/reference appropriate reusable identities while keeping new job state, numbering, approvals and exported media independent. Approvals must identify a specific audio asset and script revision, not just ‘Take 02’.

Store job media in a known user-approved root, with safe path handling and security-scoped bookmarks if sandboxed. Atomic writes: temp file → validate → durable move/rename → database commit. Repair orphan temp files after crashes. Never overwrite a successful prior take or use opaque backend-generated filenames as public asset names.

## 4. Engineer: model-independent conversation-to-action layer

### 4.1 Design

The in-app conversational model is an **interpreter and dispatcher**, not the source of truth. It receives the current compact job state and exposes typed tools. Each tool is Swift-side deterministic code returning structured success/error. The model must not fabricate previous jobs, actor names, licenses, available model capabilities or completed outputs.

Candidate providers:

1. **Cloud rapid-prototype:** OpenAI Realtime / GPT-Live speech-to-speech interface with explicit function calling and interruption. Evaluate real microphone-to-acknowledgement latency and cost, and verify macOS transport/API handshake in current SDK docs. A generic vendor-adapter interface must support swapping models.
2. **Local alternative:** AVAudioEngine capture → FluidAudio streaming ASR/VAD/EOU → small local instruction model → Gradium Phonon 31M in Swift/Core ML for spoken replies; the app's tool dispatcher remains identical. Phonon is English-only in the 31M model, so do not imply multilingual Engineer support without a suitable voice model.
3. Optional research comparison: Gemini Live, using the same tool calls and saved dialogue scenarios.

Build a `ConversationProvider` protocol, a `StudioToolDispatcher`, a `SessionStateStore`, and an `AudioCoordinator` with one authority over microphone capture and playback. Avoid unnecessary network services for locally accessible operations.

### 4.2 Typed actions (illustrative API contract, adapt to repository)

```text
jobs.list_recent(limit, filter?)
jobs.find(client?, brand?, market?, text?)
jobs.open(job_id)
jobs.create(name, script_text?, client_id?, brand_id?, market_id?)
jobs.fork(source_job_id, new_name, inherit_fields[])
script.set(job_id, text, expected_revision)
casting.search(job_id, constraints, preserve[])
casting.audition(job_id, candidate_actor_ids[], segment_ids[])
casting.select(job_id, actor_binding_id)
voices.verify_rights(voice_master_id, job_id, market_id)
actor.lock_for_take(job_id, actor_binding_id, segment_ids[])
takes.render(job_id, actor_binding_id, segment_ids[], direction_id?, guide_id?, engine_id?)
takes.get_status(take_id)
takes.play(take_id)
takes.approve(take_id)
takes.compare(take_ids[])
guides.capture(job_id, segment_hint?)
guides.align(guide_id, script_revision_id)
performance.propose_change(target_take_id, guide_id?, natural_direction, preserve[])
performance.voice_convert(source_audio_id, target_actor_id, provider_id)
exports.get_take(job_id, take_id)
```

Mutating tools require validated job and object IDs, expected versions where collisions matter, and explicit confirm/authorization for rights-sensitive operations. `render` returns a **queued/run ID** first, not invented audio; `ready` follows successful completion and a validated asset. Use idempotency keys for retries, reconnects and duplicate model tool calls. Important ambiguous utterances (“go back to the second girl”) should ask a short clarification only if the recorded audition order genuinely leaves uncertainty.

### 4.3 Voice behaviour

Engineer is warm, brief and professional, never verbose or fawning. “Sure.” “Got it.” “I'll try Jane.” “That's ready, here you go.” Avoid narrating implementation details. A request to ‘Again, warmer’ normally triggers a new performance rather than a lecture about warmth. When engine functionality is unavailable, be transparent: “I can try a fresh read, but I can't transfer that exact performance with this engine yet.”

Use a state machine: `disconnected → connecting → listening → interpreting → toolRunning/rendering → ready/playback → listening`, with separate concurrent audio processing as needed. Engineer acknowledgements can arrive immediately; actual actor generation is asynchronous and must not block conversation. Treat interruptions: stop the Engineer's speech or current actor playback when the director speaks, preserve position, don't accidentally capture actor/Engineer playback as a new instruction. Use echo cancellation / far-end reference where available, headphone preference and appropriate gating.

### 4.4 Audio capture ownership

Capture the microphone **once**, then route time-stamped chunks to conversation provider, local STT, and optional raw guide recorder through a coordinator with explicit permissions. Keep raw and resampled versions separately. Common audio I/O may run 48 kHz on macOS; adapt to the particular cloud/model contract at its boundary. Keep original guide audio intact with SHA-256, timestamps, trim windows and microphone device details. Support mic hot-plug and denied permission without crashing.

Distinguish ordinary instruction, quoted examples, and demonstrated script performances. Do not include “can you do it like this” as part of the script audio to convert. Detect when the example begins/ends; offer a tiny recoverable retake control if automatic boundaries are wrong. If a director deliberately reads just the end of a sentence, align only those words and do not fabricate an unseen full-line performance. A speech recognizer is not an emotion analyser; keep the waveform and measure actual pitch contour, prominence, speech rate and pauses when supported.

## 5. Actor renderer integration and comparative shootouts

**VoiceStudio is the primary reference platform, not a mandate to embed its UI or source.** Its published service supports OpenAI-style speech generation, voice profiles, instructions, voice discovery and local API/MCP interfaces. Its API returns/accepts renderer-dependent capabilities; do not assume prose style prompts work in every engine. VoiceStudio’s application licence is AGPL-3.0-only; research with a separately installed program or process is distinct from copying proprietary-incompatible code. Review distribution obligations and separate model licences before embedding or bundling anything.

**Voicebox** is separately connected through its locally documented REST API (health, profiles, generation, history, audio retrieval). The user has a verified Voicebox app/source installation on their Mac; verify precise version and endpoints in the environment before writing the adapter.

**Direct Qwen** uses the **existing operational Renderer Bench Qwen3 0.6B Base** as the frozen baseline. Optionally add newer Qwen 1.7B Base/CustomVoice/VoiceDesign paths as separately versioned adapters only after capability inspection. Never treat a Base model as instruction-capable without evidence or overwrite pinned environments.

Implement an `ActorEngineAdapter` protocol:

```text
identify/version
health and load status
list existing voice profiles
capability declaration (text generation, supplied voice, design,
  explicit direction, speech-to-speech, audio infill, streaming,
  supported language, exact duration, stable seed, sample rate)
prepare voice binding
render(request) -> run status + validated audio/result
cancel(request)
measure provenance, warnings, error states
```

`RendererRequest` in existing `RendererBenchCore` should be reused or wrapped, not silently replaced. Renderer-neutral `DirectionIntent` is the stable value; adapters translate it only into controls genuinely supported by that renderer. Explicit `unsupported` is better than a fake success.

### 5.1 Two shootouts, not one

**A — Best each engine can do:** For the same script/casting brief, audition VoiceStudio's actual available engines, Voicebox's engine(s), and direct Qwen. Compare useful creative outcome, regional authenticity, first-take quality and time.

**B — Host-to-host parity:** Where VoiceStudio, Voicebox and direct runner can use the exact same Qwen weights/profile/reference/text/settings, compare them with tightly controlled conditioning. This isolates wrapping, inference backend, postprocessing and API behavior. If exact parity is impossible, record the reason and do not call it a fair same-model shootout.

Keep an optional **ElevenLabs v4 or Voice Changer reference** as external context, with clear model, settings, voice ID and cost. Do not call unmatched voice references a scientific quality comparison.

### 5.2 Metrics and listening

Capture model load time, cold/warm total render, time to first audio if genuinely streaming, real-time factor, clip duration, pronunciation, skipped/repeated words, WER/CER with human review, perceived actor identity, accent authenticity, timing, naturalness, performance intent, editability, failure/truncation rate and cost. All subjective decisions require human blind-ish listening and editorial notes. No fabricated aggregate winner or emotive-number score. Include several actual short-form commercial lines, 15/20/30-second passages, punctuation/brand-name challenges, a Mancunian audition and a de-DE passage; use authorised voice references and avoid leaking test holdouts to conditioning.

Freeze source, voice refs, prompts, and output hashes for each qualified run. Attach exact runtime version and model revision. Evaluate failures rather than filtering them out silently. Build a simple compare/play view in the studio; detailed reports can live in the bench.

## 6. Voice-to-voice performance and controlling it afterward

This is our potentially differentiating **voice-to-voice direction** track. It is **not** identical to ordinary text-to-speech direction.

### 6.1 Path A — Exact guide-to-actor conversion (Build 01 experimental milestone)

Director reads an actual script passage into the microphone; JUJU saves and isolates that performed span, verifies script alignment, chooses Jane's authorised destination voice, then uses an available **speech-to-speech/voice-conversion** backend. The first cloud candidate is **ElevenLabs Voice Changer**, which documents `POST /v1/voice-changer/:voice_id`, `audio`, `model_id`, optional per-request voice settings and output formatting. Use `eleven_multilingual_sts_v2` only after verifying availability for the account and target language; do not assume this is the same engine as ElevenLabs v4 TTS. Cloud transfer requires visible consent and an authorised account. The request should send only the intended guide recording, not the entire Engineer conversation.

The returned audio is saved as a new take with `method=speechToSpeech`, source guide ID, rights/account identification, backend model ID, voice ID, exact settings, duration, validation and hashes. The Engineer says “Here's Jane doing it your way” only when the take exists. Preserve original guide and prior takes. The product should make manual recording/upload feel unnecessary; an upload may still happen privately through the API, with the director's informed consent.

### 6.2 Path B — Change a voice-transferred performance using suggestions

**The hard unresolved question:** After translating a director's read into Jane's voice, how easily can the director say “slightly less posh”, “more fun”, or “less urgency” and get a changed *performance*, retaining the selected voice and previous successful nuances?

Do not invent a magical intensity slider. Treat this as explicit experimental branches:

1. **New guide** (most reliable first test): ask for or accept a new spoken demonstration, regenerate in the same target voice, compare.
2. **Modify the performance without new human audio:** extract a versioned `PerformanceIntent` / phrase-level timing and stress graph from the guide; test supported actor TTS/voice-design controls to generate a new guide/performance and optionally voice-convert that. Mark this as a *different* pipeline and listen critically for flattening, drift and unintended copy changes.
3. **Supported speech-to-speech settings:** assess whether a particular STS backend exposes actionable output controls (not just voice identity/stability). If the requested performance change cannot be expressed by the API, surface `unsupported` rather than implying control.
4. **Local post-edit/phrase regeneration:** only where editorially defensible, adjust timing/gain/small phrasing boundaries with explicit provenance; do not call time stretch a recreation of emotional intent. Never rewrite approved audio invisibly.

Test “more fun”, “less salesy”, “hold ONLY longer”, “less emphasis on only”, and “keep the beginning, change the ending.” For each distinguish: preserved text, voice identity, accent, performance change, untouched portions, artefacts and timing. Build a clear operator evaluation: did the requested change happen *without new guide audio*? If not, the Engineer should say “Can you give me another read of that part?” This is acceptable and useful.

### 6.3 Transfer limitations, must be honest

Speech-to-speech follows the provided words and recording; a 3-word demonstration does not itself generate an entire 30-second script. Vocal demonstration may carry unwanted pronunciation/accent. A model can change actor timbre without preserving all intonation, identity or emotional nuance. Do not conflate emotion recognition and successful acting. The full script remains the authoritative text: if the guide diverges, identify it and ask whether to use the exact copy or intentionally take an alternate. Protected copy/brand phrases cannot be silently changed.

## 7. File naming, delivery and approval

**No `elevenlabs8746578456487.wav` ever reaches the user as a take name.**

```text
<JobName>-<ActorName>-YYYY-MM-DD-Line01-Take01.wav
AutumnCampaign-Jane-2026-10-28-Line01-Take01.wav
AutumnCampaign-Jane-2026-10-28-Line01-Take02.wav
AutumnCampaign-Lucy-2026-10-28-Line01-Take01.wav
AutumnCampaign-Jane-2026-10-28-FullRead-Take01.wav
```

Use safe canonical names, preserving display names separately and clearly handling collisions. The date should reflect the local production date at take creation, not a later export date. Increment take numbers per job/actor/segment as consistently documented; never overwrite. If two actors have the same display name, preserve uniqueness through internal IDs and add a human-readable disambiguator when needed. Optionally support user-configurable naming later. Filename and in-app take label should agree.

Every accepted render is written immediately; approval is a separate flag/state, not a Save command. Approved audio is never modified in place. User can export selected take, approved sequence or all takes. Output should be clean PCM WAV at chosen delivery sample rate/bit depth, with no silent sample-rate conversion or loudness normalization: if conversion is required, create a derivative and record the change. Embedded WAV metadata contains the minimal immutable recovery identifiers, with full render provenance retained in JUJU’s local store; optional sidecars are supplemental only. The front-facing filename stays meaningful.

## 7A. WAV-to-session recall — core Build 01 functionality (not later polish)

### 7A.1 Data contract: a file can open its precise session

Every JUJU-exported WAV SHALL contain **the exact immutable job UUID and the exact take UUID** in the WAV file itself, plus an **export UUID** for distinguishing derivatives of the same take. The IDs are deliberately separate:

- `JUJU_JOB_UUID` → the owning project/session.
- `JUJU_TAKE_UUID` → the actual original take/performance and its saved context, regardless of renamed human-friendly filename.
- `JUJU_EXPORT_UUID` → which exported rendition was sent (e.g. 48 kHz/24-bit versus another delivery derivative).
- `JUJU_METADATA_VERSION` → format version for forward migrations.

Generate valid version-4 UUIDs (or repository-consistent UUIDs) at job/take/export creation. Do not use actor display names, timestamps, file paths or provider-generated strings as database keys. **Do not mistake export UUID for take UUID.** The same take may have many exports. Never recycle identifiers.

Recommended interchange method:

- Emit ordinary compatible PCM **Broadcast WAV (BWF)** with `bext` for human-friendly production information and a standard **iXML** chunk containing JUJU-namespaced fields in its `USER` extension; verify exact iXML structure against the current specification. Store full canonical UUID strings in iXML. iXML USER is intended for extensible application data; do not rely on nonstandard top-level element names.
- For an optional redundant BWF fallback, put a short `JUJU job=<UUID>; take=<UUID>` description in the 256-character `bext.Description` field if it fits. Note that `bext.OriginatorReference` is limited to **32 ASCII characters** and is subject to standard originator-reference conventions; never insert a hyphenated 36-character UUID there or truncate it without a documented reversible encoding. An appropriate originator reference may be used if interoperable, but iXML remains the canonical JUJU ID source.
- Write metadata on **every WAV export**, including audition WAVs, approved takes, renders and any exported comp that maps to a source take. For multi-take comps, use a separate immutable `CompID` and explicit source take list rather than falsely pretending that an assembly is one source take; scope an implementation separately if comps do not yet exist.
- Use a safe RIFF/WAVE/BWF writer/parser. Preserve PCM `fmt ` and `data` bytes and correct chunk sizes, padding and valid formats. Inspect and validate metadata after writing by reopening the *actual exported WAV*. Support modest metadata sizes; never embed private audio, API keys, full project configurations, host consent records, absolute file paths or full scripts in the exported file merely to make recall work.
- The WAV UUIDs are **lookup keys only**, not an authentication token or proof of ownership. When opening an unknown file, never automatically execute model operations, change approval states, send audio to cloud providers or mutate the saved job.

### 7A.2 Finder, Dock and in-app drag behaviour

Register `.wav`/`public.wav` as an **alternate** supported document type in the macOS application bundle, not the default player for all audio. Handle document URLs arriving when the app is closed or already open, using the supported `NSApplicationDelegate` / SwiftUI URL handling for the actual project architecture. Also accept drag-and-drop within the studio. Queue incoming URLs safely until app/database startup completes; support file access via macOS sandbox / security scope when applicable.

After receipt:

1. Validate the file is an actual readable WAV with safe chunk bounds; do not trust its extension.
2. Extract and validate JUJU metadata (UUID parse, version, consistency, no duplicate conflicting metadata fields).
3. Look up the job UUID in the local database. Look up the take UUID **within that job**. If provided, resolve export UUID and confirm association with that take.
4. Load the original job with *its current saved state*, restore its script and complete settings history; select the exact **historical** take and immutable take snapshot. Point the player at the original canonical audio. If the returned file is a different delivery derivative, show the corresponding export version instead of assuming the audio bytes are identical.
5. Place the selected take in the central playback area, wave ready to play, with job, actor name, script segment, take number, delivery/export source and status legible. Show the welcome conversation text, and speak it if the Engineer is already connected and enabled. Wait for director's choice: edit this job or use these settings for a new job.
6. Never silently overwrite, approve, regenerate or update old take audio as part of resolving a drop.

The saved job **retains all job parameters** and each take retains its actual renderer/voice/performance/format parameters (see Section 3). If director later requests a new take, the Engineer should explain which settings are inherited and any unavailable model/version/voice credentials before rendering. A historical session can always be browsed even if the original model cannot currently run.

### 7A.3 Metadata absent or altered: graceful fallback, not a dead end

Some DAWs, editors, file converters and messaging workflows may strip BWF/iXML chunks. Filename handling is therefore part of the design:

1. Exact valid JUJU UUIDs: authoritative lookup if consistent with database.
2. Otherwise, **exact canonical basename** lookup in the local `WAVRecallIndex` (including original export names) — a client can say a filename, director finds that WAV anywhere on disk and drags it in.
3. If metadata and filename are absent/modified, optionally try the **audio-data checksum** against known exports/originals, when a true content match is available; this is a convenience, not a required audio fingerprinting system.
4. If multiple jobs share the same basename, show a minimal chooser (job/actor/date) instead of picking the wrong one. Never fuzzy-match a filename and silently open a guess. If no match, offer the ordinary WAV import path and a text filename search; don't manufacture a job from the metadata or hallucinate a previous session.
5. If the identifier points to a job not present on this Mac (archive moved, library deleted, another workstation), show “This file came from a JUJU job, but the source project isn't available here,” with the embedded ID and an option to locate/restore the relevant project. The WAV alone is **not** a self-contained job archive.

Store an export index even if the user later changes the export destination. Search is by a saved **name or ID**, not by remembered disk paths; no need to watch every folder or run a background disk crawler. Keep filename disambiguation efficient and straightforward. Never use a private client-provided WAV to auto-create a cloned voice.

### 7A.4 Test vectors and acceptance criteria

Mandatory automated tests plus hands-on Finder/Dock tests:

- Export a known job `A`, named actor `Jane`, line 03 take 04 with fixed test UUIDs. Parse the exported WAV using an **independent** RIFF/iXML reader; assert UUIDs exactly match database values and exported PCM passes the usual audio/WAV validation.
- Create second export of the same take at a different supported format; assert same `JobUUID` + `TakeUUID`, distinct `ExportUUID`, stable original take, and correct resolved delivery version.
- Rename the WAV; with metadata intact, dropping it still opens the exact job and take.
- Strip iXML/bext but retain the canonical filename; dropping the file still resolves the exact job and take through the export index.
- Quit app, Finder-drag WAV onto Dock icon; launch and reopen the correct job once database is ready. Repeat with the app already running; repeat using in-window drop.
- Simulate missing job, malformed/huge RIFF chunk lengths, bad UUID, unsupported metadata version, conflicting UUIDs, duplicate filenames, missing original audio and a cancelled file permission; each must fail safely with intelligible options.
- Reopen historical audio with the renderer unavailable: read/play/inspect must still work; new rendering is unavailable but existing audio remains intact.
- Select “Make changes today” → create a new *take in the existing job* without replacing the original. Select “New job with these settings” → create a new UUID and preserve links/provenance to the source, without importing old approvals as new ones.
- Client supplies only the filename; director locates the WAV in Finder and drags it to the app. No need to remember job name or settings, enter an ID or find a sidecar. **This is a first-class manual acceptance test.**

**Product principle:** A delivered read is the fastest route back to the exact session that made it.

## 8. Client memory and privacy

Keep **Client → Brand/Product → Market/Locale → Jobs**, with independent reusable Voice Masters. The reusable memory is a curated structured production record, not a summary of every conversation. Retrieve last approved actor, source job, pronunciation, brand direction and relevant renderer settings. Distinguish hard requirements from preferences and one-off experiment notes. Contradictory campaign preferences are retained as versioned variants, not averaged together.

Consent is a product feature: the microphone may feed a cloud Engineer and selected performance guides may optionally be uploaded to a speech-to-speech API. Clearly indicate which service receives what. Provide a local-only mode with no cloud calls, secure account/API storage, opt-out of guide upload, and clear handling of source references, cloned voices and expiry/revocation of rights. Do not save raw private microphone recordings outside the explicit session/job capture policy. Never leak voice-host reference recordings through unrelated diagnostic logging.

## 9. Build stages: keep it small and demonstrably working

**Stage 0 — audit, no changes:** Inventory source/branch, runtime/SDK, existing Voicebox/VoiceStudio endpoints, Qwen workers, model versions, benchmarks, test health, disk locations, permissions, voice rights and availability. Record a compatibility and licensing matrix. Before building anything, write an environment report. No downloading multiple large models by default.

**Stage 1 — persistent native shell and WAV recall:** Implement recent jobs, new job, job name/script, reopen, actor display, take list, complete versioned job/take settings snapshots, media storage, automatic filenames, embedded Job/Take/Export UUIDs in exported BWF/iXML, WAV export index and Finder/Dock/in-app WAV-drop recall. Demonstrate quit/relaunch recovery, source-WAV-to-exact-take navigation and no overwrites **without an Engineer**.

**Stage 2 — one working actor path:** Wrap the existing Qwen bench behind a production adapter and achieve create → render → validate → auto-save → play → approve. Preserve the frozen bench tests. If already possible, don't duplicate it.

**Stage 3 — fast Engineer:** Implement a `ConversationProvider` with real speech, tool calling and explicit mic state. Use GPT Realtime first only if provisioned; provide text-direction mode for tests and local fallback plan. Connect job recall, script, actor choice and render tool. Measure latency. Add safe interruption handling.

**Stage 4 — casting and client memory:** Natural-language casting search, at least two candidates where genuinely available, on-screen names, host-authored cloned voice names, relative casting/performance instructions, Job fork, client/brand/locale matching, rights gate, context-aware welcome.

**Stage 5 — VoiceStudio/Voicebox shootouts:** Integrate these as isolated local backends, discover capabilities dynamically, run best-engine and parity trials, present take comparisons, preserve model manifests.

**Stage 6 — guide audio / voice-to-voice spike:** Record the director's example in-session, align with script, trial one authorised STS path (ElevenLabs Voice Changer if available; else clearly document unsupported and test a suitable alternative). Prove one sentence can be heard in the named actor voice without manual recording/upload UI. Compare how far verbal re-direction can go without an additional guide.

**Stage 7 — polish and evidence:** Deterministic state/recovery tests, performance summaries, full regression, measured latency, crash/reconnect behaviour, audible blind trials, packaging review. Do not move on because a demo merely looks convincing.

Do not implement a full audiobooks/dubbing suite, full editing DAW, broad global accent training, autonomous emotion critic, exact-duration guaranteed generator, live full-script surgical audio infill or general ElevenLabs v4 integration in Build 01. Keep clean extension points.

## 10. Required quality gates

1. Start app → see actual recent jobs in descending order; close/reopen preserves correct order and settings.
2. Open old job → hear truthful welcome when Engineer is connected → continue or fork settings; original take/media remains unchanged.
3. Create new Lenor Germany job → retrieve appropriate previous German-market job and approved Anna profile after confirmation, not Austria/Swiss settings.
4. Director says “female, early 30s, Manchester” → casting brief correctly preserves requirements; unavailable authenticity is reported honestly.
5. “She's posh; someone more fun” searches alternative actor; “same girl, less cheerful” keeps actor and changes proposed performance state.
6. Host-cloned Jane remains named Jane across UI, conversation, saved profile and WAV; rights gate must be honoured.
7. “Lock Jane for this next take” snapshots Jane's actual profile and engine; switching to Lucy afterward leaves Jane's take intact.
8. Every take has a unique, meaningful WAV filename **and exact persisted Job/Take UUIDs in WAV metadata**, plus unique Export UUID for each derivative; taking/approving/rejecting/returning never destroys a previous file.
8A. A WAV dragged onto JUJU from Finder/Dock while the app is closed or running opens its exact job with the exact historical read on the desk; metadata-stripped files with unchanged export filename resolve through the saved index; missing/ambiguous matches never silently open the wrong job.
8B. Each job and take has a complete, versioned parameter snapshot; a WAV alone is a reference, not a project backup; creating a new job with old settings never overwrites or misattributes historical renders.
9. Speech capture cleanly distinguishes Engineer conversation from the director's demonstration, or offers a quick correction when boundaries are ambiguous.
10. Actor render failures/timeouts/interruption are honest, recoverable and never reported as ready.
11. Qwen baseline is operational and RB-006/RB-007 files remain byte-for-byte identical; original tests still pass.
12. VoiceStudio, Voicebox and Qwen capabilities and versions are recorded; shootout results disclose incomparable configurations.
13. Voice-to-voice sample returns named actor WAV in a new take when a compatible authorised backend exists; otherwise the app gracefully marks the experiment unavailable.
14. Suggested adjustment to an STS-generated take either produces a **demonstrably** altered performance by supported method or requests a new guide honestly.
15. Disconnected/offline/microphone-denied modes still allow the user to work via conventional UI.
16. No plaintext secrets, voice reference audio leak or unauthorised cloud upload; cloud indicator visible.

For performance, record p50/p90/p95 (where sufficient samples exist) for microphone last meaningful word → first audible Engineer acknowledgement, acknowledgement → render start, render start → validated playable WAV, and turn interruption response. Initial **development targets**, not promises: Engineer acknowledgement should feel near-immediate (aim at sub-second where the backend and network permit), playback must be responsive, and there should be no dropped or mangled saved takes. Compare against local Phonon without treating its advertised synthesis time as total response latency.

## 11. Engineering rules for Fable

- Work on the actual repository after inspection. Before edits, produce a concise inventory and an implementation map. Distinguish verified existing code from references and aspirations.
- Keep the native macOS shell in Swift/SwiftUI, use AVFoundation/Core Audio, GRDB/SQLite where appropriate, Keychain for credentials, and structured concurrency with cancellation and actors where sensible. The app may target the user's intended macOS 27 environment if installed; don't silently raise the shared RB-007 package's platform requirement or break its Xcode 26 baseline.
- Keep backend workers isolated and version-pinned; no dependency upgrades in frozen environments. Prefer local loopback APIs/persistent processes and a capability registry over calling or rebuilding third-party UIs.
- Separate user-facing Engineer voice, backend function-calling, rendering, project storage and playback into clean interfaces with deterministic operations and tests.
- Do not copy VoiceStudio AGPL code into a closed-source JUJU target without a licence decision. Inspect each third-party model's source and weight/output rights individually. For ElevenLabs STS, use the user's authorised key only if enabled, and distinguish development feasibility from distribution/OEM licensing.
- Every async action produces an honest persisted state, carries a request ID and handles cancellation, duplicate calls, retries, timeouts and crash recovery.
- Don't replace a genuine audio result with a mocked one without labelling the mock. Maintain separate demo fixtures.
- Prefer no UI complexity until needed; when a capability is absent, omit or disable its control rather than expose a misleading button.
- Never destroy prior takes, re-use a generated take ID for another output, or discard provenance because a new engine sounds better.
- On completion of each stage: report changed files, exact manual steps, environment assumptions, tests run/passed/failed, known limitations and next smallest slice. Never report a stage as complete solely because code compiled.

## 12. Demonstration the first successful build must pass

1. Launch JUJU Voice Director; see previous jobs, or a valid empty state.
2. Create `AutumnCampaign`, paste two-line commercial script and connect the Engineer.
3. “I want a woman in her early thirties, from Manchester.” Hear genuine available auditions, or an honest limitation.
4. Select **Jane**. “Let's go for a take.” Engineer says “Locking in Jane for this next read.” Jane's first take renders and is auto-saved as `AutumnCampaign-Jane-<local-date>-Line01-Take01.wav`.
5. Say “She's a bit posh—do we have someone more fun?” Engineer offers alternate actors while preserving the original Jane take.
6. Return to Jane and give an actual spoken emphasis demonstration: “Today ONLY at our store.” Capture the guide and produce either a supported re-directed TTS take or STS transfer if an authorised backend is enabled. State which route was used.
7. Say “Slightly less pushy.” Try supported output controls; if this is an STS-only take without usable controls, honestly request another guide, then produce a new take.
8. Approve a take, close the app, reopen the job, hear “Welcome back…”, see exact actors, takes and direction history.
8A. Export a WAV; have a client hypothetically return only that file or its human-readable filename. Locate the WAV via Finder and drag it onto the JUJU Dock icon. JUJU opens the original job with the **same exact take highlighted, waveform ready and full saved settings available**. Engineer (when connected) asks “Are we making changes to this today, or something new with the same settings?” Test both answers.
9. Start a new job: “Another Lenor detergent commercial for Germany.” Find the right past job and ask permission to inherit its actor and settings. Do not change the old job.
10. Run VoiceStudio vs Voicebox vs direct Qwen trial with saved manifest, versions and controlled/uncontrolled distinctions clearly identified.

**Definition of success:** The user feels like they're directing a real voice-over session. They do not have to understand the synth model, upload a guide manually, invent filenames, recreate client history or lose an approved take. The product can be commercially useful even before its local renderers equal ElevenLabs' best acting quality.

## 13. Primary references to inspect at implementation time

**Historical project references** (supplied in the user's ChatGPT Library; access in Claude session will need local originals or copies):

- `TALKBACK_END_GAME.md`
- `PROJECT_HANDOVER(6).md` — RB-007
- `JUJU_Voice_Director_Performance_Upgrade_Research_Oct2026.md`

**Published developer documentation:**

- VoiceStudio: https://github.com/debpalash/VoiceStudio and https://github.com/debpalash/VoiceStudio/blob/main/docs/agentic-voice.md
- VoiceStudio licence: https://github.com/debpalash/VoiceStudio/blob/main/LICENSE-NOTICE.md
- Voicebox: https://github.com/jamiepine/voicebox and https://github.com/jamiepine/voicebox/blob/main/docs/openapi.json
- Qwen3-TTS: https://github.com/QwenLM/Qwen3-TTS
- Phonon Swift/Core ML: https://github.com/gradium-ai/xn-ptts/blob/main/ios/PhononTTS/README.md
- FluidAudio: https://github.com/FluidInference/FluidAudio
- OpenAI Realtime API: https://developers.openai.com/api/docs/guides/realtime and https://developers.openai.com/api/docs/guides/realtime-mcp
- ElevenLabs Voice Changer: https://elevenlabs.io/docs/api-reference/speech-to-speech/convert

**Final instruction to Claude Fable:** Audit first. Plan the minimal additive integration. Implement and validate one vertical slice at a time. Do not hide a missing capability behind an optimistic UI. Protect the user's existing evidence, voice identities, jobs, takes and audio assets. The director directs; the Engineer handles the machinery; the actor performs.
