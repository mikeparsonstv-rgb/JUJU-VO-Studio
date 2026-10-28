# Chatterbox Multilingual V3 RB-005 Licence and Provenance Check

Checked: 2026-08-08  
Status: **PASS — the exact selected Multilingual V3 stack meets the project's open-core gate**  
Scope: engineering due-diligence record, not legal advice.

## Decision

The official Chatterbox source, exact official model snapshot containing the Multilingual V3 checkpoint and shared decoder/voice/tokenizer assets, and the PerTh watermark implementation/assets use the MIT licence. The S3 tokenizer package required by the pinned source uses Apache-2.0. These published terms permit commercial use, modification, and redistribution subject to retaining the applicable copyright, permission, licence, and notice text. No non-commercial, research-only, gated-access, or separate-permission restriction was found for the exact selected artifacts.

RB-005 is therefore authorised to install and test this exact stack. This is not authorisation to substitute Multilingual V2, Turbo, Nano, a Single Language Pack, or an unofficial Apple-Silicon conversion.

## Components checked

| Component | Repository / model ID | Exact revision / artifact | Licence | Commercial use | Modification | Redistribution | Relationship and obligations |
|---|---|---|---|---|---|---|---|
| Official source and `chatterbox-tts` package | `resemble-ai/chatterbox` | `5de7a54aa4e5e2baadb0182dde554908b48b85c2`; package version 0.1.7 | MIT | Permitted | Permitted | Permitted | Official implementation. Retain Resemble AI copyright and MIT permission text in copies/substantial portions. |
| Official model repository | `ResembleAI/chatterbox` | `5bb1f6ee58e50c3b8d408bc82a6d3740c2db6e18` | MIT model-card metadata | Permitted | Permitted | Permitted | Public, ungated official repository containing the selected V3 checkpoint and shared inference assets. Retain MIT notice. |
| Multilingual V3 T3 weights | `ResembleAI/chatterbox` | `t3_mtl23ls_v3.safetensors`; SHA-256 `5abca8321ede76f8e61f1cc0d19aea6c946b28871017ce8726f8a69203f05953` in model revision above | MIT repository scope | Permitted | Permitted | Permitted | Exact 500M-class Multilingual V3 T3 checkpoint selected by `t3_model="v3"`. V2 is not selected. |
| Shared S3Gen decoder weights | `ResembleAI/chatterbox` | `s3gen.pt`; SHA-256 `9b9ff07e60b20c136e2b1b3d7563a24604e8d2c4c267888d1ee929dd0151d2a3` | MIT repository scope | Permitted | Permitted | Permitted | Decoder asset explicitly loaded by the pinned official Multilingual V3 implementation. |
| Shared voice encoder | `ResembleAI/chatterbox` | `ve.pt`; SHA-256 `4b16d836bc598509860f6fa068165a8bb5e9ac84f05582dfcf278a5a372879f1` | MIT repository scope | Permitted | Permitted | Permitted | Voice-clone conditioning asset explicitly loaded by the pinned source. |
| Tokenizer and optional bundled condition assets | `ResembleAI/chatterbox` | `grapheme_mtl_merged_expanded_v1.json` SHA-256 `69632f47220a788a52ce2661d096453c5655e9bf25289d89a8d832c46ee07dbf`; `Cangjie5_TC.json` SHA-256 `7073fd9de919443ae88e0bd2449917a65fe54898a4413ed1edcc4b67f28bce8c`; `conds.pt` SHA-256 `6552d70568833628ba019c6b03459e77fe71ca197d5c560cef9411bee9d87f4e` in the pinned model revision | MIT repository scope | Permitted | Permitted | Permitted | Exact allow-list used by the pinned multilingual loader. The benchmark supplies reference audio and does not treat the bundled condition as its comparison identity. |
| PerTh neural watermark code and bundled watermark assets | `resemble-ai/Perth` | `ce86c49d029f42272c1902eccb675556b9ed2330` | MIT | Permitted | Permitted | Permitted | Official Chatterbox dependency. Preserve copyright and MIT permission text. Its implicit neural watermark is instantiated and applied by the official generator. |
| S3 tokenizer runtime | PyPI `s3tokenizer` | 0.3.0, frozen with artifact hashes in `Workers/Chatterbox/uv.lock` | Apache-2.0 | Permitted | Permitted | Permitted | Runtime code used by Chatterbox's embedded S3 tokenizer wrapper. Include licence/notices and mark modifications if redistributed. |
| Multilingual word-segmentation runtime and model | `explosion/spacy-pkuseg` / `spacy_ontonotes` | Package 1.0.1; official release asset `spacy_ontonotes.zip` SHA-256 `b216e7f92de7ae285aeab8feba2faa8ea8216e5995ff6fb3d391cc8356db1bfe` | MIT | Permitted | Permitted | Permitted | Transitive tokenizer dependency and its declared official model asset. Retain MIT notice; RB-005 isolates and verifies the archive instead of allowing an implicit user-cache download. |
| PyTorch / torchaudio Apple-Silicon runtime | PyPI `torch` / `torchaudio` | 2.6.0, frozen with exact wheel hashes in `Workers/Chatterbox/uv.lock` | BSD-style | Permitted | Permitted | Permitted | Official PyTorch MPS execution path. Preserve applicable licence and notices. |

All component checks in this table were performed on 2026-08-08. Source URLs map as follows: Chatterbox code/package to the exact source commit and licence below; model weights/tokenizers/condition assets to the exact Hugging Face model tree below; PerTh to its exact commit below; S3Tokenizer and spaCy-pkuseg to their package/source records below; and PyTorch/torchaudio to the upstream licence below.

## Primary sources

- Official source repository: https://github.com/resemble-ai/chatterbox
- Exact source commit: https://github.com/resemble-ai/chatterbox/commit/5de7a54aa4e5e2baadb0182dde554908b48b85c2
- Exact MIT licence: https://github.com/resemble-ai/chatterbox/blob/5de7a54aa4e5e2baadb0182dde554908b48b85c2/LICENSE
- Exact package metadata: https://github.com/resemble-ai/chatterbox/blob/5de7a54aa4e5e2baadb0182dde554908b48b85c2/pyproject.toml
- Exact V3/MPS multilingual implementation: https://github.com/resemble-ai/chatterbox/blob/5de7a54aa4e5e2baadb0182dde554908b48b85c2/src/chatterbox/mtl_tts.py
- Official model metadata: https://huggingface.co/api/models/ResembleAI/chatterbox
- Exact model tree: https://huggingface.co/ResembleAI/chatterbox/tree/5bb1f6ee58e50c3b8d408bc82a6d3740c2db6e18
- PerTh repository: https://github.com/resemble-ai/Perth
- Exact PerTh commit/licence: https://github.com/resemble-ai/Perth/tree/ce86c49d029f42272c1902eccb675556b9ed2330
- S3 tokenizer package: https://pypi.org/project/s3tokenizer/
- spaCy-pkuseg source/licence: https://github.com/explosion/spacy-pkuseg
- Exact official word-segmentation model release: https://github.com/explosion/spacy-pkuseg/releases/tag/v0.0.26
- Exact spaCy-pkuseg package metadata: https://pypi.org/project/spacy-pkuseg/1.0.1/
- PyTorch licence: https://github.com/pytorch/pytorch/blob/main/LICENSE

## Exact-path observations

- The pinned source declares `chatterbox-tts 0.1.7` and documents `cuda`, `cpu`, and `mps` device choices.
- The exact Multilingual V3 call is `ChatterboxMultilingualTTS.from_pretrained(device=..., t3_model="v3")`. The resolver maps only that selection to `t3_mtl23ls_v3.safetensors`.
- Upstream still defaults to the legacy V2 filename when `t3_model` is omitted. RB-005 must therefore pass and verify V3 explicitly; an omitted or V2 selection is an integration failure.
- The pinned source includes CPU-first checkpoint deserialisation for non-CUDA devices before moving the voice encoder, V3 T3 model, S3Gen decoder, and conditionals to MPS.
- Upstream's convenience `from_pretrained` resolves the model branch named `main` and may silently select CPU when MPS is unavailable. RB-005 setup instead downloads the exact revision, and the worker loads it locally and fails rather than accepting a forced-backend fallback.
- The official V3 path downloads only `ve.pt`, `t3_mtl23ls_v3.safetensors`, `s3gen.pt`, `grapheme_mtl_merged_expanded_v1.json`, `conds.pt`, and `Cangjie5_TC.json`. It does not require the V2, Turbo, Nano, Single Language Pack, `s3gen_v3`, or alternate safetensor assets.
- `generate` accepts text, a language ID, reference audio, exaggeration, CFG weight, temperature, repetition penalty, minimum probability, and top-p. It does not accept or use a reference transcript.
- The official class instantiates `perth.PerthImplicitWatermarker` and applies it to every returned waveform. RB-005 will retain this behavior and persist its expected/enabled/version state.
- The first integration load exposed a transitive `spacy-pkuseg` download of the official `spacy_ontonotes` segmentation model. The setup now materialises that exact MIT-licensed release asset under the renderer-owned model cache, and worker health requires its known archive hash and extracted files before reporting the model available.

## Dependency and distribution note

Each transitive package retains its own licence. The 146-package lock records exact resolved versions and artifact hashes, but a distributable product still needs a complete generated third-party-notices inventory. Reference audio must be lawfully authorised regardless of these software/model permissions.
