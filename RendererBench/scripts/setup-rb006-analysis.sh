#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANALYSIS_PROJECT="$PROJECT_ROOT/Analysis/RB006"
ENV_DIR="${RB006_ANALYSIS_ENV_DIR:-$PROJECT_ROOT/.analysis-envs/rb006}"
MODEL_DIR="${RB006_ANALYSIS_MODEL_DIR:-$PROJECT_ROOT/.analysis-models/rb006/whisper}"
UV_CACHE_DIR="${RB006_ANALYSIS_UV_CACHE_DIR:-$PROJECT_ROOT/.analysis-envs/.uv-cache}"

if ! command -v uv >/dev/null 2>&1; then
  echo "error: uv is required" >&2
  exit 1
fi

mkdir -p "$ENV_DIR" "$MODEL_DIR" "$UV_CACHE_DIR"
UV_CACHE_DIR="$UV_CACHE_DIR" UV_PROJECT_ENVIRONMENT="$ENV_DIR" \
  uv sync --project "$ANALYSIS_PROJECT" --locked --python 3.12

RB006_MODEL_DIR="$MODEL_DIR" "$ENV_DIR/bin/python" -c \
  'import os, whisper; whisper.load_model("turbo", device="cpu", download_root=os.environ["RB006_MODEL_DIR"]); print(whisper._MODELS["turbo"])'

echo "RB-006 analysis environment ready: $ENV_DIR"
echo "Whisper model cache: $MODEL_DIR"
