#!/bin/bash
# R58J-marks: r57y-netdiag2 + (1) push() that gives up at once on HTTP 429 (ntfy.sh daily cap hit at 08:28 on 2026-11-20 made the
#   old push retry 45 times per message and eat the run) and (2) 0x6004 cleared to 00 right before echo mem, so 0x22 afterwards means a wake.
#   Kernel: suspend_enter() marks at 0x6020=ee, 0x6021 = P (after noirq) B/C (around CPU offline) I/Y|X (syscore) E (enter) R (back).
# R57Y-netdiag2: r57x-netdiag with other diag bytes: 0x6008 port 1 (SD) LINKSTS, 0x6009 Wi-Fi PWREN (smc gpio-13) as debugfs shows it (1 hi, 0 lo, ff unknown), 0x600a AP gpio-4 (Wi-Fi reset) value (1 hi, 0 lo, ff unknown).
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
NTFY_DEAD=0
push() {  # R58J: one try per message while the network is up; HTTP 429 (daily cap) stops all further pushes
    local i c
    [ $NTFY_DEAD = 1 ] && { log "push skipped (ntfy cap): $1"; return 1; }
    for i in $(seq 1 20); do
        c=$(curl -sS -m 10 -o /dev/null -w "%{http_code}" -H "Title: $1" -H "Tags: test_tube" -d "$2" "https://ntfy.sh/$TOPIC" 2>/dev/null)
        case "$c" in 2*) return 0 ;; 429) NTFY_DEAD=1; log "push 429: ntfy cap, no more pushes"; return 1 ;; esac
        sleep 2
    done
    log "push failed: $1"; return 1
}
PUSH_TRIES=8
set1() { [ -e "$1" ] && echo "$2" > "$1"; printf '%s=%s ' "$(basename $1)" "$(cat $1 2>/dev/null || echo MISSING)"; }
w() { $J/mmio-read $1 1 2>/dev/null | awk '{print $2}'; }
atc() { for a in 278 288 298 2a8 228 230 238 240; do printf '%s ' "$(w 0x28e080$a)"; done; }
V=$(tr -d '\0' < $C/asahi,m1n1-stage2-version)
log "R57J kernel $(uname -r); stage2 $V; cmdline aop: $(grep -o 'aop.sleep_ap_idle=[0-9]*' /proc/cmdline || echo none)"
case "$V" in *86776585*|*4ad0e031*|*c9339c54*|*f943b89e*|*3c23b09b*|*7ebd699e*|*eecbb13d*|*3029e360*|*6861c027*|*568fd45a*|*b05607ab*|*60f4cbde*|*32a2d310*|*b23a4df6*|*3aa5ddf2*) ;; *) log "stage 2 is not image 105-108: stopping"; return 0 ;; esac
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
N0=$(ls /sys/bus/nvmem/devices/spmi_nvmem*/nvmem 2>/dev/null | head -1); [ -n "$N0" ] && printf '\x00' | dd of=$N0 bs=1 seek=$((0x6004)) conv=notrunc status=none
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
pb() { [ -w "$N" ] && printf "\\x$(printf '%02x' $(($2 & 0xff)))" | dd of="$N" bs=1 seek=$(($1)) count=1 conv=notrunc 2>/dev/null; }
# 0x6006: PCIe port 0 (Wi-Fi) LINKSTS low byte (bit 0 = link up)
LS=$($J/mmio-read 0x594008208 1 2>/dev/null | awk '{print $2}'); pb 0x6006 $(( ${LS:-0} & 0xff ))
# 0x6007: Wi-Fi config space vendor, live read: 1 = 14e4, 2 = ffff, 3 = other, 0 = no device
V=$(od -An -tx2 -N2 /sys/bus/pci/devices/0000:01:00.0/config 2>/dev/null | tr -d ' ')
case "$V" in 14e4) pb 0x6007 1;; ffff) pb 0x6007 2;; "") pb 0x6007 0;; *) pb 0x6007 3;; esac
# 0x6008: wlan0 operstate: 1 up, 2 down, 3 dormant, 4 other, 0 absent
OS=$(cat /sys/class/net/wlan0/operstate 2>/dev/null)
L1=$($J/mmio-read 0x595008208 1 2>/dev/null | awk '{print $2}'); pb 0x6008 $(( ${L1:-0} & 0xff ))
mount -t debugfs none /sys/kernel/debug 2>/dev/null
G=/sys/kernel/debug/gpio
PW=$(awk '/macsmc/{f=1} f && /gpio-13 /{print; exit}' $G 2>/dev/null)
case "$PW" in *" hi"*) pb 0x6009 1;; *" lo"*) pb 0x6009 0;; *) pb 0x6009 255;; esac
RS=$(awk '/39b028000/{f=1} /^gpiochip/ && !/39b028000/{f=0} f && /gpio-4 /{print; exit}' $G 2>/dev/null)
case "$RS" in *" hi"*) pb 0x600a 1;; *" lo"*) pb 0x600a 0;; *) pb 0x600a 255;; esac
# 0x6009: brcmf lines since the resume; 0x600a: DART / PCIe error lines since the resume
L0=$(dmesg | grep -n 'PM: suspend exit' | tail -1 | cut -d: -f1); L0=${L0:-1}
C1=$(dmesg | tail -n +$L0 | grep -c brcmf)
C2=$(dmesg | tail -n +$L0 | grep -ciE 'dart|NO PMD|pcie.*(err|fail|down)|AER')
pb 0x600b 1
PUSH_TRIES=6
if push "R57J resumed" "$RES | wifi: link=$LS vendor=$V oper=$OS brcmf=$C1 err=$C2 | $(dmesg | tail -n +$L0 | grep -iE 'brcmf|dart|pcie' | tail -6 | cut -c1-120 | tr '\n' '|')"; then
    pb 0x600b 4
else
    pb 0x600b 2
    for f in /sys/bus/pci/devices/0000:01:00.1 /sys/bus/pci/devices/0000:01:00.0; do [ -e $f/remove ] && echo 1 > $f/remove; done
    sleep 3; echo 1 > /sys/bus/pci/rescan; sleep 5; systemctl restart iwd 2>/dev/null
    OS2=$(cat /sys/class/net/wlan0/operstate 2>/dev/null)
    PUSH_TRIES=20
    push "R57J resumed (after Wi-Fi rescan)" "$RES | before: link=$LS vendor=$V oper=$OS brcmf=$C1 err=$C2; after rescan oper=$OS2 | $(dmesg | tail -n +$L0 | grep -iE 'brcmf|dart|pcie|iwd' | tail -8 | cut -c1-120 | tr '\n' '|')" && pb 0x600b 3
fi
$J/aura-ctl 0 0 0 > /dev/null 2>&1
