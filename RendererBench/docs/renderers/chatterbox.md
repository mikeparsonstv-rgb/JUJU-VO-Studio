# Chatterbox Multilingual V3 Renderer — RB-005

Status: persistent official PyTorch MPS path operational on the target Mac  
Checked: 2026-08-08

## Exact identity

- renderer ID/family: `chatterbox` / Chatterbox
- variant: Multilingual V3; `t3_model=v3`
- official source: `resemble-ai/chatterbox@5de7a54aa4e5e2baadb0182dde554908b48b85c2`
- official model: `ResembleAI/chatterbox@5bb1f6ee58e50c3b8d408bc82a6d3740c2db6e18`
- V3 checkpoint: `t3_mtl23ls_v3.safetensors`, SHA-256 `5abca8321ede76f8e61f1cc0d19aea6c946b28871017ce8726f8a69203f05953`
- shared weights: `s3gen.pt`, `ve.pt`, `conds.pt`, plus the pinned multilingual tokenizer assets
- adapter: `1.0.0-rb005`; worker protocol 1
- backend: official PyTorch MPS, with no CPU or alternate-variant fallback

The open-core licence/provenance gate passes; see `docs/licensing/CHATTERBOX_V3_LICENSE_CHECK.md`. The worker verifies both the explicit `v3` resolver result and exact local snapshot. Requests naming V2, Turbo, Nano, another revision, or a non-MPS backend fail.

## Isolated installation

`scripts/setup-chatterbox.sh` creates `.renderer-envs/chatterbox` with Python 3.12.13 and a 146-package `uv.lock` resolution (129 installed packages). Key runtime versions are Chatterbox 0.1.7, PyTorch/torchaudio 2.6.0, Transformers 5.2.0, Hugging Face Hub 1.27.0, S3Tokenizer 0.3.0, PerTh 1.0.1, and spaCy-pkuseg 1.0.1.

The exact model allow-list lives in `.renderer-models/chatterbox`. A transitive `spacy_ontonotes` word-segmentation download discovered during the first load is now pre-fetched into that renderer-owned cache; worker health requires its official archive SHA-256 and extracted model files. Runtime model resolution is local-only. No global Python install, shared Qwen/Vox environment, MLX conversion, or bundled Swift-package weights are used.

## Lifecycle and protocol

```text
launch → health → load → render → render → … → shutdown
```

The long-lived worker speaks versioned newline-delimited JSON on stdin/stdout and keeps diagnostics on stderr. It implements starting, ready-unloaded, loading, ready-loaded, rendering, failed, shutting-down, and stopped states. The Swift client serializes access, validates response/request identity, uses nonblocking line framing, enforces a timeout, and tears down uncertain sessions after malformed output, EOF, exit, or timeout. One V3 model is loaded per session and reused for all renders.

## Clone path and settings

The tested mode is `zero_shot_reference_audio`: exactly one reference WAV plus new text and an explicit Chatterbox language ID. Chatterbox does not consume the reference transcript. Results therefore distinguish `reference_transcript_available=true` from `reference_transcript_used=false` while retaining `reference_asset_id=reference-001`.

Baseline values are the official V3 defaults exposed by the pinned generator:

- exaggeration 0.5
- CFG weight 0.5
- temperature 0.8
- repetition penalty 1.2
- min-p 0.05
- top-p 1.0

These are renderer-native controls, not translations of Qwen/Vox settings. Generic direction is unsupported and rejected.

## Watermark behavior

The official generator creates `PerthImplicitWatermarker` and applies it to output. RB-005 leaves it enabled. Results persist expected/enabled state, system `PerTh implicit`, and version 1.0.1. The bench records the upstream behavior; it does not independently decode the embedded watermark.

## Target-Mac evidence

Machine: Mac Studio Mac13,2, Apple M1 Ultra, 20 CPU cores, 128 GB unified memory, macOS 26.5.1, arm64.

Initial integration smoke:

- imports 56.350 s; model load 14.321 s; MPS memory after load 3,205,989,632 bytes
- A01 cold: 72.980 s generation, 11.320 s output, RTF 6.448
- C01 warm: 34.893 s generation, 12.320 s output, RTF 2.833
- A01 warm: 32.614 s generation, 11.120 s output, RTF 2.934

Controlled three-way session after caches were warm:

- imports 4.575 s; model load 10.806 s; MPS memory after load 3,205,989,632 bytes
- A01 cold: 36.391 s generation, 36.398 s adapter total, 10.800 s output, RTF 3.370
- C01 warm: 34.284 s generation, 34.293 s total, 12.560 s output, RTF 2.730
- A01 warm: 30.671 s generation, 30.679 s total, 11.200 s output, RTF 2.739

All outputs passed the unchanged common WAV validator and are mono 24 kHz PCM-16. These are small-sample elapsed-generation measurements, not first-audio latency or quality evidence.

## Capability truth

Verified: local text-to-speech, supplied-reference zero-shot voice cloning, multilingual model/language-ID execution, official MPS execution, persistent model reuse, and retained PerTh watermarking.

Declared false: natural-language direction, structured direction, guide-performance transfer, streaming/first-audio, deterministic seed, generic pronunciation/pause/speed/pitch/duration controls. The wider family may advertise more behavior; capability declarations describe only this exact adapter path.

## Known limitations

- `reference-001` is a temporary synthetic system-voice architecture fixture, not an approved human clone-fidelity reference.
- Human audition, speaker-similarity, intelligibility, and quality ranking are not performed by this engineering task.
- The PerTh metadata records that watermarking ran but does not verify detection from the rendered file.
- The first integration run populated a pre-existing user `~/.pkuseg` cache before this hidden dependency was isolated; no user cache was deleted.
- There is no prompt-conditioning cache, shared daemon, concurrency, or idle timeout.
- Product distribution still needs a complete transitive third-party-notices inventory.
