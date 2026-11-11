#!/bin/bash
# R18C: R17D (aura-ctl 0x7dcb1f, image 65) + the SEP told to sleep before the commit (SLEEP control message, type 2;
# apple_sep.test_sleep_msg, patches/psci-efi/linux/test-sep-sleep-msg.diff), without R18B's mailbox and ps_sep writes.
# The driver is loaded with xart_writes=0 provision_keybag=0, so this boot never writes the shared xART store.
# The SLEEP runs in a freezer-only suspend pass (pm_test=freezer) so its result is pushed before the quiet commit.
# 0x1000 (WD1 off) is left out: WD1 (120 s from the suspend) is the net if the commit hangs.
# Outcomes after "R18C committing": (a) reset about 76 s later (the S2R timer, as R17), (b) a real sleep the 40 s alarm ends,
# (c) a resume into this job (then it logs and pushes), (d) reset about 35 s later = a kernel panic in the suspend path.
J=/run/usbtest/job; C=/proc/device-tree/chosen; R=/sys/class/rtc/rtc0; M=/sys/module
PUSH_TRIES=8
set1() { [ -e "$1" ] && echo "$2" > "$1"; printf '%s=%s ' "$(basename $1)" "$(cat $1 2>/dev/null || echo MISSING)"; }
w() { $J/mmio-read $1 1 2>/dev/null | awk '{print $2}'; }
atc() { for a in 278 288 298 2a8 228 230 238 240; do printf '%s ' "$(w 0x28e080$a)"; done; }
V=$(tr -d '\0' < $C/asahi,m1n1-stage2-version)
log "R18C kernel $(uname -r); stage2 $V; cmdline aop: $(grep -o 'aop.sleep_ap_idle=[0-9]*' /proc/cmdline || echo none)"
case "$V" in *b22c3766*) ;; *) log "stage 2 is not image 65: stopping"; return 0 ;; esac
[ -e $R/wakealarm ] && grep -q deep /sys/power/mem_sleep || { log "no wakealarm or no deep, stopping"; return 0; }
grep -q 'aop.sleep_ap_idle=3' /proc/cmdline || { log "aop.sleep_ap_idle=3 not on the cmdline: stopping"; return 0; }
[ -e $M/appledrm/parameters/test_sleep_off ] || { log "appledrm has no test_sleep_off: stopping"; return 0; }
# --- the SEP: load read-only, send SLEEP alone in a freezer-only pass, report, then go on
# R18B (SLEEP + OUTBOX_CTRL clear + ps_sep write) reset the Mac about 9 s after this pass began, kernel.panic=10: most
# likely a panic on a mailbox access after the enclave slept. S3: in this root ps_sep already reads 0x1000030f with the
# driver bound, so the write is not needed. Here: SLEEP only, nothing touches the mailbox afterwards, pushes before and after.
SP=$M/apple_sep/parameters; SB=/sys/bus/platform/drivers/apple_sep/396400000.sep
P0=$(w 0x290280c00)
[ -d $M/apple_sep ] || modprobe apple_sep xart_writes=0 provision_keybag=0 2>&1 | tail -1
[ -e $SP/test_sleep_msg ] || { log "apple_sep has no test_sleep_msg: stopping"; return 0; }
for i in $(seq 1 30); do [ -e $SB ] && break; sleep 1; done
[ -e $SB ] || { log "apple_sep did not bind: stopping"; return 0; }
sleep 6
RC=/sys/class/misc/hw_random/rng_current
RNG0=$(cat $RC 2>/dev/null); echo none > $RC 2>/dev/null; RNG1=$(cat $RC 2>/dev/null)
B="ps_sep before the driver $P0, bound $(w 0x290280c00); rng_current $RNG0 -> $RNG1; panic=$(cat /proc/sys/kernel/panic); the SLEEP pass is next"
log "sep: $B"; push "R18C sep bound" "$B"
echo 2 > $SP/test_sleep_msg; echo N > $SP/test_sleep_psoff
echo freezer > /sys/power/pm_test
echo mem > /sys/power/state; frc=$?
PA=$(w 0x290280c00)
echo none > /sys/power/pm_test
echo 0 > $SP/test_sleep_msg
sleep 2
SEPL="freezer pass rc=$frc; ps_sep right after $PA, 2 s later $(w 0x290280c00); $(dmesg | grep -E 'TEST SLEEP|apple_sep.*(fail|error|timeout|warn)' | tail -4 | cut -c1-140 | tr '\n' '|')"
log "sep: $SEPL"
push "R18C sep asleep" "$SEPL"
case "$SEPL" in *"TEST SLEEP type 2: reply"*) ;; *) log "the SLEEP got no reply: stopping"; return 0 ;; esac
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
CTL=$($J/aura-ctl 0x7dcb1f 0 0 2>&1 | tail -1); log "aura ctl: $CTL"
case "$CTL" in *7dcb1f*) ;; *) log "aura-ctl did not read back 0x7dcb1f: stopping"; $J/aura-ctl 0 0 0 >/dev/null 2>&1; return 0 ;; esac
echo 0 > $R/wakealarm 2>/dev/null; echo +40 > $R/wakealarm
push "R18C committing" "suspend at $(date -u +%T) UTC, alarm +40 s. $S | $CTL"
T0=$(date +%s.%N)
log "echo mem at $(date -u +%T.%N | cut -c1-12) UTC"
echo mem > /sys/power/state; rc=$?
T1=$(date +%s.%N)
DUR=$(echo "$T1 $T0" | awk '{printf "%.1f", $1-$2}')
RES="R18C RESUMED INTO THE JOB: rc=$rc after $DUR s, online $(cat /sys/devices/system/cpu/online)
dbg: $($J/scan-magic 0xA0AA0001 64 2>&1 | head -1)
dbg2: $($J/scan-magic 0xA0AA0002 64 52 2>&1 | head -1)
counters: $($J/pmgrcnt show 2>&1 | tail -1)
atc after: $(atc)
pm lines: $(dmesg | grep -E 'PM: |TEST|macsmc' | tail -12 | cut -c1-120 | tr '\n' '|')"
log "$RES"
push "R18C resumed" "$RES"
$J/aura-ctl 0 0 0 > /dev/null 2>&1
