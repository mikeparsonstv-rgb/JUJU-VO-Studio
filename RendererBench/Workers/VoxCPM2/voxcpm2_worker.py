#!/usr/bin/env python3
"""Persistent VoxCPM2 BF16 MLX JSON-lines worker. Protocol output is stdout-only."""

from __future__ import annotations

import contextlib
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
MODEL_ID = "mlx-community/VoxCPM2-bf16"
MODEL_REVISION = "a7fb80d9056983135a54ca3f71fcc5a637ccddf5"
UPSTREAM_MODEL_ID = "openbmb/VoxCPM2"
UPSTREAM_MODEL_REVISION = "bffb3df5a29440629464e5e839f4d214c8714c3d"
RUNTIME_ID = "mlx-audio"
RUNTIME_REVISION = "d28d68c6ac4e28f7d2d66007f640b06cf3fd8ceb"
STARTED = time.monotonic()
SESSION_ID = str(uuid.uuid4())
STATE = "starting"
WORKER_STARTUP_SECONDS = 0.0
PYTHON_IMPORT_SECONDS = 0.0
MESSAGE_COUNT = 0
RENDER_COUNT = 0
MODEL: Any | None = None
MODEL_SNAPSHOT: Path | None = None
MX: Any | None = None
METAL_AVAILABLE = False
ACTUAL_BACKEND = "unknown"


def package_version(name: str) -> str:
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return "not-installed"


def versions() -> dict[str, str]:
    return {
        "mlx-audio": package_version("mlx-audio"),
        "mlx": package_version("mlx"),
        "mlx-lm": package_version("mlx-lm"),
        "transformers": package_version("transformers"),
        "huggingface-hub": package_version("huggingface-hub"),
        "miniaudio": package_version("miniaudio"),
    }


def peak_memory_bytes() -> int:
    if MX is None:
        return 0
    try:
        return int(MX.get_peak_memory())
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
        "upstream_model_id": UPSTREAM_MODEL_ID,
        "upstream_model_revision": UPSTREAM_MODEL_REVISION,
        "runtime_id": RUNTIME_ID,
        "runtime_revision": RUNTIME_REVISION,
        "package_versions": versions(),
        "python_version": platform.python_version(),
        "os_version": platform.platform(),
        "machine_architecture": platform.machine(),
        "actual_backend": ACTUAL_BACKEND,
        "metal_available": METAL_AVAILABLE,
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
    }


def validate_identity(request: dict[str, Any]) -> None:
    if request.get("protocol_version") != PROTOCOL_VERSION:
        raise ValueError("Unsupported worker protocol version")
    if request.get("model_id") != MODEL_ID or request.get("model_revision") != MODEL_REVISION:
        raise ValueError("Worker accepts only the pinned RB-004 BF16 MLX conversion")
    if request.get("upstream_model_id") != UPSTREAM_MODEL_ID or request.get("upstream_model_revision") != UPSTREAM_MODEL_REVISION:
        raise ValueError("Worker accepts only the pinned RB-004 upstream model lineage")


def inspect_environment(response: dict[str, Any]) -> bool:
    global MX, MODEL_SNAPSHOT, PYTHON_IMPORT_SECONDS, METAL_AVAILABLE, ACTUAL_BACKEND
    try:
        if MX is None:
            started = time.monotonic()
            import mlx.core as mx
            MX = mx
            PYTHON_IMPORT_SECONDS += time.monotonic() - started
        started = time.monotonic()
        from huggingface_hub import snapshot_download
        import mlx_audio
        PYTHON_IMPORT_SECONDS += time.monotonic() - started

        device_description = str(MX.default_device()).lower()
        METAL_AVAILABLE = "gpu" in device_description
        ACTUAL_BACKEND = "mlx-metal" if METAL_AVAILABLE else f"mlx-{device_description}"
        MODEL_SNAPSHOT = Path(snapshot_download(
            repo_id=MODEL_ID, revision=MODEL_REVISION, local_files_only=True
        ))
        required = [
            MODEL_SNAPSHOT / "config.json",
            MODEL_SNAPSHOT / "model-00001.safetensors",
            MODEL_SNAPSHOT / "model-00002.safetensors",
            MODEL_SNAPSHOT / "model.safetensors.index.json",
            MODEL_SNAPSHOT / "tokenizer.json",
        ]
        available = all(path.is_file() for path in required)
        ready = available and METAL_AVAILABLE and package_version("mlx-audio") == "0.4.6"
        response["model_available"] = available
        response["render_attemptable"] = ready
        if not ready:
            response["error"] = "Pinned BF16 model, mlx-audio 0.4.6, or MLX Metal execution is unavailable"
        return ready
    except Exception as error:
        response["error"] = f"Environment unavailable: {type(error).__name__}: {error}"
        return False
    finally:
        response["python_import_seconds"] = PYTHON_IMPORT_SECONDS
        response["metal_available"] = METAL_AVAILABLE
        response["actual_backend"] = ACTUAL_BACKEND


def load_model(response: dict[str, Any]) -> bool:
    global MODEL, STATE, PYTHON_IMPORT_SECONDS
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
        from mlx_audio.tts.utils import load
        PYTHON_IMPORT_SECONDS += time.monotonic() - started
        load_started = time.monotonic()
        MODEL = load(MODEL_SNAPSHOT, lazy=False, strict=True)
        response.update(
            success=True, error=None, model_reused=False,
            model_load_seconds=time.monotonic() - load_started,
            python_import_seconds=PYTHON_IMPORT_SECONDS,
            render_attemptable=True,
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
        response.update(model_available=True, render_attemptable=True, model_reused=True)
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
        "inference_timesteps": 10,
        "cfg_value": 2.0,
        "warmup_patches": 0,
        "max_tokens": 2000,
        "min_tokens": 2,
        "streaming_prefix_len": 4,
    }
    metadata = {"reference_asset_id"}
    unknown = set(raw) - set(defaults) - metadata
    if unknown:
        raise ValueError(f"Unsupported VoxCPM2 generation settings: {sorted(unknown)}")
    settings = defaults | {key: value for key, value in raw.items() if key in defaults}
    if int(settings["inference_timesteps"]) < 1:
        raise ValueError("inference_timesteps must be positive")
    if float(settings["cfg_value"]) < 2.0:
        raise ValueError("cfg_value must be at least 2.0 in the pinned MLX implementation")
    return settings


def render(request: dict[str, Any]) -> dict[str, Any]:
    global STATE, RENDER_COUNT
    response = base_response(str(request.get("request_id", "unknown")))
    try:
        validate_identity(request)
        had_model = MODEL is not None
        if not load_model(response):
            raise RuntimeError(response["error"] or "VoxCPM2 model is unavailable")
        text = str(request.get("text") or "").strip()
        reference_text = str(request.get("reference_text") or "").strip()
        reference = Path(str(request.get("reference_audio") or ""))
        output = Path(str(request.get("output_audio") or ""))
        if not text:
            raise ValueError("text is required")
        if not reference_text:
            raise ValueError("reference_text is required for RB-004 continuation cloning")
        if not reference.is_absolute() or not reference.is_file():
            raise ValueError("reference_audio must be an existing absolute file")
        if not output.is_absolute() or not output.parent.is_dir():
            raise ValueError("output_audio must be an absolute path in an existing bench directory")
        settings = generation_settings(request.get("settings") or {})
        if request.get("seed") is not None:
            response["warnings"].append("Seed was supplied but is not applied; deterministic capability is false")
        from mlx_audio.audio_io import write as audio_write

        response.update(model_reused=had_model, cold_start=RENDER_COUNT == 0,
                        render_index=RENDER_COUNT,
                        clone_mode="continuation_prompt_audio_transcript",
                        actual_settings=settings)
        STATE = "rendering"
        generation_started = time.monotonic()
        generation_text = text if reference_text.endswith((" ", "\n", "\t")) else " " + text
        result = next(MODEL.generate(
            text=generation_text,
            prompt_text=reference_text,
            prompt_audio=str(reference),
            **settings,
        ))
        response["generation_seconds"] = time.monotonic() - generation_started
        samples = int(result.samples)
        sample_rate = int(result.sample_rate)
        if samples <= 0 or sample_rate <= 0:
            raise RuntimeError("VoxCPM2 returned no audio samples")
        audio_write(str(output), result.audio, sample_rate, format="wav")
        response.update(success=True, error=None, output_audio=str(output),
                        sample_rate=sample_rate,
                        duration_seconds=float(samples / sample_rate))
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
    response["actual_backend"] = ACTUAL_BACKEND
    response["metal_available"] = METAL_AVAILABLE
    response["worker_reused"] = MESSAGE_COUNT > 1
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
