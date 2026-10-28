#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: scripts/compare-qwen-voxcpm2-chatterbox.sh <reference asset id> <BenchData parent>" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSET_ID="$1"
DATA_PARENT="$2"
LOCAL_MAP="$PROJECT_ROOT/BenchAssets/local-assets.json"
METADATA="$PROJECT_ROOT/BenchAssets/references/$ASSET_ID/metadata.json"
BUNDLE="$DATA_PARENT/listening-bundle"

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

mkdir -p "$DATA_PARENT" "$BUNDLE"
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

swift run chatterbox-session-bench \
  --reference-audio "$REFERENCE_AUDIO" \
  --reference-text "$REFERENCE_TEXT" \
  --reference-asset-id "$ASSET_ID" \
  --definitions "$PROJECT_ROOT/BenchAssets/benchmarks" \
  --data "$DATA_PARENT/chatterbox" \
  --warm-runs 1 2>&1 | tee "$DATA_PARENT/chatterbox-session.log"

select_result() {
  local root="$1"
  local test_id="$2"
  local renderer="$3"
  local wanted_cold="$4"
  local result
  for result in "$root/runs/$test_id"/*/"$renderer"/result.json; do
    [[ -f "$result" ]] || continue
    if [[ "$(jq -r '.environmentSnapshot.cold_start // "false"' "$result")" == "$wanted_cold" ]]; then
      echo "$result"
      return 0
    fi
  done
  return 1
}

QWEN_A01_RESULT="$(select_result "$DATA_PARENT/qwen3" A01 qwen3 true)"
QWEN_C01_RESULT="$(select_result "$DATA_PARENT/qwen3" C01 qwen3 false)"
VOX_A01_RESULT="$(select_result "$DATA_PARENT/voxcpm2" A01 voxcpm2 true)"
VOX_C01_RESULT="$(select_result "$DATA_PARENT/voxcpm2" C01 voxcpm2 false)"
CHATTERBOX_A01_RESULT="$(select_result "$DATA_PARENT/chatterbox" A01 chatterbox true)"
CHATTERBOX_C01_RESULT="$(select_result "$DATA_PARENT/chatterbox" C01 chatterbox false)"

QWEN_A01_AUDIO="$(jq -er '.outputAudioPath' "$QWEN_A01_RESULT")"
QWEN_C01_AUDIO="$(jq -er '.outputAudioPath' "$QWEN_C01_RESULT")"
VOX_A01_AUDIO="$(jq -er '.outputAudioPath' "$VOX_A01_RESULT")"
VOX_C01_AUDIO="$(jq -er '.outputAudioPath' "$VOX_C01_RESULT")"
CHATTERBOX_A01_AUDIO="$(jq -er '.outputAudioPath' "$CHATTERBOX_A01_RESULT")"
CHATTERBOX_C01_AUDIO="$(jq -er '.outputAudioPath' "$CHATTERBOX_C01_RESULT")"

cp "$QWEN_A01_AUDIO" "$BUNDLE/A01_qwen.wav"
cp "$VOX_A01_AUDIO" "$BUNDLE/A01_voxcpm2.wav"
cp "$CHATTERBOX_A01_AUDIO" "$BUNDLE/A01_chatterbox.wav"
cp "$QWEN_C01_AUDIO" "$BUNDLE/C01_qwen.wav"
cp "$VOX_C01_AUDIO" "$BUNDLE/C01_voxcpm2.wav"
cp "$CHATTERBOX_C01_AUDIO" "$BUNDLE/C01_chatterbox.wav"
cp "$QWEN_A01_RESULT" "$BUNDLE/A01_qwen.result.json"
cp "$VOX_A01_RESULT" "$BUNDLE/A01_voxcpm2.result.json"
cp "$CHATTERBOX_A01_RESULT" "$BUNDLE/A01_chatterbox.result.json"
cp "$QWEN_C01_RESULT" "$BUNDLE/C01_qwen.result.json"
cp "$VOX_C01_RESULT" "$BUNDLE/C01_voxcpm2.result.json"
cp "$CHATTERBOX_C01_RESULT" "$BUNDLE/C01_chatterbox.result.json"

jq -n \
  --arg asset_id "$ASSET_ID" \
  --arg reference_audio "$REFERENCE_AUDIO" \
  --arg qwen_a01_result "$QWEN_A01_RESULT" --arg qwen_c01_result "$QWEN_C01_RESULT" \
  --arg vox_a01_result "$VOX_A01_RESULT" --arg vox_c01_result "$VOX_C01_RESULT" \
  --arg chatterbox_a01_result "$CHATTERBOX_A01_RESULT" --arg chatterbox_c01_result "$CHATTERBOX_C01_RESULT" \
  '{schema_version:1, blind:false, subjective_scores:false, reference_asset_id:$asset_id,
    reference_audio:$reference_audio,
    source_results:{qwen_a01:$qwen_a01_result,qwen_c01:$qwen_c01_result,
                    voxcpm2_a01:$vox_a01_result,voxcpm2_c01:$vox_c01_result,
                    chatterbox_a01:$chatterbox_a01_result,chatterbox_c01:$chatterbox_c01_result},
    outputs:{A01:{qwen:{file:"A01_qwen.wav",result:"A01_qwen.result.json"},
                  voxcpm2:{file:"A01_voxcpm2.wav",result:"A01_voxcpm2.result.json"},
                  chatterbox:{file:"A01_chatterbox.wav",result:"A01_chatterbox.result.json"}},
             C01:{qwen:{file:"C01_qwen.wav",result:"C01_qwen.result.json"},
                  voxcpm2:{file:"C01_voxcpm2.wav",result:"C01_voxcpm2.result.json"},
                  chatterbox:{file:"C01_chatterbox.wav",result:"C01_chatterbox.result.json"}}}}' \
  > "$BUNDLE/manifest.json"

echo "Human-audition bundle: $BUNDLE"
