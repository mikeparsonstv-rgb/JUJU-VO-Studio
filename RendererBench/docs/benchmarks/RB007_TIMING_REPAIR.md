# RB-007 Timing Repair Control

Date: 2026-08-09  
Status: **engineering derivatives complete; identified operator audition pending**

> **RB-007 tests whether correcting overall timing alone materially improves perceived performance. It does not test Actor Model direction, semantic intent, phrase-level timing, energy control, or renderer-native performance steering.**

RB-006 remains the frozen untuned authority. RB-007 made no renderer request, changed no model setting, and used no human target as conditioning. The withheld target human contributes only a clearly labelled `oracle_target_performed_span` to post-generation diagnostic derivatives.

## Method

Performed span is the last meaningful speech offset minus the first meaningful speech onset. It excludes arbitrary head/tail silence while retaining all internal pauses. Every file uses `librosa.effects.split`, top-dB 35, frame length 2048, hop length 512, method version `rb007_performed_span_v1`.

- BHM01 oracle performed span: 28.773 seconds
- BHM02 oracle performed span: 29.589 seconds
- Completeness gate: transcript coverage ≥ 0.80 and assistive Whisper WER ≤ 0.35
- Fixed time-scale guardrail: 0.85–1.20
- Repair: macOS 26.5.1 `AVAudioUnitTimePitch` through offline `AVAudioEngine`, pitch 0 cents
- Processing: performed region only; original head/tail retained; internal pauses scale with the region
- Explicitly absent: gain adjustment, normalization, EQ, compression, limiting, denoise, dereverb, formant shift, breath synthesis, pause editing, phrase rearrangement, and spectral enhancement

## Eligibility outcome

Nine derivatives qualify:

- Qwen: six of six
- Chatterbox: one of six (`BHM02_CHATTERBOX_run2`)
- ElevenLabs: two of four (both BHM02-target generations)
- VoxCPM2: zero of six

All six VoxCPM2 calls fail completeness and are not stretched. Five Chatterbox calls and the two BHM01-target ElevenLabs calls are complete enough but outside the ratio guardrail. The threshold was not widened to manufacture more listening material.

## Measurements

| Pair | Original span | Scale | Repaired span | Error | Active RMS Δ | Median F0 Δ | WER before → after |
|---|---:|---:|---:|---:|---:|---:|---:|
| BHM02 ElevenLabs 1 | 28.352 s | 1.0444 | 29.600 s | +10.7 ms | −0.024 dB | +1.07 Hz | 0.164 → 0.164 |
| BHM02 ElevenLabs 2 | 27.028 s | 1.0951 | 29.557 s | −32.0 ms | −0.044 dB | −1.04 Hz | 0.149 → 0.149 |
| BHM02 Chatterbox 2 | 25.365 s | 1.1665 | 29.632 s | +42.7 ms | −0.091 dB | −2.25 Hz | 0.090 → 0.104 |
| BHM02 Qwen 1–3 | 26.219 s | 1.1286 | 29.568 s | −21.3 ms | −0.016 dB | −2.47 Hz | 0.090 → 0.090 |
| BHM01 Qwen 1–3 | 25.365 s | 1.1344 | 28.736 s | −37.3 ms | −0.102 dB | 0.00 Hz | 0.029 → 0.029 |

All nine repairs meet the 50 ms performed-span tolerance. Per-pair JSON records retain source file/result/run identity, source and derivative hashes, full duration/span/active/pause measurements, pitch range, level, spectral/MFCC descriptors, ASR hypotheses, algorithm/platform, ratio, and error.

A direct AVFoundation decode of the MP3 market benchmarks introduced approximately −3 dB. Those attempted derivatives were rejected and preserved outside primary evidence. Accepted ElevenLabs repairs instead use the frozen RB-006 48 kHz mono PCM copies, whose policy is resampling/channel conversion only; the original MP3 identities and hashes remain the source provenance.

## Listening boundary

Each target has an identified raw-level bundle and a separate attenuation-only level-matched bundle. Original and repaired files are adjacent wherever repair was eligible. The operator must assess:

- whether pace feels less rushed and closer to the human performance;
- whether high energy or push remains after timing correction;
- whether identity and Birmingham character survive;
- whether breaths, consonants, pauses, or texture reveal stretch artefacts;
- whether overall performance improves without interpretive change;
- whether `Hah!` remains the same semantic “gotcha” failure, as expected from a timing-only repair.

Engineering measurements cannot answer those questions, and RB-007 declares no winner. Renderer-native/source-derived pace, phrase-level retiming, energy control, semantic direction, and the `Hah!` Actor Model benchmark remain roadmap items only.
