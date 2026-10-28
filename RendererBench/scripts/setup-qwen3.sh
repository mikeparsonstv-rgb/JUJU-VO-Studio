#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKER_PROJECT="$PROJECT_ROOT/Workers/Qwen3"
ENV_DIR="${QWEN3_ENV_DIR:-$PROJECT_ROOT/.renderer-envs/qwen3}"
MODEL_HOME="${QWEN3_MODEL_HOME:-$PROJECT_ROOT/.renderer-models/qwen3}"
MODEL_ID="Qwen/Qwen3-TTS-12Hz-0.6B-Base"
MODEL_REVISION="5d83992436eae1d760afd27aff78a71d676296fc"

if ! command -v uv >/dev/null 2>&1; then
  echo "error: uv is required (https://docs.astral.sh/uv/)" >&2
  exit 1
fi

mkdir -p "$ENV_DIR" "$MODEL_HOME"
UV_PROJECT_ENVIRONMENT="$ENV_DIR" uv sync --project "$WORKER_PROJECT" --locked --python 3.12

HF_HOME="$MODEL_HOME" "$ENV_DIR/bin/hf" download "$MODEL_ID" --revision "$MODEL_REVISION"

echo "Qwen3 RB-002 environment ready."
echo "Python: $ENV_DIR/bin/python"
echo "Model cache: $MODEL_HOME"
echo "Pinned model: $MODEL_ID@$MODEL_REVISION"
