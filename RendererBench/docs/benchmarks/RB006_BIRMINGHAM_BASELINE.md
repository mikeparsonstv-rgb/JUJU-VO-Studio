# RB-006 Birmingham Cross-Holdout Untuned Baseline

Date: 2026-08-08  
Status: **complete engineering evidence; identified operator audition pending**

RB-006 used the private Birmingham commercial voice in two leakage-controlled directions: BHM01 human reference generated the withheld BHM02 text, and BHM02 human reference generated the withheld BHM01 text. Each established renderer made three calls per direction. No settings, reference crops, or outputs were optimized or selected.

## Transcript and asset authority

The operator accepted the recommended transcripts and explicitly retained the opening/final `Hah!` where performed. BHM01 authoritative transcript SHA-256 is `3e9e7ba2eb9f23d7bbba4db82e7010f2abff616e2a4d21727a05f836c4b3a79c`; BHM02 is `af1c9689b57a32372a837e4f35156a603bdcc879e0861bcc7392bbc2a2d9d1ad`. Human-reference SHA-256 values:

- BHM01: `ead6baecac68910aff1254bc2d368b4dd4b750f3cb4705e88ece03fd55a511c4`
- BHM02: `1a46eccf382b352a3ab7dcd16a6533021cc7bde78a8dc0b0d948b0ded166a696`

The decision trail is in `RB006_TRANSCRIPT_VERIFICATION.md`. Private transcript bodies and media are not reproduced here.

## Exact renderer identities

- Qwen3-TTS: `Qwen/Qwen3-TTS-12Hz-0.6B-Base@5d83992436eae1d760afd27aff78a71d676296fc`, tokenizer `Qwen/Qwen3-TTS-Tokenizer-12Hz@7dd38ad4e9bad454aae9cd937d0cd577604fe229`, qwen-tts 0.1.1, adapter `1.1.0-rb003`, PyTorch MPS.
- VoxCPM2: `openbmb/VoxCPM2@bffb3df5a29440629464e5e839f4d214c8714c3d` through `mlx-community/VoxCPM2-bf16@a7fb80d9056983135a54ca3f71fcc5a637ccddf5`, mlx-audio 0.4.6 revision `d28d68c6ac4e28f7d2d66007f640b06cf3fd8ceb`, adapter `1.0.0-rb004`, MLX Metal.
- Chatterbox Multilingual V3: source `resemble-ai/chatterbox@5de7a54aa4e5e2baadb0182dde554908b48b85c2`, model `ResembleAI/chatterbox@5bb1f6ee58e50c3b8d408bc82a6d3740c2db6e18`, explicit `t3_model=v3`, adapter `1.0.0-rb005`, PyTorch MPS, PerTh retained.

## Compact measured comparison

| Renderer | Direction | Output duration mean (range) | Generation mean (range) | RTF | Whisper WER | F0 median | Pause |
|---|---|---:|---:|---:|---:|---:|---:|
| Qwen3-TTS | BHM-XH-01 | 26.24 s (26.24–26.24) | 48.23 s (46.31–50.70) | 1.84 | 0.090 | 215.1 Hz | 0.202 |
| Qwen3-TTS | BHM-XH-02 | 25.84 s (25.84–25.84) | 48.39 s (47.89–48.75) | 1.87 | 0.029 | 200.7 Hz | 0.200 |
| VoxCPM2 | BHM-XH-01 | 5.12 s (0.80–13.76) | 5.15 s (1.36–11.08) | 2.22 | 0.950 | 374.8 Hz | 0.420 |
| VoxCPM2 | BHM-XH-02 | 8.27 s (6.72–10.56) | 7.01 s (5.86–8.70) | 0.90 | 0.676 | 234.7 Hz | 0.207 |
| Chatterbox V3 | BHM-XH-01 | 24.72 s (23.80–25.96) | 187.29 s (67.66–333.62) | 7.43 | 0.090 | 200.0 Hz | 0.173 |
| Chatterbox V3 | BHM-XH-02 | 19.35 s (18.08–20.28) | 56.58 s (52.58–60.25) | 2.92 | 0.103 | 176.4 Hz | 0.131 |

All 18 files are structurally valid WAV output. That does not imply complete speech: VoxCPM2 stopped early in every long-form call, including two 0.80-second BHM-XH-01 results. Those files remain authoritative untuned evidence. Qwen's established seed 1003 produced identical output within each direction, so its calls measure fixed-baseline repeatability rather than stochastic diversity. Chatterbox varied across calls and showed substantial latency variance.

## Human and evaluator context

BHM01 is 28.88 seconds with 21.77 seconds active speech, pause proportion 0.246, and median F0 179.8 Hz. BHM02 is 30.00 seconds with 22.61 seconds active speech, pause proportion 0.246, and median F0 182.9 Hz. Their mean-MFCC Euclidean distance is 12.80. These describe two performances by the same speaker; they are neither an identity score nor a mathematical ceiling.

Official OpenAI Whisper 20250625 `turbo`, model SHA-256 `aff26ae408abcba5fbf8813c21e62b0941638c5f6eebfb145be0c9839262a19a`, ran locally on CPU after its separate MIT licence/provenance gate. WER/CER is assistive evidence only. No separately gated speaker verifier was added, so speaker similarity is explicitly unavailable. Automated accent scoring is unavailable by design.

## Audition evidence and limits

The ignored local evidence root is `BenchData/qualifications/RB006-Birmingham-Baseline`. It contains per-run evidence and measurements, raw 48 kHz mono PCM-16 audition copies, and attenuation-only level-matched copies. Each identified target bundle contains the human ground truth, three Qwen calls, three VoxCPM2 calls, three Chatterbox calls, and two supplied ElevenLabs files.

ElevenLabs audio is untouched operator-supplied market context. Its exact conditioning and settings are unknown; it was never used for conditioning, tuning, or API integration and is not a controlled renderer comparison.

No machine listening judgement, subjective winner, or Birmingham-accent claim was generated. Exact run IDs, per-run measurements, ASR hypotheses, gain metadata, and bundle manifests are preserved in the local `report/report.json` and sibling evidence. RB-007 was not begun.
