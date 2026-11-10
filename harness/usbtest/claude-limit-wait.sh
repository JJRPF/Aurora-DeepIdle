#!/bin/bash
# GH-5: started by claude-limit-hook.sh when the unattended session stops on the usage limit.
#   claude-limit-wait.sh <session id> <transcript> <dir> <claude pid>
# Every 10 min: if the transcript has moved on (Claude Code continued by itself, or the owner typed), stop.
# Otherwise ask the API a one-word question; once that works the limit is over. Wait 5 more minutes for Claude
# Code's own automatic continue, and if the session is still silent, close that claude and reopen the session in
# a terminal with a "continue" prompt. Gives up after 26 h.
SID=$1; T=$2; DIR=$3; PID=$4
export PATH=$HOME/.local/share/mise/shims:$HOME/.local/bin:/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:$PATH
say() { echo "$(date '+%F %T') limit-wait $SID: $*"; }
moved() { [ "$(stat -c %Y "$T" 2>/dev/null || echo 0)" -gt $((START + 180)) ]; }
START=$(date +%s); say "waiting (claude pid $PID)"
while [ $(( $(date +%s) - START )) -lt 93600 ]; do
    sleep 600
    moved && { say "the session moved on by itself"; exit 0; }
    (cd /tmp && timeout 180 claude -p "Reply with the single word OK." --model haiku < /dev/null 2>&1 | grep -q OK) || continue
    say "the limit is over"; sleep 300
    moved && { say "the session continued by itself"; exit 0; }
    if [ "$PID" -gt 1 ] && kill -0 "$PID" 2>/dev/null; then kill "$PID"; sleep 10; fi
    say "reopening the session"
    exec xdg-terminal-exec --title="deep-idle (Claude)" --dir="$DIR" -- bash -lc "claude --resume $SID --dangerously-skip-permissions 'The usage limit that stopped this session has reset (automatic resume by claude-limit-wait.sh). Check the state first (git log, the end of docs/worklog.md, /var/lib/deepidle/usbtest/last/summary), then continue the task you were on; do not repeat finished work.'; echo \"claude exited: \$?\"; exec bash"
done
say "gave up after 26 h"
