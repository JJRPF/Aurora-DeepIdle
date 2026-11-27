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
[ -e $P/deadman_s ] && echo ${DEADMAN:-60} > $P/deadman_s && log "dead-man $(cat $P/deadman_s) s"
for drv in ${UNBIND:-}; do   # UNBIND="apple-sio rtkit-helper": drivers unbound before the run, to bisect
    for d in /sys/bus/*/drivers/$drv; do [ -d $d ] || continue
        for l in $d/*; do [ -L $l ] && [ -e $l/driver ] && echo "$(basename $l)" > $d/unbind && log "unbound $drv $(basename $l)"; done
    done
    done
echo 1 > $PM/pm_print_times; echo 1 > $PM/pm_debug_messages 2>/dev/null
WDT_P=/sys/module/apple_wdt/parameters/suspend_timeout; [ -e $WDT_P ] && echo 120 > $WDT_P
run_levels() {
    for lv in $LEVELS; do
        echo $lv > $PM/pm_test || { log "pm_test $lv rejected"; continue; }
        log "BEGIN level=$lv"; push "P1 BEGIN $lv" "$(tail -3 $LOG)"
        echo mem > $PM/state; rc=$?
        log "END level=$lv rc=$rc; online $(cat /sys/devices/system/cpu/online); $(dmesg | grep -E 'apple-sleep|dry run' | tail -2 | cut -c1-160 | tr '\n' '|')"
        sleep 3
    done
}
# MODULES="aurora snd_soc_macaudio hci_bcm4377": each is loaded in turn (modprobe pulls its dependencies) and the levels run after each,
# so a dead-man reset names the module whose presence makes the sleep hang. Empty: just the levels.
run_levels
for m in ${MODULES:-}; do
    modprobe $m && log "loaded $m ($(lsmod | wc -l) modules)" || { log "modprobe $m failed"; continue; }
    sleep 5; run_levels
    done
echo none > $PM/pm_test
log "P1 done; errors: $(dmesg -l err,crit,alert,emerg | wc -l); last: $(dmesg -l err,crit,alert,emerg | tail -3 | cut -c1-120 | tr '\n' '|')"
