# RB-005 Controlled Three-Way Renderer Evidence

Run date: 2026-08-08  
Machine: Mac Studio Mac13,2, Apple M1 Ultra, 20 CPU cores, 128 GB unified memory  
OS: macOS 26.5.1 (25F80), arm64  
Evidence root: `/tmp/RendererBench-RB005-ThreeWay-20260808`  
Preserved project-local copy: `BenchData/runs/RB005-ThreeWay-20260808`

## Controlled inputs

Qwen3-TTS, VoxCPM2, and Chatterbox Multilingual V3 used the unchanged A01/C01 case text, `reference_asset_id=reference-001`, the same `/tmp/RB002-Qwen-reference.wav`, `en-GB`, empty generic direction, one machine, persistent sessions, and common WAV validation. Qwen and Vox use the available exact transcript. Chatterbox correctly records that it was available but not consumed by its reference-audio-only API.

`reference-001` is a temporary synthetic architecture identity, not a valid human clone-quality benchmark. This run establishes integration, provenance, timing, and comparable artifacts—not a voice-quality winner.

Native settings remain separate: Qwen sampling uses temperature 0.9/top-k 50/top-p 1.0/seed 1003; VoxCPM2 uses 10 diffusion steps/CFG 2.0; Chatterbox uses exaggeration 0.5/CFG 0.5/temperature 0.8/repetition 1.2/min-p 0.05/top-p 1.0.

## Load evidence

| Renderer | Backend | Imports | Model load | Session ID |
|---|---|---:|---:|---|
| Qwen3-TTS | MPS | 6.934 s | 2.799 s | `077cb4fc-2072-4dc1-bd9c-32c073c24339` |
| VoxCPM2 BF16 | MLX Metal | 0.332 s | 1.902 s | `74ab033b-28a7-48fa-bfd9-3d8e8873ff2a` |
| Chatterbox Multilingual V3 | PyTorch MPS | 4.575 s | 10.806 s | `09c61e9b-bf35-4b77-9d17-ca0b20bb091d` |

Load/import numbers are filesystem-cache sensitive. Each session performed one explicit load; all render responses reported the same session ID, increasing render index, `worker_reused=true`, and `model_reused=true`.

## Comparable render evidence

| Renderer | Case | Context | Generation | Adapter total | Output | Rate | RTF | Run ID |
|---|---|---|---:|---:|---:|---:|---:|---|
| Qwen3-TTS | A01 | cold generation | 25.731 s | 25.744 s | 13.280 s | 24 kHz | 1.939 | `a09ee8e5-fe90-4110-bc5f-6be00deea6ab` |
| VoxCPM2 | A01 | cold generation | 9.665 s | 10.092 s | 11.520 s | 48 kHz | 0.876 | `57dcf2c4-651e-47fe-b85f-ae46b374f735` |
| Chatterbox V3 | A01 | cold generation | 36.391 s | 36.398 s | 10.800 s | 24 kHz | 3.370 | `865cb6df-aa8b-45e0-a6be-cab9568afe06` |
| Qwen3-TTS | C01 | warm | 21.190 s | 21.204 s | 12.320 s | 24 kHz | 1.721 | `7c7d7374-f3ff-4a08-80bd-aa7ad9987722` |
| VoxCPM2 | C01 | warm | 9.444 s | 9.943 s | 13.280 s | 48 kHz | 0.749 | `2726e854-35a6-4fb4-a4c1-2536335a0874` |
| Chatterbox V3 | C01 | warm | 34.284 s | 34.293 s | 12.560 s | 24 kHz | 2.730 | `7bbff1e7-a0e4-4671-8f46-87945b507b0f` |

Additional warm A01 evidence:

- Qwen: 22.550 s generation, 13.280 s output, RTF 1.699, run `5071b872-1990-4d35-89bb-0608baad59f9`
- VoxCPM2: 8.185 s generation, 11.520 s output, RTF 0.746, run `c1b52479-a673-4c70-b1cc-e6c772301192`
- Chatterbox V3: 30.671 s generation, 11.200 s output, RTF 2.739, run `2c997a5d-7cf4-45d4-99f0-978a8db7045b`

RTF is adapter elapsed time divided by validated output duration; below 1 is faster than real time. Qwen/Chatterbox outputs are 24 kHz and Vox outputs 48 kHz; all are mono PCM-16 WAV validated by the same renderer-neutral parser. Timing is not a subjective rank.

## Listening bundle

`listening-bundle` contains the six required named WAVs, six adjacent result JSON files, and a non-blind manifest. The manifest retains original source-result locations while pointing audition entries to its self-contained result copies. No ratings, quality notes, or subjective scores were fabricated.

## Comparability and architecture audit

Comparable: case text, reference identity/audio, language, machine, process persistence, validated duration/rate, elapsed generation/adapter timing, cold/warm state, success, and later human audition.

Not equivalent: native controls, transcript use, cloning architecture, sample rate, seed semantics, model size, graph warmup, watermarking, or audio quality. Chatterbox retains PerTh implicit watermarking; the other results do not claim equivalent watermark behavior.

Common-core changes required for Chatterbox: **none**. The core request/result schemas, runner, evidence store, registry mechanics, and WAV validator were unchanged. Chatterbox identity, lifecycle, native controls, transcript-use truth, and watermark state fit the existing descriptor/settings/environment snapshots.

MOSS and Microsoft remain unavailable placeholders. RB-006 was not begun.
