# Reference Asset Catalogue

No reference audio is committed.

The temporary macOS system voice used for architecture testing is not a human reference and its redistribution terms were not established, so promoting it into a permanent benchmark asset would be misleading. No celebrity, talent, client, or private production recording may be added here without explicit rights and provenance.

An approved asset directory must contain `reference.wav` plus `metadata.json` conforming to the renderer-neutral `ReferenceAssetMetadata` schema. Required facts include source, licence, redistribution permission, exact transcript, language, speaker description, sample rate, channel count, duration, notes, and date added.

Until an approved asset exists, integration scripts require an operator-supplied absolute reference path and transcript. Those files remain outside source control.

RB-004 establishes the stable local identity `reference-001`. Its committed metadata is under `references/reference-001/metadata.json`; its WAV path is resolved through gitignored `BenchAssets/local-assets.json`. The current mapping uses the temporary synthetic system-voice architecture fixture and is not a human clone-quality reference. Replace the mapping with an authorised recording before subjective identity evaluation, without changing the asset ID or transcript silently.
