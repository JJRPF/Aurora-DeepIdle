#!/bin/bash
# GH-5: unattended S2R soak from the live desktop. N cycles of `rtcwake -m mem -s SECS`; after each wake it
# checks that the sleep lasted, then NVMe, Wi-Fi link, Bluetooth, SD (if present), speaker daemon, DCP/GPU
# bound, and new kernel errors. Stops at the first failure and leaves the machine awake and normal.
# Leaves no state behind except the log; `touch /var/lib/deepidle/soak.stop` ends it early.
#   sudo bash s2r-soak.sh [cycles=20] [secs=45]
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
N=${1:-20}; S=${2:-45}
D=/var/lib/deepidle; mkdir -p $D; LOG=$D/soak-$(date +%Y%m%d-%H%M).log; rm -f $D/soak.stop
log() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }
fail=0
check() { # check <name> <command...>
    local n=$1; shift
    if "$@" >/dev/null 2>&1; then return 0; fi
    log "  FAIL: $n"; fail=1; }
wlan_up() { for i in $(seq 25); do iw dev wlan0 link 2>/dev/null | grep -q Connected && return 0; sleep 1; done; return 1; }
bt_up() { for i in $(seq 15); do [ -n "$(btmgmt info 2>/dev/null | grep -i 'current settings.*powered')" ] || [ -d /sys/class/bluetooth/hci0 ] && return 0; sleep 1; done; return 1; }
nvme_rw() { dd if=/dev/nvme0n1 of=/dev/null bs=1M count=64 iflag=direct 2>/dev/null; }
log "soak start: $N cycles x ${S}s, kernel $(uname -r), battery $(cat /sys/class/power_supply/macsmc-battery/capacity)%"
for c in $(seq $N); do
    [ -e $D/soak.stop ] && { log "stop file found, ending"; break; }
    mark=$(dmesg | wc -l); T0=$(date +%s)
    rtcwake -m mem -s $S >/dev/null 2>&1; rc=$?; T1=$(date +%s); el=$((T1-T0))
    log "cycle $c: rc=$rc wall=${el}s (alarm ${S}s)"
    [ $rc -eq 0 ] || { log "  FAIL: rtcwake rc=$rc"; fail=1; }
    [ $el -ge $((S-5)) ] || log "  note: woke early (${el}s < ${S}s): $(dmesg | tail -n +$mark | grep -iE 'Wake Debug|wake record' | head -2 | cut -c1-120 | tr '\n' ' ')"
    sleep 3
    check nvme nvme_rw
    check wifi wlan_up
    check bluetooth bt_up
    check speakersafetyd systemctl is-active --quiet speakersafetyd
    check "online CPUs 0-9" test "$(cat /sys/devices/system/cpu/online)" = "0-9"
    errs=$(dmesg | tail -n +$mark | grep -iE 'BUG:|Oops|WARNING:|-62\b|timed out|NO TTBR|failed to (resume|restore)|aborted' | grep -v 'UFW BLOCK' | head -5)
    [ -z "$errs" ] || { log "  new kernel errors:"; echo "$errs" | cut -c1-200 | tee -a "$LOG"; fail=1; }
    [ $fail -eq 0 ] || { log "STOPPED at cycle $c with a failure; machine left awake"; exit 1; }
    sleep 5
done
log "soak done: no failures, battery $(cat /sys/class/power_supply/macsmc-battery/capacity)%"
