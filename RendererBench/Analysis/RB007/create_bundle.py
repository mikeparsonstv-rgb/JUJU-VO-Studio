#!/usr/bin/env python3
"""Create paired identified raw-level and gain-only level-matched RB-007 bundles."""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path

import numpy as np
import soundfile as sf

from common import detailed_measure, read_json, write_json


def convert(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(source), "-ar", "48000", "-ac", "1",
                    "-c:a", "pcm_s16le", str(destination)], check=True)


def short_label(identity: str, target: str) -> str:
    prefix = "BHM01_" if target == "BHM01_target" else "BHM02_"
    return identity.removeprefix(prefix)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rb006", required=True, type=Path)
    parser.add_argument("--rb007", required=True, type=Path)
    args = parser.parse_args()
    plan = read_json(args.rb007 / "source_manifest/timing-repair-plan.json")
    repair = read_json(args.rb007 / "repaired/repair-summary.json")
    repair_by_identity = {item["identity"]: item for item in repair["repairs"]}
    signal = read_json(args.rb006 / "measurements/signal-summary.json")
    humans = {item["asset_id"]: item for item in signal["measurements"] if item["kind"] == "human_ground_truth"}
    bundle_root = args.rb007 / "listening-bundle"
    for target in ["BHM01_target", "BHM02_target"]:
        target_root = bundle_root / target
        if target_root.exists():
            raise SystemExit(f"refusing to overwrite listening bundle: {target_root}")
        raw_root, matched_root = target_root / "raw", target_root / "level_matched"
        raw_root.mkdir(parents=True, exist_ok=False)
        matched_root.mkdir(parents=True, exist_ok=False)
        entries = []
        counter = 1
        human_id = plan["targets"][target]["asset_id"]
        human = humans[human_id]
        filename = f"{counter:02d}_HUMAN_TARGET.wav"; counter += 1
        raw = raw_root / filename
        convert(Path(human["path"]), raw)
        entries.append({"pair_id": "human_target", "variant": "human_target", "identity": human_id,
                        "source_path": human["path"], "source_sha256": human["sha256"],
                        "raw_file": f"raw/{filename}", "source_run_id": None,
                        "oracle_use": "evaluation/listening target and diagnostic performed-span target only; never conditioning"})

        candidates = [item for item in plan["items"] if item["target"] == target and
                      (item["renderer_id"] in {"qwen3", "chatterbox"} or item["kind"] == "closed_external_benchmark")]
        order = {"qwen3": 0, "chatterbox": 1, None: 2}
        candidates.sort(key=lambda item: (order[item["renderer_id"]], item["identity"]))
        for item in candidates:
            label = short_label(item["identity"], target)
            original_name = f"{counter:02d}_{label}_ORIGINAL.wav"; counter += 1
            raw_original = raw_root / original_name
            convert(Path(item["source_path"]), raw_original)
            entry = {"pair_id": item["identity"], "variant": "original", "identity": item["identity"],
                     "kind": item["kind"], "renderer_id": item["renderer_id"],
                     "source_run_id": item["source_run_id"], "source_result_path": item["source_result_path"],
                     "source_path": item["source_path"], "source_sha256": item["source_sha256"],
                     "raw_file": f"raw/{original_name}", "repair_status": item["status"],
                     "repair_exclusion_reason": item["exclusion_reason"]}
            entries.append(entry)
            if item["identity"] in repair_by_identity:
                repaired = repair_by_identity[item["identity"]]
                repaired_name = f"{counter:02d}_{label}_TIMING_REPAIRED.wav"; counter += 1
                raw_repaired = raw_root / repaired_name
                convert(Path(repaired["repaired_path"]), raw_repaired)
                entries.append({"pair_id": item["identity"], "variant": "timing_repaired",
                                "identity": item["identity"], "kind": item["kind"],
                                "renderer_id": item["renderer_id"], "source_run_id": item["source_run_id"],
                                "source_result_path": item["source_result_path"],
                                "source_path": repaired["repaired_path"], "source_sha256": repaired["repaired_sha256"],
                                "raw_file": f"raw/{repaired_name}", "repair_status": "eligible_repaired",
                                "oracle_target_source": "oracle_target_performed_span",
                                "time_scale": repaired["time_scale"],
                                "duration_error_milliseconds": repaired["duration_error_milliseconds"]})

        levels = []
        for entry in entries:
            measurement = detailed_measure(target_root / entry["raw_file"])
            entry["raw_active_rms_dbfs"] = measurement["level"]["active_rms_dbfs"]
            levels.append(entry["raw_active_rms_dbfs"])
        target_level = min(levels)
        for entry in entries:
            source = target_root / entry["raw_file"]
            destination = matched_root / source.name
            audio, sample_rate = sf.read(source, dtype="float32")
            gain_db = target_level - entry["raw_active_rms_dbfs"]
            sf.write(destination, np.asarray(audio * (10 ** (gain_db / 20)), dtype=np.float32),
                     sample_rate, subtype="PCM_16", format="WAV")
            entry["level_matched_file"] = f"level_matched/{source.name}"
            entry["applied_gain_db"] = gain_db
        manifest = {
            "schema_version": 1, "milestone": "RB-007", "target": target,
            "identified": True, "blind": False, "subjective_ratings": False,
            "scientific_question": "Does correcting overall timing alone materially improve perceived performance?",
            "raw_policy": "48 kHz mono PCM-16; resampling/channel conversion only; original levels retained",
            "level_match_policy": "gain-only attenuation to quietest active-speech RMS; no normalization of authority, limiting, compression, EQ, denoise, or enhancement",
            "pair_order_policy": "original immediately followed by timing repair where eligible",
            "oracle_warning": "withheld human target span is diagnostic evaluation information, never renderer conditioning",
            "level_match_target_active_rms_dbfs": target_level, "entries": entries,
        }
        write_json(target_root / "manifest.json", manifest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
