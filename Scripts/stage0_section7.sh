#!/bin/bash
# JUJU VO Studio — Stage 0 §7 checks (run on the Mac, in Terminal).
#   bash "$HOME/Documents/CLAUDE_MAY/JUJU VO Studio/Scripts/stage0_section7.sh"
# Read-only apart from: SwiftPM .build folders, a temp Voicebox data dir, and the log below.
# Nothing is downloaded; Voicebox is started on a private port and stopped again.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORIG="$HOME/Documents/CODEX/JUJU VoiceOver/CuePitchBrief/TalkBack_Renderer_Bench_Brief_v0_1"
VBAPP="/Volumes/EDITBOX-RAID/JUJU LOCAL AI/Apps/Voicebox/Verified/Voicebox.app"
LOG="$ROOT/Notes/STAGE0_S7_RESULTS.txt"
VBPORT=17499

: > "$LOG"
say()  { echo "$*" | tee -a "$LOG"; }
sect() { say ""; say "=== $* ==="; }
# run_t <seconds> <cmd...> — macOS has no `timeout`
run_t() { local t=$1; shift; perl -e 'alarm shift; exec @ARGV' "$t" "$@"; }

say "JUJU VO Studio — Stage 0 §7 results — $(date '+%Y-%m-%d %H:%M:%S %Z') — $(hostname -s)"

sect "7.4 Toolchain and OS"
sw_vers 2>&1 | tee -a "$LOG"
xcodebuild -version 2>&1 | tee -a "$LOG"
xcode-select -p 2>&1 | tee -a "$LOG"
swift --version 2>&1 | tee -a "$LOG"
python3 --version 2>&1 | tee -a "$LOG"
uv --version 2>&1 | tee -a "$LOG"
say "arch: $(uname -m)"

sect "7.1 swift build / swift test — tracked copy (JUJU VO Studio/RendererBench)"
cd "$ROOT/RendererBench" || exit 1
swift build 2>&1 | tail -25 | tee -a "$LOG"; say "swift build exit: ${PIPESTATUS[0]}"
swift test > "$ROOT/Notes/.s7_swift_test_full.log" 2>&1; RC=$?
grep -E "Test run with|passed after|failed after|✘|error:" "$ROOT/Notes/.s7_swift_test_full.log" | tail -40 | tee -a "$LOG"
say "swift test exit: $RC  (full output: Notes/.s7_swift_test_full.log, not committed)"

sect "7.2 renderer-bench health — original folder (workers + envs live there)"
if [ -d "$ORIG" ]; then
  cd "$ORIG"
  swift build --product renderer-bench 2>&1 | tail -5 | tee -a "$LOG"
  for r in qwen3 voxcpm2 chatterbox; do
    say "--- health $r"
    run_t 300 swift run --skip-build renderer-bench health "$r" 2>&1 | tail -20 | tee -a "$LOG"
    say "exit: ${PIPESTATUS[0]}"
  done
else
  say "MISSING: $ORIG"
fi

sect "7.x Frozen baseline — RB-006 / RB-007 byte-identical check"
for m in "$ROOT"/Evidence/frozen-baseline/*.sha256; do
  top=$(head -1 "$m" | awk '{print $2}' | cut -d/ -f1)
  base=$(find "$ORIG" -maxdepth 4 -type d -name "$top" 2>/dev/null | head -1)
  if [ -z "$base" ]; then say "$(basename "$m"): cannot find folder $top under original bench"; continue; fi
  (cd "$(dirname "$base")" && shasum -a 256 -c "$m" 2>&1) > "$ROOT/Notes/.s7_hash.log"
  ok=$(grep -c ': OK$' "$ROOT/Notes/.s7_hash.log"); bad=$(grep -vc ': OK$' "$ROOT/Notes/.s7_hash.log")
  say "$(basename "$m"): $ok OK, $bad not OK  (root: $(dirname "$base"))"
  grep -v ': OK$' "$ROOT/Notes/.s7_hash.log" | head -10 | tee -a "$LOG"
done

sect "7.3 Voicebox 0.5.0 bundled server"
if [ -d "$VBAPP" ]; then
  defaults read "$VBAPP/Contents/Info" CFBundleShortVersionString 2>&1 | sed 's/^/bundle version: /' | tee -a "$LOG"
  VBS=$(find "$VBAPP/Contents" -type f -name 'voicebox-server*' -perm +111 2>/dev/null | head -1)
  say "server binary: ${VBS:-NOT FOUND}"
  if [ -n "$VBS" ]; then
    run_t 60 "$VBS" --help > "$ROOT/Notes/.s7_vb_help.txt" 2>&1
    head -40 "$ROOT/Notes/.s7_vb_help.txt" | tee -a "$LOG"
    TMPD=$(mktemp -d /tmp/juju-vb-s7.XXXX)
    ARGS=(--port "$VBPORT")
    grep -q -- '--data-dir' "$ROOT/Notes/.s7_vb_help.txt" && ARGS+=(--data-dir "$TMPD")
    grep -q -- '--host' "$ROOT/Notes/.s7_vb_help.txt" && ARGS+=(--host 127.0.0.1)
    say "launch: $VBS ${ARGS[*]}"
    "$VBS" "${ARGS[@]}" > "$TMPD/server.log" 2>&1 & VBPID=$!
    up=0
    for i in $(seq 1 120); do
      if curl -fsS -m 2 "http://127.0.0.1:$VBPORT/health" > "$TMPD/health.json" 2>/dev/null; then up=1; break; fi
      sleep 1
    done
    if [ $up = 1 ]; then
      say "up after ~${i}s"
      say "--- /health"; cat "$TMPD/health.json" | tee -a "$LOG"; say ""
      say "--- /models/status"; curl -sS -m 30 "http://127.0.0.1:$VBPORT/models/status" 2>&1 | tee -a "$LOG"; say ""
      say "--- /v1/models (0.6.0 route; 404 expected on 0.5.0)"; curl -sS -m 10 -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:$VBPORT/v1/models" | tee -a "$LOG"
    else
      say "server did not answer /health within 120 s; last log lines:"; tail -30 "$TMPD/server.log" | tee -a "$LOG"
    fi
    kill $VBPID 2>/dev/null; sleep 2; kill -9 $VBPID 2>/dev/null
    say "server stopped; temp data dir: $TMPD"
  fi
else
  say "MISSING (RAID not mounted?): $VBAPP"
fi

sect "7.5 Hugging Face cache inventory (read-only)"
HF="${HF_HOME:-$HOME/.cache/huggingface}/hub"
say "cache: $HF"
if [ -d "$HF" ]; then
  du -sh "$HF"/models--* 2>/dev/null | sort -k2 | tee -a "$LOG"
  say "--- of interest (Qwen TTS any size, Chatterbox, VoxCPM, MOSS, Zonos, Fish, Kokoro, Parakeet, Whisper):"
  ls -1 "$HF" | grep -iE 'qwen.*tts|chatterbox|voxcpm|moss|zonos|fish|kokoro|parakeet|whisper|omnivoice|luxtts|tada' | tee -a "$LOG"
else
  say "no cache at $HF"
fi
for d in "/Volumes/EDITBOX-RAID/JUJU LOCAL AI/Models"; do [ -d "$d" ] && { say "--- $d"; ls -1 "$d" | tee -a "$LOG"; }; done

sect "done"
say "Log: $LOG"
