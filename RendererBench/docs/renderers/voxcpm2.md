# VoxCPM2 Renderer — RB-004

Status: persistent BF16 MLX path operational on the target Mac  
Checked: 2026-08-08

## Exact identity and lineage

- renderer ID: `voxcpm2`
- display name: VoxCPM2 (MLX BF16)
- official source: `OpenBMB/VoxCPM@616d3d3e630a9c96c2853250eef91b0f39dcd5fa`
- upstream model: `openbmb/VoxCPM2@bffb3df5a29440629464e5e839f4d214c8714c3d`
- Apple-Silicon conversion: `mlx-community/VoxCPM2-bf16@a7fb80d9056983135a54ca3f71fcc5a637ccddf5`
- runtime: `mlx-audio 0.4.6`, source tag/commit `d28d68c6ac4e28f7d2d66007f640b06cf3fd8ceb`
- adapter: `1.0.0-rb004`; protocol version 1

The conversion is a full-precision BF16 MLX representation of the upstream model. It is not described as byte-identical execution of upstream PyTorch/CUDA. Both identities and the runtime revision are persisted in every result. The licence gate passes; see `docs/licensing/VOXCPM2_LICENSE_CHECK.md`.

## Installed environment

- Python 3.12.13
- mlx-audio 0.4.6
- MLX / mlx-metal 0.32.0
- mlx-lm 0.31.3
- Transformers 5.12.1
- Hugging Face Hub 1.27.0
- miniaudio 1.71
- environment: `.renderer-envs/voxcpm2` (about 412 MB)
- model cache: `.renderer-models/voxcpm2` (about 4.6 GiB on disk)

`Workers/VoxCPM2/uv.lock` records all 42 exact package versions and hashes. Setup downloads only the pinned BF16 model into its separate cache. It does not modify Qwen's environment and does not install packages globally.

## Persistent lifecycle and safety

```text
launch → health → load → render → render → … → shutdown
```

The JSON-lines protocol supports `health`, `load`, `render`, and `shutdown`, with the same conceptual states as Qwen: starting, ready-unloaded, loading, ready-loaded, rendering, failed, shutting-down, and stopped. stdout is protocol-only and diagnostics are captured separately on stderr.

The Swift client serializes access, validates protocol and request IDs, uses `poll` plus POSIX `read` for framing, times out individual requests, handles malformed output/EOF/exit, and gracefully shuts down with terminate/kill fallback. The worker remains resident with one loaded model. An uncertain render failure ends the worker so the next request starts from clean state.

## Reference-audio-plus-transcript path

The pinned MLX implementation's actual transcript-conditioned path is `prompt_audio + prompt_text` continuation. Its separate `ref_text` parameter is present but unused by generation at this revision. RB-004 therefore uses the working continuation path and records:

```text
clone_mode = continuation_prompt_audio_transcript
```

This is the closest runtime-exposed match to upstream “Ultimate Cloning” and Qwen's ICL reference-audio-plus-transcript baseline. Exactly one audio file and a non-empty exact transcript are required. Voice design and style instruction are deliberately not used for A01/C01.

## Settings and timing

Quality-first defaults used for controlled evidence:

- inference timesteps: 10
- classifier-free guidance: 2.0
- warmup patches: 0
- maximum tokens: 2000
- minimum tokens: 2 (runtime default)
- continuation prefix: 4 (runtime default)

Requested settings and actual expanded defaults are both persisted. Timing separates worker startup, imports, model load, generation, adapter total, validated duration, and bench RTF. No first-audio or streaming latency is claimed.

## Target-Mac evidence

Machine: Mac Studio Mac13,2, Apple M1 Ultra, 20 CPU cores, 128 GB unified memory, macOS 26.5.1, arm64.

Initial persistent smoke:

- imports: 1.506 s
- model load: 2.397 s
- MLX peak memory after load: 4,955,183,244 bytes
- A01 cold generation: 26.826 s; output 13.120 s; bench RTF 2.088
- C01 warm generation: 9.450 s; output 13.440 s; RTF 0.741
- A01 warm generation: 9.114 s; output 12.960 s; RTF 0.739

Controlled comparison session after filesystem cache warming:

- imports: 0.176 s
- model load: 0.991 s
- A01 cold generation: 9.541 s; output 12.640 s; RTF 0.791
- C01 warm generation: 9.460 s; output 13.440 s; RTF 0.740
- A01 warm generation: 8.662 s; output 12.320 s; RTF 0.738

All six VoxCPM2 outputs passed the unchanged common WAV validator and are mono 48 kHz PCM-16 WAV. `mlx-metal` and Metal availability were explicitly reported; no fallback or warning occurred. These small samples do not establish general performance or quality.

## Capability declaration for the tested adapter

Verified true: local TTS, supplied-reference speech, voice cloning/continuation, multilingual model execution, MLX Metal.

Declared false: natural-language direction, structured direction, guide-performance transfer, streaming, deterministic seed, pronunciation/pause/speed/pitch/duration controls. Upstream or the wider MLX implementation may contain voice design, controllable cloning, and streaming concepts, but RB-004 does not expose or verify them. Capability truth belongs to this adapter path, not the family marketing list.

## Known limitations

- `reference-001` currently maps to a synthetic system-voice architecture fixture, not an approved human clone-fidelity reference.
- Transcript-conditioned continuation is used because `ref_text` is unused in the pinned MLX generator.
- First generation can include substantial one-time MLX graph compilation beyond explicit model loading.
- Seed determinism is not exposed or claimed.
- There is no prompt embedding cache, daemon sharing, concurrency, or idle timeout.
- Full transitive third-party notices remain required before product distribution.
- Human listening/identity scoring has not been performed by this engineering task.
