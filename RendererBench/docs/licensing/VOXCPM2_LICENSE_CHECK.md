# VoxCPM2 RB-004 Licence Check

Checked: 2026-08-08  
Status: **PASS — the selected BF16 MLX stack meets the project's open-core gate**  
Scope: engineering due-diligence record, not legal advice.

## Decision

The official VoxCPM source, official VoxCPM2 weights, selected full-precision BF16 MLX conversion, `mlx-audio` runtime, and Apple MLX framework all use permissive Apache-2.0 or MIT terms. Their published terms permit commercial use, modification, and redistribution subject to attribution/notice conditions. No non-commercial, research-only, gated-access, or separate-permission term was found for the exact artifacts selected below.

The conversion is recorded as an MLX derivative/runtime representation of `openbmb/VoxCPM2`, not as byte-identical execution of the upstream PyTorch/CUDA implementation.

## Components checked

| Component | Repository/model | Exact revision | Licence | Commercial use | Modification | Redistribution | Relationship / obligations |
|---|---|---|---|---|---|---|---|
| Official source | `OpenBMB/VoxCPM` | `616d3d3e630a9c96c2853250eef91b0f39dcd5fa` | Apache-2.0 | Permitted | Permitted | Permitted | Official upstream implementation. Include licence; retain notices; mark modified files; preserve applicable NOTICE attribution; no trademark grant. |
| Official model weights/assets | `openbmb/VoxCPM2` | `bffb3df5a29440629464e5e839f4d214c8714c3d` | Apache-2.0 | Permitted | Permitted | Permitted | Upstream 2B BF16 model lineage. Public and ungated. Same Apache notice/attribution obligations. |
| Apple-Silicon BF16 conversion | `mlx-community/VoxCPM2-bf16` | `a7fb80d9056983135a54ca3f71fcc5a637ccddf5` | Apache-2.0 | Permitted | Permitted | Permitted | Full-precision MLX conversion declaring base model `openbmb/VoxCPM2`; approximately 4.96 GB. Same Apache obligations, including notices for upstream material. |
| MLX audio runtime | `Blaizzy/mlx-audio`, PyPI `mlx-audio 0.4.6` | tag/commit `d28d68c6ac4e28f7d2d66007f640b06cf3fd8ceb`; wheel SHA-256 `cd9c3958d50bf3f30fc78d64fc1b638f84961a6aadb0731582a5c16efe7bb7e5` | MIT | Permitted | Permitted | Permitted | Runtime implementing the VoxCPM2 MLX architecture. Preserve copyright and permission notice in substantial copies. |
| Apple MLX framework | `ml-explore/mlx`, PyPI `mlx 0.32.0` / `mlx-metal 0.32.0` | Exact wheel hashes recorded in `Workers/VoxCPM2/uv.lock` | MIT | Permitted | Permitted | Permitted | Core Apple-Silicon array/Metal runtime. Preserve copyright and permission notice in substantial copies. |

## Primary sources

- Official source repository and model/code licence statement: https://github.com/OpenBMB/VoxCPM
- Exact source commit: https://github.com/OpenBMB/VoxCPM/commit/616d3d3e630a9c96c2853250eef91b0f39dcd5fa
- Exact source licence: https://github.com/OpenBMB/VoxCPM/blob/616d3d3e630a9c96c2853250eef91b0f39dcd5fa/LICENSE
- Official model API metadata/revision: https://huggingface.co/api/models/openbmb/VoxCPM2
- Exact official model tree: https://huggingface.co/openbmb/VoxCPM2/tree/bffb3df5a29440629464e5e839f4d214c8714c3d
- Exact BF16 conversion API metadata/revision: https://huggingface.co/api/models/mlx-community/VoxCPM2-bf16
- Exact BF16 conversion tree: https://huggingface.co/mlx-community/VoxCPM2-bf16/tree/a7fb80d9056983135a54ca3f71fcc5a637ccddf5
- `mlx-audio` v0.4.6 source: https://github.com/Blaizzy/mlx-audio/tree/d28d68c6ac4e28f7d2d66007f640b06cf3fd8ceb
- `mlx-audio` MIT licence: https://github.com/Blaizzy/mlx-audio/blob/d28d68c6ac4e28f7d2d66007f640b06cf3fd8ceb/LICENSE
- PyPI v0.4.6 metadata and hashes: https://pypi.org/pypi/mlx-audio/0.4.6/json
- Apple MLX repository/licence: https://github.com/ml-explore/mlx

## Exact artifact observations

- The official model API reports revision `bffb3df5a29440629464e5e839f4d214c8714c3d`, Apache-2.0 metadata, public/ungated access, BF16 weights, 2,290,004,544 parameters, and approximately 9.54 GB repository storage.
- The selected conversion API reports revision `a7fb80d9056983135a54ca3f71fcc5a637ccddf5`, Apache-2.0 metadata, public/ungated access, `mlx-audio` runtime identity, `openbmb/VoxCPM2` base-model lineage, BF16 weights, and approximately 4.96 GB repository storage.
- The official repository describes 30-language generation, voice cloning, reference-audio-plus-transcript continuation, voice design, controllable cloning, streaming, and 48 kHz output. RB-004 will declare only capabilities actually exposed and verified by the selected MLX path.
- Upstream's published misuse warning and voice-authorization responsibility remain product-governance concerns even though they are not additional licence restrictions. Reference audio must be lawfully authorized.
- No official sample audio, private voice material, model weights, or runtime environment will be committed to the Swift package.
- The resolved environment uses Python 3.12.13, `mlx-audio 0.4.6`, `mlx 0.32.0`, `mlx-metal 0.32.0`, `mlx-lm 0.31.3`, Transformers 5.12.1, and Hugging Face Hub 1.27.0. Exact transitive versions and artifact hashes are in `Workers/VoxCPM2/uv.lock`.

## Dependency and distribution note

Every transitive Python dependency retains its own licence. `uv.lock` will preserve exact resolved versions and hashes for reproducibility; a distributable product still requires a generated third-party-notices inventory covering the complete environment. This gate authorizes the selected engineering integration, not an unreviewed product redistribution bundle.
