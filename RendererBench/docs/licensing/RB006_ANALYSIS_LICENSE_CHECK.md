# RB-006 Analysis Evaluator Licence and Provenance Gate

Checked: 2026-08-08  
Status: **PASS for isolated assistive ASR; no speaker-verifier model authorised**  
Scope: engineering due diligence, not legal advice.

## Decision

RB-006 may use the official OpenAI Whisper `turbo` model through package `openai-whisper 20250625` in a separate analysis environment. OpenAI publishes both Whisper code and model weights under MIT. Commercial use, modification, and redistribution are permitted subject to retention of the copyright and permission notice.

The evaluator is used only to assist transcript verification and optional intelligibility measurement. Its hypotheses are not authoritative human transcripts, identity judgements, accent scores, or subjective ratings. No speaker embedding/verifier has passed a separate gate, so speaker-model similarity remains explicitly unavailable in RB-006.

## Pinned components

| Component | Exact identity | Licence | Use |
|---|---|---|---|
| Whisper code/package | `openai-whisper 20250625` | MIT | Local ASR implementation |
| Whisper model weights | official OpenAI `large-v3-turbo.pt`; SHA-256 `aff26ae408abcba5fbf8813c21e62b0941638c5f6eebfb145be0c9839262a19a` | MIT | English transcription assistance |
| PyTorch runtime | 2.13.0, frozen in `Analysis/RB006/uv.lock` | BSD-style | CPU inference, isolated from renderer environments |
| librosa / soundfile / NumPy / SciPy | exact versions frozen in `Analysis/RB006/uv.lock` | permissive open-source licences | Model-free signal measurement |

## Primary sources

- OpenAI Whisper repository and model-weight licence statement: https://github.com/openai/whisper
- Exact MIT licence: https://github.com/openai/whisper/blob/main/LICENSE
- Official model card and limitations: https://github.com/openai/whisper/blob/main/model-card.md
- Published package: https://pypi.org/project/openai-whisper/20250625/

## Distribution note

The lock captures exact resolved package artifacts, but redistribution still requires a complete third-party-notices inventory. The private Birmingham audio is input data and remains outside source control.
