#!/usr/bin/env python3
"""Model-free RB-006 signal measurements for authoritative and benchmark audio."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any

import librosa
import numpy as np
import soundfile as sf


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value) or "untitled"


def finite(value: float) -> float | None:
    return float(value) if math.isfinite(float(value)) else None


def measure(path: Path, identity: dict[str, Any]) -> dict[str, Any]:
    info = sf.info(str(path))
    multi, sr = sf.read(str(path), always_2d=True, dtype="float32")
    y = np.mean(multi, axis=1)
    duration = len(y) / sr
    peak = float(np.max(np.abs(y))) if y.size else 0.0
    rms = float(np.sqrt(np.mean(np.square(y), dtype=np.float64))) if y.size else 0.0
    peak_dbfs = 20 * math.log10(max(peak, 1e-12))
    rms_dbfs = 20 * math.log10(max(rms, 1e-12))

    intervals = librosa.effects.split(y, top_db=35, frame_length=2048, hop_length=512)
    active_samples = int(sum(end - start for start, end in intervals))
    active_duration = active_samples / sr
    active = np.concatenate([y[start:end] for start, end in intervals]) if active_samples else np.array([], dtype=np.float32)
    active_rms = float(np.sqrt(np.mean(np.square(active), dtype=np.float64))) if active.size else 0.0
    active_rms_dbfs = 20 * math.log10(max(active_rms, 1e-12))

    feature_sr = 16_000
    feature_y = librosa.resample(y, orig_sr=sr, target_sr=feature_sr) if sr != feature_sr else y
    hop = 256
    f0, voiced, voiced_prob = librosa.pyin(feature_y, fmin=60, fmax=400, sr=feature_sr, frame_length=1024, hop_length=hop)
    voiced_f0 = f0[np.isfinite(f0)]
    f0_p10 = float(np.percentile(voiced_f0, 10)) if voiced_f0.size else math.nan
    f0_p90 = float(np.percentile(voiced_f0, 90)) if voiced_f0.size else math.nan
    f0_range_st = 12 * math.log2(f0_p90 / f0_p10) if f0_p10 > 0 and f0_p90 > 0 else math.nan

    centroid = librosa.feature.spectral_centroid(y=feature_y, sr=feature_sr)
    bandwidth = librosa.feature.spectral_bandwidth(y=feature_y, sr=feature_sr)
    rolloff = librosa.feature.spectral_rolloff(y=feature_y, sr=feature_sr, roll_percent=0.85)
    zcr = librosa.feature.zero_crossing_rate(feature_y)
    mfcc = librosa.feature.mfcc(y=feature_y, sr=feature_sr, n_mfcc=13)
    result = {
        "schema_version": 1, **identity, "path": str(path), "sha256": sha256(path),
        "container": info.format, "codec_subtype": info.subtype,
        "sample_rate_hz": int(sr), "channels": int(multi.shape[1]),
        "duration_seconds": duration, "active_speech_seconds": active_duration,
        "silence_pause_proportion": max(0.0, min(1.0, 1 - active_duration / duration)) if duration else 1.0,
        "level": {"peak_dbfs": peak_dbfs, "rms_dbfs": rms_dbfs, "active_rms_dbfs": active_rms_dbfs},
        "pitch": {
            "voiced_fraction": float(np.mean(voiced)) if voiced.size else 0.0,
            "mean_voiced_probability": finite(np.nanmean(voiced_prob)) if voiced_prob.size else 0.0,
            "f0_median_hz": finite(np.median(voiced_f0)) if voiced_f0.size else None,
            "f0_p10_hz": finite(f0_p10), "f0_p90_hz": finite(f0_p90),
            "f0_robust_range_semitones": finite(f0_range_st),
        },
        "spectral": {
            "centroid_mean_hz": float(np.mean(centroid)), "centroid_std_hz": float(np.std(centroid)),
            "bandwidth_mean_hz": float(np.mean(bandwidth)), "bandwidth_std_hz": float(np.std(bandwidth)),
            "rolloff85_mean_hz": float(np.mean(rolloff)), "zero_crossing_rate_mean": float(np.mean(zcr)),
        },
        "mfcc": {"mean": [float(v) for v in np.mean(mfcc, axis=1)], "std": [float(v) for v in np.std(mfcc, axis=1)]},
        "feature_preprocessing": "mono mix; resampled to 16 kHz for F0/spectral/MFCC only; level/duration measured at source rate",
        "interpretation_warning": "Signal descriptors are not a speaker-identity or accent score.",
    }
    return result


def sources(root: Path, local: dict[str, str]) -> list[tuple[Path, dict[str, Any]]]:
    items: list[tuple[Path, dict[str, Any]]] = []
    for asset_id in ["BHM01_human_reference", "BHM02_human_reference"]:
        items.append((Path(local[asset_id]), {"kind": "human_ground_truth", "asset_id": asset_id}))
    for asset_id in [key for key in local if "elevenlabs" in key.lower()]:
        items.append((Path(local[asset_id]), {"kind": "closed_external_benchmark", "asset_id": asset_id,
                                                "conditioning_parity": "unknown"}))
    for session_path in sorted((root / "authoritative/metadata").glob("*-session.json")):
        session = json.loads(session_path.read_text())
        for record in session["renders"]:
            items.append((Path(record["output_audio"]), {
                "kind": "open_renderer_generated", "renderer_id": record["renderer_id"],
                "direction_id": record["direction_id"], "iteration": record["iteration"],
                "run_id": record["run_id"], "ground_truth_asset_id": record["ground_truth_asset_id"],
            }))
    return items


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--local-assets", required=True, type=Path)
    args = parser.parse_args()
    local = json.loads(args.local_assets.read_text())
    output = args.root / "measurements/signal"
    output.mkdir(parents=True, exist_ok=True)
    measurements = []
    for index, (path, identity) in enumerate(sources(args.root, local), 1):
        print(f"[{index}] measuring {identity.get('asset_id') or identity.get('run_id')}: {path}", flush=True)
        value = measure(path, identity)
        name = identity.get("asset_id") or f"{identity['renderer_id']}_{identity['direction_id']}_run{identity['iteration']}"
        (output / f"{safe(str(name))}.json").write_text(json.dumps(value, indent=2) + "\n")
        measurements.append(value)

    variations: dict[str, Any] = {}
    generated = [item for item in measurements if item["kind"] == "open_renderer_generated"]
    for renderer in sorted({item["renderer_id"] for item in generated}):
        for direction in ["BHM-XH-01", "BHM-XH-02"]:
            group = [item for item in generated if item["renderer_id"] == renderer and item["direction_id"] == direction]
            key = f"{renderer}:{direction}"
            variations[key] = {"run_count": len(group)}
            for label, getter in {
                "duration_seconds": lambda x: x["duration_seconds"],
                "active_speech_seconds": lambda x: x["active_speech_seconds"],
                "silence_pause_proportion": lambda x: x["silence_pause_proportion"],
                "active_rms_dbfs": lambda x: x["level"]["active_rms_dbfs"],
                "f0_median_hz": lambda x: x["pitch"]["f0_median_hz"],
                "spectral_centroid_hz": lambda x: x["spectral"]["centroid_mean_hz"],
            }.items():
                values = np.array([getter(item) for item in group if getter(item) is not None], dtype=float)
                variations[key][label] = {"mean": finite(np.mean(values)) if values.size else None,
                                           "std": finite(np.std(values)) if values.size else None,
                                           "min": finite(np.min(values)) if values.size else None,
                                           "max": finite(np.max(values)) if values.size else None}
            mfcc_vectors = [np.array(item["mfcc"]["mean"]) for item in group]
            distances = [float(np.linalg.norm(mfcc_vectors[i] - mfcc_vectors[j]))
                         for i in range(len(mfcc_vectors)) for j in range(i + 1, len(mfcc_vectors))]
            variations[key]["pairwise_mfcc_mean_distance"] = finite(np.mean(distances)) if distances else None

    summary = {
        "schema_version": 1, "measurement_count": len(measurements), "measurements": measurements,
        "run_to_run_variation": variations,
        "speaker_similarity": {"state": "unavailable", "reason": "No speaker-verifier model passed an RB-006 licence/provenance gate."},
        "accent_score": {"state": "unavailable", "reason": "Accent fidelity requires identified human listening; no synthetic Birmingham score is valid."},
    }
    (args.root / "measurements/signal-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
