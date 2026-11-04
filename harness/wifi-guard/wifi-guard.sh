#!/bin/bash
# Boot-time Wi-Fi guard: if no Wi-Fi link is connected 120 s after boot, reboot.
# Gives up after MAX_TRIES consecutive failed boots (no reboot loop); a good boot resets the count.
# Skipped when /var/lib/deepidle/wifi-guard.off exists (deliberate Wi-Fi-off tests).
set -u
LIMIT=${LIMIT:-120}; MAX_TRIES=${MAX_TRIES:-3}
D=/var/lib/deepidle; C=$D/wifi-guard.count; LOG=$D/wifi-guard.log
mkdir -p "$D"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
[ -e "$D/wifi-guard.off" ] && { log "disabled by wifi-guard.off"; exit 0; }
connected() { nmcli -t -f TYPE,STATE device 2>/dev/null | grep -q '^wifi:connected'; }
up=$(cut -d. -f1 /proc/uptime); wait=$(( LIMIT - up )); [ "$wait" -lt 0 ] && wait=0
end=$(( $(date +%s) + wait ))
while [ "$(date +%s)" -lt "$end" ]; do connected && break; sleep 3; done
if connected; then
    log "wifi connected (uptime $(cut -d. -f1 /proc/uptime)s)"; echo 0 > "$C"; exit 0
fi
n=$(( $(cat "$C" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$C"
log "no wifi after ${LIMIT}s of uptime (failure $n of $MAX_TRIES); kernel $(uname -r)"
journalctl -k -b --no-pager 2>/dev/null | grep -i -E "brcm|wlan|wifi" | tail -15 >> "$LOG"
if [ "$n" -ge "$MAX_TRIES" ]; then log "giving up, not rebooting"; exit 0; fi
sync; systemctl reboot
