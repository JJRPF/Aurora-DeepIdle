#!/bin/bash
# Pi side: keep a copy of the Mac's kernel log and its reachability while a test runs, so the
# evidence survives the Mac losing its disk. (SMC step 7, 2026-10-22: after the slpa resume the
# NVMe writes failed, root went read-only and the Mac's journal kept nothing of the failure.)
#   ~/deepidle/pi-watch.sh start [TAG]    start in the background (survives Mac reboots)
#   ~/deepidle/pi-watch.sh stop | status
# Files: ~/deepidle/watch/<stamp>-<TAG>.kmsg  the Mac's `dmesg -w`, each line prefixed with the
#        Pi's wall clock; reconnects after suspend/reboot, skips lines already seen (same boot)
#        ~/deepidle/watch/<stamp>-<TAG>.ping  reachability changes (ping every 5 s)
# Uses the Pi's ssh alias `mac` (Tailscale). dmesg needs no root on the Mac (dmesg_restrict 0).
set -u
D=$HOME/deepidle/watch; mkdir -p "$D"
PIDF=$D/watch.pid
MACIP=${MACIP:-$(ssh -G mac | awk '/^hostname /{print $2}')}
now() { printf '%(%F %T)T' -1; }

kmsg_loop() {
    local f=$1.kmsg last=-1 boot='' l t n b
    while :; do
        b=$(ssh -o BatchMode=yes -o ConnectTimeout=8 mac 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null)
        if [ -n "$b" ]; then
            [ "$b" != "$boot" ] && { echo "$(now) == Mac boot $b" >> "$f"; boot=$b; last=-1; }
            while IFS= read -r l; do
                t=${l#\[}; t=${t%%\]*}; t=${t// /}; n=${t/./}
                [[ $n =~ ^[0-9]+$ ]] && { n=$((10#$n)); [ $n -le $last ] && continue; last=$n; }
                echo "$(now) $l" >> "$f"
            done < <(ssh -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=5 \
                         -o ServerAliveCountMax=6 mac 'dmesg -w' 2>/dev/null)
            echo "$(now) -- stream ended" >> "$f"
        fi
        sleep 5
    done
}

ping_loop() {
    local f=$1.ping st='' s
    while :; do
        ping -c1 -W2 "$MACIP" > /dev/null 2>&1 && s=up || s=down
        [ "$s" != "$st" ] && { echo "$(now) $s" >> "$f"; st=$s; }
        sleep 5
    done
}

case "${1:-status}" in
start)
    if [ -e "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
        echo "already running: $(cat "$D/current")"; exit 0
    fi
    F=$D/$(date +%Y%m%d-%H%M%S)-${2:-test}
    echo "$F" > "$D/current"
    setsid nohup bash "$0" run "$F" > /dev/null 2>&1 < /dev/null &
    echo $! > "$PIDF"
    echo "watching: $F.kmsg / $F.ping" ;;
run)
    kmsg_loop "$2" & ping_loop "$2" & wait ;;
stop)
    [ -e "$PIDF" ] && kill -- -"$(cat "$PIDF")" 2>/dev/null
    rm -f "$PIDF"; echo "stopped: $(cat "$D/current" 2>/dev/null)" ;;
status)
    if [ -e "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
        F=$(cat "$D/current"); echo "running: $F"
        echo "kmsg lines $(wc -l < "$F.kmsg" 2>/dev/null || echo 0); ping: $(tail -1 "$F.ping" 2>/dev/null)"
    else echo "not running"; fi ;;
*) echo "usage: $0 start [TAG] | stop | status"; exit 1 ;;
esac
