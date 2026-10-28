# RB-003 Controlled Qwen Backend Evidence

Run date: 2026-08-08  
Machine: Mac Studio Mac13,2, Apple M1 Ultra, 20 CPU cores, 128 GB unified memory  
OS: macOS 26.5.1 (25F80), arm64  
Model/tokenizer: unchanged pinned RB-002 identities and revisions

## Control conditions

MPS and CPU received byte-for-byte equivalent persisted A01 requests: the same stable script, `/tmp/RB002-Qwen-reference.wav`, exact reference transcript, `en-GB`, seed 1003, and generation settings (`do_sample=true`, temperature 0.9, top-k 50, top-p 1). The temporary 24 kHz mono PCM-16 system-voice reference is architecture-only and is not committed or catalogued as an approved human benchmark asset.

Each backend used one persistent worker: health, explicit model load, A01 cold, C01 warm, two further A01 warm runs, and graceful shutdown. Raw evidence is under `/tmp/RendererBench-RB003-Controlled-20260808`; session logs are `mps-session.log` and `cpu-session.log`.

## Load observations

| Backend | Requested / actual | Python imports | Model load | Worker session |
|---|---|---:|---:|---|
| MPS | mps / mps | 7.132 s | 2.817 s | `af54abce-d901-497b-b613-12d6c2f5e0ea` |
| CPU | cpu / cpu | 4.125 s | 0.960 s | `a8bd9fad-6c8e-4db0-89da-7bf03fce2e20` |

## Render observations

| Backend | Case/context | Index | Generation | Output duration | RTF | Run ID |
|---|---|---:|---:|---:|---:|---|
| MPS | A01 cold | 0 | 26.597 s | 13.280 s | 2.004 | `07746591-a642-4521-947b-f9d79cbd75e2` |
| MPS | C01 warm | 1 | 21.304 s | 12.320 s | 1.730 | `a180f95e-755d-4b4b-9c1a-a5a4cf818c58` |
| MPS | A01 warm 1 | 2 | 22.670 s | 13.280 s | 1.708 | `c69ee067-19b9-431a-b198-b2af3c0b8866` |
| MPS | A01 warm 2 | 3 | 22.840 s | 13.280 s | 1.721 | `6baa2927-8a21-4987-9fd2-e993e53b7881` |
| CPU | A01 cold | 0 | 59.604 s | 12.880 s | 4.628 | `088527d0-3aa7-44ed-be05-7d81a697930a` |
| CPU | C01 warm | 1 | 57.359 s | 12.720 s | 4.510 | `5ce3c192-6d67-4b9c-a6dc-cbed347d3de1` |
| CPU | A01 warm 1 | 2 | 59.376 s | 12.880 s | 4.611 | `61267cc5-e504-4076-bb65-e9fdfb9c2886` |
| CPU | A01 warm 2 | 3 | 57.437 s | 12.880 s | 4.460 | `6c0d9f67-cbe2-415d-961a-7df147065847` |

All render responses reported `model_reused=true`; explicit model-load evidence is kept separately from render timings. All eight outputs passed common validation and are 24 kHz mono PCM-16 WAV. There were no warnings or backend fallbacks, and no worker remained after shutdown.

These are small-sample operational measurements. They do not establish quality equivalence, deterministic equivalence, first-audio latency, or general performance beyond this machine and pinned environment. Despite matching seeds and requests, MPS and CPU A01 output durations differ, so output equivalence is explicitly not claimed.
