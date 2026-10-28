#!/usr/bin/env python3
"""Persistent Qwen3-TTS JSON-lines worker. Protocol output is the only stdout content."""

from __future__ import annotations

import contextlib
import importlib.metadata
import json
import os
import platform
import resource
import sys
import time
import traceback
import uuid
from pathlib import Path
from typing import Any

PROTOCOL_VERSION = 1
MODEL_ID = "Qwen/Qwen3-TTS-12Hz-0.6B-Base"
MODEL_REVISION = "5d83992436eae1d760afd27aff78a71d676296fc"
TOKENIZER_ID = "Qwen/Qwen3-TTS-Tokenizer-12Hz"
TOKENIZER_REVISION = "7dd38ad4e9bad454aae9cd937d0cd577604fe229"
STARTED = time.monotonic()
SESSION_ID = str(uuid.uuid4())
STATE = "starting"
MODEL: Any | None = None
TORCH: Any | None = None
MODEL_SNAPSHOT: Path | None = None
ACTUAL_BACKEND = "unknown"
PYTHON_IMPORT_SECONDS = 0.0
WORKER_STARTUP_SECONDS = 0.0
RENDER_COUNT = 0
MESSAGE_COUNT = 0


def package_version(name: str) -> str:
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return "not-installed"


def versions() -> dict[str, str]:
    return {
        "qwen-tts": package_version("qwen-tts"),
        "torch": package_version("torch"),
        "torchaudio": package_version("torchaudio"),
        "transformers": package_version("transformers"),
        "huggingface-hub": package_version("huggingface-hub"),
        "soundfile": package_version("soundfile"),
    }


def requested_backend() -> str:
    return os.environ.get("QWEN3_DEVICE", "auto").lower()


def peak_memory_bytes() -> int:
    peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return int(peak if platform.system() == "Darwin" else peak * 1024)


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
        "tokenizer_id": TOKENIZER_ID,
        "tokenizer_revision": TOKENIZER_REVISION,
        "package_versions": versions(),
        "python_version": platform.python_version(),
        "os_version": platform.platform(),
        "machine_architecture": platform.machine(),
        "device": ACTUAL_BACKEND,
        "worker_startup_seconds": WORKER_STARTUP_SECONDS,
        "dependency_import_seconds": PYTHON_IMPORT_SECONDS,
        "python_import_seconds": PYTHON_IMPORT_SECONDS,
        "model_load_seconds": None,
        "generation_seconds": None,
        "peak_resident_memory_bytes": peak_memory_bytes(),
        "model_available": bool(MODEL_SNAPSHOT),
        "tokenizer_available": False,
        "render_attemptable": MODEL is not None,
        "warnings": [],
        "worker_state": STATE,
        "worker_session_id": SESSION_ID,
        "worker_reused": MESSAGE_COUNT > 1,
        "model_reused": None,
        "cold_start": None,
        "requested_backend": requested_backend(),
        "actual_backend": ACTUAL_BACKEND,
        "render_index": None,
        "reference_prompt_reused": False,
    }


def validate_identity(request: dict[str, Any]) -> None:
    if request.get("protocol_version") != PROTOCOL_VERSION:
        raise ValueError("Unsupported worker protocol version")
    if request.get("model_id") != MODEL_ID or request.get("model_revision") != MODEL_REVISION:
        raise ValueError("Worker accepts only the pinned RB-002 model and revision")
    if request.get("tokenizer_id") != TOKENIZER_ID or request.get("tokenizer_revision") != TOKENIZER_REVISION:
        raise ValueError("Worker accepts only the pinned RB-002 tokenizer identity and revision")
    requested = str(request.get("requested_backend") or "auto").lower()
    configured = requested_backend()
    if requested != configured:
        raise ValueError(f"Request backend '{requested}' does not match worker backend '{configured}'")


def select_device(torch: Any) -> str:
    requested = requested_backend()
    if requested not in {"auto", "mps", "cpu"}:
        raise ValueError("QWEN3_DEVICE must be auto, mps, or cpu")
    if requested == "mps":
        if not torch.backends.mps.is_available():
            raise RuntimeError("MPS was requested but PyTorch reports it unavailable")
        return "mps"
    if requested == "cpu":
        return "cpu"
    return "mps" if torch.backends.mps.is_available() else "cpu"


def inspect_environment(response: dict[str, Any]) -> bool:
    global TORCH, MODEL_SNAPSHOT, ACTUAL_BACKEND, PYTHON_IMPORT_SECONDS
    try:
        if TORCH is None:
            imports_started = time.monotonic()
            import torch
            TORCH = torch
            PYTHON_IMPORT_SECONDS += time.monotonic() - imports_started
        imports_started = time.monotonic()
        from huggingface_hub import snapshot_download
        PYTHON_IMPORT_SECONDS += time.monotonic() - imports_started

        ACTUAL_BACKEND = select_device(TORCH)
        MODEL_SNAPSHOT = Path(snapshot_download(
            repo_id=MODEL_ID, revision=MODEL_REVISION, local_files_only=True
        ))
        response["model_available"] = (MODEL_SNAPSHOT / "model.safetensors").is_file()
        tokenizer_files = [
            MODEL_SNAPSHOT / "speech_tokenizer" / "model.safetensors",
            MODEL_SNAPSHOT / "speech_tokenizer" / "config.json",
        ]
        response["tokenizer_available"] = all(path.is_file() for path in tokenizer_files)
        ready = bool(
            response["package_versions"]["qwen-tts"] != "not-installed"
            and response["model_available"] and response["tokenizer_available"]
        )
        response["render_attemptable"] = ready
        if not ready:
            response["error"] = "Worker dependencies or pinned model/tokenizer assets are incomplete"
        return ready
    except Exception as error:
        response["error"] = f"Environment unavailable: {type(error).__name__}: {error}"
        return False
    finally:
        response["python_import_seconds"] = PYTHON_IMPORT_SECONDS
        response["dependency_import_seconds"] = PYTHON_IMPORT_SECONDS
        response["actual_backend"] = ACTUAL_BACKEND
        response["device"] = ACTUAL_BACKEND


def load_model(response: dict[str, Any]) -> bool:
    global MODEL, STATE, PYTHON_IMPORT_SECONDS
    if MODEL is not None:
        response["success"] = True
        response["model_reused"] = True
        response["model_load_seconds"] = 0.0
        response["render_attemptable"] = True
        STATE = "ready_loaded"
        return True
    STATE = "loading"
    response["worker_state"] = STATE
    if not inspect_environment(response):
        STATE = "failed"
        return False
    try:
        imports_started = time.monotonic()
        from qwen_tts import Qwen3TTSModel
        PYTHON_IMPORT_SECONDS += time.monotonic() - imports_started
        load_started = time.monotonic()
        MODEL = Qwen3TTSModel.from_pretrained(
            str(MODEL_SNAPSHOT), device_map=ACTUAL_BACKEND,
            dtype=TORCH.float32, attn_implementation="sdpa"
        )
        response["model_load_seconds"] = time.monotonic() - load_started
        response["python_import_seconds"] = PYTHON_IMPORT_SECONDS
        response["dependency_import_seconds"] = PYTHON_IMPORT_SECONDS
        response["model_reused"] = False
        response["render_attemptable"] = True
        response["success"] = True
        response["error"] = None
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
    if MODEL is not None:
        response["success"] = True
        response["model_available"] = True
        response["tokenizer_available"] = True
        response["render_attemptable"] = True
        response["model_reused"] = True
    else:
        response["success"] = True
        inspect_environment(response)
    return response


def load(request: dict[str, Any]) -> dict[str, Any]:
    response = base_response(str(request.get("request_id", "unknown")))
    validate_identity(request)
    load_model(response)
    return response


def generation_settings(raw: dict[str, Any]) -> dict[str, Any]:
    allowed = {
        "do_sample", "top_k", "top_p", "temperature", "repetition_penalty",
        "subtalker_dosample", "subtalker_top_k", "subtalker_top_p",
        "subtalker_temperature", "max_new_tokens",
    }
    metadata = {"reference_asset_id", "disable_prompt_cache"}
    unknown = set(raw) - allowed - metadata
    if unknown:
        raise ValueError(f"Unsupported Qwen generation settings: {sorted(unknown)}")
    return {key: value for key, value in raw.items() if key in allowed}


def render(request: dict[str, Any]) -> dict[str, Any]:
    global STATE, RENDER_COUNT
    response = base_response(str(request.get("request_id", "unknown")))
    try:
        validate_identity(request)
        had_model = MODEL is not None
        if not load_model(response):
            raise RuntimeError(response["error"] or "Qwen model is unavailable")
        response["model_reused"] = had_model
        response["cold_start"] = RENDER_COUNT == 0
        response["render_index"] = RENDER_COUNT
        text = str(request.get("text") or "").strip()
        language = str(request.get("language") or "Auto")
        reference = Path(str(request.get("reference_audio") or ""))
        output = Path(str(request.get("output_audio") or ""))
        reference_text = request.get("reference_text")
        if not text:
            raise ValueError("text is required")
        if not reference.is_absolute() or not reference.is_file():
            raise ValueError("reference_audio must be an existing absolute file")
        if not output.is_absolute() or not output.parent.is_dir():
            raise ValueError("output_audio must be an absolute path in an existing bench directory")
        if request.get("seed") is not None:
            TORCH.manual_seed(int(request["seed"]))
        if not reference_text:
            response["warnings"].append(
                "Reference transcript absent; using speaker-embedding-only clone path"
            )
        import soundfile as sf

        STATE = "rendering"
        generation_started = time.monotonic()
        wavs, sample_rate = MODEL.generate_voice_clone(
            text=text,
            language=language,
            ref_audio=str(reference),
            ref_text=reference_text if reference_text else None,
            x_vector_only_mode=not bool(reference_text),
            non_streaming_mode=True,
            **generation_settings(request.get("settings") or {}),
        )
        response["generation_seconds"] = time.monotonic() - generation_started
        if not wavs or len(wavs[0]) == 0 or int(sample_rate) <= 0:
            raise RuntimeError("Qwen returned no audio samples")
        sf.write(str(output), wavs[0], int(sample_rate), subtype="PCM_16", format="WAV")
        response.update(
            success=True,
            error=None,
            output_audio=str(output),
            sample_rate=int(sample_rate),
            duration_seconds=float(len(wavs[0]) / int(sample_rate)),
        )
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
    response["success"] = True
    response["error"] = None
    STATE = "stopped"
    response["worker_state"] = STATE
    return response


def handle(request: dict[str, Any]) -> dict[str, Any]:
    operation = request.get("operation")
    if operation == "health":
        return health(request)
    if operation == "load":
        return load(request)
    if operation == "render":
        return render(request)
    if operation == "shutdown":
        return shutdown(request)
    raise ValueError(f"Unsupported operation: {operation}")


def emit(response: dict[str, Any]) -> None:
    response["worker_state"] = STATE if STATE != "shutting_down" else response.get("worker_state", STATE)
    response["worker_startup_seconds"] = WORKER_STARTUP_SECONDS
    response["python_import_seconds"] = PYTHON_IMPORT_SECONDS
    response["dependency_import_seconds"] = PYTHON_IMPORT_SECONDS
    response["peak_resident_memory_bytes"] = peak_memory_bytes()
    response["actual_backend"] = ACTUAL_BACKEND
    response["device"] = ACTUAL_BACKEND
    response["worker_reused"] = MESSAGE_COUNT > 1
    sys.stdout.write(json.dumps(response, sort_keys=True, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main() -> int:
    global STATE, MESSAGE_COUNT, WORKER_STARTUP_SECONDS
    one_shot = "--one-shot" in sys.argv[1:]
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
        if one_shot or request.get("operation") == "shutdown" or STATE == "failed":
            return 0 if response.get("success") else 1


if __name__ == "__main__":
    raise SystemExit(main())
