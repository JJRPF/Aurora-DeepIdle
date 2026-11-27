#!/bin/bash
# P1: the sleep.c port's pm_test levels, in the RAM root (no desktop, no disk). A line is pushed BEFORE each level, so a hang still leaves the level it died in.
# LEVELS (default "devices platform processors core none") and SKIP (dbg_skip mask) come from /run/usbtest/job/env if present.
J=/run/usbtest/job; P=/sys/module/apple_sleep/parameters; PM=/sys/power
[ -f $J/env ] && . $J/env
LEVELS=${LEVELS:-devices platform processors core none}
PUSH_TRIES=8
log "P1 kernel $(uname -r); deep=$(cat $P/deep) untested_commit=$(cat $P/untested_commit); mem_sleep $(cat $PM/mem_sleep); LEVELS=$LEVELS SKIP=${SKIP:-0}"
grep -q deep $PM/mem_sleep || { log "no deep in mem_sleep, stopping"; return 0; }
echo deep > $PM/mem_sleep
echo 0 > $P/pmu_notes 2>/dev/null
[ -n "${SKIP:-}" ] && echo $SKIP > $P/dbg_skip
echo 1 > $PM/pm_print_times; echo 1 > $PM/pm_debug_messages 2>/dev/null
WDT_P=/sys/module/apple_wdt/parameters/suspend_timeout; [ -e $WDT_P ] && echo 120 > $WDT_P
for lv in $LEVELS; do
    echo $lv > $PM/pm_test || { log "pm_test $lv rejected"; continue; }
    log "BEGIN level=$lv"; push "P1 BEGIN $lv" "$(tail -3 $LOG)"
    echo mem > $PM/state; rc=$?
    log "END level=$lv rc=$rc; online $(cat /sys/devices/system/cpu/online); $(dmesg | grep -E 'apple-sleep|dry run' | tail -2 | cut -c1-160 | tr '\n' '|')"
    sleep 3
done
echo none > $PM/pm_test
log "P1 done; errors: $(dmesg -l err,crit,alert,emerg | wc -l); last: $(dmesg -l err,crit,alert,emerg | tail -3 | cut -c1-120 | tr '\n' '|')"
