#!/bin/bash
# R57W: copy of r57v with alarm +30 s and kernel.panic=27 (was 10 from the cmdline). The PMU reset stamp (0x1419 >> 15) minus the alarm (0x140c) was 10 s in R57V2: alarm + ~27 s now = a kernel panic right after the wake; still ~10 s = Aura stage 1 or something else.
# R57J: R57A with ramoops (the page reserved by reserve_mem (console log kept in RAM)) so the panic/oops after the wake can be read from main. Look at the "R57J ramoops" push, then read-phys.py 0x10790000000 on main.
# R57J: image 105 (exact R56C entry 0xc17dcb3f 0 0 0 241, alarm +25 s for fast resume iteration)
# + Aura resume fixes:
#   - restores all psci_force_ps_lower() domains parents-first in psci_quiesce_undo()
#   - cold-starts powered-off secondary CPUs via RVBAR + CPUSTART+4/+8 and psci_enter() in smp_secondary_entry()
# + PMU crumbs: 0x6004 steps 21 -> 23 -> 24 -> 25 -> 26 -> 27 -> 22;
#   userspace stamps 0x601f=0xaa, 0x6014=rc, 0x600c=nproc right after echo mem returns (visible even if PCIe/Wi-Fi is down)
# Outcomes after "R57J committing": "R57J resumed" or 0x601f=aa = LINUX RESUMED TO USERSPACE!;
# main boot ~+95..+110 s without 0x601f=aa = still stalled in kernel resume after 0x6004=0x26/27/22. Hold power only if dark > 6 min.
J=/run/usbtest/job; C=/proc/device-tree/chosen; R=/sys/class/rtc/rtc0; M=/sys/module
PUSH_TRIES=8
set1() { [ -e "$1" ] && echo "$2" > "$1"; printf '%s=%s ' "$(basename $1)" "$(cat $1 2>/dev/null || echo MISSING)"; }
w() { $J/mmio-read $1 1 2>/dev/null | awk '{print $2}'; }
atc() { for a in 278 288 298 2a8 228 230 238 240; do printf '%s ' "$(w 0x28e080$a)"; done; }
V=$(tr -d '\0' < $C/asahi,m1n1-stage2-version)
log "R57J kernel $(uname -r); stage2 $V; cmdline aop: $(grep -o 'aop.sleep_ap_idle=[0-9]*' /proc/cmdline || echo none)"
case "$V" in *86776585*|*4ad0e031*|*c9339c54*|*f943b89e*|*3c23b09b*|*7ebd699e*|*eecbb13d*) ;; *) log "stage 2 is not image 105-108: stopping"; return 0 ;; esac
[ -e $R/wakealarm ] && grep -q deep /sys/power/mem_sleep || { log "no wakealarm or no deep, stopping"; return 0; }
grep -q 'aop.sleep_ap_idle=3' /proc/cmdline || { log "aop.sleep_ap_idle=3 not on the cmdline: stopping"; return 0; }
[ -e $M/appledrm/parameters/test_sleep_off ] || { log "appledrm has no test_sleep_off: stopping"; return 0; }
# --- SIO axi2af tunables (macOS figs_1, T6020): offset clear set
AX=0x39a000000
AXB="afnc2 words before: $(for a in 0x290280160 0x290280168 0x290280170 0x290280178; do printf '%s ' "$(w $a)"; done)"
AXL=
for t in "0x0 0x3 0x1" "0xc 0xfffff 0xd" "0x10 0xfffff 0xc" "0x14 0xfff 0x1" "0x18 0xfff 0x1" "0x1c 0xfff 0x3" "0x20 0xfff 0x3" "0x24 0xfff 0x3" "0x28 0xfff 0x3" "0x2c 0xfff 0x3" \
         "0x108 0x3 0x1" "0x10c 0xfffff 0xd" "0x110 0xfffff 0xc" "0x114 0xfff 0x1" "0x118 0xfff 0x1" "0x11c 0xfff 0x3" "0x120 0xfff 0x3" "0x124 0xfff 0x3" "0x128 0xfff 0x3" "0x12c 0xfff 0x3" \
         "0x400 0xc00103ff 0xc0010010" "0xa00 0x1ffffff 0x1ffffff"; do
    set -- $t; a=$(printf '0x%x' $((AX+$1))); old=$(w $a)
    [ -n "$old" ] || { AXL="$AXL read-failed:$a"; continue; }
    new=$(printf '0x%x' $(( ((old & ~$2) | $3) & 0xffffffff )))
    $J/mmio-write $a $new >/dev/null 2>&1 || AXL="$AXL write-failed:$a"
    AXL="$AXL $1:$old>$(w $a)"
done
log "axi2af: $AXL"
log "$AXB; after: $(for a in 0x290280160 0x290280168 0x290280170 0x290280178; do printf '%s ' "$(w $a)"; done)"
push "R57J axi2af" "$AXL"
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
# Main, 2026-11-10 21:25: the enclave sets its own PS_AUTO. Idle it reads 0x1000030f (auto-enable, floor 0, gated);
# serving a request it raises the floor (0x1400034f) and drops back within 0.1 s; a periodic wake about every 60 s
# (0x1f0003ff). R18C sent SLEEP 9 s after the bind while the word still read 0x1f0002ff (busy since boot).
# So: wait for the idle word first (up to 90 s), then SLEEP, then check it is idle again before the commit.
SI=0; for i in $(seq 1 90); do case "$(w 0x290280c00)" in 0x100003?f) SI=$i; break ;; esac; sleep 1; done
RC=/sys/class/misc/hw_random/rng_current
RNG0=$(cat $RC 2>/dev/null); echo none > $RC 2>/dev/null; RNG1=$(cat $RC 2>/dev/null)
B="ps_sep before the driver $P0, idle after ${SI} s (0 = never): $(w 0x290280c00); rng_current $RNG0 -> $RNG1; panic=$(cat /proc/sys/kernel/panic); the SLEEP pass is next"
log "sep: $B"; push "R57J sep bound" "$B"
echo 2 > $SP/test_sleep_msg; echo N > $SP/test_sleep_psoff
echo freezer > /sys/power/pm_test
echo mem > /sys/power/state; frc=$?
PA=$(w 0x290280c00)
echo none > /sys/power/pm_test
echo 0 > $SP/test_sleep_msg
sleep 2
SEPL="freezer pass rc=$frc; ps_sep right after $PA, 2 s later $(w 0x290280c00); $(dmesg | grep -E 'TEST SLEEP|apple_sep.*(fail|error|timeout|warn)' | tail -4 | cut -c1-140 | tr '\n' '|'); the commit is next (Aura does the outbox and the word)"
log "sep: $SEPL"
push "R57J sep asleep" "$SEPL"
case "$SEPL" in *"TEST SLEEP type 2: reply"*) ;; *) log "the SLEEP got no reply: stopping"; return 0 ;; esac
# R18F to R18H: the outbox off and the word written from Linux hang the system within 10 s. Image 67 does both in
# Aura's quiet commit (aura-ctl bit 24, 0x1000000), after Linux is done. Here only the SLEEP, as R18C (which reached Aura).
for dev in 702280000.usb b02280000.usb f02280000.usb; do
    for f in /sys/bus/platform/devices/$dev/power/wakeup /sys/bus/platform/devices/$dev/xhci-hcd.*/power/wakeup; do
        [ -e "$f" ] && echo disabled > "$f"
    done
done
echo deep > /sys/power/mem_sleep
echo 27 > /proc/sys/kernel/panic
S="$(set1 $M/apple_wdt/parameters/suspend_timeout 120)"
S="$S$(set1 $M/macsmc_reboot/parameters/deep_steps 191)$(set1 $M/macsmc/parameters/pmp_sleep 1)"
S="$S$(set1 $M/pmp_report/parameters/test_release_aon 1)$(set1 $M/pmp_report/parameters/test_release_ids 0x1000)"
S="$S$(set1 $M/pmp_report/parameters/test_pcpm 0x300)$(set1 $M/pmgr_pwrstate/parameters/test_sleep_keep afr)"
S="$S$(set1 $M/pm_genpd/parameters/test_dump Y)$(set1 $M/dwc3_apple/parameters/test_deep_teardown 1)"
S="$S$(set1 $M/appledrm/parameters/test_sleep_off 1)"
log "switches: $S"
case "$S" in *MISSING*) log "a switch is missing: stopping"; return 0 ;; esac
log "pmgr counters: $($J/pmgrcnt enable 2>&1 | tail -1)"
log "before: atc $(atc); pmp req $(w 0x28e3c2000) ack $(w 0x28e3c2080); usb $(lsusb 2>/dev/null | wc -l)"
MM=$(find /sys/firmware/devicetree/base -name 'aura,psci-runtime-mmio' | head -1)
[ -n "$MM" ] || { log "no aura,psci-runtime-mmio in the device tree: stopping"; return 0; }
NR=$(( $(wc -c < "$MM") / 16 )); ED=$(od -An -v -tx1 -w16 "$MM" | tr -d ' ' | grep -c '^000000021[012][0-3]10000')
log "runtime mmio: $NR ranges, $ED external debug pages"
[ "$ED" -ge 10 ] || { log "the external debug pages are not in the runtime map: stopping"; return 0; }
CTL=$($J/aura-ctl 0xc17dcb3f 0 0 0 241 2>&1 | head -1); log "aura ctl: $CTL"
case "$CTL" in *c17dcb3f*) ;; *) log "aura-ctl did not read back 0xc17dcb3f: stopping"; $J/aura-ctl 0 0 0 >/dev/null 2>&1; return 0 ;; esac
# R57N: persistent trace ring buffer in the reserved RAM page (reserve_mem=1M:2M:oops + trace_instance=boot_map@oops on the UKI cmdline): power events recorded across the sleep, read from main afterwards (read-phys.py + strings)
TR=/sys/kernel/tracing/instances/boot_map
if [ -d $TR ]; then echo 0 > $TR/tracing_on; echo > $TR/trace; for e in power/device_pm_callback_start power/device_pm_callback_end power/suspend_resume; do echo 1 > $TR/events/$e/enable 2>/dev/null; done; echo 1 > $TR/tracing_on; fi
push "R57N trace" "instance: $([ -d $TR ] && echo yes || echo NO) on=$(cat $TR/tracing_on 2>&1) size=$(cat $TR/buffer_size_kb 2>&1 | head -1) events=$(grep -l 1 $TR/events/power/*/enable 2>/dev/null | wc -l); $(dmesg | grep -i 'reserve_mem\|boot_map\|persistent' | tail -3 | tr '\n' '|' | cut -c1-300); cmdline: $(cut -c1-200 /proc/cmdline)"
echo 0 > $R/wakealarm 2>/dev/null; echo +30 > $R/wakealarm
push "R57J committing" "suspend at $(date -u +%T) UTC, alarm +30 s, panic=$(cat /proc/sys/kernel/panic). $S | $CTL | mmio $NR ranges, $ED debug pages"
T0=$(date +%s.%N)
log "echo mem at $(date -u +%T.%N | cut -c1-12) UTC"
echo mem > /sys/power/state; rc=$?
N=$(ls /sys/bus/nvmem/devices/spmi_nvmem*/nvmem 2>/dev/null | head -1)
if [ -w "$N" ]; then
    printf '\xaa' | dd of="$N" bs=1 seek=$((0x601f)) count=1 conv=notrunc 2>/dev/null
    printf "\\x$(printf '%02x' $((rc & 0xff)))" | dd of="$N" bs=1 seek=$((0x6014)) count=1 conv=notrunc 2>/dev/null
    NCPU=$(nproc 2>/dev/null || echo 0)
    printf "\\x$(printf '%02x' $((NCPU & 0xff)))" | dd of="$N" bs=1 seek=$((0x600c)) count=1 conv=notrunc 2>/dev/null
fi
T1=$(date +%s.%N)
DUR=$(echo "$T1 $T0" | awk '{printf "%.1f", $1-$2}')
RES="R57J RESUMED INTO THE JOB: rc=$rc after $DUR s, online $(cat /sys/devices/system/cpu/online)
dbg: $($J/scan-magic 0xA0AA0001 64 2>&1 | head -1)
dbg2: $($J/scan-magic 0xA0AA0002 64 52 2>&1 | head -1)
counters: $($J/pmgrcnt show 2>&1 | tail -1)
atc after: $(atc)
pm lines: $(dmesg | grep -E 'PM: |TEST|macsmc' | tail -12 | cut -c1-120 | tr '\n' '|')"
log "$RES"
PUSH_TRIES=3
push "R57J resumed" "$RES"
$J/aura-ctl 0 0 0 > /dev/null 2>&1
