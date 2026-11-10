#!/bin/bash
# GH-5: Claude Code StopFailure hook: a turn ended on an API error. If it is the usage limit and this is the
# unattended session (~/.local/state/deepidle/resume names its directory), start claude-limit-wait.sh, which
# brings the session back once the limit has reset, unless Claude Code's own "continue automatically at usage
# limit" (autoContinueAtUsageLimit, on in ~/.claude/settings.json) has already done so.
# Installed as ~/.claude/hooks/claude-limit-hook.sh; every call is logged in ~/.local/state/deepidle/limit.log.
STATE=$HOME/.local/state/deepidle; mkdir -p "$STATE"
IN=$(cat)
echo "$(date '+%F %T') StopFailure: $(echo "$IN" | tr '\n' ' ' | cut -c1-1500)" >> "$STATE/limit.log"
echo "$IN" | grep -qiE 'rate_limit|usage.?limit|limit reached' || exit 0
[ -s "$STATE/resume" ] || exit 0
DIR=$(head -1 "$STATE/resume"); CWD=$(echo "$IN" | jq -r '.cwd // empty')
case "$CWD/" in "$DIR"/*) ;; *) exit 0 ;; esac
T=$(echo "$IN" | jq -r '.transcript_path // empty'); SID=$(echo "$IN" | jq -r '.session_id // empty')
[ -n "$T" ] && [ -n "$SID" ] || exit 0
# the claude process this hook belongs to
P=$PPID; while [ "$P" -gt 1 ] && ! grep -qa claude "/proc/$P/cmdline" 2>/dev/null; do P=$(awk '{print $4}' "/proc/$P/stat"); done
pgrep -f "claude-limit-wait.sh $SID" >/dev/null && exit 0
setsid nohup bash "$(dirname "$0")/claude-limit-wait.sh" "$SID" "$T" "$DIR" "$P" >> "$STATE/limit.log" 2>&1 < /dev/null &
exit 0
