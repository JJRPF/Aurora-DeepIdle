#!/bin/bash
# PMP wake from IDLE, the macOS way, tested in s2idle (deepidle3 kernel, no reboot needed).
# deepidle2 put the PMP's RTKit into IDLE but woke it with INIT, which macOS uses only after
# QUIESCED: the PMP never answered again. This pmp.ko (only module changed; the kernel image
# stays 46375fe1) stops the PMP's CPU after the IDLE ack (CPU_STATUS & 3, then clear RUN in
# CPU_CONTROL) and on wake sets RUN again, waits 10 ms and sends AP ON, falling back to the
# INIT wake if that fails. Success: every cycle logs "CPU stopped", the IOP's own report back to
# ON (0x201 -> 0x20, rtkit.c dynamic debug) and "AP ON acked", and the IDLE request of the next
# cycle is acked too (in deepidle2 it timed out).
#   sudo bash /home/jjr/Work/deepidle-harness/pmp-wake/run.sh [CYCLES]     default 3
# Nothing persists: pmp stays blacklisted for the next boot, the module is loaded from staging
# with insmod; USB wakeup is off only during the test; at the end the s2idle hook is turned off
# (apple_pmp_sleep.s2idle_idle=0) so a later lid close cannot leave the PMP stuck. A reboot
# unloads the PMP again. Omarchy stay-awake is off only around each suspend.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
CYCLES=${1:-3}
KO=/home/jjr/Work/deepidle-11.35/staging-pmpwake/pmp.ko
KOSHA=a8ae3a2d7835fd12
WAKER=/home/jjr/Work/deepidle-harness/deepidle3/s2idle-wake.ko
STAMP=$(date +%Y%m%d-%H%M)
OUT=/var/lib/deepidle/results-pmpwake-$STAMP
SUM=/home/jjr/Work/deep-idle-build/pmp-wake-$STAMP.txt
mkdir -p $OUT; chmod 755 $OUT
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/run.log; }
awake() { sudo -u jjr env HOME=/home/jjr XDG_RUNTIME_DIR=/run/user/1001 /usr/share/omarchy/bin/omarchy-toggle-idle "$1" >/dev/null 2>&1; }
pmplog() { journalctl -k --since "$1" --no-pager -o short-monotonic | grep -i -E 'pmp|rtkit' ; }

# Preconditions
case "$(uname -r)" in *-deepidle3) ;; *) echo "not the deepidle3 kernel"; exit 1 ;; esac
[ "$(sha256sum $KO | cut -c1-16)" = $KOSHA ] || { echo "staged pmp.ko missing or changed"; exit 1; }
[ "$(tr -d '\0' < /sys/firmware/devicetree/base/soc/pmp@28e700000/status 2>/dev/null)" = okay ] \
    || { echo "PMP node not enabled in this boot's DT: boot boot.bin.pmpwake-test (pmp-wake/arm.sh)"; exit 1; }
lsmod | grep -q '^pmp ' && { echo "pmp already loaded (the old hook would run); reboot first"; exit 1; }
R=$(dirname $(grep -l macsmc-rtc /sys/class/rtc/rtc*/name 2>/dev/null) 2>/dev/null)
[ -n "$R" ] && [ -e $R/wakealarm ] || { echo "no macsmc-rtc alarm"; exit 1; }

# Undo on any exit: stay-awake on, USB wakeup back, backup waker out, hook off
USBW=$OUT/usb-wakeup-saved.txt; : > $USBW
cleanup() {
    awake stay-awake
    while read -r f; do echo enabled > "$f" 2>/dev/null; done < $USBW
    rmmod s2idle_wake 2>/dev/null
    [ -e /sys/module/apple_pmp_sleep/parameters/s2idle_idle ] && echo 0 > /sys/module/apple_pmp_sleep/parameters/s2idle_idle
    echo 'file drivers/soc/apple/rtkit.c -p' > /sys/kernel/debug/dynamic_debug/control 2>/dev/null
    chmod -R a+r $OUT
}
trap cleanup EXIT

log "start: $(uname -r), pmp.ko $KOSHA, $CYCLES cycles"
for f in /sys/bus/usb/devices/*/power/wakeup; do
    [ "$(cat $f 2>/dev/null)" = enabled ] && { echo $f >> $USBW; echo disabled > $f; }
done
log "USB wakeup turned off on $(wc -l < $USBW) devices (restored at the end)"
echo 'file drivers/soc/apple/rtkit.c +p' > /sys/kernel/debug/dynamic_debug/control 2>/dev/null \
    && log "dynamic debug on for rtkit.c (power-state transitions)"
insmod $WAKER seconds=120 && log "backup waker loaded (120 s)"

since=$(date '+%F %T')
insmod $KO || { log "insmod pmp.ko failed"; exit 1; }
sleep 5
pmplog "$since" > $OUT/probe.txt
log "probe: $(grep -c . $OUT/probe.txt) PMP/RTKit lines; hook: $(grep -o 's2idle hook registered.*' $OUT/probe.txt | tail -1); s2idle_idle=$(cat /sys/module/apple_pmp_sleep/parameters/s2idle_idle)"
echo 1 > /sys/module/apple_pmp_sleep/parameters/s2idle_idle
sleep 20

pass=0
for i in $(seq 1 $CYCLES); do
    since=$(date '+%F %T')
    awake allow-idle
    t0=$(date +%s.%N)
    timeout 300 rtcwake -d $(basename $R) -m freeze -s 30 > $OUT/rtcwake-$i.txt 2>&1; rc=$?
    t1=$(date +%s.%N)
    awake stay-awake
    sleep 5
    pmplog "$since" > $OUT/cycle-$i.txt
    # Count the PMP's own lines only: with dynamic debug every RTKit coprocessor logs transitions
    grep -i 'pmp' $OUT/cycle-$i.txt > $OUT/cycle-$i-pmp.txt
    st=$(grep -c 'CPU stopped' $OUT/cycle-$i-pmp.txt); on=$(grep -c 'AP ON acked' $OUT/cycle-$i-pmp.txt)
    # the IOP's own report after RUN: RTKit is only "running" again once the IOP state is ON
    iop=$(grep -c 'IOP power state transition: 0x201 -> 0x20$' $OUT/cycle-$i-pmp.txt)
    bad=$(grep -c -i -E 'idle failed|wake failed|AP ON failed|not idle|timed out|crash' $OUT/cycle-$i-pmp.txt)
    [ $st = 1 ] && [ $on = 1 ] && [ $iop -ge 1 ] && [ $bad = 0 ] && pass=$((pass + 1))
    log "cycle $i: rtcwake $rc, $(echo "$t1 - $t0" | bc) s, wakeup irq $(cat /sys/power/pm_wakeup_irq 2>&1); CPU stopped $st, IOP back to ON $iop, AP ON acked $on, problems $bad"
    grep -i -E 'pmp-sleep|s2idle:|power state transition' $OUT/cycle-$i-pmp.txt | sed 's/^/    /' | tee -a $OUT/run.log
    sleep 20
done
log "result: $pass of $CYCLES cycles stopped and woke the PMP cleanly"
ip -br addr > $OUT/net-after.txt 2>&1
journalctl -k --since "-30min" --no-pager > $OUT/dmesg.txt
{ cat $OUT/run.log; echo; echo "== probe"; cat $OUT/probe.txt; for i in $(seq 1 $CYCLES); do echo "== cycle $i"; cat $OUT/cycle-$i.txt; done; } > $SUM
chown jjr:jjr $SUM
log "summary: $SUM (the PMP stays loaded with the hook off until a reboot)"
