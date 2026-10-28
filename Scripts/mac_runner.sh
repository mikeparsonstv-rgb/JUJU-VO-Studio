#!/bin/bash
# JUJU VO Studio — Mac job runner (Mike starts it; Ctrl-C stops it).
#   bash "$HOME/Documents/CLAUDE_MAY/JUJU VO Studio/Scripts/mac_runner.sh"
# Runs ONLY files named Runner/inbox/*.sh, one at a time, from the repo root.
# Each job's text is echoed here before it runs; output -> Runner/outbox/<job>.log, exit code -> <job>.exit.
# Keeps the Mac awake (caffeinate) while it runs; each job is limited to 45 minutes.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$JUJU_RUNNER_CAFFEINATED" ]; then
  export JUJU_RUNNER_CAFFEINATED=1
  exec caffeinate -dimsu /bin/bash "$0" "$@"
fi
IN="$ROOT/Runner/inbox"; OUT="$ROOT/Runner/outbox"; DONE="$ROOT/Runner/done"
mkdir -p "$IN" "$OUT" "$DONE"
JOB_LIMIT=$((45*60))
trap 'echo "runner stopped"; rm -f "$OUT/.runner_alive"; exit 0' INT TERM
echo "JUJU runner watching $IN  (caffeinated; Ctrl-C to stop)"
while true; do
  date '+%Y-%m-%d %H:%M:%S' > "$OUT/.runner_alive"
  job=$(ls -1 "$IN"/*.sh 2>/dev/null | sort | head -1)
  if [ -z "$job" ]; then sleep 2; continue; fi
  name=$(basename "$job" .sh)
  mv "$job" "$DONE/$name.sh" || { sleep 2; continue; }
  echo ""; echo "━━━ $(date '+%H:%M:%S') job $name ━━━"; sed 's/^/  │ /' "$DONE/$name.sh"
  echo "running" > "$OUT/$name.exit"
  ( cd "$ROOT" && perl -e 'alarm shift; exec @ARGV' "$JOB_LIMIT" /bin/bash "$DONE/$name.sh" ) > "$OUT/$name.log" 2>&1 < /dev/null
  rc=$?; echo "$rc" > "$OUT/$name.exit"
  [ $rc -eq 142 ] && echo "(job hit the 45-minute limit)" >> "$OUT/$name.log"
  echo "  └ exit $rc  ($(wc -l < "$OUT/$name.log" | tr -d ' ') lines → Runner/outbox/$name.log)"
done
