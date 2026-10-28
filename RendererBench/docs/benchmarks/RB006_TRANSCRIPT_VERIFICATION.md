# RB-006 Birmingham Transcript Verification Gate

Checked: 2026-08-08  
Status: **PASS — operator confirmed the recommended authoritative transcripts on 2026-08-08**

## Evidence checked

The eight local/private assets in `birmingham 01` match every SHA-256 value in `RB006_BIRMINGHAM_ASSETS.json`. Three filenames omit duplicate-download suffixes from the manifest, but their byte hashes are exact. The source screenshots also match their recorded hashes.

Human references:

- BHM01: `ead6baecac68910aff1254bc2d368b4dd4b750f3cb4705e88ece03fd55a511c4`
- BHM02: `1a46eccf382b352a3ab7dcd16a6533021cc7bde78a8dc0b0d948b0ded166a696`

Candidate transcript hashes:

- BHM01 candidate: `3751e73d1a5a0396e8ff9bf247b739d718016a53f72cef6d4f0c1aa02631ec0d`
- BHM02 candidate: `f85fcd1f11ba512e011df623da465c57742e6b4c196542e99f70ca21567159ac`

## Verification method and limit

The copy-source screenshots were visually checked against the candidate files. The human WAVs were then transcribed locally with the licence-gated official OpenAI Whisper `turbo` evaluator: `openai-whisper 20250625`, model SHA-256 `aff26ae408abcba5fbf8813c21e62b0941638c5f6eebfb145be0c9839262a19a`, PyTorch 2.13.0, CPU. Timestamped hypotheses are preserved in the ignored qualification evidence directory.

Whisper is assistive evidence, not authority. The discrepancies below require an operator listening decision because Qwen and VoxCPM2 condition on the transcript.

## BHM01 findings

The candidate largely matches the copy screenshot and ASR hypothesis. Items needing confirmation:

1. The screenshot/candidate includes `hah!` after the opening question; ASR does not lexicalise it. Confirm whether the recording contains a spoken “hah”, a non-verbal laugh, or neither.
2. At 21.76–22.16 s, the screenshot/candidate says `thick`; ASR proposes `fit` with only 0.689 probability. Confirm the actual spoken word. This may be accent-related ASR error.
3. At 22.50–22.74 s, the candidate says `giving a brill clean`; ASR proposes `giving the brill clean` with low 0.487 probability on the article. Confirm `a` versus `the`.

Punctuation, capitalization, `Let's`, and `Daz gel` spacing are normalization questions rather than clear wording mismatches.

## BHM02 material findings

1. Opening copy/candidate: `your prediction` (singular). Audio ASR at 1.72–2.26 s: `your predictions` (plural), probability 0.994.
2. Copy/candidate: `AHA! Laundry Overspiller!`. Audio ASR at 8.42–9.94 s: `The laundry overspiller`, with `The` probability 0.957.
3. Copy/candidate: `giving a controlled does`. Audio ASR at 21.80–23.02 s: `giving you a controlled dose`; `you` probability 0.998 and `dose` probability 0.999. The screenshot's `does` is evidently at least a copy typo, but it must not be silently corrected.
4. The screenshot/candidate places `hah!` after the opening and at the end. ASR does not lexicalise the opening interjection and hears the ending as `Ha ha!`; confirm how non-verbal/spoken laughter should be represented.

## Proposed transcript decisions requiring confirmation

Please confirm or amend these exact wording choices before the authoritative 18-render run:

- BHM01: retain `predictions`; confirm opening `Hah!`; confirm `lusciously thick`; confirm `giving a brill clean` versus `giving the brill clean`.
- BHM02: change `prediction` to `predictions`; decide whether to include `The` before `Laundry Overspiller`; change `giving a controlled does` to `giving you a controlled dose`; confirm opening/final laughter wording.

The operator confirmed the recommended wording: BHM01 retains `predictions`, opening `Hah!`, `lusciously thick`, and `giving a brill clean`; BHM02 uses `predictions`, `The Laundry Overspiller`, `giving you a controlled dose`, and retains its opening/final `Hah!`. Exact authoritative transcript hashes are `3e9e7ba2eb9f23d7bbba4db82e7010f2abff616e2a4d21727a05f836c4b3a79c` (BHM01) and `af1c9689b57a32372a837e4f35156a603bdcc879e0861bcc7392bbc2a2d9d1ad` (BHM02). The gate now permits the authoritative run.
