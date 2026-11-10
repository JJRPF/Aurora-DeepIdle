#!/bin/bash
# K5: the alarm fix (rtc-macsmc clears the PMU control byte's "fired" latch, bit 1) and Aura's sleep cap.
# 1. Awake: two alarms, +6 s each; the macsmc-rtc interrupt count must go 0 -> 1 -> 2. If it does not, STOP: no suspend.
# 2. Cap test: one deep suspend with NO alarm and the cap at 1 heartbeat: Aura must resume by itself after about 60 s.
# 3. Three deep suspends woken by the alarm (+15 s), cap at Aura's default (5 heartbeats = 5 min).
# A line is pushed before every suspend, so a hang still leaves a report. Longest possible run: about 20 min.
J=/run/usbtest/job; C=/proc/device-tree/chosen; R=/sys/class/rtc/rtc0
NV=$(ls /sys/bus/spmi/devices/0-0b/spmi_nvmem*/nvmem 2>/dev/null | head -1)
reg() { dd if=$NV bs=1 skip=$(($1)) count=${2:-1} 2>/dev/null | xxd -p; }
cnt() { grep macsmc-rtc /proc/interrupts | awk '{s=0; for(i=2;i<=11;i++) s+=$i; print s+0}'; }
pmu() { echo "ctrl=$(reg 0x1401) ev=$(reg 0x14c0 2) irqs=$(cnt)"; }
PUSH_TRIES=8
log "K5 kernel $(uname -r); stage2 $(tr -d '\0' < $C/asahi,m1n1-stage2-version); mem_sleep $(cat /sys/power/mem_sleep); $(pmu)"
[ -e $R/wakealarm ] || { log "no wakealarm, stopping. dmesg: $(dmesg | grep -iE 'rtc|BTF|macsmc' | tail -8 | cut -c1-140 | tr '\n' '|')"; return 0; }
c0=$(cnt)
for n in 1 2; do
    echo 0 > $R/wakealarm 2>/dev/null; echo +6 > $R/wakealarm
    log "awake alarm $n armed: $(pmu)"
    sleep 9
    log "awake alarm $n +9 s: $(pmu)"
done
c2=$(cnt)
[ $((c2 - c0)) = 2 ] || { log "RESULT: awake alarms raised $((c2 - c0)) of 2 interrupts: alarm NOT fixed, no suspend"; return 0; }
log "RESULT: awake alarms 2 of 2 interrupts"
grep -q deep /sys/power/mem_sleep || { log "no deep in mem_sleep, stopping"; return 0; }
case "$(tr -d '\0' < $C/asahi,m1n1-stage2-version)" in *876622bf*) ;; *) log "stage 2 is not the capped Aura (876622bf): no suspend"; return 0 ;; esac
echo deep > /sys/power/mem_sleep
WDT_P=/sys/module/apple_wdt/parameters/suspend_timeout; [ -e $WDT_P ] && echo 120 > $WDT_P
susp() {  # susp <name> <alarm seconds or 0>
    echo 0 > $R/wakealarm 2>/dev/null; [ "$2" = 0 ] || echo "+$2" > $R/wakealarm
    log "$1: suspending ($([ "$2" = 0 ] && echo 'no alarm' || echo "alarm in $2 s"); $($J/aura-ctl 2>&1 | tail -1))"
    push "K5 $1" "$(tail -4 $LOG)"
    local t0=$(date +%s.%N) i0=$(cnt)
    echo mem > /sys/power/state; rc=$?
    local t1=$(date +%s.%N)
    DUR=$(echo "$t1 $t0" | awk '{printf "%.1f", $1-$2}')
    log "$1: rc=$rc, $DUR s, alarm irqs +$(( $(cnt) - i0 )), $(pmu), online $(cat /sys/devices/system/cpu/online), wake: $(dmesg | grep -iE 'PM: (suspend|resume)|wake' | tail -2 | cut -c1-80 | tr '\n' '|')"
    sleep 5
    return $rc
}
log "set cap 1: $($J/aura-ctl 0 0 1 2>&1 | tail -1)"
susp "cap test" 0 || { log "RESULT: cap test suspend failed"; return 0; }
log "RESULT: cap test resumed after $DUR s (expected about 60)"
log "set cap default: $($J/aura-ctl 0 0 0 2>&1 | tail -1)"
ok=0
for i in 1 2 3; do
    susp "cycle $i" 15 || break
    awk -v d=$DUR 'BEGIN{exit !(d < 40)}' && ok=$((ok + 1))
done
log "RESULT: alarm woke $ok of 3 deep suspends"
log "errors: $(dmesg -l err,crit,alert,emerg | wc -l) lines; last: $(dmesg -l err,crit,alert,emerg | tail -4 | cut -c1-100 | tr '\n' '|')"
