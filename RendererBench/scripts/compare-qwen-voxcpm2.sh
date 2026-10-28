#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: scripts/compare-qwen-voxcpm2.sh <reference asset id> <BenchData parent>" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSET_ID="$1"
DATA_PARENT="$2"
LOCAL_MAP="$PROJECT_ROOT/BenchAssets/local-assets.json"
METADATA="$PROJECT_ROOT/BenchAssets/references/$ASSET_ID/metadata.json"

if [[ ! -f "$LOCAL_MAP" ]]; then
  echo "error: create BenchAssets/local-assets.json from local-assets.example.json" >&2
  exit 2
fi
if [[ ! -f "$METADATA" ]]; then
  echo "error: no committed metadata for $ASSET_ID" >&2
  exit 2
fi

REFERENCE_AUDIO="$(jq -er --arg id "$ASSET_ID" '.assets[$id].path' "$LOCAL_MAP")"
REFERENCE_TEXT="$(jq -er '.transcript' "$METADATA")"
if [[ ! -f "$REFERENCE_AUDIO" ]]; then
  echo "error: mapped reference audio does not exist: $REFERENCE_AUDIO" >&2
  exit 2
fi

mkdir -p "$DATA_PARENT"
cd "$PROJECT_ROOT"

swift run qwen-session-bench \
  --backend mps \
  --reference-audio "$REFERENCE_AUDIO" \
  --reference-text "$REFERENCE_TEXT" \
  --reference-asset-id "$ASSET_ID" \
  --definitions "$PROJECT_ROOT/BenchAssets/benchmarks" \
  --data "$DATA_PARENT/qwen3" \
  --warm-runs 1 2>&1 | tee "$DATA_PARENT/qwen3-session.log"

swift run voxcpm2-session-bench \
  --reference-audio "$REFERENCE_AUDIO" \
  --reference-text "$REFERENCE_TEXT" \
  --reference-asset-id "$ASSET_ID" \
  --definitions "$PROJECT_ROOT/BenchAssets/benchmarks" \
  --data "$DATA_PARENT/voxcpm2" \
  --warm-runs 1 2>&1 | tee "$DATA_PARENT/voxcpm2-session.log"
