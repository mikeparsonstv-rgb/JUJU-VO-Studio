#!/usr/bin/env python3
"""Licence-gated Whisper ASR for RB-007 external originals or repaired derivatives."""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
from pathlib import Path
from urllib.parse import urlparse

import whisper

from common import edit_distance, read_json, sha256, words, write_json


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rb006", required=True, type=Path)
    parser.add_argument("--rb007", required=True, type=Path)
    parser.add_argument("--model-cache", required=True, type=Path)
    parser.add_argument("--mode", required=True, choices=["external", "repaired"])
    args = parser.parse_args()
    target_text = {
        "BHM01_target": (args.rb006 / "inputs/BHM01_authoritative.txt").read_text().strip(),
        "BHM02_target": (args.rb006 / "inputs/BHM02_authoritative.txt").read_text().strip(),
    }
    if args.mode == "external":
        signal = read_json(args.rb006 / "measurements/signal-summary.json")
        sources = [{"identity": item["asset_id"], "target": "BHM01_target" if item["asset_id"].startswith("BHM01") else "BHM02_target",
                    "path": item["path"], "source_sha256": item["sha256"]}
                   for item in signal["measurements"] if item["kind"] == "closed_external_benchmark"]
    else:
        repair = read_json(args.rb007 / "repaired/repair-summary.json")
        sources = [{"identity": item["identity"], "target": item["target"], "path": item["repaired_path"],
                    "source_sha256": item["repaired_sha256"]} for item in repair["repairs"]]

    model_name = "turbo"
    model = whisper.load_model(model_name, device="cpu", download_root=str(args.model_cache))
    model_url = whisper._MODELS[model_name]
    model_path = args.model_cache / Path(urlparse(model_url).path).name
    results = []
    for index, source in enumerate(sources, 1):
        print(f"[{index}/{len(sources)}] ASR {args.mode}: {source['identity']}", flush=True)
        decoded = model.transcribe(source["path"], language="en", task="transcribe", fp16=False,
                                   temperature=0.0, word_timestamps=True, verbose=False)
        expected = target_text[source["target"]]
        hypothesis = decoded.get("text", "").strip()
        expected_words, actual_words = words(expected), words(hypothesis)
        expected_chars, actual_chars = list("".join(expected_words)), list("".join(actual_words))
        results.append({
            **source, "hypothesis": hypothesis,
            "reference_word_count": len(expected_words), "hypothesis_word_count": len(actual_words),
            "transcript_coverage": min(1.0, len(actual_words) / max(1, len(expected_words))),
            "wer": edit_distance(expected_words, actual_words) / max(1, len(expected_words)),
            "cer": edit_distance(expected_chars, actual_chars) / max(1, len(expected_chars)),
            "segments": decoded.get("segments", []),
        })
    output = {
        "schema_version": 1, "mode": args.mode,
        "evaluator": {"name": "OpenAI Whisper", "package_version": importlib.metadata.version("openai-whisper"),
                      "model": model_name, "model_url": model_url, "model_sha256": sha256(model_path),
                      "device": "cpu", "role": "assistive completeness/intelligibility evidence only"},
        "results": results,
    }
    write_json(args.rb007 / f"measurements/asr-{args.mode}.json", output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
