# Qwen3-TTS RB-002 Licence Check

Checked: 2026-08-08  
Status: **PASS — permitted by the project's open-core gate**  
Scope: engineering due-diligence record, not legal advice.

## Decision

The official Qwen3-TTS source, the exact 0.6B Base checkpoint selected by RB-002, and its official 12 Hz speech-tokenizer assets are all identified as Apache License 2.0 by their respective upstream repositories. Apache-2.0 permits commercial use, modification, and redistribution subject to its conditions. No non-commercial, research-only, gated-access, or separate-permission term was found for these exact artifacts.

## Components checked

| Component | Repository / model ID | Revision checked | Licence | Commercial use | Modification | Redistribution | Obligations |
|---|---|---|---|---|---|---|---|
| Qwen3-TTS source and `qwen-tts` package source | `QwenLM/Qwen3-TTS` | `022e286b98fbec7e1e916cb940cdf532cd9f488e` | Apache-2.0 | Permitted | Permitted | Permitted | Provide licence when redistributing; mark modified files; retain applicable copyright, patent, trademark and attribution notices; reproduce any applicable NOTICE attribution; do not imply trademark permission. |
| RB-002 model checkpoint and bundled assets | `Qwen/Qwen3-TTS-12Hz-0.6B-Base` | `5d83992436eae1d760afd27aff78a71d676296fc` | Apache-2.0 | Permitted | Permitted | Permitted | Same Apache-2.0 redistribution/notice conditions. Model repository is public, ungated, and tagged `license:apache-2.0`. |
| Standalone speech tokenizer checkpoint | `Qwen/Qwen3-TTS-Tokenizer-12Hz` | `7dd38ad4e9bad454aae9cd937d0cd577604fe229` | Apache-2.0 | Permitted | Permitted | Permitted | Same Apache-2.0 redistribution/notice conditions. Repository is public, ungated, and tagged `license:apache-2.0`. |
| Tokenizer assets embedded in the exact Base model repository | `speech_tokenizer/*` within `Qwen/Qwen3-TTS-12Hz-0.6B-Base` | In model revision `5d83992436eae1d760afd27aff78a71d676296fc` | Apache-2.0 repository scope | Permitted | Permitted | Permitted | Same Apache-2.0 redistribution/notice conditions. |

## Primary sources

- Source repository: https://github.com/QwenLM/Qwen3-TTS
- Source licence text: https://github.com/QwenLM/Qwen3-TTS/blob/022e286b98fbec7e1e916cb940cdf532cd9f488e/LICENSE
- Source package metadata declaring Apache-2.0: https://github.com/QwenLM/Qwen3-TTS/blob/022e286b98fbec7e1e916cb940cdf532cd9f488e/pyproject.toml
- Exact model repository: https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base/tree/5d83992436eae1d760afd27aff78a71d676296fc
- Exact model metadata API (licence, files, revision): https://huggingface.co/api/models/Qwen/Qwen3-TTS-12Hz-0.6B-Base
- Exact tokenizer repository: https://huggingface.co/Qwen/Qwen3-TTS-Tokenizer-12Hz/tree/7dd38ad4e9bad454aae9cd937d0cd577604fe229
- Exact tokenizer metadata API (licence, files, revision): https://huggingface.co/api/models/Qwen/Qwen3-TTS-Tokenizer-12Hz
- Official checkpoint capability table and voice-clone usage: https://github.com/QwenLM/Qwen3-TTS/blob/022e286b98fbec7e1e916cb940cdf532cd9f488e/README.md

## Exact artifact observations

- The Base model API reports revision `5d83992436eae1d760afd27aff78a71d676296fc`, Apache-2.0 metadata, public/ungated access, a 1.83 GB model safetensors file, and embedded `speech_tokenizer` configuration/weights. Total repository storage reported at the check was approximately 2.51 GB.
- The standalone tokenizer API reports revision `7dd38ad4e9bad454aae9cd937d0cd577604fe229`, Apache-2.0 metadata, public/ungated access, and approximately 682 MB storage.
- The embedded tokenizer weight and the standalone tokenizer weight resolve to the same Hugging Face linked ETag (`836b7b357f5ea43e889936a3709af68dfe3751881acefe4ecf0dbd30ba571258`) and Xet content hash (`2770552d9ac6119e00cc15f368f2e08a4ae4787b1f94234e639af510f8eb2ea0`). The worker therefore uses the exact official 12 Hz tokenizer content bundled into the pinned Base snapshot without downloading a duplicate 682 MB copy.
- The official source package at the checked commit declares `qwen-tts` version `0.1.1`, Python 3.9–3.13, Apache-2.0, and pinned Transformers `4.57.3`.
- No model weights or official sample audio are committed to this repository. Operator-supplied reference audio remains outside source control.

## Dependency note

Python runtime dependencies retain their own licences and notices. The reproducible environment records installed package versions, but this gate addresses the Qwen code and downloaded Qwen model/tokenizer assets required by RB-002. A distributable product bundle will need a generated third-party-notices inventory for the complete resolved Python environment.
