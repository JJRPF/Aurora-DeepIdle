#!/bin/bash
# deepidle3 smoke test, once, as root after boot: the PMU RTC alarm (macsmc-rtc with the
# PMU alarm cells, SPMI peripheral interrupt 2 on AIC 724). 1) an alarm while awake;
# 2) three s2idle cycles woken by the alarm (rtcwake -m freeze). Results world-readable.
# Omarchy stay-awake is turned off only around each suspend and back on right after.
set -u
OUT=/var/lib/deepidle/results-deepidle3
mkdir -p $OUT; chmod 755 $OUT
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/smoke.log; }
awake() { sudo -u jjr env HOME=/home/jjr XDG_RUNTIME_DIR=/run/user/1001 /usr/share/omarchy/bin/omarchy-toggle-idle "$1" >/dev/null 2>&1; }
irqs() { awk '/apple_spmi|macsmc-rtc|rtc/ {print}' /proc/interrupts; }
rm -f /var/lib/deepidle/deepidle3-armed
log "booted $(uname -r), m1n1 $(cat /run/deepidle3-booted-sha 2>/dev/null)"
case "$(uname -r)" in *-deepidle3) ;; *) log "not the deepidle3 kernel: nothing to do"; exit 0 ;; esac
sleep 60
since=$(date '+%F %T')
R=$(dirname $(grep -l macsmc-rtc /sys/class/rtc/rtc*/name))
pmu() { python3 -I /home/jjr/Work/deepidle-harness/mmio/pmu-rtc.py show | head -1; }
# Backup waker: no cycle may sleep longer than 120 s even if the alarm fails
insmod /home/jjr/Work/deepidle-harness/deepidle3/s2idle-wake.ko seconds=120 && log "backup waker loaded (120 s)"
log "rtc0 $(cat $R/name 2>&1); wakealarm file: $([ -e $R/wakealarm ] && echo yes || echo no); wakeup: $(cat $R/device/power/wakeup 2>&1)"
log "rtc time $(cat $R/since_epoch 2>&1), system $(date +%s)"
irqs > $OUT/irqs-0.txt
grep -i -E "spmi|rtc" <(journalctl -k -b) > $OUT/dmesg-boot-rtc.txt

# 1) two awake alarms back to back (the PMU's fired bit must not block the second)
for a in 1 2; do
    echo 0 > $R/wakealarm
    echo +10 > $R/wakealarm; log "awake alarm $a set: $(cat $R/wakealarm), now $(date +%s); $(pmu)"
    sleep 15
    log "after awake alarm $a: wakealarm '$(cat $R/wakealarm)' (empty = fired); $(pmu); $(irqs)"
done
irqs > $OUT/irqs-1.txt

# 2) s2idle woken by the alarm, 30 s each
for i in 1 2 3; do
    awake allow-idle
    t0=$(date +%s.%N)
    log "cycle $i before: $(pmu)"
    timeout 300 rtcwake -d $(basename $R) -m freeze -s 30 > $OUT/rtcwake-$i.txt 2>&1; rc=$?
    t1=$(date +%s.%N)
    awake stay-awake
    log "s2idle cycle $i: rtcwake exit $rc, $(echo "$t1 - $t0" | bc) s wall, wakeup irq $(cat /sys/power/pm_wakeup_irq 2>&1), suspend stats success $(cat /sys/power/suspend_stats/success 2>&1) fail $(cat /sys/power/suspend_stats/fail 2>&1)"
    sleep 20
done
awake stay-awake
rmmod s2idle_wake
irqs > $OUT/irqs-2.txt
journalctl -k --since "$since" > $OUT/dmesg.txt
grep -E "PM: suspend|PM: resume|rtc|spmi|Freezing|Wakeup|wakeup" $OUT/dmesg.txt | tail -60 > $OUT/pm-lines.txt
ip -br addr > $OUT/net-after.txt 2>&1
chmod -R a+r $OUT
log "done"
