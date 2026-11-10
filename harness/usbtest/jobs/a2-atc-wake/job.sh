#!/bin/bash
# A2: why A1's two suspends ended after 3 s on the SMC line (865) and not on the 20 s alarm.
# Four deep suspends on the normal path, 20 s alarm each, one variable at a time:
#   1 base            aura-ctl 0,       USB untouched   (K5c: the alarm, about 20 s)
#   2 atc             aura-ctl 0x80000, USB untouched
#   3 usb             aura-ctl 0,       USB-C wakeup off + dwc3 teardown
#   4 usb + atc       aura-ctl 0x80000, the same        (A1's first suspend)
# One summary line per suspend is pushed at the end, and one line before each suspend.
J=/run/usbtest/job; C=/proc/device-tree/chosen; R=/sys/class/rtc/rtc0
PUSH_TRIES=8
cnt() { grep macsmc-rtc /proc/interrupts | awk '{s=0; for(i=2;i<=11;i++) s+=$i; print s+0}'; }
smc() { grep -E '2a2400000|smc' /proc/interrupts | awk '{s=0; for(i=2;i<=11;i++) s+=$i; t+=s} END{print t+0}'; }
w() { $J/mmio-read $1 1 2>/dev/null | awk '{print $2}'; }
atc() { for a in 278 288 298 2a8 228 230 238 240; do printf '%s ' "$(w 0x28e080$a)"; done; }
V=$(tr -d '\0' < $C/asahi,m1n1-stage2-version)
log "A2 kernel $(uname -r); stage2 $V"
case "$V" in *a1215d2f*) ;; *) log "stage 2 is not image 63: stopping"; return 0 ;; esac
[ -e $R/wakealarm ] && grep -q deep /sys/power/mem_sleep || { log "no wakealarm or no deep, stopping"; return 0; }
log "before: atc pcie0-3 common0-3: $(atc); usb $(lsusb 2>/dev/null | wc -l) devices"
echo deep > /sys/power/mem_sleep
WDT_P=/sys/module/apple_wdt/parameters/suspend_timeout; [ -e $WDT_P ] && echo 120 > $WDT_P
RES=""
susp() {  # susp <name> <aura-ctl steps>
    $J/aura-ctl $2 0 0 > /dev/null 2>&1
    echo 0 > $R/wakealarm 2>/dev/null; echo +20 > $R/wakealarm
    push "A2 $1" "suspending, aura-ctl $2"
    local t0=$(date +%s.%N) i0=$(cnt) s0=$(smc)
    echo mem > /sys/power/state; rc=$?
    local t1=$(date +%s.%N)
    DUR=$(echo "$t1 $t0" | awk '{printf "%.1f", $1-$2}')
    local d=$($J/scan-magic 0xA0AA0001 64 2>&1 | head -1)
    local line=$(( 0x$(echo $d | awk '{print $5}') )) ms=$(( 0x$(echo $d | awk '{print $6}') / 24000 )) to=$(echo $d | awk '{print $24}')
    local r="$1: rc=$rc ${DUR}s wake line $line after ${ms}ms in Aura, alarm irqs +$(( $(cnt) - i0 )), smc irqs +$(( $(smc) - s0 )), poll timeouts $to, atc after $(atc)"
    log "$r"; log "$1: dbg $d"
    log "$1: smc/usb lines: $(dmesg | tail -60 | grep -iE 'macsmc|tipd|typec|dwc3|xhci' | tail -5 | cut -c1-110 | tr '\n' '|')"
    RES="$RES$r
"
    $J/aura-ctl 0 0 0 > /dev/null 2>&1
    sleep 8
    return $rc
}
susp "1 base" 0 && susp "2 atc" 0x80000
for dev in 702280000.usb b02280000.usb f02280000.usb; do
    for f in /sys/bus/platform/devices/$dev/power/wakeup /sys/bus/platform/devices/$dev/xhci-hcd.*/power/wakeup; do
        [ -e "$f" ] && echo disabled > "$f"
    done
done
UT_P=/sys/module/dwc3_apple/parameters/test_deep_teardown; [ -e $UT_P ] && echo 1 > $UT_P
log "usb wakeup off, teardown $(cat $UT_P 2>/dev/null || echo none)"
susp "3 usb" 0 && susp "4 usb+atc" 0x80000
log "usb after: $(lsusb 2>/dev/null | wc -l) devices"
push "A2 results" "$RES"
log "RESULT: $(echo "$RES" | grep -c 'rc=0') of 4 suspends returned rc=0"
