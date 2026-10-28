#!/bin/bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "usage: scripts/smoke-voxcpm2.sh <reference.wav> <reference transcript> <reference asset id> <BenchData path>" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
swift run voxcpm2-session-bench \
  --reference-audio "$1" \
  --reference-text "$2" \
  --reference-asset-id "$3" \
  --definitions "$PROJECT_ROOT/BenchAssets/benchmarks" \
  --data "$4" \
  --warm-runs 1
