#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKER_PROJECT="$PROJECT_ROOT/Workers/VoxCPM2"
ENV_DIR="${VOXCPM2_ENV_DIR:-$PROJECT_ROOT/.renderer-envs/voxcpm2}"
MODEL_HOME="${VOXCPM2_MODEL_HOME:-$PROJECT_ROOT/.renderer-models/voxcpm2}"
MODEL_ID="mlx-community/VoxCPM2-bf16"
MODEL_REVISION="a7fb80d9056983135a54ca3f71fcc5a637ccddf5"

if ! command -v uv >/dev/null 2>&1; then
  echo "error: uv is required (https://docs.astral.sh/uv/)" >&2
  exit 1
fi

echo "Preparing isolated VoxCPM2 MLX environment at $ENV_DIR"
echo "Downloading only the pinned BF16 conversion $MODEL_ID@$MODEL_REVISION into $MODEL_HOME"
mkdir -p "$ENV_DIR" "$MODEL_HOME"
UV_PROJECT_ENVIRONMENT="$ENV_DIR" uv sync --project "$WORKER_PROJECT" --locked --python 3.12
HF_HOME="$MODEL_HOME" "$ENV_DIR/bin/hf" download "$MODEL_ID" --revision "$MODEL_REVISION"

echo "VoxCPM2 RB-004 environment ready."
echo "Python: $ENV_DIR/bin/python"
echo "Model cache: $MODEL_HOME"
echo "Pinned model: $MODEL_ID@$MODEL_REVISION"
