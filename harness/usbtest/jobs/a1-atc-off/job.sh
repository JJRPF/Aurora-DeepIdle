#!/bin/bash
# A1: Aura image 63's new step on the NORMAL path (no slpa, no S2R timer): PSCI_S2R_ATC (aura-ctl 0x80000) sets
# atcN_pcie and atcN_common to target 0 before the deep WFI and writes them back on resume. macOS has them off at
# sleep entry; our DT keeps them always-on. Questions: do the eight words reach actual 0, does the write hang
# anything, does the resume survive it, does USB-C come back.
# 1. One deep suspend with the step alone (alarm +20 s). 2. One with the fabric step too (0xc0000, image 62's, never run).
# Linux side as runs S5 to R17: USB-C wakeup off and the dwc3 cores stopped, so atcN_usb (children) are off first.
# A line is pushed before each suspend. Aura's cap (5 min) ends a sleep the alarm does not.
J=/run/usbtest/job; C=/proc/device-tree/chosen; R=/sys/class/rtc/rtc0
PUSH_TRIES=8
cnt() { grep macsmc-rtc /proc/interrupts | awk '{s=0; for(i=2;i<=11;i++) s+=$i; print s+0}'; }
w() { $J/mmio-read $1 1 2>/dev/null | awk '{print $2}'; }
atc() { for a in 278 288 298 2a8 228 230 238 240; do printf '%s ' "$(w 0x28e080$a)"; done; }
fab() { for a in 0x28e080210 0x290280178 0x290280418; do printf '%s ' "$(w $a)"; done; }
V=$(tr -d '\0' < $C/asahi,m1n1-stage2-version)
log "A1 kernel $(uname -r); stage2 $V; mem_sleep $(cat /sys/power/mem_sleep)"
case "$V" in *a1215d2f*) ;; *) log "stage 2 is not image 63 (a1215d2f): stopping"; return 0 ;; esac
[ -e $R/wakealarm ] || { log "no wakealarm, stopping"; return 0; }
grep -q deep /sys/power/mem_sleep || { log "no deep in mem_sleep, stopping"; return 0; }
log "before: atc pcie0-3 common0-3: $(atc); fabric: $(fab)"
log "usb: $(lsusb 2>/dev/null | wc -l) devices; typec: $(ls /sys/class/typec 2>/dev/null | tr '\n' ' ')"
for dev in 702280000.usb b02280000.usb f02280000.usb; do
    for f in /sys/bus/platform/devices/$dev/power/wakeup /sys/bus/platform/devices/$dev/xhci-hcd.*/power/wakeup; do
        [ -e "$f" ] && echo disabled > "$f" && log "wakeup off: ${f#/sys/bus/platform/devices/}"
    done
done
UT_P=/sys/module/dwc3_apple/parameters/test_deep_teardown; [ -e $UT_P ] && echo 1 > $UT_P
GD_P=/sys/module/pm_genpd/parameters/test_dump; [ -e $GD_P ] && echo Y > $GD_P
log "usb teardown: $(cat $UT_P 2>/dev/null || echo none); genpd dump: $(cat $GD_P 2>/dev/null || echo none)"
echo deep > /sys/power/mem_sleep
WDT_P=/sys/module/apple_wdt/parameters/suspend_timeout; [ -e $WDT_P ] && echo 120 > $WDT_P
susp() {  # susp <name> <aura-ctl steps>
    log "$1: set $($J/aura-ctl $2 0 0 2>&1 | tail -1)"
    echo 0 > $R/wakealarm 2>/dev/null; echo +20 > $R/wakealarm
    push "A1 $1" "$(tail -5 $LOG)"
    local t0=$(date +%s.%N) i0=$(cnt)
    echo mem > /sys/power/state; rc=$?
    local t1=$(date +%s.%N)
    DUR=$(echo "$t1 $t0" | awk '{printf "%.1f", $1-$2}')
    log "$1: rc=$rc, $DUR s, alarm irqs +$(( $(cnt) - i0 )), online $(cat /sys/devices/system/cpu/online)"
    log "$1: after: atc $(atc); fabric $(fab)"
    log "$1: aura dbg: $($J/scan-magic 0xA0AA0001 64 2>&1 | head -3 | tr '\n' ';')"
    log "$1: aura dbg2: $($J/scan-magic 0xA0AA0002 64 52 2>&1 | head -2 | tr '\n' ';')"
    log "$1: genpd: $(dmesg | grep 'genpd test syscore suspend' | tail -8 | grep -E 'domains on|held' | cut -c1-150 | tr '\n' '|')"
    log "$1: on at suspend, of ours: $(dmesg | grep 'genpd test syscore suspend:' | tail -3 | tr ' ' '\n' | grep -E '^(atc|apcie|afnc1_lw2|afnc2_lw1)' | tr '\n' ' ')"
    $J/aura-ctl 0 0 0 > /dev/null 2>&1
    sleep 8
    log "$1: usb after: $(lsusb 2>/dev/null | wc -l) devices; errors: $(dmesg -l err,crit,alert,emerg | wc -l) lines; last: $(dmesg -l err,crit,alert,emerg | tail -3 | cut -c1-110 | tr '\n' '|')"
    return $rc
}
susp "atc off" 0x80000 || { log "RESULT: suspend with the ATC step failed (rc $rc)"; return 0; }
log "RESULT: ATC step: back after $DUR s"
susp "atc + fabric" 0xc0000 || { log "RESULT: suspend with ATC + fabric failed (rc $rc)"; return 0; }
log "RESULT: ATC + fabric: back after $DUR s"
