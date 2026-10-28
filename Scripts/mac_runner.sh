#!/bin/bash
# JUJU VO Studio — Mac job runner (Mike starts it; Ctrl-C stops it).
#   bash "$HOME/Documents/CLAUDE_MAY/JUJU VO Studio/Scripts/mac_runner.sh"
# Runs ONLY files named Runner/inbox/*.sh, one at a time, from the repo root.
# Each job's text is echoed here before it runs; output -> Runner/outbox/<job>.log, exit code -> <job>.exit.
# Stops by itself after 3 hours with no jobs.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IN="$ROOT/Runner/inbox"; OUT="$ROOT/Runner/outbox"; DONE="$ROOT/Runner/done"
mkdir -p "$IN" "$OUT" "$DONE"
IDLE_LIMIT=$((3*3600)); last=$(date +%s)
echo "JUJU runner watching $IN  (Ctrl-C to stop)"
date '+%Y-%m-%d %H:%M:%S' > "$OUT/.runner_alive"
while true; do
  job=$(ls -1 "$IN"/*.sh 2>/dev/null | sort | head -1)
  if [ -z "$job" ]; then
    now=$(date +%s); date '+%Y-%m-%d %H:%M:%S' > "$OUT/.runner_alive"
    [ $((now-last)) -gt $IDLE_LIMIT ] && { echo "idle 3h — stopping"; rm -f "$OUT/.runner_alive"; exit 0; }
    sleep 2; continue
  fi
  name=$(basename "$job" .sh)
  mv "$job" "$DONE/$name.sh"
  echo ""; echo "━━━ $(date '+%H:%M:%S') job $name ━━━"; sed 's/^/  │ /' "$DONE/$name.sh"
  echo "running" > "$OUT/$name.exit"
  ( cd "$ROOT" && bash "$DONE/$name.sh" ) > "$OUT/$name.log" 2>&1
  rc=$?; echo "$rc" > "$OUT/$name.exit"
  echo "  └ exit $rc  ($(wc -l < "$OUT/$name.log" | tr -d ' ') lines → Runner/outbox/$name.log)"
  last=$(date +%s)
done
