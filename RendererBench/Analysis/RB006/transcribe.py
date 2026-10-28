#!/usr/bin/env python3
"""Opt-in RB-006 transcription using the isolated, licence-gated Whisper evaluator."""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
from urllib.parse import urlparse


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--model-cache", required=True, type=Path)
    parser.add_argument("--model", default="turbo")
    args = parser.parse_args()
    if not args.audio.is_file() or not args.audio.is_absolute():
        parser.error("--audio must be an existing absolute file")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.model_cache.mkdir(parents=True, exist_ok=True)

    import torch
    import whisper

    model = whisper.load_model(args.model, device="cpu", download_root=str(args.model_cache))
    result = model.transcribe(
        str(args.audio), language="en", task="transcribe", fp16=False,
        temperature=0.0, word_timestamps=True, verbose=False,
    )
    model_url = whisper._MODELS[args.model]
    model_path = args.model_cache / Path(urlparse(model_url).path).name
    evidence = {
        "schema_version": 1,
        "evaluator": "OpenAI Whisper",
        "evaluator_role": "assistive transcript verification; not human authority",
        "package_version": importlib.metadata.version("openai-whisper"),
        "model": args.model,
        "model_url": model_url,
        "model_sha256": sha256(model_path),
        "torch_version": torch.__version__,
        "device": "cpu",
        "audio_path": str(args.audio),
        "audio_sha256": sha256(args.audio),
        "language": result.get("language"),
        "text": result.get("text", "").strip(),
        "segments": result.get("segments", []),
    }
    args.output.write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n")
    print(evidence["text"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
