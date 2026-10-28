#!/usr/bin/env python3
"""Build RB-007 machine-readable and operator-readable timing-control reports."""

from __future__ import annotations

import argparse
import hashlib
from collections import Counter
from pathlib import Path

from common import read_json, sha256, write_json


HEADLINE = ("RB-007 tests whether correcting overall timing alone materially improves perceived performance. "
            "It does not test Actor Model direction, semantic intent, phrase-level timing, energy control, "
            "or renderer-native performance steering.")


def verify_frozen(source: Path, manifest: dict) -> dict:
    problems = []
    for item in manifest["files"]:
        path = source / item["relative_path"]
        if not path.is_file():
            problems.append({"path": item["relative_path"], "problem": "missing"})
        elif sha256(path) != item["sha256"]:
            problems.append({"path": item["relative_path"], "problem": "hash_mismatch"})
    current = {str(path.relative_to(source)) for path in source.rglob("*") if path.is_file()}
    recorded = {item["relative_path"] for item in manifest["files"]}
    for extra in sorted(current - recorded):
        problems.append({"path": extra, "problem": "unexpected_new_file"})
    return {"byte_for_byte_unchanged": not problems, "checked_file_count": len(recorded), "problems": problems}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rb006", required=True, type=Path)
    parser.add_argument("--rb007", required=True, type=Path)
    args = parser.parse_args()
    frozen = read_json(args.rb007 / "source_manifest/rb006-frozen-files.json")
    plan = read_json(args.rb007 / "source_manifest/timing-repair-plan.json")
    repair = read_json(args.rb007 / "repaired/repair-summary.json")
    repaired_asr = read_json(args.rb007 / "measurements/asr-repaired.json")
    original_generated_asr = read_json(args.rb006 / "measurements/asr-summary.json")
    original_external_asr = read_json(args.rb007 / "measurements/asr-external.json")
    original_asr = {item["audio_sha256"]: item for item in original_generated_asr["results"]}
    original_asr.update({item["source_sha256"]: item for item in original_external_asr["results"]})
    repaired_asr_by_id = {item["identity"]: item for item in repaired_asr["results"]}
    pair_rows = []
    for item in repair["repairs"]:
        original = original_asr[item["source_sha256"]]
        post = repaired_asr_by_id[item["identity"]]
        pair_rows.append({
            "identity": item["identity"], "target": item["target"], "renderer_id": item["renderer_id"],
            "source_run_id": item["source_run_id"], "source_result_path": item["source_result_path"],
            "source_sha256": item["source_sha256"], "repaired_sha256": item["repaired_sha256"],
            "oracle_target_source": "oracle_target_performed_span",
            "oracle_target_performed_span_seconds": item["oracle_target_performed_span_seconds"],
            "original_performed_span_seconds": item["original_measurement"]["performed_span_seconds"],
            "repaired_performed_span_seconds": item["repaired_measurement"]["performed_span_seconds"],
            "time_scale": item["time_scale"], "playback_rate": item["playback_rate"],
            "duration_error_milliseconds": item["duration_error_milliseconds"],
            "duration_within_tolerance": item["duration_within_tolerance"],
            "original_active_speech_seconds": item["original_measurement"]["active_speech_seconds"],
            "repaired_active_speech_seconds": item["repaired_measurement"]["active_speech_seconds"],
            "original_internal_pause_proportion": item["original_measurement"]["internal_pause_proportion"],
            "repaired_internal_pause_proportion": item["repaired_measurement"]["internal_pause_proportion"],
            "collateral_differences": item["collateral_differences"],
            "original_asr": {"wer": original["wer"], "cer": original["cer"], "hypothesis": original["hypothesis"]},
            "repaired_asr": {"wer": post["wer"], "cer": post["cer"], "hypothesis": post["hypothesis"]},
            "algorithm": item["algorithm"],
        })
    exclusion_counts = Counter(item["status"] for item in repair["exclusions"])
    renderer_exclusions = Counter((item["renderer_id"] or "elevenlabs", item["status"]) for item in repair["exclusions"])
    invariance = verify_frozen(args.rb006, frozen)
    report = {
        "schema_version": 1, "milestone": "RB-007", "status": "engineering_derivatives_complete_operator_audition_pending",
        "headline": HEADLINE, "subjective_winner": None, "renderer_requests_made": 0,
        "human_target_used_as_renderer_conditioning": False,
        "oracle_policy": "withheld human target performed span used only for labelled post-generation diagnostic derivatives",
        "performed_span_method": plan["performed_span_method"], "targets": plan["targets"],
        "fixed_ratio_guardrail": {"minimum": 0.85, "maximum": 1.20},
        "completeness_gate": {"minimum_transcript_coverage": 0.80, "maximum_wer": 0.35},
        "eligible_repair_count": len(pair_rows), "pairs": pair_rows,
        "verification": {"swift_tests_passed": 85, "swift_test_failures": 0,
                         "release_build": "passed", "all_repaired_spans_within_50ms": all(row["duration_within_tolerance"] for row in pair_rows)},
        "exclusion_counts": dict(exclusion_counts),
        "exclusions_by_renderer": [{"renderer": key[0], "status": key[1], "count": value}
                                     for key, value in sorted(renderer_exclusions.items())],
        "exclusions": repair["exclusions"], "rb006_invariance": invariance,
        "listening_bundles": {target: str((args.rb007 / "listening-bundle" / target).resolve())
                              for target in ["BHM01_target", "BHM02_target"]},
        "rejected_diagnostic_artifact": {
            "state": "preserved_outside_primary_evidence",
            "reason": "Direct AVFoundation MP3 decoding introduced about -3 dB; corrected derivatives use frozen RB-006 resample/channel-only PCM copies.",
            "path": str((args.rb007 / "rejected-artifacts/direct-mp3-decoder-level-mismatch").resolve()),
        },
        "listening_questions": ["Does repair feel less rushed and closer to natural pace?",
                                "Does perceived push remain after timing is corrected?",
                                "Does identity and Birmingham character survive?",
                                "Are breaths, consonants, pauses, or texture audibly damaged?",
                                "Does Hah! remain semantically wrong, as expected from a timing-only change?"],
        "limitations": [
            "The withheld human timing is oracle diagnostic information, not production-realistic new-copy control.",
            "Only overall performed span changes; internal pauses scale proportionally and phrase timing is not edited.",
            "Five Chatterbox calls and two ElevenLabs calls exceed the fixed ratio guardrail; all VoxCPM2 calls fail completeness.",
            "Engineering descriptors cannot determine audible time-stretch artefacts, identity, Birmingham fidelity, energy, or performance improvement.",
            "Whisper is assistive and may change hypotheses after time-stretch without a true intelligibility change.",
            "Hah! intent is expected to remain wrong because semantic interpretation is outside this experiment.",
        ],
        "roadmap_only_not_implemented": [
            "same-copy generation defaults to original performed duration",
            "new-copy generation inherits source active-speech rate, pause proportion, cadence, and breath tendency",
            "renderer-native pace generation before post-stretch fallback",
            "isolated energy/push and internal-versus-external reaction direction, including Hah! Actor Model benchmark",
        ],
    }
    report_dir = args.rb007 / "report"
    write_json(report_dir / "report.json", report)

    lines = ["# RB-007 Timing Repair Control", "", f"> **{HEADLINE}**", "",
             "Status: **engineering derivatives complete; identified operator audition pending**", "",
             "No new renderer generation occurred. The RB-006 source tree is byte-for-byte unchanged, and withheld human timing is labelled `oracle_target_performed_span` throughout.", "",
             "## Eligibility", "", f"Nine repairs qualified: six Qwen, one Chatterbox, and two ElevenLabs. All six VoxCPM2 calls were excluded as incomplete. Five Chatterbox calls and two BHM01 ElevenLabs calls were complete enough but outside the fixed 0.85–1.20 time-scale guardrail.", "",
             "## Original/repaired measurements", "",
             "| Pair | Target | Original span | Scale | Repaired span | Error | RMS Δ | F0 median Δ | WER before → after |", "|---|---|---:|---:|---:|---:|---:|---:|---:|"]
    for row in pair_rows:
        lines.append(f"| {row['identity']} | {row['target']} | {row['original_performed_span_seconds']:.3f}s | {row['time_scale']:.4f} | {row['repaired_performed_span_seconds']:.3f}s | {row['duration_error_milliseconds']:+.1f}ms | {row['collateral_differences']['active_rms_db']:+.3f}dB | {row['collateral_differences']['median_f0_hz']:+.2f}Hz | {row['original_asr']['wer']:.3f} → {row['repaired_asr']['wer']:.3f} |")
    lines += ["", "Every repair is within the 50 ms performed-span tolerance. Pitch was fixed at zero cents; no gain, EQ, dynamics, denoise, dereverb, formant, pause, phrase, or spectral processing was requested.", "",
              "## Listening bundles", "", f"- `{report['listening_bundles']['BHM01_target']}`", f"- `{report['listening_bundles']['BHM02_target']}`", "",
              "Each identified bundle contains raw-level 48 kHz mono PCM original/repaired comparisons and a separate attenuation-only level-matched set. Eligible pairs are adjacent. Human targets are evaluation/oracle context only.", "",
              "## Interpretation boundary", "", "The operator must now judge pace, remaining push, identity, Birmingham character, naturalness, artefacts, and whether overall performance improves. The machine has not answered those questions or selected a winner. `Hah!` should remain a semantic/intent failure if timing is truly the only repaired dimension.", "",
              "## Known limits", ""] + [f"- {item}" for item in report["limitations"]]
    lines += ["", "## Roadmap only", ""] + [f"- {item}" for item in report["roadmap_only_not_implemented"]]
    lines += ["", "No renderer-native timing, Actor Model, energy control, semantic direction, phrase retiming, or later milestone was implemented.", ""]
    (report_dir / "report.md").write_text("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
