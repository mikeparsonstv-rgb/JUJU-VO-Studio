# RB-004 Controlled Qwen3-TTS vs VoxCPM2 Evidence

Run date: 2026-08-08  
Machine: Mac Studio Mac13,2, Apple M1 Ultra, 20 CPU cores, 128 GB unified memory  
OS: macOS 26.5.1 (25F80), arm64  
Evidence root: `/tmp/RendererBench-RB004-Comparison-20260808`

## Controlled inputs

Both renderers used stable, unchanged A01/C01 definitions, `reference_asset_id=reference-001`, the same `/tmp/RB002-Qwen-reference.wav`, exact transcript, `en-GB`, empty direction, and the same machine. Persisted common input fields were inspected and match.

`reference-001` is the temporary synthetic system-voice architecture identity. It is not a human clone-fidelity reference and is not committed. The comparison proves integration and measurable operation, not identity quality.

Renderer-native settings were retained rather than inventing parameter equivalence:

- Qwen: sampling enabled, temperature 0.9, top-k 50, top-p 1.0, seed 1003
- VoxCPM2: BF16 MLX continuation, 10 diffusion timesteps, CFG 2.0, warmup 0, max tokens 2000; deterministic seed not claimed

## Load evidence

| Renderer | Backend | Imports | Model load | Session ID |
|---|---|---:|---:|---|
| Qwen3-TTS | MPS | 6.147 s | 2.499 s | `226bfd52-ad02-4196-947e-4ef4b1ba5521` |
| VoxCPM2 BF16 | MLX Metal | 0.176 s | 0.991 s | `6844fbbc-206b-4a62-aedd-74b80c7f3517` |

Load figures were observed after prior installation/smoke activity and are filesystem-cache sensitive. VoxCPM2's first smoke load was 2.397 s, and its first generation incurred additional MLX graph warmup.

## Comparable render evidence

| Renderer | Case | Context | Generation | Adapter total | Output | Sample rate | Bench RTF | Run ID |
|---|---|---|---:|---:|---:|---:|---:|---|
| Qwen3-TTS | A01 | cold generation | 23.485 s | 23.498 s | 13.280 s | 24 kHz | 1.769 | `4b61d8c2-15b7-49d8-b985-c9b0389be3e6` |
| VoxCPM2 | A01 | cold generation | 9.541 s | 9.993 s | 12.640 s | 48 kHz | 0.791 | `80176f8a-fdc9-4d50-a118-f81ea35049df` |
| Qwen3-TTS | C01 | warm | 19.262 s | 19.271 s | 12.320 s | 24 kHz | 1.564 | `9585efc1-e1ab-4f9d-a82f-1491a4c6023d` |
| VoxCPM2 | C01 | warm | 9.460 s | 9.946 s | 13.440 s | 48 kHz | 0.740 | `c7d66841-b5c6-4750-88c0-a0e35c6abcef` |

Additional warm A01 evidence:

- Qwen: 20.570 s generation, 13.280 s output, RTF 1.550, run `2440a526-bbff-44f0-93b9-4f01a5041ffa`
- VoxCPM2: 8.662 s generation, 12.320 s output, RTF 0.738, run `e6db9128-e7f4-43dc-b06e-a3f8bcdf7a12`

Bench RTF is elapsed/output duration; values below 1 are faster than real time. All outputs passed the same common validator. No worker remained after shutdown.

## What is and is not comparable

Comparable: successful generation, validation, output duration, generation/adapter timing, bench RTF, same reference use, language, sample rate, and later human audition.

Not directly equivalent: Qwen sampling controls versus VoxCPM diffusion/CFG controls, seed semantics, internal cold-load/graph compilation, sample rate, and architecture. No quality winner, deterministic equivalence, or parameter equivalence is claimed.

## Listening status

No subjective winner or qualitative listening notes were assigned by the coding agent. The outputs are preserved for a human editor/director to audition; inventing a listening judgment would violate the bench's evidence discipline. This section should be extended only after an identified listener performs a controlled pass.

## Architecture audit

Common-core changes required for VoxCPM2: **none**.

No changes were made to `RendererBenchCore`, `BenchmarkRunner`, common result/request schemas, persistence, registry mechanics, or WAV validation. RB-004 added a renderer-specific target, worker, harness, scripts, and metadata through existing settings/environment snapshots. The only existing-adapter change was teaching Qwen to surface `reference_asset_id` already passed in its renderer settings.
