#!/bin/bash
# Pi side: push a phone notification (ntfy, the owner's agent-notify topic) a while after a guest run starts,
# with instructions for what the owner must do at the Mac. Run in the background by the test procedure.
#   notify-when-guest.sh <delay s> <title> <message>
D=$HOME/deepidle; DELAY=$1; TITLE=$2; MSG=$3
RUN=$(ls -dt "$D"/hv/*/ | head -1)
for _ in $(seq 600); do grep -q "starting the guest" "${RUN}run.txt" 2>/dev/null && break; sleep 2; done
sleep "$DELAY"
curl -fsS -H "Title: $TITLE" -H "Priority: urgent" -H "Tags: computer" -d "$MSG" "https://ntfy.sh/$(cat "$D/secret/ntfy-topic")" > /dev/null \
    && echo "$(date '+%F %T') notified: $TITLE" >> "$D/guard.log"
