#!/bin/bash
# Pi side: watch the Mac while nobody is at the keyboard, and recover it when a test strands it.
#   ~/deepidle/mac-guard.sh start | stop | status | hold <seconds>
# Not a hand-off: the Claude Code session on the Mac drives the project. This only
#  1. reboots the Mac through the Aura proxy when it is stuck in Aura (Mac off the network for
#     RESET_AFTER s, /dev/m1n1 present, no guest run in progress): tools/reboot.py, no LLM involved;
#  2. when the Mac stays unreachable for HELP_AFTER s (or the reboot fails), asks agy (Gemini 3.8 Flash,
#     high) to diagnose from the logs and write a report. agy changes nothing but the report; it cannot
#     press the power key, so a hang before Aura needs the owner.
# `hold N` pauses both for N seconds (a test where the Mac is expected to be away: suspend, guest run).
# Events: ~/deepidle/guard.log. Reports: ~/deepidle/rescue/.
set -u
D=$HOME/deepidle; LOG=$D/guard.log; HOLD=$D/guard-hold; PIDF=$D/guard.pid
RESET_AFTER=${RESET_AFTER:-300}; HELP_AFTER=${HELP_AFTER:-900}
MACIP=${MACIP:-$(ssh -G mac | awk '/^hostname /{print $2}')}
now() { date '+%F %T'; }
log() { echo "$(now) $*" >> "$LOG"; }
loop() {
    local down_since=0 reset_done=0 help_done=0 t
    while :; do
        sleep 30
        t=$(date +%s)
        [ -e "$HOLD" ] && [ "$t" -lt "$(cat "$HOLD" 2>/dev/null || echo 0)" ] && { down_since=0; continue; }
        if ping -c1 -W2 "$MACIP" > /dev/null 2>&1; then
            [ "$down_since" != 0 ] && log "Mac reachable again after $((t - down_since)) s"
            down_since=0; reset_done=0; help_done=0; continue
        fi
        [ "$down_since" = 0 ] && { down_since=$t; log "Mac unreachable"; }
        pgrep -f "run_guest.py|hv-run.sh" > /dev/null && continue
        gone=$((t - down_since))
        if [ "$gone" -ge "$RESET_AFTER" ] && [ "$reset_done" = 0 ] && [ -e /dev/m1n1 ]; then
            reset_done=1; log "down $gone s, Aura proxy present: rebooting the Mac through it"
            ( cd "$D/aura/proxyclient" && timeout 60 python3 tools/reboot.py < /dev/null >> "$LOG" 2>&1 ) \
                && log "reboot sent" || log "reboot via proxy failed"
        fi
        if [ "$gone" -ge "$HELP_AFTER" ] && [ "$help_done" = 0 ]; then
            help_done=1; log "down $gone s: asking agy for a diagnosis"
            "$D/agy-rescue.sh" >> "$LOG" 2>&1 &
        fi
    done
}
case "${1:-status}" in
start) [ -e "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null && { echo "already running"; exit 0; }
    setsid -f bash "$0" _run > /dev/null 2>&1 < /dev/null; sleep 1; echo started ;;
_run) echo $$ > "$PIDF"; log "guard started (reset after $RESET_AFTER s, help after $HELP_AFTER s)"; loop ;;
stop) [ -e "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null; rm -f "$PIDF"; log "guard stopped"; echo stopped ;;
hold) echo $(( $(date +%s) + ${2:?seconds} )) > "$HOLD"; log "hold for $2 s"; echo "held until $(date -d @$(cat "$HOLD") '+%T')" ;;
status) [ -e "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null && echo "running (pid $(cat "$PIDF"))" || echo "not running"
    tail -5 "$LOG" 2>/dev/null ;;
esac
