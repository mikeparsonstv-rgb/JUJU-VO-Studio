# JUJU VO Studio — Stage 0 Audit

Date: 28 October 2026 · Author: Claude (Fable 5.1) with Mike Parsons · Status: complete — §7 run on the Mac 28 Oct 2026 19:42 (results in §9)

## 1. Decisions taken tonight (override the Build 01 brief where they differ)

- Product name: **JUJU VO Studio** (brief says "Voice Director").
- Engineer: **local from the start** (FluidAudio ASR/VAD/EOU → small local instruction LLM → fast local voice). OpenAI Realtime becomes a *comparison* adapter behind `ConversationProvider`, not the primary.
- Licensing: parked during the research phase; `Notes/LICENSING_NOTES.md` records what must be resolved before any release.
- Source control: local git + GitHub (private) from day one. Evidence, private audio, model weights and envs are never committed.
- Birmingham recordings (BHM01/BHM02, RB-006 cross-holdout) remain the fixed control for all renderer comparisons.
- Two direction sources, one representation: `PerformanceIntent` is `guideDerived` (director demonstrates "more like THIS") or `conversationDerived` (Engineer infers delivery from the briefing). Schema carries this from Stage 1.

## 2. Verified locations (this machine)

| Component | Verified path | Notes |
|---|---|---|
| Renderer Bench (original, frozen) | `/Users/editstudio/Documents/CODEX/JUJU VoiceOver/CuePitchBrief/TalkBack_Renderer_Bench_Brief_v0_1` | Full Swift 6.2 package, 3 workers, locked envs, model caches, `.build` (9 Aug, macOS 26), RB-005/006/007 evidence. **Not a git repo.** The LOCAL AI docs cite a `VOICE OVER RESEARCH` path that does not match — correct them. |
| Renderer Bench (tracked copy) | `JUJU VO Studio/RendererBench/` | Source, docs, tests, workers, scripts only (107 files). Evidence/envs/models excluded by `.gitignore`. |
| Frozen baseline hashes | `JUJU VO Studio/Evidence/frozen-baseline/*.sha256` | RB-006: 209 files, RB-007: 98 files. RB-006 cross-checked against RB-007's own `rb006-frozen-files.json`: **0 mismatches** (3 `.DS_Store` entries deliberately skipped). Nothing has drifted since 9 Aug. |
| Build 01 brief | `JUJU VO Studio/Briefs/JUJU_VO_Studio_Build_01_Brief_Rev1.1_2026-10-28.md` | Rev 1.1, 57,550 bytes. |
| Voicebox app (verified) | `/Volumes/EDITBOX-RAID/JUJU LOCAL AI/Apps/Voicebox/Verified/Voicebox.app` | **v0.5.0**; bundle ships `voicebox`, `voicebox-server`, `voicebox-mcp` binaries. |
| Voicebox source | `/Volumes/EDITBOX-RAID/JUJU LOCAL AI/Source/voicebox` | commit `8af7efe`, package version **0.6.0** + unreleased changes. |
| Soundbox source | `/Volumes/EDITBOX-RAID/JUJU LOCAL AI/Source/soundbox` | commit `4698eb5`. Not inspected further; Mac inference unproven per its own README. |
| VoiceStudio | **not on disk** | Must be cloned in Stage 5 (or earlier if used as reference). |
| `TALKBACK_END_GAME.md`, Performance Upgrade Research doc | **not on disk / not supplied** | Brief cites both. Needed before Stage 3/4 design work. |

## 3. Renderer Bench — as found

- Package: swift-tools 6.2, `platforms: [.macOS(.v26)]`. Library products: `RendererBenchCore`, `Qwen3RendererAdapter`, `VoxCPM2RendererAdapter`, `ChatterboxRendererAdapter`, `RB006Qualification`, `RB007TimingRepair`. Executables: `renderer-bench`, `*-session-bench` ×3, `rb006-qualification-bench`, `rb007-time-repair`. One test target, 7 test files; handover reports 85/85 passing on macOS 26.5.1 / Xcode 26.
- `RendererBenchCore` surface to reuse, not replace: `RendererAdapter` protocol (`healthCheck`, `render(_:to:)`), `RendererRequest/Result`, registry (IDs `qwen3`, `voxcpm2`, `chatterbox`, `moss`, `microsoft`; mock marked `isTestFixture`), runner (persists request first, serialises adapter errors), `AudioFileValidator` (independent WAV validation), run layout `runs/<test-id>/<run-id>/<renderer-id>/`.
- Workers (JSON-lines over stdin/stdout, persistent, POSIX `read` framing): all Python 3.12.13 in `.renderer-envs/{qwen3,voxcpm2,chatterbox}`.
  - Qwen3: `qwen-tts @ QwenLM/Qwen3-TTS@022e286`; model `Qwen/Qwen3-TTS-12Hz-0.6B-Base@5d83992`; PyTorch/MPS; `generate_voice_clone(text, language, ref_audio, ref_text)`; seed via `torch.manual_seed`. Cache 2.4 GB.
  - VoxCPM2: `mlx-audio==0.4.6`; `mlx-community/VoxCPM2-bf16`. Cache 4.7 GB. Long-form truncation unresolved.
  - Chatterbox: `resemble-ai/chatterbox@5de7a54` + Perth watermark; Multilingual V3 (`t3_model=v3`); MPS. Cache 3.1 GB.
  - Analysis: Whisper `large-v3-turbo.pt` (1.6 GB), isolated `.analysis-envs/rb006`.
- `BenchAssets/rb006-local-assets.json` maps asset IDs to private absolute paths (by design; it was gitignored upstream and is now tracked only because the copy kept it — **move to .gitignore before pushing**).

## 4. Voicebox — as found (source `8af7efe`)

- Backend: FastAPI (`backend/app.py`, `main.py --port`), engines in `backend/backends/`. `GenerationRequest` (backend/models.py:82): `profile_id`, `text` (≤50k), `language` (23 codes incl. `de`, `fr`), `seed`, `model_size` `1.7B|0.6B|1B|3B`, **`instruct`** (≤500 chars), `engine` ∈ `qwen | qwen_custom_voice | qwen_voice_design | luxtts | chatterbox | chatterbox_turbo | tada | kokoro | omnivoice`, `personality`, `max_chunk_chars`, `crossfade_ms`, `normalize` (default **true** — must be turned off for bench-grade output), `effects_chain`.
- Routes: `/health`, `/profiles` CRUD + samples, `/generate`, `/history`, `/audio/{id}`, `/transcribe`, `/models/{load,unload,status,download,progress}`, plus (unreleased) OpenAI-compatible `/v1/audio/speech` + `/v1/models` where `instructions` feeds the engine instruct prompt. MCP tools `voicebox_speak` etc.
- `docs/openapi.json` is **stale** (0.1.0 schema; `language` en|zh only, no `engine`/`instruct`). Use `backend/models.py` as the contract.
- MLX path pins `mlx-audio==0.4.1 --no-deps` (transformers ≤4.57.6 cap). Chatterbox multilingual via MLX since 0.6.0.
- Version gap: verified app = 0.5.0 (25 Apr); CHANGELOG records 0.6.0 (4 Oct, "stability release": MLX thread-affinity crash, memory growth on unload, offline cache retries) but the GitHub releases page still shows 0.5.0 as latest. **Decision needed:** run the 0.5.0 app's bundled `voicebox-server`, or build the 0.6.0 backend from source into an isolated env. Recommendation: build from source for the bench (reproducible commit), keep the verified app untouched.
- Default model cache `~/.cache/huggingface/hub` — outside the shared folders; set `HF_HOME` per isolated env so JUJU-owned downloads land under `JUJU LOCAL AI/Models/`.

## 5. Today's claimed candidates — verification status

| Claim (from today's research chat) | Verified tonight | Finding |
|---|---|---|
| VoiceStudio (debpalash) AGPL-3.0, Apple Silicon stable, local API + MCP | yes (repo page) | Electron + Python/uv backend (Tauri before 0.5.3); default engine OmniVoice (k2-fsa, **CC-BY-NC weights**); "dozens" of engines via Model Manager; iOS preview. Version/date not shown on page. |
| Gradium Phonon Swift/Core ML, ~7 ms TTFB | yes (repo page) | `PhononTTS` SwiftPM package, Core ML, **macOS 15+**. 31m = English-only, Apache-2.0; 40m = 5 languages, **CC-BY-NC**. Vendor-reported latency only. Cloning/design needs a Gradium API key (cloud) — Engineer voice should use preset/31m. |
| FluidAudio: Parakeet ASR, VAD, EOU, PocketTTS | yes (repo page) | v0.12.4, Apache-2.0, Core ML / Neural Engine. Parakeet TDT v3 (25 EU langs + ja), Parakeet EOU streaming (English-only), Silero VAD, diarisation, PocketTTS **with voice cloning** (beta, US English). Strong fit for the local Engineer ears + fallback mouth. |
| MLX-Audio 0.6.2 released 26 Oct with ECAPA, Fish Drama 3, MOSS | **not confirmed** | Releases page snapshot shows latest **v0.5.8 (5 Oct)**. MOSS appears only as an STT weight-loading fix. Re-check live before relying on it; do not assume ECAPA speaker verifier exists there. |
| Voicebox 0.6.0 available | partial | In source CHANGELOG, **not** on releases page. See §4. |
| MOSS-TTS v1.5 (4B local-transformer, 8B), `[pause 1.2s]` markers, MLX path | **unverified** | No repo inspected tonight. Verify at Stage 5 before any download. |
| ZONOS2 Metal, emotion vectors + calibration scripts | **unverified** | Verify at RB-010 stage. |
| dots.tts.edit, FireRedTTS3, Vevo2, CtrlSpeech, SteerSpeech, EDICT, E3, Emo-BPO, RLAIF-SPA | **unverified** | Research track only; not Build 01. |
| ElevenLabs v4 (28 Sep 2026), Voice Changer API | **unverified** | Needed only for the controlled v4 reference and the optional STS spike. |
| Modulate Velma 2.0 emotion API + pricing | **unverified** | Stage 2 of research track; cloud, opt-in only. |

## 6. Machine

Mac Studio M1 Ultra, 128 GB (per LOCAL AI handover: macOS 27.0.1, Xcode 27.1). Node 26, pnpm, Rust, CMake, ffmpeg, uv on PATH. The Claude session's shell is a Linux VM with the shared folders mounted — it can read/write/git but **cannot run swift, xcodebuild or Metal**; those steps run on the Mac via computer-use or a user-run script.

## 7. Outstanding Stage 0 checks (need the Mac itself)

1. `swift build` and `swift test` of `RendererBench/` under Xcode 27.1 / macOS 27 — confirm 85/85 still pass; record any toolchain drift from the Xcode 26 baseline (do **not** raise the package's platform requirement).
2. `swift run renderer-bench health qwen3|voxcpm2|chatterbox` from the original folder (workers + envs live there).
3. Launch `voicebox-server` from the 0.5.0 bundle, hit `/health` and `/models/status`; record which engines/models it reports.
4. `xcodebuild -version`, `sw_vers`, `python3 --version`, `uv --version`.
5. Inventory `~/.cache/huggingface/hub` (read-only) for any Qwen 1.7B / Chatterbox Turbo weights already present.

## 8. Risks found tonight

- Bench `.build` is from macOS 26; macOS 27 / Xcode 27.1 compatibility is unproven.
- Voicebox 0.5.0 app predates MLX stability fixes; long Engineer sessions may hit the thread/memory bugs 0.6.0 fixed.
- Voicebox `normalize=true` by default and `crossfade`/chunking alter output — bench-grade renders must disable them and record it.
- Several of today's "new model" claims rest on one web-research pass; two already failed verification (MLX-Audio 0.6.2; Voicebox 0.6.0 release). Treat the rest as hypotheses.
- Private-path file `rb006-local-assets.json` is currently tracked — fix before first push.

## 9. §7 results — run on the Mac, 28 Oct 2026 19:42–19:46 (Claude, Opus 5.5, via the repo's job runner)

Raw log: `Notes/STAGE0_S7_RESULTS.txt` (script `Scripts/stage0_section7.sh`).

| Check | Result |
|---|---|
| 7.4 Toolchain | macOS **27.0.1** (26A434) · Xcode **27.1** (27A9275) · Apple Swift **6.4** (swiftlang-6.4.0.34.1) · arm64 · system `python3` 3.14.7 (bench envs stay on 3.12.13) · uv 0.10.9 |
| 7.1 RendererBench (tracked copy) | `swift build` clean under Swift 6.4 — no toolchain drift needing source changes; platform left at `.macOS(.v26)`. `swift test`: **85 tests, 84 passed, 1 failed** on the first run — `timeoutTerminatesAndNextRequestRestarts` (RB003Tests) hit its own 0.5 s timeout on the *restart* request under full-suite parallel load. Isolated re-runs 3/3 pass (0.61–0.66 s); full-suite re-run **85/85 pass**. Classified as a timing flake of a deliberately tight test, not a behaviour change. Test left untouched (frozen); noted as a known flake. |
| 7.2 `renderer-bench health` (original folder) | **qwen3** healthy (Qwen3-TTS-12Hz-0.6B-Base @5d83992, tokenizer @7dd38ad, transformers 4.57.3, import 4.0 s) · **voxcpm2** healthy (mlx-audio @d28d68c, VoxCPM2-bf16 @a7fb80d, import 0.45 s) · **chatterbox** healthy (MPS, import 11.8 s; `watermark_enabled: false` while `watermark_expected: true` — reported as before, worth re-reading against RB-005 notes). All `ready_unloaded`, exit 0. |
| Frozen baseline | RB-006 **209/209** and RB-007 **98/98** SHA-256 OK against `Evidence/frozen-baseline/` (root: original `BenchData/qualifications`). Nothing has drifted. |
| 7.3 Voicebox 0.5.0 bundled server | `voicebox-server` (Python 3.12.10, `--host/--port/--data-dir/--parent-pid`) up in ~15 s on 127.0.0.1:17499 with a temp data dir. `/health`: healthy, `backend_type: mlx`, **`backend_variant: cpu`**, GPU MPS available, no model loaded. `/models/status` lists Qwen TTS 1.7B/0.6B Base (MLX bf16), Qwen CustomVoice 1.7B/0.6B, LuxTTS, Chatterbox multilingual + Turbo, HumeAI TADA 1B/3B-ml, Kokoro 82M, Whisper base→turbo, Qwen3 0.6B/1.7B/4B (4-bit LLMs) — **none downloaded**. `/v1/models` → 404 (as expected for 0.5.0). Server stopped afterwards. |
| 7.5 Hugging Face cache | `~/.cache/huggingface/hub`: **no TTS/ASR weights** (no Qwen-TTS 1.7B, Chatterbox Turbo, Kokoro, Parakeet, Whisper). Present: `mlx-community/Qwen3.5-27B-4bit` (15 GB), `mlx-community/Qwen3-Coder-Next-4bit` (42 GB), SAM 2.1 (309 MB). `JUJU LOCAL AI/Models/` does not exist yet. |

Consequences:
- Bench is green on macOS 27 / Xcode 27.1 / Swift 6.4; Stage 1 can depend on `RendererBenchCore` as planned.
- Any Qwen 1.7B / Chatterbox Turbo trial (RB-009, Stage 5) needs a download first — say so and size it before starting.
- `Qwen3.5-27B-4bit` already on disk is a free first candidate for the Stage 3 Engineer LLM latency check (alongside a small 4-bit model); nothing to download to run that comparison.
- Voicebox reporting `backend_variant: cpu` for its MLX backend needs explaining before any Voicebox shootout (Stage 5).

