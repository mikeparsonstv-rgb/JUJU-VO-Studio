# JUJU VO Studio — V1 test bed (Stages 2 + 3) and morning test guide

Built overnight 28→29 Oct 2026 by Claude (Opus 5.5) on Mike's Mac (macOS 27.0.1, Xcode 27.1, Swift 6.4).
Status: **V1 end-to-end loop working and demonstrated** — script → cast a real cloned voice → talk to a local
Engineer → real renders → approve → broadcast export → client WAV reopens the exact take → "new job, same settings".
Look is plain native on purpose (house style to be worked up together).

## 1. Morning test (≈10 minutes)

App: `VOStudio/build/DerivedData/Build/Products/Debug/JUJU VO Studio.app` (signed with your Developer ID).
Library: `~/Documents/CLAUDE_MAY/JUJU VO Studio Library` (jobs *Daz Autumn* and *Daz Winter*; the voice *Birmingham*).

1. Open the app → **Daz Autumn** → **Connect** (Engineer panel, bottom right, ⌘K).
   First time only: macOS asks for **Speech Recognition** and **Microphone** — Allow both. The panel then shows "mic on · on-device".
   The Engineer's brain (local LLM) takes ~15 s to load the first time; until then it understands the common phrases instantly.
2. Say (or type + **Send**): **"Let's do line three."** → "Line three. Okay, locking in Birmingham…" → ~5–10 s → "That's ready, here you go." → plays.
3. **"Again, a bit more fun, and really lean on only."** (line 1) → livelier read, *only* capitalised in the text sent (experimental).
4. **"Go back to the first take."** · **"That's the one."** · **"Export that one."** → `Exports/DazAutumn/…wav` at 48 kHz / 24-bit.
5. **"I want a woman in her early thirties from Manchester."** → honest answer: only Birmingham is in the library.
6. **"Make it 30 seconds."** / **"Just the last two words."** / **"Do it like this…"** → honest "can't yet" replies.
7. Quit (⌘Q). Drag the exported WAV from Finder onto the Dock icon → welcome banner + exact take; Connect → it says
   "Welcome back… changes today, or something new with the same settings?" → answer either way.
8. Listen critically: is Birmingham recognisable? Do *Livelier* / *Steadier* / stress actually change anything audible? (§4)

Everything you say is half-duplex: the mic pauses while the Engineer talks or a take plays. To interrupt, press **Stop** or say "stop" after it finishes.

## 2. Stage 2 — one real actor path (done)

- `ActorEngine` protocol + renderer-neutral `PerformanceDirection` (variation, emphasis, pause-after, director's words).
- `QwenBenchActorEngine` wraps the **frozen** Renderer Bench Qwen3-TTS 0.6B Base persistent worker (offline, pinned env and weights,
  run from the original bench folder; writes only into the JUJU library).
- `RenderCoordinator`: run persisted as *queued* before the engine is called → *rendering* → independent WAV validation →
  trim of **exact digital silence only** (Qwen pads up to ~5 s of zeros; trimmed to a 150 ms tail, raw hash kept) → atomic take
  save → *succeeded*. Failures are recorded and never shown as ready; unfinished runs become *interrupted* at next launch.
- Every take snapshot records: engine + adapter version, model revision, seed, voice reference ID + SHA-256 + transcript flag,
  language, the exact text sent, sampling settings, controls applied, controls not possible, post-processing.
- Voices: `Birmingham` (host-cloned, en-GB) with two references — BHM01 *Hot Washer* (default) and BHM02 *Overspiller*
  (hashes match RB-006). Rights note says local research only; client reuse needs the host's authorisation.
- **Broadcast export**: default export is 48 kHz / 24-bit PCM — a *recorded derivative* (Apple mastering-quality SRC, no level,
  loudness or timing change), its own export UUID; recall maps it back to the same take. Native 24 kHz/16-bit export is under More.
- Measured: warm render 4–10 s per line (engine 4.1 s for a 2 s line); 8/8 real renders succeeded; words Whisper-checked.

## 3. Stage 3 — local Engineer (done for typed direction; mic built, awaiting your permission)

- Architecture per brief §4: typed `EngineerAction`s executed by the same code as the buttons (`AppModel` *is* the Engineer's
  studio — one source of truth), `ConversationProvider` protocol, `Engineer` state machine (listening → thinking → working →
  speaking), latency recorded per turn.
- **Rules first**, then a **local LLM**: common studio talk is understood instantly and deterministically; anything else goes to
  Qwen3-Coder-Next 4-bit (MLX, already in your HF cache) via a loopback OpenAI-compatible `mlx_lm.server` the app starts on Connect
  and stops on quit. Own pinned env: `Engines/engineer-llm` (`setup.sh`).
- **Truthful speech**: the Engineer only says what the studio actually did; "That's ready" only after a validated take exists.
  Casting talk ("someone more fun") is kept separate from performance talk ("same girl, less cheerful").
- Speech in: Apple on-device speech recognition (SFSpeechRecognizer, en-GB), end of utterance after 0.85 s pause, gated while
  speaking/playing. Speech out: Apple system voice (Daniel, en-GB). Nothing leaves the Mac.
- Evaluation (24 director lines, real model): **rules 20/24 correct, instant; LLM p50 1.43 s, p90 1.74 s**. In-app: rules
  replies ~0.0 s, LLM casting reply 2.8 s.

## 4. Honest limits of V1

- **Direction with Qwen 0.6B Base is crude**: "livelier/steadier" changes sampling temperature (1.05 / 0.7); stress and pauses
  are text markup (capitals, ellipsis) — *experimental, not yet proven audible*. The Engineer says so when it uses them.
- **One voice** (Birmingham). Casting search only lists the library; no new-voice search, auditions or rights gate UI yet (Stage 4).
- **No voice-to-voice / guide capture** (Stage 6): "like this" requests get an honest refusal and are logged as direction events.
- **Mic path not yet exercised live** — it needs your Speech Recognition + Microphone approval. Half-duplex; no barge-in.
- Engineer voice is Apple's standard *Daniel*; a premium/enhanced voice installed in System Settings › Accessibility › Spoken Content
  is picked up automatically.
- The local LLM uses ~42 GB of unified memory while the Engineer is connected.
- No VoiceStudio / Voicebox shootouts yet (Stage 5); no exact durations, pickups or partial edits.
- Plain native UI; layout tuned for a ~1000 px window.

## 5. Bugs found and fixed overnight

- App hung loading Qwen: macOS was holding the worker behind a Documents-folder privacy prompt; app now signed with your
  Developer ID so grants persist across rebuilds.
- Quit hung when the Engineer had been connected but the mic permission was still pending (AVAudioEngine input node created
  lazily during shutdown). Fixed; SIGTERM now quits like ⌘Q and stops the LLM server.
- "Have we got someone more fun?" was first read as a livelier re-take — now correctly a casting request.
- Takes row clipped the selected take; render bar cramped; menus replaced by buttons.

## 6. Test evidence

RendererBench 85/85 · BroadcastWave 17/17 · VOStudioCore 51/51 (Stage 2: 12 render/voice/derivative tests; Stage 3: 12 Engineer
tests incl. rule phrase table, tolerant model parsing, truthful announcements, follow-up questions). RB-006 209/209 and RB-007
98/98 byte-identical. Delivered export independently parsed: 48 kHz/24-bit PCM, `fmt bext iXML data`, IDs exact.

## 7. Suggested next slices

1. Your listening verdicts on Birmingham takes (identity, accent, whether the direction levers do anything).
2. Live mic session + latency numbers (the panel shows p50/p90).
3. Stage 4: second voice + casting/auditions, client/brand/market memory, rights gate.
4. House style pass (together), then Stage 5 shootouts / newer voice models against the ElevenLabs v4 bar.
