#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: scripts/smoke-chatterbox.sh <reference asset id> <BenchData path>" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSET_ID="$1"
DATA_PATH="$2"
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

cd "$PROJECT_ROOT"
swift run chatterbox-session-bench \
  --reference-audio "$REFERENCE_AUDIO" \
  --reference-text "$REFERENCE_TEXT" \
  --reference-asset-id "$ASSET_ID" \
  --definitions "$PROJECT_ROOT/BenchAssets/benchmarks" \
  --data "$DATA_PATH" \
  --warm-runs 1
