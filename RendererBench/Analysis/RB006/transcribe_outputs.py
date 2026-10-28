#!/usr/bin/env python3
"""Licence-gated ASR intelligibility measurements for RB-006 generated outputs."""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import re
from pathlib import Path
from urllib.parse import urlparse

import whisper


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+(?:'[a-z0-9]+)?", text.lower())


def chars(text: str) -> list[str]:
    return list("".join(words(text)))


def distance(a: list[str], b: list[str]) -> int:
    previous = list(range(len(b) + 1))
    for i, left in enumerate(a, 1):
        current = [i]
        for j, right in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (left != right)))
        previous = current
    return previous[-1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--model-cache", required=True, type=Path)
    args = parser.parse_args()
    signal = json.loads((args.root / "measurements/signal-summary.json").read_text())
    target_text = {
        "BHM-XH-01": (args.root / "inputs/BHM02_authoritative.txt").read_text().strip(),
        "BHM-XH-02": (args.root / "inputs/BHM01_authoritative.txt").read_text().strip(),
    }
    model_name = "turbo"
    model = whisper.load_model(model_name, device="cpu", download_root=str(args.model_cache))
    model_url = whisper._MODELS[model_name]
    model_path = args.model_cache / Path(urlparse(model_url).path).name
    output = args.root / "measurements/asr"
    output.mkdir(parents=True, exist_ok=True)
    results = []
    generated = [item for item in signal["measurements"] if item["kind"] == "open_renderer_generated"]
    for index, item in enumerate(generated, 1):
        print(f"[{index}/{len(generated)}] ASR {item['renderer_id']} {item['direction_id']} run{item['iteration']}", flush=True)
        decoded = model.transcribe(item["path"], language="en", task="transcribe", fp16=False,
                                   temperature=0.0, word_timestamps=True, verbose=False)
        intended = target_text[item["direction_id"]]
        hypothesis = decoded.get("text", "").strip()
        expected_words, actual_words = words(intended), words(hypothesis)
        expected_chars, actual_chars = chars(intended), chars(hypothesis)
        record = {
            "schema_version": 1, "renderer_id": item["renderer_id"], "direction_id": item["direction_id"],
            "iteration": item["iteration"], "run_id": item["run_id"], "audio_sha256": item["sha256"],
            "intended_text": intended, "intended_text_sha256": hashlib.sha256((intended + "\n").encode()).hexdigest(),
            "hypothesis": hypothesis, "wer": distance(expected_words, actual_words) / max(1, len(expected_words)),
            "cer": distance(expected_chars, actual_chars) / max(1, len(expected_chars)),
            "reference_word_count": len(expected_words), "hypothesis_word_count": len(actual_words),
            "segments": decoded.get("segments", []),
        }
        name = f"{item['renderer_id']}_{item['direction_id']}_run{item['iteration']}.json"
        (output / name).write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n")
        results.append(record)
    evaluator = {
        "name": "OpenAI Whisper", "package_version": importlib.metadata.version("openai-whisper"),
        "model": model_name, "model_url": model_url, "model_sha256": sha256(model_path),
        "device": "cpu", "role": "assistive intelligibility metric; not transcript or listening authority",
    }
    groups = {}
    for renderer in ["qwen3", "voxcpm2", "chatterbox"]:
        for direction in ["BHM-XH-01", "BHM-XH-02"]:
            group = [r for r in results if r["renderer_id"] == renderer and r["direction_id"] == direction]
            groups[f"{renderer}:{direction}"] = {
                "wer_mean": sum(r["wer"] for r in group) / len(group),
                "wer_min": min(r["wer"] for r in group), "wer_max": max(r["wer"] for r in group),
                "cer_mean": sum(r["cer"] for r in group) / len(group),
                "hypothesis_word_counts": [r["hypothesis_word_count"] for r in group],
            }
    (args.root / "measurements/asr-summary.json").write_text(json.dumps({
        "schema_version": 1, "state": "available", "evaluator": evaluator,
        "results": results, "groups": groups,
    }, indent=2, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
