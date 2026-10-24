#!/bin/bash
# The SMC sleep handshake in s2idle (deepidle3 kernel, no reboot needed). macOS tells the SMC
# the system sleeps (WKTP = 2, MBSE = slpw, MBSE = slpa last; on wake MBSE/MBSW read, then
# MBSE = waka, WKTP = 0); Linux never does. This macsmc-reboot.ko (only module changed; the
# kernel image stays 46375fe1) sends the steps chosen in its s2idle_steps bit mask, s2idle only:
#   1 = WKTP, 2 = slpw, 4 = slpa and waka.
#   sudo bash /home/jjr/Work/deepidle-harness/smc-sleep/run.sh STEPS [CYCLES] [owner-present]
# STEPS with bit 4 (slpa) needs the word owner-present: after slpa macOS takes the SoC down,
# and the SMC may cut power with the SoC still up in s2idle. Then only the power button helps.
# What it reports per cycle: each step's SMC result, the wake source (MBSW), the wake time, and
# whether the SMC still answers after (battery level read, Wi-Fi up).
# Nothing persists: the stock module is put back at the end (and if loading the new one fails);
# USB wakeup is off only during the test; stay-awake is off only around each suspend.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
STEPS=${1:?STEPS bit mask: 1 WKTP, 2 slpw, 4 slpa/waka}; CYCLES=${2:-3}
case $STEPS in [1-7]) ;; *) echo "STEPS must be 1..7"; exit 1 ;; esac
[ $((STEPS & 4)) = 0 ] || [ "${3:-}" = owner-present ] || { echo "slpa (4) only with owner-present"; exit 1; }
KO=/home/jjr/Work/deepidle-11.35/staging-smcsleep/macsmc-reboot.ko
KOSHA=a0cf24df426796cc
WAKER=/home/jjr/Work/deepidle-harness/deepidle3/s2idle-wake.ko
STAMP=$(date +%Y%m%d-%H%M)
OUT=/var/lib/deepidle/results-smcsleep-$STEPS-$STAMP
SUM=/home/jjr/Work/deep-idle-build/smc-sleep-$STEPS-$STAMP.txt
mkdir -p $OUT; chmod 755 $OUT
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/run.log; }
awake() { sudo -u jjr env HOME=/home/jjr XDG_RUNTIME_DIR=/run/user/1001 /usr/share/omarchy/bin/omarchy-toggle-idle "$1" >/dev/null 2>&1; }

case "$(uname -r)" in *-deepidle3) ;; *) echo "not the deepidle3 kernel"; exit 1 ;; esac
[ "$(sha256sum $KO | cut -c1-16)" = $KOSHA ] || { echo "staged macsmc-reboot.ko missing or changed"; exit 1; }
R=$(dirname $(grep -l macsmc-rtc /sys/class/rtc/rtc*/name 2>/dev/null) 2>/dev/null)
[ -n "$R" ] && [ -e $R/wakealarm ] || { echo "no macsmc-rtc alarm"; exit 1; }

USBW=$OUT/usb-wakeup-saved.txt; : > $USBW
cleanup() {
    awake stay-awake
    while read -r f; do echo enabled > "$f" 2>/dev/null; done < $USBW
    rmmod s2idle_wake 2>/dev/null
    rmmod macsmc_reboot 2>/dev/null; modprobe macsmc_reboot \
        && log "stock macsmc-reboot back: $(dmesg | grep -c 'Handling reboot and poweroff requests via SMC') handler lines in dmesg" \
        || log "MODPROBE OF THE STOCK macsmc-reboot FAILED: reboot with the power button menu, not a command"
    chmod -R a+r $OUT
}
trap cleanup EXIT

log "start: $(uname -r), macsmc-reboot.ko $KOSHA, steps $STEPS, $CYCLES cycles"
for f in /sys/bus/usb/devices/*/power/wakeup; do
    [ "$(cat $f 2>/dev/null)" = enabled ] && { echo $f >> $USBW; echo disabled > $f; }
done
log "USB wakeup turned off on $(wc -l < $USBW) devices (restored at the end)"
insmod $WAKER seconds=120 && log "backup waker loaded (120 s)"
rmmod macsmc_reboot || { log "cannot unload macsmc_reboot"; exit 1; }
insmod $KO s2idle_steps=$STEPS || { log "insmod of the new macsmc-reboot failed"; exit 1; }
log "new macsmc-reboot loaded, s2idle_steps=$(cat /sys/module/macsmc_reboot/parameters/s2idle_steps)"
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
    journalctl -k --since "$since" --no-pager -o short-monotonic > $OUT/cycle-$i.txt
    sent=$(grep -c 's2idle: ' $OUT/cycle-$i.txt)
    bad=$(grep 's2idle: ' $OUT/cycle-$i.txt | grep -c -E '\(-[0-9]+\)')
    bat=$(cat /sys/class/power_supply/macsmc-battery/capacity 2>&1)
    net=$(ip -br addr show wlan0 2>/dev/null | awk '{print $2}')
    [ $sent -gt 0 ] && [ $bad = 0 ] && [ -n "$bat" ] && [ "$net" = UP ] && pass=$((pass + 1))
    log "cycle $i: rtcwake $rc, $(echo "$t1 - $t0" | bc) s, wakeup irq $(cat /sys/power/pm_wakeup_irq 2>&1); SMC steps logged $sent, errors $bad; battery $bat%, wlan0 $net"
    grep 's2idle: ' $OUT/cycle-$i.txt | sed 's/^/    /' | tee -a $OUT/run.log
    sleep 20
done
log "result: $pass of $CYCLES cycles sent every step without an error and came back with the SMC answering"
{ cat $OUT/run.log; for i in $(seq 1 $CYCLES); do echo "== cycle $i"; grep -E 'PM: |s2idle|macsmc|smc|rtkit|RTKit' $OUT/cycle-$i.txt; done; } > $SUM
chown jjr:jjr $SUM
log "summary: $SUM"
