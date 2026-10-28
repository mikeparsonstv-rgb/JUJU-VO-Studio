#!/usr/bin/env python3
"""Build machine-readable and human-readable RB-006 qualification reports."""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path

import numpy as np


def stats(values: list[float]) -> dict:
    return {"mean": statistics.mean(values), "min": min(values), "max": max(values),
            "std": statistics.pstdev(values)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    args = parser.parse_args()
    signal = json.loads((args.root / "measurements/signal-summary.json").read_text())
    asr = json.loads((args.root / "measurements/asr-summary.json").read_text())
    manifest = json.loads(args.manifest.read_text())
    gate = json.loads((args.root / "transcript-gate/gate.json").read_text())
    transcript_authority = {}
    for transcript in manifest["transcripts"]:
        transcript_path = Path(transcript["path"])
        if not transcript_path.is_absolute():
            transcript_path = Path.cwd() / transcript_path
        transcript_authority[transcript["id"]] = {
            "sha256": transcript["sha256"],
            "status": transcript["status"],
            "exact_text": transcript_path.read_text().strip(),
        }
    sessions = {path.stem.removesuffix("-session"): json.loads(path.read_text())
                for path in (args.root / "authoritative/metadata").glob("*-session.json")}

    human = {item["asset_id"]: item for item in signal["measurements"] if item["kind"] == "human_ground_truth"}
    h1, h2 = human["BHM01_human_reference"], human["BHM02_human_reference"]
    human_context = {
        "BHM01": h1, "BHM02": h2,
        "absolute_differences": {
            "duration_seconds": abs(h1["duration_seconds"] - h2["duration_seconds"]),
            "active_speech_seconds": abs(h1["active_speech_seconds"] - h2["active_speech_seconds"]),
            "silence_pause_proportion": abs(h1["silence_pause_proportion"] - h2["silence_pause_proportion"]),
            "f0_median_hz": abs(h1["pitch"]["f0_median_hz"] - h2["pitch"]["f0_median_hz"]),
            "f0_range_semitones": abs(h1["pitch"]["f0_robust_range_semitones"] - h2["pitch"]["f0_robust_range_semitones"]),
            "spectral_centroid_hz": abs(h1["spectral"]["centroid_mean_hz"] - h2["spectral"]["centroid_mean_hz"]),
            "mfcc_mean_euclidean_distance": float(np.linalg.norm(np.array(h1["mfcc"]["mean"]) - np.array(h2["mfcc"]["mean"]))),
        },
        "interpretation": "Same-speaker performance context, not an absolute mathematical ceiling or identity score."
    }

    comparison = {}
    for renderer, session in sessions.items():
        first_result = json.loads(Path(session["renders"][0]["result_json"]).read_text())
        comparison[renderer] = {
            "renderer_identity": {
                "renderer_id": first_result["rendererID"],
                "renderer_version": first_result["rendererVersion"],
                "model_checkpoint": first_result["modelCheckpoint"],
                "descriptor_snapshot": first_result["descriptorSnapshot"],
            },
            "native_baseline_settings": first_result["settingsSnapshot"],
            "load_environment": session["load_environment"],
            "directions": {},
        }
        for direction in ["BHM-XH-01", "BHM-XH-02"]:
            records = [record for record in session["renders"] if record["direction_id"] == direction]
            generation = []
            for record in records:
                result = json.loads(Path(record["result_json"]).read_text())
                generation.append(float(result["environmentSnapshot"]["generation_seconds"]))
            variation = signal["run_to_run_variation"][f"{renderer}:{direction}"]
            comparison[renderer]["directions"][direction] = {
                "runs": records, "run_ids": [record["run_id"] for record in records],
                "generation_seconds": stats(generation),
                "adapter_total_seconds": stats([record["render_time_seconds"] for record in records]),
                "output_duration_seconds": stats([record["duration_seconds"] for record in records]),
                "realtime_factor": stats([record["realtime_factor"] for record in records]),
                "signal_summary": variation, "asr_summary": asr["groups"][f"{renderer}:{direction}"],
            }

    eleven = [{"asset_id": asset["id"], "sha256": asset["sha256"],
               "role": "closed external benchmark", "conditioning_parity": "unknown"}
              for asset in manifest["assets"] if asset["external_benchmark"]]
    report = {
        "schema_version": 1, "milestone": "RB-006", "qualification_id": manifest["qualification_id"],
        "status": "complete_untuned_baseline", "subjective_winner": None,
        "accent_score": {"state": "unavailable", "reason": "No validated automated Birmingham-accent metric was authorized."},
        "transcript_gate": gate, "transcript_authority": transcript_authority, "manifest": manifest,
        "renderer_comparison": comparison, "human_vs_human_context": human_context,
        "signal_measurements": "../measurements/signal-summary.json",
        "asr": {"state": "available", "evaluator": asr["evaluator"], "summary": asr["groups"],
                "raw_results": "../measurements/asr-summary.json"},
        "speaker_similarity": signal["speaker_similarity"],
        "elevenlabs": {"policy": "operator-supplied closed benchmark; API not integrated; never used for conditioning or tuning; conditioning parity unknown",
                       "assets": eleven},
        "audition": {"raw": "../audition_raw_pcm", "level_matched": "../audition_level_matched",
                     "identified_bundles": "../listening-bundle"},
        "limitations": [
            "No subjective listening, identity judgement, or accent score was produced by the machine.",
            "Whisper WER/CER is assistive and can itself make recognition errors, especially on regional delivery and brand terms.",
            "No speaker-verifier passed a separate licence/provenance gate, so embedding similarity is unavailable.",
            "VoxCPM2 produced severe untuned truncation in this long-form cross-holdout; files are preserved rather than rerun or selected.",
            "Qwen's established fixed seed produced repeatable calls; this measures baseline repeatability rather than stochastic diversity.",
            "Chatterbox generation latency varied substantially and PerTh watermarking remained enabled.",
            "ElevenLabs conditioning provenance/parity is unknown and its files are market context, not a controlled renderer comparison.",
            "Signal descriptors are separate observations and must not be collapsed into speaker identity or a winner score."
        ],
    }
    report_dir = args.root / "report"; report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "report.json").write_text(json.dumps(report, indent=2) + "\n")

    lines = [
        "# RB-006 Birmingham Cross-Holdout Untuned Baseline", "", "Status: **complete engineering evidence; identified human listening pending**", "",
        "No subjective winner or automated Birmingham-accent score is claimed.", "", "## Compact comparison", "",
        "| Renderer | Direction | Output duration mean (range) | Generation mean (range) | RTF mean | WER mean | F0 median mean | Pause proportion mean |",
        "|---|---|---:|---:|---:|---:|---:|---:|",
    ]
    display = {"qwen3": "Qwen3-TTS", "voxcpm2": "VoxCPM2", "chatterbox": "Chatterbox V3"}
    for renderer in ["qwen3", "voxcpm2", "chatterbox"]:
        for direction in ["BHM-XH-01", "BHM-XH-02"]:
            value = comparison[renderer]["directions"][direction]
            duration, generation = value["output_duration_seconds"], value["generation_seconds"]
            f0 = value["signal_summary"]["f0_median_hz"]["mean"]
            pause = value["signal_summary"]["silence_pause_proportion"]["mean"]
            lines.append(f"| {display[renderer]} | {direction} | {duration['mean']:.2f}s ({duration['min']:.2f}–{duration['max']:.2f}) | {generation['mean']:.2f}s ({generation['min']:.2f}–{generation['max']:.2f}) | {value['realtime_factor']['mean']:.2f} | {value['asr_summary']['wer_mean']:.3f} | {f0:.1f} Hz | {pause:.3f} |")
    lines += ["", "## Run IDs", ""]
    for renderer in ["qwen3", "voxcpm2", "chatterbox"]:
        for direction in ["BHM-XH-01", "BHM-XH-02"]:
            ids = ", ".join(f"`{value}`" for value in comparison[renderer]["directions"][direction]["run_ids"])
            lines.append(f"- {display[renderer]} {direction}: {ids}")
    diffs = human_context["absolute_differences"]
    lines += [
        "", "## Human-vs-human context", "",
        f"BHM01 is {h1['duration_seconds']:.2f}s with {h1['active_speech_seconds']:.2f}s active speech; BHM02 is {h2['duration_seconds']:.2f}s with {h2['active_speech_seconds']:.2f}s active speech. Pause proportions are {h1['silence_pause_proportion']:.3f} and {h2['silence_pause_proportion']:.3f}; median F0 values are {h1['pitch']['f0_median_hz']:.1f} and {h2['pitch']['f0_median_hz']:.1f} Hz. MFCC mean-vector distance is {diffs['mfcc_mean_euclidean_distance']:.2f}. These are natural same-speaker/performance differences, not an identity ceiling.",
        "", "## Objective observations", "",
        "- Qwen produced byte/feature-identical output within each fixed-seed direction and low assistive ASR error.",
        "- Chatterbox produced complete-looking durations and low assistive ASR error, with meaningful acoustic and latency variation across calls.",
        "- VoxCPM2 terminated early on every long-form candidate in this baseline, most severely at 0.8 seconds in two BHM-XH-01 runs; WER and duration expose this without a subjective score.",
        "- Speaker-verifier similarity and automated accent scoring are explicitly unavailable.",
        "", "## Audition and ElevenLabs", "",
        "Identified raw and gain-only level-matched bundles are under `../listening-bundle/BHM01_target` and `../listening-bundle/BHM02_target`. ElevenLabs files are untouched operator-supplied closed benchmarks. Their conditioning parity is unknown; they were never used for conditioning or tuning.",
        "", "## Limitations", "",
    ] + [f"- {item}" for item in report["limitations"]]
    lines += ["", "RB-007 was not begun.", ""]
    (report_dir / "report.md").write_text("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
