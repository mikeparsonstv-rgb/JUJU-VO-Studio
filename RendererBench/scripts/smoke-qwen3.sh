#!/bin/bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: scripts/smoke-qwen3.sh <reference.wav> <reference transcript> <BenchData path> [auto|mps|cpu]" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REFERENCE_AUDIO="$1"
REFERENCE_TEXT="$2"
DATA_ROOT="$3"
BACKEND="${4:-auto}"

cd "$PROJECT_ROOT"
swift run qwen-session-bench \
  --backend "$BACKEND" \
  --reference-audio "$REFERENCE_AUDIO" \
  --reference-text "$REFERENCE_TEXT" \
  --definitions "$PROJECT_ROOT/BenchAssets/benchmarks" \
  --data "$DATA_ROOT" \
  --warm-runs 1
