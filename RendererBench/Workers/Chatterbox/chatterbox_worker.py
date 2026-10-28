#!/usr/bin/env python3
"""Persistent Chatterbox Multilingual V3 PyTorch MPS JSON-lines worker."""

from __future__ import annotations

import contextlib
import hashlib
import importlib.metadata
import json
import os
import platform
import sys
import time
import traceback
import uuid
from pathlib import Path
from typing import Any

PROTOCOL_VERSION = 1
SOURCE_REVISION = "5de7a54aa4e5e2baadb0182dde554908b48b85c2"
MODEL_ID = "ResembleAI/chatterbox"
MODEL_REVISION = "5bb1f6ee58e50c3b8d408bc82a6d3740c2db6e18"
VARIANT = "Multilingual V3"
T3_MODEL = "v3"
T3_FILENAME = "t3_mtl23ls_v3.safetensors"
RUNTIME_ID = "chatterbox-tts"
RUNTIME_REVISION = SOURCE_REVISION
PERTH_REVISION = "ce86c49d029f42272c1902eccb675556b9ed2330"
REQUESTED_BACKEND = os.environ.get("CHATTERBOX_DEVICE", "mps").lower()
PKUSEG_HOME = Path(os.environ.get("PKUSEG_HOME", "")).expanduser()
PKUSEG_ARCHIVE_SHA256 = "b216e7f92de7ae285aeab8feba2faa8ea8216e5995ff6fb3d391cc8356db1bfe"
STARTED = time.monotonic()
SESSION_ID = str(uuid.uuid4())
STATE = "starting"
WORKER_STARTUP_SECONDS = 0.0
PYTHON_IMPORT_SECONDS = 0.0
MESSAGE_COUNT = 0
RENDER_COUNT = 0
MODEL: Any | None = None
MODEL_SNAPSHOT: Path | None = None
TORCH: Any | None = None
MPS_AVAILABLE = False
MPS_BUILT = False
ACTUAL_BACKEND = "unknown"
WATERMARK_ENABLED = False


def package_version(name: str) -> str:
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return "not-installed"


def versions() -> dict[str, str]:
    return {
        "chatterbox-tts": package_version("chatterbox-tts"),
        "resemble-perth": package_version("resemble-perth"),
        "torch": package_version("torch"),
        "torchaudio": package_version("torchaudio"),
        "transformers": package_version("transformers"),
        "s3tokenizer": package_version("s3tokenizer"),
        "huggingface-hub": package_version("huggingface-hub"),
        "safetensors": package_version("safetensors"),
        "librosa": package_version("librosa"),
        "soundfile": package_version("soundfile"),
        "spacy-pkuseg": package_version("spacy-pkuseg"),
    }


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def peak_memory_bytes() -> int:
    if TORCH is None or not MPS_AVAILABLE:
        return 0
    try:
        return int(TORCH.mps.current_allocated_memory())
    except Exception:
        return 0


def base_response(request_id: str) -> dict[str, Any]:
    return {
        "protocol_version": PROTOCOL_VERSION,
        "request_id": request_id,
        "success": False,
        "error": None,
        "output_audio": None,
        "sample_rate": None,
        "duration_seconds": None,
        "model_id": MODEL_ID,
        "model_revision": MODEL_REVISION,
        "source_revision": SOURCE_REVISION,
        "variant": VARIANT,
        "t3_model": T3_MODEL,
        "t3_filename": T3_FILENAME,
        "runtime_id": RUNTIME_ID,
        "runtime_revision": RUNTIME_REVISION,
        "package_versions": versions(),
        "python_version": platform.python_version(),
        "os_version": platform.platform(),
        "machine_architecture": platform.machine(),
        "requested_backend": REQUESTED_BACKEND,
        "actual_backend": ACTUAL_BACKEND,
        "mps_available": MPS_AVAILABLE,
        "mps_built": MPS_BUILT,
        "worker_startup_seconds": WORKER_STARTUP_SECONDS,
        "python_import_seconds": PYTHON_IMPORT_SECONDS,
        "model_load_seconds": None,
        "generation_seconds": None,
        "peak_resident_memory_bytes": peak_memory_bytes(),
        "model_available": MODEL_SNAPSHOT is not None,
        "render_attemptable": MODEL is not None,
        "warnings": [],
        "worker_state": STATE,
        "worker_session_id": SESSION_ID,
        "worker_reused": MESSAGE_COUNT > 1,
        "model_reused": None,
        "cold_start": None,
        "render_index": None,
        "clone_mode": None,
        "actual_settings": {},
        "watermark_expected": True,
        "watermark_enabled": WATERMARK_ENABLED,
        "watermark_system": "PerTh implicit",
        "watermark_version": package_version("resemble-perth"),
        "reference_transcript_used": False,
    }


def validate_identity(request: dict[str, Any]) -> None:
    if request.get("protocol_version") != PROTOCOL_VERSION:
        raise ValueError("Unsupported worker protocol version")
    if request.get("model_id") != MODEL_ID or request.get("model_revision") != MODEL_REVISION:
        raise ValueError("Worker accepts only the pinned official Chatterbox model snapshot")
    if request.get("source_revision") != SOURCE_REVISION:
        raise ValueError("Worker accepts only the pinned RB-005 Chatterbox source revision")
    if request.get("variant") != VARIANT or request.get("t3_model") != T3_MODEL:
        raise ValueError("Worker requires Chatterbox Multilingual V3; V2/Turbo/Nano are forbidden")
    if request.get("requested_backend") != "mps" or REQUESTED_BACKEND != "mps":
        raise ValueError("RB-005 requires the official PyTorch MPS path")


def inspect_environment(response: dict[str, Any]) -> bool:
    global TORCH, MODEL_SNAPSHOT, PYTHON_IMPORT_SECONDS, MPS_AVAILABLE, MPS_BUILT, ACTUAL_BACKEND
    try:
        if TORCH is None:
            started = time.monotonic()
            import torch
            TORCH = torch
            PYTHON_IMPORT_SECONDS += time.monotonic() - started
        started = time.monotonic()
        from huggingface_hub import snapshot_download
        from chatterbox.mtl_tts import ChatterboxMultilingualTTS, _resolve_multilingual_t3_model
        import perth
        PYTHON_IMPORT_SECONDS += time.monotonic() - started
        del ChatterboxMultilingualTTS, perth

        MPS_BUILT = bool(TORCH.backends.mps.is_built())
        MPS_AVAILABLE = bool(TORCH.backends.mps.is_available())
        ACTUAL_BACKEND = "mps" if MPS_AVAILABLE else "unavailable"
        resolved = _resolve_multilingual_t3_model(T3_MODEL)
        if resolved != T3_FILENAME:
            raise RuntimeError(f"V3 resolver selected unexpected checkpoint {resolved}")
        MODEL_SNAPSHOT = Path(snapshot_download(
            repo_id=MODEL_ID,
            revision=MODEL_REVISION,
            local_files_only=True,
            allow_patterns=[
                "ve.pt", T3_FILENAME, "s3gen.pt",
                "grapheme_mtl_merged_expanded_v1.json", "conds.pt", "Cangjie5_TC.json",
            ],
        ))
        required = [
            MODEL_SNAPSHOT / "ve.pt",
            MODEL_SNAPSHOT / T3_FILENAME,
            MODEL_SNAPSHOT / "s3gen.pt",
            MODEL_SNAPSHOT / "grapheme_mtl_merged_expanded_v1.json",
            MODEL_SNAPSHOT / "conds.pt",
            MODEL_SNAPSHOT / "Cangjie5_TC.json",
        ]
        pkuseg_archive = PKUSEG_HOME / "spacy_ontonotes.zip"
        pkuseg_files = [
            PKUSEG_HOME / "spacy_ontonotes/features.msgpack",
            PKUSEG_HOME / "spacy_ontonotes/weights.npz",
        ]
        pkuseg_available = (
            pkuseg_archive.is_file()
            and file_sha256(pkuseg_archive) == PKUSEG_ARCHIVE_SHA256
            and all(path.is_file() for path in pkuseg_files)
        )
        available = all(path.is_file() for path in required) and pkuseg_available
        packages_exact = (
            package_version("chatterbox-tts") == "0.1.7"
            and package_version("resemble-perth") == "1.0.1"
            and package_version("torch") == "2.6.0"
            and package_version("torchaudio") == "2.6.0"
        )
        ready = available and packages_exact and MPS_BUILT and MPS_AVAILABLE
        response["model_available"] = available
        response["render_attemptable"] = ready
        if not ready:
            response["error"] = "Pinned V3 assets/runtime or official PyTorch MPS execution is unavailable"
        return ready
    except Exception as error:
        response["error"] = f"Environment unavailable: {type(error).__name__}: {error}"
        return False
    finally:
        response["python_import_seconds"] = PYTHON_IMPORT_SECONDS
        response["mps_available"] = MPS_AVAILABLE
        response["mps_built"] = MPS_BUILT
        response["actual_backend"] = ACTUAL_BACKEND


def load_model(response: dict[str, Any]) -> bool:
    global MODEL, STATE, PYTHON_IMPORT_SECONDS, WATERMARK_ENABLED
    if MODEL is not None:
        response.update(success=True, error=None, model_reused=True,
                        model_load_seconds=0.0, render_attemptable=True)
        STATE = "ready_loaded"
        return True
    STATE = "loading"
    response["worker_state"] = STATE
    if not inspect_environment(response):
        STATE = "failed"
        return False
    try:
        started = time.monotonic()
        from chatterbox.mtl_tts import ChatterboxMultilingualTTS
        PYTHON_IMPORT_SECONDS += time.monotonic() - started
        load_started = time.monotonic()
        MODEL = ChatterboxMultilingualTTS.from_local(
            MODEL_SNAPSHOT, device="mps", t3_model=T3_MODEL
        )
        if str(MODEL.device) != "mps":
            raise RuntimeError(f"Official loader did not retain MPS device: {MODEL.device}")
        if getattr(MODEL, "watermarker", None) is None:
            raise RuntimeError("PerTh watermarker was not instantiated")
        WATERMARK_ENABLED = True
        response.update(
            success=True, error=None, model_reused=False,
            model_load_seconds=time.monotonic() - load_started,
            python_import_seconds=PYTHON_IMPORT_SECONDS,
            render_attemptable=True, watermark_enabled=True,
            sample_rate=int(MODEL.sr), actual_backend="mps",
        )
        STATE = "ready_loaded"
        return True
    except Exception as error:
        response["error"] = f"Model load failed: {type(error).__name__}: {error}"
        traceback.print_exc(file=sys.stderr)
        STATE = "failed"
        return False


def health(request: dict[str, Any]) -> dict[str, Any]:
    response = base_response(str(request.get("request_id", "unknown")))
    validate_identity(request)
    response["success"] = True
    if MODEL is not None:
        response.update(model_available=True, render_attemptable=True, model_reused=True,
                        watermark_enabled=WATERMARK_ENABLED)
    else:
        inspect_environment(response)
    return response


def load_operation(request: dict[str, Any]) -> dict[str, Any]:
    response = base_response(str(request.get("request_id", "unknown")))
    validate_identity(request)
    load_model(response)
    return response


def generation_settings(raw: dict[str, Any]) -> dict[str, Any]:
    defaults: dict[str, Any] = {
        "exaggeration": 0.5,
        "cfg_weight": 0.5,
        "temperature": 0.8,
        "repetition_penalty": 1.2,
        "min_p": 0.05,
        "top_p": 1.0,
    }
    metadata = {"reference_asset_id"}
    forbidden = {"t3_model", "variant", "model_variant", "watermark_enabled"}
    if forbidden.intersection(raw):
        raise ValueError("V3 identity and PerTh watermarking cannot be overridden")
    unknown = set(raw) - set(defaults) - metadata
    if unknown:
        raise ValueError(f"Unsupported Chatterbox generation settings: {sorted(unknown)}")
    settings = defaults | {key: value for key, value in raw.items() if key in defaults}
    if float(settings["exaggeration"]) < 0:
        raise ValueError("exaggeration must be non-negative")
    if float(settings["cfg_weight"]) < 0:
        raise ValueError("cfg_weight must be non-negative")
    if float(settings["temperature"]) <= 0:
        raise ValueError("temperature must be positive")
    return settings


def map_language(raw: Any) -> str:
    language = str(raw or "").strip().lower().replace("_", "-")
    if not language:
        raise ValueError("language_id is required")
    return language.split("-", 1)[0]


def render(request: dict[str, Any]) -> dict[str, Any]:
    global STATE, RENDER_COUNT
    response = base_response(str(request.get("request_id", "unknown")))
    try:
        validate_identity(request)
        had_model = MODEL is not None
        if not load_model(response):
            raise RuntimeError(response["error"] or "Chatterbox V3 model is unavailable")
        text = str(request.get("text") or "").strip()
        language_id = map_language(request.get("language_id"))
        reference = Path(str(request.get("reference_audio") or ""))
        output = Path(str(request.get("output_audio") or ""))
        if not text:
            raise ValueError("text is required")
        if not reference.is_absolute() or not reference.is_file():
            raise ValueError("reference_audio must be an existing absolute file")
        if not output.is_absolute() or not output.parent.is_dir():
            raise ValueError("output_audio must be an absolute path in an existing bench directory")
        settings = generation_settings(request.get("settings") or {})
        if request.get("seed") is not None:
            response["warnings"].append("Seed was supplied but is not applied; deterministic capability is false")

        response.update(model_reused=had_model, cold_start=RENDER_COUNT == 0,
                        render_index=RENDER_COUNT, clone_mode="zero_shot_reference_audio",
                        actual_settings=settings, reference_transcript_used=False,
                        watermark_expected=True, watermark_enabled=True,
                        watermark_system="PerTh implicit")
        STATE = "rendering"
        generation_started = time.monotonic()
        result = MODEL.generate(
            text=text,
            language_id=language_id,
            audio_prompt_path=str(reference),
            **settings,
        )
        response["generation_seconds"] = time.monotonic() - generation_started
        audio = result.squeeze().detach().cpu().numpy()
        samples = int(audio.shape[-1])
        sample_rate = int(MODEL.sr)
        if samples <= 0 or sample_rate <= 0:
            raise RuntimeError("Chatterbox returned no audio samples")
        import soundfile as sf
        sf.write(str(output), audio, sample_rate, subtype="PCM_16", format="WAV")
        response.update(success=True, error=None, output_audio=str(output),
                        sample_rate=sample_rate,
                        duration_seconds=float(samples / sample_rate),
                        actual_backend="mps")
        RENDER_COUNT += 1
        STATE = "ready_loaded"
    except Exception as error:
        response["success"] = False
        response["error"] = f"{type(error).__name__}: {error}"
        traceback.print_exc(file=sys.stderr)
        STATE = "failed"
    return response


def shutdown(request: dict[str, Any]) -> dict[str, Any]:
    global STATE
    validate_identity(request)
    STATE = "shutting_down"
    response = base_response(str(request.get("request_id", "unknown")))
    response.update(success=True, error=None)
    STATE = "stopped"
    response["worker_state"] = STATE
    return response


def handle(request: dict[str, Any]) -> dict[str, Any]:
    operation = request.get("operation")
    if operation == "health": return health(request)
    if operation == "load": return load_operation(request)
    if operation == "render": return render(request)
    if operation == "shutdown": return shutdown(request)
    raise ValueError(f"Unsupported operation: {operation}")


def emit(response: dict[str, Any]) -> None:
    response["worker_state"] = STATE
    response["worker_startup_seconds"] = WORKER_STARTUP_SECONDS
    response["python_import_seconds"] = PYTHON_IMPORT_SECONDS
    response["peak_resident_memory_bytes"] = peak_memory_bytes()
    response["requested_backend"] = REQUESTED_BACKEND
    response["actual_backend"] = ACTUAL_BACKEND
    response["mps_available"] = MPS_AVAILABLE
    response["mps_built"] = MPS_BUILT
    response["worker_reused"] = MESSAGE_COUNT > 1
    response["watermark_enabled"] = WATERMARK_ENABLED
    sys.stdout.write(json.dumps(response, sort_keys=True, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main() -> int:
    global STATE, MESSAGE_COUNT, WORKER_STARTUP_SECONDS
    STATE = "ready_unloaded"
    WORKER_STARTUP_SECONDS = time.monotonic() - STARTED
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return 0
        MESSAGE_COUNT += 1
        request: dict[str, Any] = {}
        try:
            request = json.loads(line)
            with contextlib.redirect_stdout(sys.stderr):
                response = handle(request)
        except Exception as error:
            traceback.print_exc(file=sys.stderr)
            STATE = "failed"
            response = base_response(str(request.get("request_id", "unknown")))
            response["error"] = f"Worker protocol failure: {type(error).__name__}: {error}"
        emit(response)
        if request.get("operation") == "shutdown" or STATE == "failed":
            return 0 if response.get("success") else 1


if __name__ == "__main__":
    raise SystemExit(main())
