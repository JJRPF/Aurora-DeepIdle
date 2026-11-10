#!/bin/bash
# R17A: run R17 (the full S2R entry with the PMGR commit, last run 2026-11-07, reset after 86 s) on the rebuilt chain,
# plus image 63's ATC step: aura-ctl 0xddb1f = R17's 0x1db1f | 0x80000 (atcN_pcie, atcN_common to target 0 before the
# commit, as macOS has them) | 0x40000 (the fabric write: no effect on AFNC1_LW2 in run A1; kept for its crumb,
# PMU scratch 0x600d = which fabric lanes read gated at the commit). Linux side as R17: deep_steps 62 (slpa, PMU 0x50, wake mask, PMP release), pmp_sleep,
# aop.sleep_ap_idle=3 (UKI cmdline), ISP_SYS released, PCPM0/1, afr kept, USB-C wakeup off + teardown, DCP firmware off.
# NOT self-contained after the suspend: slpa takes the SSD's controller down and the commit powers the SoC off.
# Outcomes: (a) reset about 86 s after the suspend (the S2R timer, as R17), (b) a real sleep the 30 s alarm ends,
# (c) a resume into this job (then it logs and pushes). After a reset main reads Aura's crumbs in the PMU scratch.
J=/run/usbtest/job; C=/proc/device-tree/chosen; R=/sys/class/rtc/rtc0; M=/sys/module
PUSH_TRIES=8
set1() { [ -e "$1" ] && echo "$2" > "$1"; printf '%s=%s ' "$(basename $1)" "$(cat $1 2>/dev/null || echo MISSING)"; }
w() { $J/mmio-read $1 1 2>/dev/null | awk '{print $2}'; }
atc() { for a in 278 288 298 2a8 228 230 238 240; do printf '%s ' "$(w 0x28e080$a)"; done; }
V=$(tr -d '\0' < $C/asahi,m1n1-stage2-version)
log "R17A kernel $(uname -r); stage2 $V; cmdline aop: $(grep -o 'aop.sleep_ap_idle=[0-9]*' /proc/cmdline || echo none)"
case "$V" in *a1215d2f*) ;; *) log "stage 2 is not image 63: stopping"; return 0 ;; esac
[ -e $R/wakealarm ] && grep -q deep /sys/power/mem_sleep || { log "no wakealarm or no deep, stopping"; return 0; }
grep -q 'aop.sleep_ap_idle=3' /proc/cmdline || { log "aop.sleep_ap_idle=3 not on the cmdline: stopping"; return 0; }
[ -e $M/appledrm/parameters/test_sleep_off ] || { log "appledrm has no test_sleep_off: stopping"; return 0; }
for dev in 702280000.usb b02280000.usb f02280000.usb; do
    for f in /sys/bus/platform/devices/$dev/power/wakeup /sys/bus/platform/devices/$dev/xhci-hcd.*/power/wakeup; do
        [ -e "$f" ] && echo disabled > "$f"
    done
done
echo deep > /sys/power/mem_sleep
S="$(set1 $M/apple_wdt/parameters/suspend_timeout 120)"
S="$S$(set1 $M/macsmc_reboot/parameters/deep_steps 62)$(set1 $M/macsmc/parameters/pmp_sleep 1)"
S="$S$(set1 $M/pmp_report/parameters/test_release_aon 1)$(set1 $M/pmp_report/parameters/test_release_ids 0x1000)"
S="$S$(set1 $M/pmp_report/parameters/test_pcpm 0x300)$(set1 $M/pmgr_pwrstate/parameters/test_sleep_keep afr)"
S="$S$(set1 $M/pm_genpd/parameters/test_dump Y)$(set1 $M/dwc3_apple/parameters/test_deep_teardown 1)"
S="$S$(set1 $M/appledrm/parameters/test_sleep_off 1)"
log "switches: $S"
case "$S" in *MISSING*) log "a switch is missing: stopping"; return 0 ;; esac
log "pmgr counters: $($J/pmgrcnt enable 2>&1 | tail -1)"
log "before: atc $(atc); pmp req $(w 0x28e3c2000) ack $(w 0x28e3c2080); usb $(lsusb 2>/dev/null | wc -l)"
CTL=$($J/aura-ctl 0xddb1f 0 0 2>&1 | tail -1); log "aura ctl: $CTL"
case "$CTL" in *ddb1f*) ;; *) log "aura-ctl did not read back 0xddb1f: stopping"; $J/aura-ctl 0 0 0 >/dev/null 2>&1; return 0 ;; esac
echo 0 > $R/wakealarm 2>/dev/null; echo +40 > $R/wakealarm
push "R17A committing" "suspend at $(date -u +%T) UTC, alarm +40 s. $S | $CTL"
T0=$(date +%s.%N)
log "echo mem at $(date -u +%T.%N | cut -c1-12) UTC"
echo mem > /sys/power/state; rc=$?
T1=$(date +%s.%N)
DUR=$(echo "$T1 $T0" | awk '{printf "%.1f", $1-$2}')
RES="R17A RESUMED INTO THE JOB: rc=$rc after $DUR s, online $(cat /sys/devices/system/cpu/online)
dbg: $($J/scan-magic 0xA0AA0001 64 2>&1 | head -1)
dbg2: $($J/scan-magic 0xA0AA0002 64 52 2>&1 | head -1)
counters: $($J/pmgrcnt show 2>&1 | tail -1)
atc after: $(atc)
pm lines: $(dmesg | grep -E 'PM: |TEST|macsmc' | tail -12 | cut -c1-120 | tr '\n' '|')"
log "$RES"
push "R17A resumed" "$RES"
$J/aura-ctl 0 0 0 > /dev/null 2>&1
