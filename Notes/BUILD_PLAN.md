# JUJU VO Studio — Build Plan (from Stage 0)

Read first: `Briefs/JUJU_VO_Studio_Build_01_Brief_Rev1.1_2026-10-28.md`, then `Notes/STAGE0_AUDIT.md`, then
`RendererBench/PROJECT_HANDOVER.md` and `RendererBench/KEY_FINDINGS.md`. Decisions in STAGE0_AUDIT §1 override the brief.

Mac job runner: `bash Scripts/mac_runner.sh` in a Terminal; it runs `Runner/inbox/*.sh` one at a time and logs to `Runner/outbox/` (gitignored).

Working rules (from the brief, kept short): additive changes; one vertical slice at a time; working code + passing tests +
short report + documented limits before the next stage; never a mock labelled as real; never overwrite a take; RB-006/RB-007
byte-identical (verify with `Evidence/frozen-baseline/*.sha256`); no large model downloads without saying so first.

## Repository layout

```
JUJU VO Studio/
  Briefs/            approved briefs
  RendererBench/     tracked copy of the Swift package (frozen behaviour; additive only)
  VOStudio/          new macOS app — Xcode project, SwiftUI, macOS 27, Swift 6
  Evidence/          ignored; frozen-baseline/ hashes are tracked
  Notes/             audit, plan, licensing, per-stage reports
```

`VOStudio` depends on `RendererBench` as a local SwiftPM package (`RendererBenchCore`, `Qwen3RendererAdapter`). Do not
change `RendererBench/Package.swift` platforms; add new library targets there only when the code is renderer-neutral.

## Stage 0 — finish on the Mac (small) — DONE 28 Oct (STAGE0_AUDIT §9)

Run STAGE0_AUDIT §7, append results to the audit, commit. Create the private GitHub repo and push. Move
`RendererBench/BenchAssets/rb006-local-assets.json` to .gitignore first.

## Stage 1 — persistent native shell + WAV recall (no Engineer, no renderer) — DONE 28 Oct (Notes/STAGE1_REPORT.md; Mike's Finder/Dock test passed)

Deliverable: open app → recent jobs → new job (name + script) → takes list → export WAV → quit → drag WAV on Dock → exact take on the desk.

- Persistence: GRDB/SQLite (new dependency, justified: brief asks for migrations, transactions, indices). Entities per brief §3;
  start with Job, ScriptRevision/Segment, VoiceMaster, RendererProfile, JobActorBinding, Take, AudioAsset, JobSettingsRevision,
  TakeSettingsSnapshot, WAVExport, WAVRecallIndex, DirectionEvent (with `source: guideDerived|conversationDerived`).
- Media root: user-chosen folder (security-scoped bookmark); layout `Library/<JobUUID>/takes/<TakeUUID>.wav`; atomic write
  (temp → validate → rename → DB commit).
- `BWFWriter`/`BWFReader` in a new renderer-neutral target `RendererBench/Sources/BroadcastWave` (or in VOStudio if preferred):
  RIFF/WAVE with `fmt `, `data`, `bext` (Description "JUJU job=<uuid>; take=<uuid>"; OriginatorReference = 32-char base32
  of the Take UUID bytes — documented, reversible), `iXML` with `<USER>` fields `JUJU_JOB_UUID`, `JUJU_TAKE_UUID`,
  `JUJU_EXPORT_UUID`, `JUJU_METADATA_VERSION=1`. Independent parser in tests. Reuse `AudioFileValidator` for the PCM check.
- Filenames: `<JobName>-<ActorName>-YYYY-MM-DD-LineNN-TakeNN.wav`, local date at take creation, collision-safe.
- Document type: `public.wav` as alternate; handle `application(_:open:)`, queue URLs until DB ready; in-window drop.
- Recall resolution order: UUIDs → canonical basename in WAVRecallIndex → optional data-chunk checksum → chooser/never guess.
- Tests: the brief §7A.4 vectors, all model-free.
- For Stage 1 the "actor" is a placeholder VoiceMaster and the "take" is an imported or mock-labelled WAV — labelled as such.

## Stage 2 — one real actor path (existing Qwen 0.6B) — DONE 29 Oct (Notes/V1_REPORT.md §2)

`ActorEngineAdapter` protocol (brief §5) wrapping `RendererAdapter`; `QwenBenchActorAdapter` drives the existing persistent
worker via `PersistentQwenWorkerClient`. Flow: lock actor → render (run ID first) → `AudioFileValidator` → save as take with
full `TakeSettingsSnapshot` (model rev, tokenizer rev, seed, ref asset IDs + hashes, language, settings) → play → approve.
Birmingham BHM01 as the first VoiceMaster (private; mapped by local path, not committed). Verify RB-006/007 hashes afterwards.

## Stage 3 — local Engineer — DONE 29 Oct for typed direction; mic built, awaiting permission (Notes/V1_REPORT.md §3)

`ConversationProvider` protocol + `StudioToolDispatcher` (typed tools from brief §4.2) + `SessionStateStore` +
`AudioCoordinator` (one mic capture, timestamped fan-out to ASR / guide recorder; one playback authority; interruption).
Local provider: FluidAudio (Silero VAD + Parakeet EOU streaming + Parakeet TDT v3) → local instruction LLM via an
OpenAI-compatible loopback (llama.cpp / LM Studio / Ollama; pick after a latency check on the M1 Ultra) with JSON tool
calls → Engineer voice via FluidAudio PocketTTS or Phonon 31m (macOS 15+, Apache-2.0). Text-direction mode for tests.
Measure p50/p90: end-of-speech → first acknowledgement audio. Cloud (OpenAI Realtime) as a second provider only if wanted.

## Stage 4 — casting + client memory. Stage 5 — Voicebox/VoiceStudio shootouts (clone VoiceStudio; build Voicebox 0.6.0
backend from source in an isolated env; `normalize=false`; parity trial on the same Qwen weights). Stage 6 — guide capture +
performance transfer (local path first: guide → prosody features → `PerformanceIntent` → engine controls that genuinely exist;
STS only if an authorised backend is enabled). Stage 7 — polish, evidence, blind listening.

## Research track (separate milestones, separate evidence root, same Birmingham control)

RB-008 inventory + controlled Eleven v4 reference of BHM02 words (settings recorded) · RB-009 Qwen 1.7B / MOSS v1.5 /
Chatterbox MLX in **new** locked envs · RB-010 PerformanceIntent + ZONOS2 steering · RB-011 listening/critique ·
RB-012 selective edits. Verify each candidate's repo/licence/Apple path before download (STAGE0_AUDIT §5).

## Still needed from Mike

- `TALKBACK_END_GAME.md` and `JUJU_Voice_Director_Performance_Upgrade_Research_Oct2026.md` into `Briefs/`.
- Listening verdicts on the RB-007 original/repaired pairs (as a note, evidence untouched).
- ~~GitHub~~ done: private repo `mikeparsonstv-rgb/JUJU-VO-Studio`, pushed 28 Oct.
