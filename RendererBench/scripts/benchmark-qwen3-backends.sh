#!/bin/bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: scripts/benchmark-qwen3-backends.sh <reference.wav> <reference transcript> <BenchData parent>" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REFERENCE_AUDIO="$1"
REFERENCE_TEXT="$2"
DATA_PARENT="$3"

mkdir -p "$DATA_PARENT"
cd "$PROJECT_ROOT"

swift run qwen-session-bench \
  --backend mps \
  --reference-audio "$REFERENCE_AUDIO" \
  --reference-text "$REFERENCE_TEXT" \
  --definitions "$PROJECT_ROOT/BenchAssets/benchmarks" \
  --data "$DATA_PARENT/mps" \
  --warm-runs 2 2>&1 | tee "$DATA_PARENT/mps-session.log"

swift run qwen-session-bench \
  --backend cpu \
  --reference-audio "$REFERENCE_AUDIO" \
  --reference-text "$REFERENCE_TEXT" \
  --definitions "$PROJECT_ROOT/BenchAssets/benchmarks" \
  --data "$DATA_PARENT/cpu" \
  --warm-runs 2 2>&1 | tee "$DATA_PARENT/cpu-session.log"
