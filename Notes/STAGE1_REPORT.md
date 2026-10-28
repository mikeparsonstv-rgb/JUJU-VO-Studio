# JUJU VO Studio — Stage 1 Report: persistent native shell + WAV recall

Date: 28 October 2026 · Built by Claude (Opus 5.5) with Mike Parsons · Status: **complete, pending Mike's hands-on Finder/Dock test (§5)**

Deliverable (BUILD_PLAN): open app → recent jobs → new job (name + script) → takes list → export WAV → quit → open WAV from Finder/Dock → exact take on the desk. **Done and demonstrated on the Mac** (macOS 27.0.1, Xcode 27.1, Swift 6.4). No Engineer, no renderer — by design.

## 1. What was built

| Piece | Where | Notes |
|---|---|---|
| `BroadcastWave` | `RendererBench/Sources/BroadcastWave` (new renderer-neutral target; additive to `Package.swift`, platform unchanged) | RIFF/WAVE reader that never trusts a declared length (bounds, chunk cap, duplicates, odd padding, WAVE_FORMAT_EXTENSIBLE). BWF writer: `fmt ` and `data` copied **byte-for-byte**, `bext` (EBU 3285 v2; loudness fields "not measured"; Description `JUJU job=<uuid>; take=<uuid>`; OriginatorReference = `JUJU` + RFC 4648 base32 of the 16 take-UUID bytes = 30 chars, reversible), `iXML` with `JUJU_JOB_UUID`, `JUJU_TAKE_UUID`, `JUJU_EXPORT_UUID`, `JUJU_METADATA_VERSION=1` inside `<USER>` only. Export = temp file → reopen and verify format, audio hash and IDs from disk → `link(2)` into place (cannot overwrite) → remove temp. Dependency-free (own SHA-256). |
| `VOStudioCore` | `VOStudio/Core` (SwiftPM, depends on GRDB 7 + BroadcastWave) | GRDB/SQLite schema v1: Client, Brand, Market, Job, ScriptRevision/Segment, VoiceMaster, RendererProfile, JobActorBinding, AudioAsset, Take, JobSettingsRevision, TakeSettingsSnapshot, WAVExport, WAVRecallIndex, EngineerSession, DirectionEvent (`source ∈ guideDerived / conversationDerived / manualText`), StudioEvent (append-only log). **Immutability is enforced by SQLite triggers**: a take's audio/identity/snapshot can't be changed, takes and audio assets can't be deleted, settings revisions and snapshots can't be edited, the event log is append-only, and an approval must name an asset and a script revision. |
| Media library | user-chosen folder (bookmark) | `Library/<jobUUID>/takes/<takeUUID>.wav` + `JUJU VO Studio.sqlite` side by side, so a library moves/restores as one folder. Atomic take write (temp → verify → no-replace link → DB commit; file removed if the commit fails). Launch repair deletes only our own `.juju-tmp-*` files and *reports* unknown take files. |
| Naming | `CanonicalNaming` | `<Job>-<Actor>-YYYY-MM-DD-LineNN-TakeNN.wav`, `FullRead` for whole reads, local production date at take creation, per job · actor · line numbering, never reused. Same-named actors get `Anna`, `Anna2`. Export clashes get `-2`, `-3` — never overwrite. |
| Recall resolver | `StudioLibrary.resolve(fileAt:)` | Read-only. Order: embedded iXML IDs → bext fallback → internal take-file UUID name → **exact** canonical/export file name (case-folded, no fuzzy matching) → identical audio bytes → chooser when ambiguous → clear "job not in this library" / "take not in this job" / "no match" / "unreadable" outcomes. Damaged, conflicting or newer-version metadata is reported and never trusted. |
| App | `VOStudio/App` + `project.yml` (xcodegen) | SwiftUI, macOS 27. Library setup → Home (recent jobs newest-first, filter, "search delivered names", empty state) → Studio desk (script lines, take header with provenance badge, waveform, Play/Stop, Approve, Export, takes per line, cast). `public.wav` registered as an **Alternate** document type. Finder/Dock opens go through `application(_:open:)`, queued until the library is open; in-window drop goes through the same queue. Welcome-back banner with **Make changes today** / **New job with these settings…**. |
| Demo tool | `VOStudio/Core/Sources/vostudio-demo` | Builds a labelled test library (mock tones only) and exports one take; used for the smoke test. |

Stage 1 "actors" are placeholder VoiceMasters ("Placeholder voice · no renderer"); takes are either an **imported WAV** (copied unchanged, labelled IMPORTED WAV) or a generated **MOCK TONE** (labelled MOCK everywhere, `renderer: "none"` in the snapshot). Nothing is presented as a voice render.

## 2. Tests (all model-free; all on the Mac)

- RendererBench: **85/85** (unchanged suite) + **BroadcastWave 17/17** — includes an **independent RIFF/iXML/bext parser in the test file** sharing no code with the target; brief §7A.4 vectors: exact IDs, second export (same job+take, distinct export, different format), renamed file, stripped iXML/bext, bext-only fallback, never-overwrite, huge chunk length, truncated/non-WAV, chunk flood, duplicate data, bad UUID, unsupported version, conflicting UUIDs, repeated keys, duplicate iXML, base32 round-trip, SHA-256 vectors.
- VOStudioCore: **26/26** — naming, recency, byte-for-byte import, DB-enforced immutability, unreadable audio refused with nothing left behind, approval names asset + script revision, export embeds exact IDs, second export, rename, stripped → filename (incl. upper-case name), stripped + renamed → identical audio, internal take file, duplicate names → chooser, unknown/damaged/missing file, job from another library, newer/bad metadata, resolve never mutates the DB, missing original audio (take still browsable; export fails clearly), make-changes → Take05 with Take04 and its approval untouched, new-from-settings (new identity, cast and settings carried, no takes/approvals, source unchanged, fresh numbering), crash repair, DirectionEvent source check, filename search, waveform peaks.
- The same BroadcastWave sources and tests were also compiled and passed on Linux (Swift 6.2) before going to the Mac; file hashes matched.
- RB-006 **209/209** and RB-007 **98/98** frozen hashes still OK; nothing in the original bench folder changed.

## 3. Hands-on smoke test (Claude, on the Mac, 20:10–20:57)

Library `Evidence/stage1-smoke/Library-201000` (ignored by git), built by `vostudio-demo`: Job A · Jane · Line 3 · Takes 1–4 (mock tones) · Take 4 approved and exported to `Evidence/stage1-smoke/Delivered/JobA-Jane-2026-10-28-Line03-Take04.wav`.

1. **App closed** → WAV opened with the app via LaunchServices (`open -a`, the same `application(_:open:)` path as a Dock drop) → app launched, queued the URL, opened the library, landed on Job A with Line 03 · Take 4 selected, waveform ready, **APPROVED** and **MOCK TONE** badges, "Delivered as …48000 Hz · 24-bit · 1 ch", and the banner: *"Welcome back. I've got Jane's line three, take four, from Job A. Are we making changes to this today, or doing something new with the same settings?"*
2. **Make changes today** → Add Mock Take → **Take05** created; Take04 audio and approval untouched (checked in SQLite).
3. **App running** → a copy with bext and iXML **stripped** (canonical name kept, in another folder) opened → resolved by file name to the same take.
4. **New job with these settings…** → "Job A Spring", script copied → new job with Jane cast, no takes, marked "from earlier job"; Job A unchanged. Home lists both, newest first ("Job A · 5 takes · 1 approved").
5. Play → audio plays, waveform fills as played portion; Stop restores.
6. Event log: jobCreated, actorCast, 5× takeAdded, takeApproved, takeExported, jobCreatedFromSettings.

Fixed during the smoke test: the takes row clipped the selected take (now wraps); the take title was oversized.

## 4. Known limits (documented, not hidden)

- **No Engineer, no renderer, no microphone** — Stage 2 and 3.
- **Look**: plain native SwiftUI. The JUJU house style is deliberately *not* applied yet — per the house rules it needs an approval preview first. Proposed for after Stage 2, when the desk has real content.
- App is **not sandboxed** (Stage 2 launches the local Python workers); the library folder is remembered with a plain bookmark. Revisit before any distribution.
- Waveform is a peak envelope of channel 1; no scrubbing yet. Playback is one `AVAudioPlayer` (the Stage 3 `AudioCoordinator` replaces it).
- Export copies the take's own format; no delivery-format derivatives yet (the data model already supports them: `WAVExport` per rendition).
- "Search delivered names" is a substring search over saved names, as the brief allows.
- `timeoutTerminatesAndNextRequestRestarts` (RB003) flaked once under full-suite load (Stage 0 §9); passes on every run since. Left frozen.
- One unused `takeSettingsSnapshotID` circularity (take ↔ snapshot) is written inside a single transaction; there is no FK on the take side by design.

## 5. Still for Mike

1. **The first-class manual test** (brief §7A.4): with the app **quit**, drag `Evidence/stage1-smoke/Delivered/JobA-Jane-2026-10-28-Line03-Take04.wav` from Finder onto the JUJU VO Studio Dock icon (you may need to right-click the app in the Dock › Options › Keep in Dock first); repeat with the app running; repeat by dropping onto the window. Each should land on Job A · Line 03 · Take 4 with the welcome banner. App: `VOStudio/build/DerivedData/Build/Products/Debug/JUJU VO Studio.app`.
2. Optional: point the app at a real library folder (Home › Library › Choose Another Library…) and try **Add Take from WAV…** with one of the RB-006 renders.

## 6. Next: Stage 2 — one real actor path (Qwen 0.6B)

`ActorEngineAdapter` around `RendererAdapter`; `QwenBenchActorAdapter` over the persistent worker; render → `AudioFileValidator` → `addTake(..., .render)` with a full `TakeSettingsSnapshot` (model/tokenizer revisions, seed, reference asset IDs + hashes, language, settings). Birmingham BHM01 as the first VoiceMaster (mapped by local path, not committed). Verify RB-006/007 hashes afterwards.
