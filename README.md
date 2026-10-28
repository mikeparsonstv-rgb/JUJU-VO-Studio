# JUJU VO Studio

Local AI voice-over studio for short-form TV commercials. macOS 27, Swift 6, Xcode 27.
Director directs · Engineer understands and operates · Actor performs · JUJU owns jobs, voices, takes and history.

- `Briefs/` — approved briefs (Build 01 Rev 1.1 is the current implementation spec)
- `RendererBench/` — tracked copy of the TalkBack/CuePitch Renderer Bench (RB-001…RB-007). The original under
  `~/Documents/CODEX/JUJU VoiceOver/CuePitchBrief/` stays frozen. Evidence, model caches and private audio are not tracked.
- `VOStudio/` — the new macOS app (Stage 1 onward), depending on `RendererBenchCore`
- `Evidence/` — new RB-008+ evidence (ignored) plus `frozen-baseline/` SHA-256 manifests of RB-006/RB-007
- `Notes/` — audit reports, licensing notes, decisions

© 2026 JUJU VFX. All rights reserved.
