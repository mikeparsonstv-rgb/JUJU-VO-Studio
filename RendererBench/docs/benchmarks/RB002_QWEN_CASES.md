# RB-002 Qwen Benchmark Cases

Only these two canonical intents are enabled for the first Qwen integration. Both currently use the same Base-model ICL voice-clone operation but remain distinct benchmark cases.

## A01 — Neutral new speech

Purpose: prove intelligible new speech from the supplied reference voice and establish output/timing metadata. Provide one local reference WAV and, for the preferred ICL path, its exact transcript. No automatic naturalness score is produced.

## C01 — Clone / neutral

Purpose: prove the voice-clone path and create the first renderer result that can later be compared with other engines. Record the external reference path in the persisted result, but do not copy private talent recordings into this repository.

## Operational note

If a reference transcript is supplied, the worker uses Qwen's ICL clone path. Without it, the worker explicitly uses the weaker speaker-embedding-only path. A01 and C01 must not be interpreted as evidence of natural-language performance control: the 0.6B Base checkpoint exposes no instruction-control surface in this integration.
