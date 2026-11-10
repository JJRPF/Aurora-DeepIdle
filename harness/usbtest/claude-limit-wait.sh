#!/bin/bash
# GH-5: started by claude-limit-hook.sh when the unattended session stops on the usage limit.
#   claude-limit-wait.sh <session id> <transcript> <dir> <claude pid>
# Every 10 min: if the transcript has moved on (Claude Code continued by itself, or the owner typed), stop.
# Otherwise ask the session's own model a one-word question; once that works the limit is over. Wait 5 more
# minutes for Claude Code's own automatic continue, and if the session is still silent, close that claude and
# reopen the session in a terminal with a "continue" prompt.
# If the session ran on Fable, Fable is still limited and Opus 5.5 answers, reopen it at once with
# --model claude-opus-5-5 instead of waiting for Fable. Gives up after 26 h.
SID=$1; T=$2; DIR=$3; PID=$4
export PATH=$HOME/.local/share/mise/shims:$HOME/.local/bin:/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:$PATH
OPUS=claude-opus-5-5
MODEL=$(grep -o '"model":"claude-[a-z0-9.-]*"' "$T" 2>/dev/null | tail -1 | cut -d'"' -f4)
say() { echo "$(date '+%F %T') limit-wait $SID: $*"; }
moved() { [ "$(stat -c %Y "$T" 2>/dev/null || echo 0)" -gt $((START + 180)) ]; }
probe() { (cd /tmp && timeout 180 claude -p "Reply with the single word OK." --model "$1" < /dev/null 2>&1) | tail -c 400 | tr '\n' ' '; }
ok() { echo "$1" | grep -qE '(^| )OK\.?( |$)'; }
reopen() {   # reopen "<extra claude arguments>" "<first sentence of the prompt>"
    if [ "$PID" -gt 1 ] && kill -0 "$PID" 2>/dev/null; then kill "$PID"; sleep 10; fi
    say "reopening the session $1"
    exec xdg-terminal-exec --title="deep-idle (Claude)" --dir="$DIR" -- bash -lc "claude --resume $SID $1 --dangerously-skip-permissions '$2 Check the state first (git log, the end of docs/worklog.md, /var/lib/deepidle/usbtest/last/summary), then continue the task you were on; do not repeat finished work.'; echo \"claude exited: \$?\"; exec bash"
}
START=$(date +%s); say "waiting (claude pid $PID, model ${MODEL:-unknown})"
while [ $(( $(date +%s) - START )) -lt 93600 ]; do
    sleep 600
    moved && { say "the session moved on by itself"; exit 0; }
    R=$(probe "${MODEL:-haiku}")
    if ok "$R"; then
        say "the limit is over"; sleep 300
        moved && { say "the session continued by itself"; exit 0; }
        reopen "" "The usage limit that stopped this session has reset (automatic resume by claude-limit-wait.sh)."
    fi
    case "$MODEL" in *fable*|*mythos*)
        R2=$(probe $OPUS)
        if ok "$R2"; then
            say "$MODEL is still limited ($R); $OPUS answers: switching"
            reopen "--model $OPUS" "The Fable usage limit stopped this session, so it now runs on Opus 5.5 (automatic switch by claude-limit-wait.sh; go back with /model once Fable has reset)."
        fi ;;
    esac
done
say "gave up after 26 h"
