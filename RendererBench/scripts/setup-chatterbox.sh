#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKER_PROJECT="$PROJECT_ROOT/Workers/Chatterbox"
ENV_DIR="${CHATTERBOX_ENV_DIR:-$PROJECT_ROOT/.renderer-envs/chatterbox}"
MODEL_HOME="${CHATTERBOX_MODEL_HOME:-$PROJECT_ROOT/.renderer-models/chatterbox}"
UV_CACHE_DIR="${CHATTERBOX_UV_CACHE_DIR:-$PROJECT_ROOT/.renderer-envs/.uv-cache}"
MODEL_ID="ResembleAI/chatterbox"
MODEL_REVISION="5bb1f6ee58e50c3b8d408bc82a6d3740c2db6e18"

if ! command -v uv >/dev/null 2>&1; then
  echo "error: uv is required (https://docs.astral.sh/uv/)" >&2
  exit 1
fi

echo "Preparing isolated Chatterbox Multilingual V3 environment at $ENV_DIR"
echo "Installing exact source and PerTh revisions from the locked environment"
echo "Downloading only exact V3-path assets from $MODEL_ID@$MODEL_REVISION into $MODEL_HOME"
mkdir -p "$ENV_DIR" "$MODEL_HOME" "$UV_CACHE_DIR"
UV_CACHE_DIR="$UV_CACHE_DIR" UV_PROJECT_ENVIRONMENT="$ENV_DIR" uv sync --project "$WORKER_PROJECT" --locked --python 3.12
HF_HOME="$MODEL_HOME" "$ENV_DIR/bin/hf" download "$MODEL_ID" \
  ve.pt \
  t3_mtl23ls_v3.safetensors \
  s3gen.pt \
  grapheme_mtl_merged_expanded_v1.json \
  conds.pt \
  Cangjie5_TC.json \
  --revision "$MODEL_REVISION"
PKUSEG_HOME="$MODEL_HOME/pkuseg" "$ENV_DIR/bin/python" -c \
  'import spacy_pkuseg; spacy_pkuseg.pkuseg(model_name="spacy_ontonotes")'

echo "Chatterbox RB-005 environment ready."
echo "Python: $ENV_DIR/bin/python"
echo "Model cache: $MODEL_HOME"
echo "Tokenizer cache: $MODEL_HOME/pkuseg"
echo "Pinned model: $MODEL_ID@$MODEL_REVISION"
echo "Required variant: Chatterbox Multilingual V3 / t3_mtl23ls_v3.safetensors"
