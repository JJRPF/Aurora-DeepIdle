#!/bin/bash
# Pi side: push a phone notification (ntfy, the owner's agent-notify topic) a while after a guest run starts,
# with instructions for what the owner must do at the Mac. Run in the background by the test procedure.
#   notify-when-guest.sh <delay s> <title> <message>
# Waits for a run directory created AFTER this script started (the run's own), then for its "starting the
# guest" line; every step and any curl error goes to guard.log.
D=$HOME/deepidle; DELAY=$1; TITLE=$2; MSG=$3
log() { echo "$(date '+%F %T') notify: $*" >> "$D/guard.log"; }
T0=$(date +%s); RUN=
log "waiting for a new run (delay $DELAY s)"
for _ in $(seq 400); do
    for d in "$D"/hv/*/; do [ -d "$d" ] && [ "$(stat -c %Y "$d")" -ge "$T0" ] && RUN=$d; done
    [ -n "$RUN" ] && grep -q "starting the guest" "${RUN}run.txt" 2>/dev/null && break
    sleep 2
done
[ -n "$RUN" ] && grep -q "starting the guest" "${RUN}run.txt" 2>/dev/null || { log "no guest start seen, giving up"; exit 1; }
log "guest started in $(basename "$RUN"), sleeping $DELAY s"
sleep "$DELAY"
out=$(curl -sS -m 20 -H "Title: $TITLE" -H "Priority: urgent" -H "Tags: computer" -d "$MSG" "https://ntfy.sh/$(cat "$D/secret/ntfy-topic")" -w ' http %{http_code}' 2>&1)
log "sent: ${out##* }"
