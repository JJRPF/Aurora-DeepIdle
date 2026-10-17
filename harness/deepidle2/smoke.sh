#!/bin/bash
# deepidle2 smoke test, once, as root after boot: load the PMP driver, then run s2idle
# with pm_test=platform (devices suspend, the s2idle platform hooks run, nothing sleeps)
# three times and check that the PMP went IDLE and came back. Results are world-readable.
set -u
OUT=/var/lib/deepidle/results-deepidle2
mkdir -p $OUT; chmod 755 $OUT
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/smoke.log; }
rm -f /var/lib/deepidle/deepidle2-armed
log "booted $(uname -r), m1n1 $(cat /run/deepidle2-booted-sha 2>/dev/null)"
case "$(uname -r)" in *-deepidle2) ;; *) log "not the deepidle2 kernel: nothing to do"; exit 0 ;; esac
sleep 60
since=$(date '+%F %T')
timeout 120 modprobe pmp; log "modprobe pmp: exit $?"
sleep 30
ls /sys/bus/platform/drivers/apple_pmp/ > $OUT/pmp-bound.txt 2>&1
log "pmp bound: $(grep -c pmp $OUT/pmp-bound.txt); s2idle_idle=$(cat /sys/module/apple_pmp_sleep/parameters/s2idle_idle 2>&1)"
cat /sys/power/mem_sleep > $OUT/mem_sleep.txt
for i in 1 2 3; do
    echo platform > /sys/power/pm_test
    t0=$(date +%s.%N)
    echo freeze > /sys/power/state; rc=$?
    echo none > /sys/power/pm_test
    log "pm_test platform cycle $i: exit $rc, $(echo "$(date +%s.%N) - $t0" | bc) s"
    sleep 10
done
journalctl -k --since "$since" > $OUT/dmesg.txt
log "idle ok: $(grep -c 'PMP idle in' $OUT/dmesg.txt), awake ok: $(grep -c 'PMP awake in' $OUT/dmesg.txt), failures: $(grep -c -E 'apple-pmp-sleep: (idle|wake) failed|PMP firmware crashed' $OUT/dmesg.txt)"
grep -E "apple-pmp-sleep|pmp|rtkit" $OUT/dmesg.txt | tail -40 > $OUT/pmp-lines.txt
chmod -R a+r $OUT
log "done"
