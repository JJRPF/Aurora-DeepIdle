#!/bin/bash
# C2: baseline PSCI SYSTEM_SUSPEND on the rebuilt chain, the old Phase 2 gate (image 48: 20 of 20): Aura's control
# word 0 (no S2R steps: the boot core waits in deep WFI with retention, SoC on), every CPU offlined by the kernel,
# woken by the PMU alarm. 3 cycles of `echo mem` with mem_sleep deep. Nothing is mounted from disk in this root.
J=/run/usbtest/job; C=/proc/device-tree/chosen
log "C2 kernel $(uname -r); stage2 $(tr -d '\0' < $C/asahi,m1n1-stage2-version); online $(cat /sys/devices/system/cpu/online); mem_sleep $(cat /sys/power/mem_sleep)"
R=/sys/class/rtc/rtc0
grep -q deep /sys/power/mem_sleep || { log "no deep in mem_sleep: not on the test chain, stopping"; return 0; }
[ -e $R/wakealarm ] || { log "no wakealarm: nothing would wake the Mac, stopping"; return 0; }
log "aura ctl: $($J/aura-ctl 2>&1 | tail -1)"
echo deep > /sys/power/mem_sleep
WDT_P=/sys/module/apple_wdt/parameters/suspend_timeout; [ -e $WDT_P ] && echo 120 > $WDT_P
for i in 1 2 3; do
    echo 0 > $R/wakealarm 2>/dev/null; echo +12 > $R/wakealarm
    t0=$(date +%s.%N); log "cycle $i: suspending, alarm in 12 s"
    echo mem > /sys/power/state; rc=$?
    t1=$(date +%s.%N)
    log "cycle $i: rc=$rc, $(echo "$t1 $t0" | awk '{printf "%.1f", $1-$2}') s, online $(cat /sys/devices/system/cpu/online), wake: $(dmesg | grep -iE 'PM: (suspend|resume)|wake' | tail -3 | cut -c1-90 | tr '\n' '|')"
    [ $rc = 0 ] || break
    sleep 5
done
log "errors: $(dmesg -l err,crit,alert,emerg | wc -l) lines; last: $(dmesg -l err,crit,alert,emerg | tail -5 | cut -c1-100 | tr '\n' '|')"
