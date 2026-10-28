#!/usr/bin/env python3
"""Shared RB-007 measurement and provenance helpers."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from typing import Any

import librosa
import numpy as np
import soundfile as sf

SPAN_METHOD = {
    "name": "librosa.effects.split",
    "version": "rb007_performed_span_v1",
    "top_db": 35,
    "frame_length": 2048,
    "hop_length": 512,
    "definition": "last meaningful speech offset minus first meaningful speech onset; internal pauses retained",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def words(text: str) -> list[str]:
    import re
    return re.findall(r"[a-z0-9]+(?:'[a-z0-9]+)?", text.lower())


def edit_distance(a: list[str], b: list[str]) -> int:
    previous = list(range(len(b) + 1))
    for index, left in enumerate(a, 1):
        current = [index]
        for column, right in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[column] + 1,
                               previous[column - 1] + (left != right)))
        previous = current
    return previous[-1]


def performed_span(path: Path) -> dict[str, Any]:
    audio, sample_rate = sf.read(path, always_2d=True, dtype="float32")
    mono = np.mean(audio, axis=1)
    intervals = librosa.effects.split(mono, top_db=SPAN_METHOD["top_db"],
                                      frame_length=SPAN_METHOD["frame_length"],
                                      hop_length=SPAN_METHOD["hop_length"])
    if not len(intervals):
        raise ValueError(f"No meaningful speech interval detected: {path}")
    onset = int(intervals[0][0])
    offset = int(intervals[-1][1])
    active_samples = int(sum(end - start for start, end in intervals))
    span_samples = offset - onset
    active_seconds = active_samples / sample_rate
    span_seconds = span_samples / sample_rate
    internal_pause = max(0.0, span_seconds - active_seconds)
    return {
        "source_file_duration_seconds": len(mono) / sample_rate,
        "performed_span_seconds": span_seconds,
        "active_speech_seconds": active_seconds,
        "internal_pause_seconds": internal_pause,
        "internal_pause_proportion": internal_pause / span_seconds if span_seconds else 0.0,
        "first_speech_onset_seconds": onset / sample_rate,
        "last_speech_offset_seconds": offset / sample_rate,
        "sample_rate_hz": int(sample_rate),
        "method": SPAN_METHOD,
    }


def finite(value: float) -> float | None:
    return float(value) if math.isfinite(float(value)) else None


def detailed_measure(path: Path) -> dict[str, Any]:
    audio, sample_rate = sf.read(path, always_2d=True, dtype="float32")
    mono = np.mean(audio, axis=1)
    span = performed_span(path)
    intervals = librosa.effects.split(mono, top_db=35, frame_length=2048, hop_length=512)
    active = np.concatenate([mono[start:end] for start, end in intervals])
    peak = float(np.max(np.abs(mono)))
    rms = float(np.sqrt(np.mean(np.square(mono), dtype=np.float64)))
    active_rms = float(np.sqrt(np.mean(np.square(active), dtype=np.float64)))
    feature = librosa.resample(mono, orig_sr=sample_rate, target_sr=16_000) if sample_rate != 16_000 else mono
    f0, voiced, _ = librosa.pyin(feature, fmin=60, fmax=400, sr=16_000,
                                 frame_length=1024, hop_length=256)
    voiced_f0 = f0[np.isfinite(f0)]
    p10 = float(np.percentile(voiced_f0, 10)) if voiced_f0.size else math.nan
    p90 = float(np.percentile(voiced_f0, 90)) if voiced_f0.size else math.nan
    centroid = librosa.feature.spectral_centroid(y=feature, sr=16_000)
    mfcc = librosa.feature.mfcc(y=feature, sr=16_000, n_mfcc=13)
    return {
        **span, "path": str(path), "sha256": sha256(path),
        "channels": int(audio.shape[1]),
        "level": {
            "peak_dbfs": 20 * math.log10(max(peak, 1e-12)),
            "rms_dbfs": 20 * math.log10(max(rms, 1e-12)),
            "active_rms_dbfs": 20 * math.log10(max(active_rms, 1e-12)),
        },
        "pitch": {
            "f0_median_hz": finite(np.median(voiced_f0)) if voiced_f0.size else None,
            "f0_p10_hz": finite(p10), "f0_p90_hz": finite(p90),
            "f0_robust_range_semitones": finite(12 * math.log2(p90 / p10)) if p10 > 0 and p90 > 0 else None,
            "voiced_fraction": float(np.mean(voiced)) if voiced.size else 0.0,
        },
        "spectral": {"centroid_mean_hz": float(np.mean(centroid)), "centroid_std_hz": float(np.std(centroid))},
        "mfcc": {"mean": [float(value) for value in np.mean(mfcc, axis=1)]},
        "interpretation_warning": "Descriptors verify collateral movement; they are not identity, accent, or quality scores.",
    }


def read_json(path: Path) -> Any:
    return json.loads(path.read_text())


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
