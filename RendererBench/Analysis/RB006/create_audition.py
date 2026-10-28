#!/usr/bin/env python3
"""Create identified raw and gain-only level-matched RB-006 audition copies."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path

import numpy as np
import soundfile as sf


def label(item: dict) -> tuple[str, str]:
    if item["kind"] == "human_ground_truth":
        target = "BHM01_target" if item["asset_id"].startswith("BHM01") else "BHM02_target"
        return target, "HUMAN_ground_truth.wav"
    if item["kind"] == "closed_external_benchmark":
        target = "BHM01_target" if item["asset_id"].startswith("BHM01") else "BHM02_target"
        generation = "gen1" if item["asset_id"].endswith("gen1") else "gen2"
        return target, f"ELEVENLABS_{generation}.wav"
    target = "BHM02_target" if item["direction_id"] == "BHM-XH-01" else "BHM01_target"
    names = {"qwen3": "QWEN", "voxcpm2": "VOXCPM", "chatterbox": "CHATTERBOX"}
    return target, f"{names[item['renderer_id']]}_run{item['iteration']}.wav"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    summary = json.loads((args.root / "measurements/signal-summary.json").read_text())
    items = summary["measurements"]
    raw_root = args.root / "audition_raw_pcm"
    matched_root = args.root / "audition_level_matched"
    bundle_root = args.root / "listening-bundle"
    (args.root / "metadata").mkdir(parents=True, exist_ok=True)
    records: dict[str, list[dict]] = {"BHM01_target": [], "BHM02_target": []}

    for item in items:
        target, filename = label(item)
        raw = raw_root / target / filename
        raw.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", item["path"], "-ar", "48000", "-ac", "1",
                        "-c:a", "pcm_s16le", str(raw)], check=True)
        records[target].append({"name": filename, "source": item, "raw": str(raw)})

    for target, group in records.items():
        target_level = min(record["source"]["level"]["active_rms_dbfs"] for record in group)
        for record in group:
            gain_db = target_level - record["source"]["level"]["active_rms_dbfs"]
            raw = Path(record["raw"])
            audio, sr = sf.read(raw, dtype="float32")
            matched = np.asarray(audio * (10 ** (gain_db / 20)), dtype=np.float32)
            destination = matched_root / target / record["name"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            sf.write(destination, matched, sr, subtype="PCM_16", format="WAV")
            record.update(level_matched=str(destination), applied_gain_db=gain_db,
                          level_match_target_active_rms_dbfs=target_level)

        bundle = bundle_root / target
        (bundle / "raw").mkdir(parents=True, exist_ok=True)
        (bundle / "level_matched").mkdir(parents=True, exist_ok=True)
        for record in group:
            shutil.copy2(record["raw"], bundle / "raw" / record["name"])
            shutil.copy2(record["level_matched"], bundle / "level_matched" / record["name"])
        manifest = {
            "schema_version": 1, "target": target, "identified": True, "blind": False,
            "subjective_ratings": False, "authoritative_evidence": "source files referenced in entries",
            "raw_policy": "48 kHz mono PCM-16; resampling/channel conversion only",
            "level_match_policy": "gain-only attenuation to the quietest active-speech RMS in this target group; no compression, limiting, EQ, or noise reduction",
            "entries": [{
                "name": record["name"], "kind": record["source"]["kind"],
                "renderer_id": record["source"].get("renderer_id"), "run_id": record["source"].get("run_id"),
                "asset_id": record["source"].get("asset_id"), "source_path": record["source"]["path"],
                "source_sha256": record["source"]["sha256"], "conditioning_parity": record["source"].get("conditioning_parity"),
                "raw_file": f"raw/{record['name']}", "level_matched_file": f"level_matched/{record['name']}",
                "applied_gain_db": record["applied_gain_db"],
            } for record in group],
        }
        (bundle / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (args.root / "metadata/audition-gains.json").write_text(json.dumps(records, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
