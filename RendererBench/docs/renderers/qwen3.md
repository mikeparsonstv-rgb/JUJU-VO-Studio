# Qwen3-TTS Renderer — RB-003

Status: persistent real-render path operational on the target Mac  
Checked: 2026-08-08

## Exact integration

- Source: `QwenLM/Qwen3-TTS` commit `022e286b98fbec7e1e916cb940cdf532cd9f488e`
- Python package: `qwen-tts 0.1.1`, installed from that commit
- Model: `Qwen/Qwen3-TTS-12Hz-0.6B-Base`
- Model revision: `5d83992436eae1d760afd27aff78a71d676296fc`
- Tokenizer: `Qwen/Qwen3-TTS-Tokenizer-12Hz`
- Tokenizer revision: `7dd38ad4e9bad454aae9cd937d0cd577604fe229`
- Adapter: `1.1.0-rb003`
- Worker protocol: version 1, newline-delimited JSON over stdin/stdout

The pins and Apache-2.0 licensing decision are unchanged from RB-002. The Base snapshot embeds the official tokenizer content, so setup avoids a duplicate tokenizer download. Runtime is local-files-only.

## Persistent architecture and lifecycle

The Swift adapter owns one `PersistentQwenWorkerClient`. It launches the isolated Python interpreter directly and keeps stdin/stdout open for a serialized sequence:

```text
launch → health → load → render → render → … → shutdown
```

Supported operations are `health`, `load`, `render`, and `shutdown`. Exposed states are `starting`, `ready_unloaded`, `loading`, `ready_loaded`, `rendering`, `failed`, `shutting_down`, and `stopped`. The worker retains the model/tokenizer in process memory after load and returns a stable session ID plus render index.

stdout is protocol-only; diagnostics go to a separate stderr file. The client uses newline framing, validates protocol version and request ID, applies a configurable request timeout, and handles malformed response, EOF, unexpected exit, or timeout as explicit failures. A render exception marks model state uncertain, causes worker exit, and lets the next request launch a clean process. Normal shutdown is graceful; terminate/SIGKILL are fallbacks. The client serializes requests, so one worker cannot receive interleaved protocol messages.

## Timing semantics

The worker and adapter preserve distinct measurements:

- `worker_startup_seconds`: launch-to-ready loop setup, captured once rather than process age
- `python_import_seconds`: accumulated timed Python imports only
- `model_load_seconds`: checkpoint/model construction; zero on a render reusing an already loaded model
- `generation_seconds`: blocking non-streaming `generate_voice_clone` call only
- `adapter_total_seconds`: request/response round trip plus worker-side output write
- validated `outputDuration` and runner `realtimeFactor`

`cold_start` means the first generation in a worker session. Because the benchmark explicitly calls `load` first, its first render correctly has both `cold_start=true` and `model_reused=true`; the load time is reported by the separate load operation. Generation time is not first-audio latency, and no streaming latency is claimed.

Prompt/embedding caching was considered but is not implemented in RB-003. Every result records `reference_prompt_reused=false`; correctness is preferred over unverified cache reuse.

## Setup and operation

Run `scripts/setup-qwen3.sh`. It uses `uv`, managed CPython 3.12, `Workers/Qwen3/uv.lock`, `.renderer-envs/qwen3`, and `.renderer-models/qwen3`. Neither environment nor weights are committed.

Useful overrides:

- `QWEN3_MODEL_HOME`
- `QWEN3_DEVICE=auto|mps|cpu`
- `QWEN3_TIMEOUT_SECONDS` (default 900 seconds per request)
- `QWEN3_WORKER_PYTHON`
- `QWEN3_WORKER_SCRIPT`

`auto` reports the selected backend. Forced `mps` fails if unavailable; forced `cpu` never selects MPS. The request backend must match the worker's configured backend, and every result persists requested and actual values.

Use `scripts/smoke-qwen3.sh` for one persistent backend session. Use `scripts/benchmark-qwen3-backends.sh` for sequential explicit MPS and CPU sessions with identical inputs and raw logs.

## Controlled target-Mac evidence

Test machine: Mac Studio `Mac13,2`, Apple M1 Ultra, 20 CPU cores, 128 GB unified memory, macOS 26.5.1 (25F80), arm64, Python 3.12.13, PyTorch 2.13.0, Transformers 4.57.3.

The 2026-08-08 comparison used identical A01 requests across backends: stable script, reference audio, transcript, language, seed 1003, settings, checkpoint, and tokenizer. Each backend loaded once, rendered A01 and C01, rendered A01 twice more, and shut down. No fallback or warning occurred.

| Backend | Import | Load | A01 cold generation / RTF | A01 warm generation / RTF |
|---|---:|---:|---:|---:|
| MPS | 7.132 s | 2.817 s | 26.597 s / 2.004 | 22.670 s / 1.708; 22.840 s / 1.721 |
| CPU | 4.125 s | 0.960 s | 59.604 s / 4.628 | 59.376 s / 4.611; 57.437 s / 4.460 |

Full A01/C01 rows and run IDs are in `docs/benchmarks/RB003_CONTROLLED_BACKENDS.md`. Raw evidence is under `/tmp/RendererBench-RB003-Controlled-20260808` on the test machine. This small sample supports operational/backend observations only—not quality, deterministic equivalence, or general performance claims. MPS and CPU produced different A01 durations despite matching requests and seed.

All eight generated files passed the unchanged common WAV validator and are 24 kHz, mono, 16-bit PCM RIFF/WAVE.

## Reference handling and catalogue status

The Base clone path accepts exactly one reference. A supplied transcript uses ICL voice cloning; no transcript explicitly selects speaker-embedding-only mode and records a warning. Reference path/transcript presence are snapshotted.

No approved redistributable human recording was available for RB-003. `BenchAssets/references/catalogue.json` therefore contains a versioned empty catalogue and explicit blocker. The temporary macOS system-voice file used for architecture timing was not committed because it is not a human clone-fidelity reference and its redistribution terms were not established. Operators must supply a local rights-cleared reference and transcript until an asset with complete provenance/licence metadata is approved.

## Capability declaration

For this exact adapter/checkpoint path: local multilingual supplied-reference TTS and voice cloning are supported. Natural-language direction, structured control, guide transfer, streaming, verified deterministic seeding, VoiceDesign, and CustomVoice are not exposed. Non-empty direction and unknown generation settings are rejected rather than silently ignored.

## Known limitations

- Persistence lasts only for the owning adapter/session; there is no daemon, cross-process sharing, or idle timeout.
- One request runs at a time; concurrent benchmark work needs separate workers and memory planning.
- A failed render exits the worker because continued model correctness cannot be guaranteed.
- Prompt/embedding reuse is not implemented.
- First-audio latency is unavailable in the deliberately non-streaming path.
- No approved human reference asset or clone-quality baseline is committed.
- The deterministic seed capability remains false; cross-backend outputs were not identical in duration.
- Full third-party notices for the locked dependency graph remain required before product distribution.
- File sandboxes can hide MPS; backend health must be checked in the actual render context.
