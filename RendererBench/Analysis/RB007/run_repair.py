#!/usr/bin/env python3
"""Plan and execute guarded RB-007 oracle performed-span timing derivatives."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any

import numpy as np

from common import detailed_measure, performed_span, read_json, sha256, write_json


def safe_label(item: dict[str, Any]) -> str:
    if item["kind"] == "closed_external_benchmark":
        return item["asset_id"].replace("_elevenlabs_", "_ELEVENLABS_")
    names = {"qwen3": "QWEN", "voxcpm2": "VOXCPM", "chatterbox": "CHATTERBOX"}
    target = "BHM02" if item["direction_id"] == "BHM-XH-01" else "BHM01"
    return f"{target}_{names[item['renderer_id']]}_run{item['iteration']}"


def freeze_manifest(source: Path, destination: Path) -> dict[str, Any]:
    files = []
    for path in sorted(item for item in source.rglob("*") if item.is_file()):
        files.append({"relative_path": str(path.relative_to(source)), "sha256": sha256(path), "bytes": path.stat().st_size})
    canonical = "".join(f"{item['sha256']}  {item['relative_path']}\n" for item in files).encode()
    value = {"schema_version": 1, "source_milestone": "RB-006", "frozen": True,
             "source_root": str(source.resolve()), "file_count": len(files),
             "canonical_manifest_sha256": hashlib.sha256(canonical).hexdigest(), "files": files}
    write_json(destination, value)
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rb006", required=True, type=Path)
    parser.add_argument("--rb007", required=True, type=Path)
    parser.add_argument("--processor", required=True, type=Path)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    if (args.rb007 / "repaired/repair-summary.json").exists() and not args.resume:
        raise SystemExit("refusing to overwrite existing RB-007 repair evidence")
    frozen = freeze_manifest(args.rb006, args.rb007 / "source_manifest/rb006-frozen-files.json")
    signal = read_json(args.rb006 / "measurements/signal-summary.json")
    rb006_asr = read_json(args.rb006 / "measurements/asr-summary.json")
    external_asr = read_json(args.rb007 / "measurements/asr-external.json")
    generated_asr = {(item["run_id"]): item for item in rb006_asr["results"]}
    market_asr = {item["identity"]: item for item in external_asr["results"]}
    sessions = [read_json(path) for path in sorted((args.rb006 / "authoritative/metadata").glob("*-session.json"))]
    result_paths = {record["run_id"]: record["result_json"] for session in sessions for record in session["renders"]}
    humans = {item["asset_id"]: item for item in signal["measurements"] if item["kind"] == "human_ground_truth"}
    human_spans = {asset: performed_span(Path(item["path"])) for asset, item in humans.items()}
    targets = {
        "BHM01_target": {"asset_id": "BHM01_human_reference", "measurement": human_spans["BHM01_human_reference"]},
        "BHM02_target": {"asset_id": "BHM02_human_reference", "measurement": human_spans["BHM02_human_reference"]},
    }
    candidates = [item for item in signal["measurements"]
                  if item["kind"] in {"open_renderer_generated", "closed_external_benchmark"}]
    plan_items = []
    for item in candidates:
        if item["kind"] == "open_renderer_generated":
            target = "BHM02_target" if item["direction_id"] == "BHM-XH-01" else "BHM01_target"
            asr = generated_asr[item["run_id"]]
            coverage = min(1.0, asr["hypothesis_word_count"] / max(1, asr["reference_word_count"]))
            source_result_path = result_paths[item["run_id"]]
            source_run_id = item["run_id"]
        else:
            target = "BHM01_target" if item["asset_id"].startswith("BHM01") else "BHM02_target"
            asr = market_asr[item["asset_id"]]
            coverage = asr["transcript_coverage"]
            source_result_path = None
            source_run_id = None
        if item["kind"] == "closed_external_benchmark":
            generation = "gen1" if item["asset_id"].endswith("gen1") else "gen2"
            processing_input = args.rb006 / "audition_raw_pcm" / target / f"ELEVENLABS_{generation}.wav"
        else:
            processing_input = Path(item["path"])
        original_span = performed_span(Path(item["path"]))
        processing_span = performed_span(processing_input)
        oracle = targets[target]["measurement"]["performed_span_seconds"]
        time_scale = oracle / processing_span["performed_span_seconds"]
        complete = coverage >= 0.80 and asr["wer"] <= 0.35
        if not complete:
            status, reason = "ineligible_for_timing_repair", "ASR completeness gate failed (coverage < 0.80 or WER > 0.35)"
        elif not 0.85 <= time_scale <= 1.20:
            status, reason = "timing_repair_out_of_range", "time_scale outside fixed 0.85...1.20 guardrail"
        else:
            status, reason = "eligible", None
        plan_items.append({
            "identity": safe_label(item), "kind": item["kind"], "target": target,
            "renderer_id": item.get("renderer_id"), "direction_id": item.get("direction_id"),
            "iteration": item.get("iteration"), "source_run_id": source_run_id,
            "source_result_path": source_result_path, "source_path": item["path"],
            "source_sha256": item["sha256"], "source_measurement": original_span,
            "processing_input_path": str(processing_input.resolve()),
            "processing_input_sha256": sha256(processing_input), "processing_input_measurement": processing_span,
            "processing_input_policy": "exact RB-006 source for WAV; RB-006 48 kHz mono resample/channel-only audition copy for MP3 to avoid decoder gain change",
            "oracle_target_source": "oracle_target_performed_span",
            "oracle_target_human_asset_id": targets[target]["asset_id"],
            "oracle_target_performed_span_seconds": oracle,
            "transcript_coverage": coverage, "wer": asr["wer"], "cer": asr["cer"],
            "completeness_thresholds": {"minimum_transcript_coverage": 0.80, "maximum_wer": 0.35},
            "time_scale": time_scale, "playback_rate": 1 / time_scale,
            "ratio_guardrail": {"minimum": 0.85, "maximum": 1.20},
            "status": status, "exclusion_reason": reason,
        })
    plan = {"schema_version": 1, "milestone": "RB-007", "experiment": "timing_repair_control",
            "target_information_policy": "diagnostic oracle only; never renderer conditioning",
            "rb006_frozen_manifest_sha256": frozen["canonical_manifest_sha256"],
            "performed_span_method": human_spans["BHM01_human_reference"]["method"],
            "targets": targets, "items": plan_items}
    write_json(args.rb007 / "source_manifest/timing-repair-plan.json", plan)

    repairs = []
    for item in plan_items:
        if item["status"] != "eligible":
            continue
        output = args.rb007 / "repaired" / item["target"] / f"{item['identity']}_TIMING_REPAIRED.wav"
        metadata_path = output.with_suffix(".json")
        if output.exists() and metadata_path.exists():
            repairs.append(read_json(metadata_path))
            continue
        command = [str(args.processor.resolve()), "--input", item["processing_input_path"], "--output", str(output.resolve()),
                   "--onset", str(item["processing_input_measurement"]["first_speech_onset_seconds"]),
                   "--offset", str(item["processing_input_measurement"]["last_speech_offset_seconds"]),
                   "--target-span", str(item["oracle_target_performed_span_seconds"])]
        print(f"repairing {item['identity']} scale={item['time_scale']:.6f}", flush=True)
        completed = subprocess.run(command, check=True, capture_output=True, text=True)
        backend = json.loads(completed.stdout)
        original_measurement = detailed_measure(Path(item["source_path"]))
        repaired_measurement = detailed_measure(output)
        error_seconds = repaired_measurement["performed_span_seconds"] - item["oracle_target_performed_span_seconds"]
        mfcc_distance = float(np.linalg.norm(np.array(original_measurement["mfcc"]["mean"]) -
                                             np.array(repaired_measurement["mfcc"]["mean"])))
        record = {
            **item, "repaired_path": str(output.resolve()), "repaired_sha256": sha256(output),
            "algorithm": backend, "original_measurement": original_measurement,
            "repaired_measurement": repaired_measurement,
            "duration_error_milliseconds": error_seconds * 1000,
            "duration_error_percent": 100 * error_seconds / item["oracle_target_performed_span_seconds"],
            "duration_tolerance_milliseconds": 50,
            "duration_within_tolerance": abs(error_seconds) <= 0.050,
            "collateral_differences": {
                "active_rms_db": repaired_measurement["level"]["active_rms_dbfs"] - original_measurement["level"]["active_rms_dbfs"],
                "median_f0_hz": (repaired_measurement["pitch"]["f0_median_hz"] or 0) - (original_measurement["pitch"]["f0_median_hz"] or 0),
                "f0_range_semitones": (repaired_measurement["pitch"]["f0_robust_range_semitones"] or 0) - (original_measurement["pitch"]["f0_robust_range_semitones"] or 0),
                "spectral_centroid_hz": repaired_measurement["spectral"]["centroid_mean_hz"] - original_measurement["spectral"]["centroid_mean_hz"],
                "mfcc_mean_euclidean_distance": mfcc_distance,
            },
        }
        write_json(metadata_path, record)
        repairs.append(record)
    write_json(args.rb007 / "repaired/repair-summary.json", {
        "schema_version": 1, "milestone": "RB-007", "repairs": repairs,
        "exclusions": [item for item in plan_items if item["status"] != "eligible"],
    })
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
