#!/bin/bash
# R60O-railmap2: R60N (which stopped somewhere in its rail map, before the commit: 0x6004 = 0, no post-wake folder) with a
#   step crumb in PMU 0x6025 before each step (1 unbound, 2 base keys, 3 REG_ON off, 4 REG_ON on, 5 SD off, 6 SD on,
#   7 relink, 8 cfg, 9 past the map, 0x0a right before echo mem), and SD power cut only after REG_ON is back.
# R60N-railmap: r60m-nodrv + a rail map before the sleep. After the endpoint drivers are unbound, Wi-Fi REG_ON (gP0d)
#   and SD power (gP16) are switched off and back on through macsmc_reboot.smc_write (the macOS values: gP0d 0x00800000|v,
#   gP16 0|1), with a full SMC key dump at each step (smckeys-map-*.txt), so the rails/currents that follow each slot
#   (VR3l, IP0b/PP0b, IP8b/PP8b, ...) are known. Then the same sleep as R60M.
# R60M-nodrv: r60l without the pmVC loop, and brcmfmac / hci_bcm4377 / sdhci-pci unbound from 01:00.0, 01:00.1
#   and 02:00.0 right before echo mem (nekolyanich, 2026-11-21: with no drivers bound his Wi-Fi/BT/SD still answer
#   config reads after the native wake; ours read ffff). Config vendor/device of the three read right after echo mem
#   returns, and again after the relink work: /run/postwake/cfg.txt.
# R60L-pmvcmask: r60k without the apcie handshake (fifth word 241 again) + UKI pmp20 (macsmc_reboot.smc_write,
#   pcie_apple.s2r_redo): after the wake and the first relink, try pmVC masks (0x100 | CIO requesters) one at a time,
#   rerun the relink after each, record ports 0/1 LINKSTS. Stops at the first link up. Results in /run/postwake/pmvc.txt.
# R60K-apq: r60j + Aura image 125 psci_ctl[5] bit 8 (fifth word 241 -> 497): the t6000 apcie quiesce handshake from
#   Andreas Fernandez's t600x-s2r-reference (0x59c008014 = 1, 0x59c0082bc = 1, 2, 4; put back at the wake). Crumbs 0x6025..27.
# R60J-nostage: r60i with deep_steps 183 (191 without bit 8: no PMU boot_stage 0x50 across the sleep; the SMC MBSE low byte follows boot_stage), and the PMU dumps read in 16-byte blocks so one bad register does not lose the page, see R60J.
# R60A-postwake: r59z-phy (no PWREN cycle) + the PMU before/after and the full post-wake log written to main's /boot/deeptest/postwake/.
# R59Z-phy: r59y-ltssm with a 1 s PWREN cycle and port 0's root-port PHY words in the text bytes, see R59Z.
# R59Y-ltssm: r59x-regon with port 0's LTSSM state after the work in the text bytes, see R59Y.
# R59X-regon: r59w-perst with REG_ON (gP0d) around the sleep and the CLKREQ# pins, see R59X.
# R59W-perst: r59v-wifiretry with PERST#'s pin state in the bytes, see R59W.
# R59V-wifiretry: r59t-locknak with the Wi-Fi port retries and the SMC wake reply in the text bytes, see R59V.
# R59T-locknak: r59s-usberr2 with the pipehandler registers at the first lock NAK in the text bytes, see R59T.
# R59S-usberr2: r59q-usberr preferring the resume half, see the R59S block.
# R59Q-usberr: r58x-nvme2 with the text bytes (0x6011..17, 0x6019, 0x601d, 0x601e) = the first USB error line after the deep entry:
#   char 0 class (p phy/atcphy, t tipd/cd321x, x xhci, d dwc3, u other usb), chars 1..3 its errno digits or ---, chars 4..9 the message start, spaces removed.
# R58X-nvme2: r58v-nvme with 0x6007 = which nvme-apple reset step failed (see the R58X block).
# R58V-nvme: r58u-health + NVMe detail in 0x6007, USB counts after/before in 0x6009/0x600a.
# R58U-health: r58r-wifi + a device health bitmap in 0x6006 after the wake (see the H block).
# R58R-wifi: r58j-marks waiting for the pcie-apple S2R work before sampling (0x600d flags, 0x600e wait), no own rescan.
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
log() { echo "$(date '+%F %T') $*" | tee -a /run/usbtest/run.log; echo "usbtest-run: $*" > /dev/kmsg; curl -sS -m 2 -o /dev/null -H "Title: log" --data-binary "$*" http://192.168.1.112:8765/ 2>/dev/null; }
# R60I: nonzero words of the internal apcie blocks Linux maps (all read safely on main, 2026-11-21)
regdump() {
    for r in 0x591000000:0x100 0x594008000:0x300 0x595008000:0x300 0x59e000000:0x40 0x59e004000:0x40 0x59e008000:0x40 0x59e00c000:0x40 0x59e010000:0x40 0x59c000400:1; do
        $J/mmio-read ${r%%:*} ${r##*:} 2>&1 | awk '$2!="0x00000000"'
    done > "$1"
}
push() {  # R58J: one try per message while the network is up; HTTP 429 (daily cap) stops all further pushes
    local i c
    # R58N: the LAN log sink on the Pi first (main reads it with pi-ssh), then ntfy.sh unless capped
    curl -sS -m 4 -o /dev/null -H "Title: $1" --data-binary "$2" http://192.168.1.112:8765/ 2>/dev/null
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
case "$V" in *86776585*|*4ad0e031*|*c9339c54*|*f943b89e*|*3c23b09b*|*7ebd699e*|*eecbb13d*|*3029e360*|*6861c027*|*568fd45a*|*b05607ab*|*60f4cbde*|*32a2d310*|*b23a4df6*|*3aa5ddf2*|*c700f8bf*|*41dea591*|*6aed97c5*) ;; *) log "stage 2 is not image 105-108: stopping"; return 0 ;; esac
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
S="$S$(set1 $M/macsmc_reboot/parameters/deep_steps 183)$(set1 $M/macsmc/parameters/pmp_sleep 1)$(set1 $M/macsmc/parameters/pmp_cycle 1)"
S="$S$(set1 $M/pmp_report/parameters/test_release_aon 1)$(set1 $M/pmp_report/parameters/test_release_ids 0x1000)"
S="$S$(set1 $M/pmp_report/parameters/test_pcpm 0x300)$(set1 $M/pmgr_pwrstate/parameters/test_sleep_keep afr,gpio)"
S="$S$(set1 $M/pm_genpd/parameters/test_dump Y)$(set1 $M/dwc3_apple/parameters/test_deep_teardown 1)"
S="$S$(set1 $M/appledrm/parameters/test_sleep_off 1)"
S="$S$(set1 $M/macsmc_reboot/parameters/s2r_pmvc 0x100)"  # R60H
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
[ -n "$N0" ] && printf '\x00\x00\x00' | dd of=$N0 bs=1 seek=$((0x6025)) conv=notrunc status=none  # R60K
log "gpio ps $(w 0x28e080120)"; push "dmesg before echo mem" "$(dmesg | tail -60)"
USB0=$(lsusb 2>/dev/null | wc -l)
T0=$(date +%s.%N)
log "echo mem at $(date -u +%T.%N | cut -c1-12) UTC"
# R60A: the PMU's whole register file (64 KiB over SPMI) just before the sleep, kept in RAM, for a before/after comparison
PMUN=/sys/bus/spmi/devices/0-0b/spmi_nvmem2/nvmem; mkdir -p /run/postwake
dd if=$PMUN of=/run/postwake/pmu-pre.bin bs=16 count=768 conv=noerror,sync status=none 2>/run/postwake/pmu-pre.err
regdump /run/postwake/regs-pre.txt  # R60I
cat /sys/kernel/debug/gpio > /run/postwake/gpio-pre.txt 2>/dev/null; lspci -vv > /run/postwake/lspci-pre.txt 2>&1
# R60M: unbind the endpoint drivers (devices stay, only their drivers' suspend path is taken out)
cfg() { for b in 0000:01:00.0 0000:01:00.1 0000:02:00.0; do echo "$1 $b $(od -An -tx4 -N8 /sys/bus/pci/devices/$b/config 2>&1 | tr -s ' ') drv=$(basename $(readlink /sys/bus/pci/devices/$b/driver 2>/dev/null) 2>/dev/null)"; done >> /run/postwake/cfg.txt; }
cfg pre-unbind
for b in 0000:01:00.0 0000:01:00.1 0000:02:00.0; do [ -e /sys/bus/pci/devices/$b/driver ] && echo $b > /sys/bus/pci/devices/$b/driver/unbind; done
sleep 1; cfg post-unbind; log "R60M unbound: $(tr '\n' '|' < /run/postwake/cfg.txt | cut -c1-600)"
# R60N/R60O: rail map (devices unbound; nothing touches them meanwhile); R60O: step crumbs in PMU 0x6025
crumb() { [ -n "$N0" ] && printf "\\x$1" | dd of=$N0 bs=1 seek=$((0x6025)) conv=notrunc status=none; }
SW=/sys/module/macsmc_reboot/parameters/smc_write
kd() { cat /sys/kernel/debug/macsmc_keys > /run/postwake/smckeys-map-$1.txt 2>/dev/null; }
crumb 01; crumb 02; kd 0-base
crumb 03; echo "gP0d=0x00800000" > $SW; sleep 2; kd 1-regon-off
crumb 04; echo "gP0d=0x00800001" > $SW; sleep 2; kd 2-regon-on
crumb 05; echo "gP16=0x0" > $SW; sleep 2; kd 3-sd-off
crumb 06; echo "gP16=0x1" > $SW; sleep 2; kd 4-sd-on
log "R60N rail map done: $(dmesg | grep 'TEST smc_write' | tail -4 | tr '\n' '|' | cut -c1-600)"
crumb 07; echo 1 > /sys/module/pcie_apple/parameters/s2r_redo 2>/dev/null; sleep 3
crumb 08; cfg after-map
crumb 09
cat /sys/kernel/debug/macsmc_keys > /run/postwake/smckeys-pre.txt 2>/run/postwake/smckeys-pre.err  # R60D
crumb 0a; echo mem > /sys/power/state; rc=$?
cfg wake-0s  # R60M
cat /sys/kernel/debug/macsmc_keys > /run/postwake/smckeys-wake.txt 2>/run/postwake/smckeys-wake.err  # R60D: right after the wake
N=$(ls /sys/bus/nvmem/devices/spmi_nvmem*/nvmem 2>/dev/null | head -1)
if [ -w "$N" ]; then
    printf '\xaa' | dd of="$N" bs=1 seek=$((0x601f)) count=1 conv=notrunc 2>/dev/null
    printf "\\x$(printf '%02x' $((rc & 0xff)))" | dd of="$N" bs=1 seek=$((0x6014)) count=1 conv=notrunc 2>/dev/null
    NCPU=$(nproc 2>/dev/null || echo 0)
    printf "\\x$(printf '%02x' $((NCPU & 0xff)))" | dd of="$N" bs=1 seek=$((0x600c)) count=1 conv=notrunc 2>/dev/null
fi
# R58R: wait for the pcie-apple S2R work (1.5 s after resume) and its rescan, then summarise into 0x600d (flags) and 0x600e (s waited):
# bit0 "lost its link" seen, bit1 "link up after resume", bit2 "link down after resume", bit3 rescan done, bit4 power-on failed,
# bit5 wlan0 present, bit6 config vendor 14e4, bit7 "ready wait timeout". R58S: the flags go to 0x6008 (0x600d/e do not survive the reset)
pb() { [ -w "$N" ] && printf "\\x$(printf '%02x' $(($2 & 0xff)))" | dd of="$N" bs=1 seek=$(($1)) count=1 conv=notrunc 2>/dev/null; }
wf() { local f=0 d; d=$(dmesg | tail -n +$(dmesg | grep -n 'PM: suspend exit' | tail -1 | cut -d: -f1)); 
  case "$d" in *"lost its link"*) f=$((f|1));; esac; case "$d" in *"link up after resume"*) f=$((f|2));; esac
  case "$d" in *"still down after resume"*) f=$((f|4));; esac; case "$d" in *"rescanning after the S2R"*) f=$((f|8));; esac
  case "$d" in *"power-on after resume failed"*) f=$((f|16));; esac; [ -e /sys/class/net/wlan0 ] && f=$((f|32))
  [ "$(od -An -tx2 -N2 /sys/bus/pci/devices/0000:01:00.0/config 2>/dev/null | tr -d ' ')" = 14e4 ] && f=$((f|64))
  case "$d" in *"ready wait timeout"*) f=$((f|128));; esac; echo $f; }
for WS in $(seq 1 40); do sleep 1; WF=$(wf); pb 0x600d $WF; pb 0x600e $WS; [ $((WF & 8)) = 8 ] && [ $((WF & 32)) = 32 ] && break; done
sleep 8; systemctl restart iwd 2>/dev/null; sleep 10; WF=$(wf); pb 0x600d $WF; R58S_WF=$WF
cfg after-relink; log "R60M cfg: $(grep -E 'wake-0s|after-relink' /run/postwake/cfg.txt | tr '\n' '|' | cut -c1-700)"  # R60M
# R58U: device health after the wake into 0x6006 (survives the reset): bit0 NVMe live + 64 KiB direct read of nvme0n1 (read-only),
# bit1 as many USB devices as before, bit2 internal keyboard input device, bit3 battery capacity readable (SMC), bit4 RTC readable,
# bit5 no apple_sep error/timeout line after the wake, bit6 no "timed out" line after the wake, bit7 no WARNING/BUG/Oops after the wake
DA=$(dmesg | tail -n +$(dmesg | grep -n 'PM: suspend entry (deep)' | tail -1 | cut -d: -f1))  # R58Z: from the deep entry, so the resume-time resets are in
H=0
[ "$(cat /sys/class/nvme/nvme0/state 2>/dev/null)" = live ] && timeout 10 dd if=/dev/nvme0n1 of=/dev/null bs=4k count=16 iflag=direct 2>/dev/null && H=$((H|1))
[ "$(lsusb 2>/dev/null | wc -l)" -ge "${USB0:-99}" ] && H=$((H|2))
grep -qi "keyboard" /proc/bus/input/devices 2>/dev/null && H=$((H|4))
[ -n "$(timeout 5 cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1)" ] && H=$((H|8))
[ -n "$(timeout 5 cat /sys/class/rtc/rtc0/time 2>/dev/null)" ] && H=$((H|16))
echo "$DA" | grep -qiE 'apple_sep.*(err|fail|timeout|timed out)' || H=$((H|32))
echo "$DA" | grep -qi 'timed out' || H=$((H|64))
echo "$DA" | grep -qE 'WARNING:|BUG:|Oops' || H=$((H|128))
# R58V: NVMe and USB detail. 0x6007 = NVMe: bits 0-2 state (1 live, 2 resetting, 3 connecting, 4 dead, 5 deleting, 6 other, 0 absent),
# bit3 direct read ok, bit4 a dmesg line after the wake matching apple.nvme/nvme.*(fail|error|timeout|abort|reset), bit5 rtkit/crash/SART line,
# bit6 nvme0n1 block device present, bit7 controller reset seen ("resetting controller"). 0x6009 = USB devices after, 0x600a = before.
NS=$(cat /sys/class/nvme/nvme0/state 2>/dev/null)
case "$NS" in live) NV=1;; resetting) NV=2;; connecting) NV=3;; dead) NV=4;; deleting*) NV=5;; "") NV=0;; *) NV=6;; esac
timeout 10 dd if=/dev/nvme0n1 of=/dev/null bs=4k count=16 iflag=direct 2>/dev/null && NV=$((NV|8))
echo "$DA" | grep -qiE '(apple.nvme|nvme).*(fail|error|timeout|abort|reset)' && NV=$((NV|16))
echo "$DA" | grep -qiE 'rtkit|crash|sart' && NV=$((NV|32))
[ -b /dev/nvme0n1 ] && NV=$((NV|64))
echo "$DA" | grep -qi 'resetting controller' && NV=$((NV|128))
USB1=$(lsusb 2>/dev/null | wc -l)
# R58X: which nvme-apple reset step fails, into 0x6007 instead: bit0 "RTKit has crashed", bit1 "ANS did not boot", bit2 "ANS did not
# initialize", bit3 "Reset failure status", bit4 "TEST iorvbar: was" (restored), bit5 "TEST iorvbar: kept", bit6 an apple-rtkit/rtkit line
# with timeout/fail/error, bit7 nvme0 still present (state file exists)
NV=0
echo "$DA" | grep -q 'RTKit has crashed' && NV=$((NV|1))
echo "$DA" | grep -q 'ANS did not boot' && NV=$((NV|2))
echo "$DA" | grep -q 'ANS did not initialize' && NV=$((NV|4))
echo "$DA" | grep -q 'Reset failure status' && NV=$((NV|8))
# R59G: bit4 = ANS tunables rewritten (N > 0), bit5 = none published by Aura
echo "$DA" | grep -qE 'ANS tunables [1-9][0-9]* of' && NV=$((NV|16))
dmesg | grep -qE 'TEST s2r: [1-9][0-9]* ANS tunable writes' || NV=$((NV|32))
echo "$DA" | grep -iE 'rtkit' | grep -qiE 'timeout|timed out|fail|error' && NV=$((NV|64))
[ -e /sys/class/nvme/nvme0/state ] && NV=$((NV|128))
# R58Y: 0x6009 = low byte of the CPU_CONTROL value the patched driver logs at resume ("TEST s2r: cpu_control 0x.."), ee = no such line
CC=$(echo "$DA" | grep -o "TEST s2r: cpu_control 0x[0-9a-f]*" | tail -1 | grep -o "0x[0-9a-f]*$"); USB1=$(( ${CC:-0xee} & 0xff ))
# R59B: the NVMe power chain after the wake, actual-state nibbles (f = on): 0x6009 = ans2<<4 | afnc6_lw0, 0x600b = apcie_st_sys<<4 | apcie_st1_sys
an() { echo $(( ($($J/mmio-read $1 1 2>/dev/null | awk '{print $2}') >> 4) & 0xf )); }
R59B_A=$(( ($(an 0x2902801a8) << 4) | $(an 0x290280158) )); R59B_B=$(( ($(an 0x290280408) << 4) | $(an 0x290280410) ))
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
LS=$($J/mmio-read 0x594008208 1 2>/dev/null | awk '{print $2}'); pb 0x6006 $H
# 0x6007: Wi-Fi config space vendor, live read: 1 = 14e4, 2 = ffff, 3 = other, 0 = no device
V=$(od -An -tx2 -N2 /sys/bus/pci/devices/0000:01:00.0/config 2>/dev/null | tr -d ' ')
pb 0x6007 $NV
# 0x6008: wlan0 operstate: 1 up, 2 down, 3 dormant, 4 other, 0 absent
OS=$(cat /sys/class/net/wlan0/operstate 2>/dev/null)
: # R58Z2: 0x6008 is Aura image 123s (domains re-powered)
mount -t debugfs none /sys/kernel/debug 2>/dev/null
G=/sys/kernel/debug/gpio
PW=$(awk '/macsmc/{f=1} f && /gpio-13 /{print; exit}' $G 2>/dev/null)
# R59C: 0x6009 = the ANS RTKit stage after the wake (nvme-apple lines only): bit0 "RTKit: Initializing" (HELLO answered),
# bit1 "endpoint discovery failed", bit2 "IOP power acknowledgment failed", bit3 "co-processor has crashed", bit4 an RTKit syslog line,
# bit5 "early AP readiness failed", bit6 "TEST s2r: cpu_control", bit7 two or more "RTKit: Initializing"
NA=$(echo "$DA" | grep -i "nvme"); RK=0
echo "$NA" | grep -q "RTKit: Initializing" && RK=$((RK|1)); echo "$NA" | grep -q "endpoint discovery failed" && RK=$((RK|2))
echo "$NA" | grep -q "IOP power acknowledgment failed" && RK=$((RK|4)); echo "$NA" | grep -q "co-processor has crashed" && RK=$((RK|8))
echo "$NA" | grep -q "RTKit: syslog message" && RK=$((RK|16)); echo "$NA" | grep -q "reinit with buffers kept: 0" && RK=$((RK|32))  # R59K (was early AP readiness)
# R59F: bit6 "IOP power ack came after" (the long wait worked), bit7 "TEST s2r: sart power 0x0," (the cut cleared it)
echo "$NA" | grep -q "IOP power ack came after" && RK=$((RK|64)); echo "$NA" | grep -q "TEST s2r: sart power 0x0," && RK=$((RK|128))
# R59N: 0x6009 = USB after the wake (NVMe now works): bit0 "core stopped for deep suspend", bit1 "core restarted after deep
# suspend (role N): 0", bit2 the same with an error, bit3 an atcphy/phy error line, bit4 a tipd/cd321x/tps6598x error line, bit5
# "HC died" or xhci error, bit6 a root hub present after the wake, bit7 any other usb "error|fail" line
UA=$(echo "$DA" | grep -iE "usb|dwc3|xhci|phy|tipd|tps6598|cd321"); UB=0
echo "$UA" | grep -q "core stopped for deep suspend" && UB=$((UB|1))
echo "$UA" | grep -qE "core restarted after deep suspend \(role [0-9]+\): 0$" && UB=$((UB|2))
echo "$UA" | grep -qE "core restarted after deep suspend \(role [0-9]+\): -" && UB=$((UB|4))
echo "$UA" | grep -iE "atcphy|phy" | grep -qiE "err|fail|timeout" && UB=$((UB|8))
echo "$UA" | grep -iE "tipd|tps6598|cd321" | grep -qiE "err|fail|timeout" && UB=$((UB|16))
echo "$UA" | grep -qiE "HC died|xhci.*(err|fail)" && UB=$((UB|32))
lsusb 2>/dev/null | grep -q "root hub" && UB=$((UB|64))
echo "$UA" | grep -iE "usb" | grep -qiE "error|fail" && UB=$((UB|128))
pb 0x6009 $UB
RS=$(awk '/39b028000/{f=1} /^gpiochip/ && !/39b028000/{f=0} f && /gpio-4 /{print; exit}' $G 2>/dev/null)
pb 0x600a ${R58S_WF:-0}  # R59M: the pcie-apple S2R flags (r58r-wifi bits) in 0x600a; Aura's "still off" count is known (8)
# 0x6009: brcmf lines since the resume; 0x600a: DART / PCIe error lines since the resume
L0=$(dmesg | grep -n 'PM: suspend exit' | tail -1 | cut -d: -f1); L0=${L0:-1}
C1=$(dmesg | tail -n +$L0 | grep -c brcmf)
C2=$(dmesg | tail -n +$L0 | grep -ciE 'dart|NO PMD|pcie.*(err|fail|down)|AER')
pb 0x600b 1
PUSH_TRIES=6
APQ=$(dd if=$N bs=1 skip=$((0x6025)) count=3 status=none | od -An -tx1 | tr -s " "); log "R60K apq crumbs 6025..27:$APQ"; echo "$APQ" > /run/postwake/apq.txt 2>/dev/null
push "R60K apq" "6025..27:$APQ (6025 bit0 range ok, bit1 done, bit2 restored; 26 saved, 27 at wake: 8014 low nibble, 82bc high)"
push "R60J" "$(dmesg | grep -E 'TEST s2r: (SMC gP|pmVC|.*MEPS)|port .*(lost|link)' | sed 's/^\[[^]]*\] *//' | cut -c1-150 | tr '\n' '|' | cut -c1-1500)"
if push "R57J resumed" "$RES | wifi: link=$LS vendor=$V oper=$OS brcmf=$C1 err=$C2 | $(dmesg | tail -n +$L0 | grep -iE 'brcmf|dart|pcie' | tail -6 | cut -c1-120 | tr '\n' '|')"; then
    pb 0x600b 4
else
    pb 0x600b 2
    sleep 10
    OS2=$(cat /sys/class/net/wlan0/operstate 2>/dev/null)
    PUSH_TRIES=20
    push "R57J resumed (after Wi-Fi rescan)" "$RES | before: link=$LS vendor=$V oper=$OS brcmf=$C1 err=$C2; after rescan oper=$OS2 | $(dmesg | tail -n +$L0 | grep -iE 'brcmf|dart|pcie|iwd' | tail -8 | cut -c1-120 | tr '\n' '|')" && pb 0x600b 3
fi
# R59D/E: 0x600b = the PMP after the wake and a recovery try. bit0 apple_pmp "RTKit: Initializing" after the deep entry, bit1 "PMP firmware
# and endpoint ready" after it, bit2 "PMP firmware crashed", bit3 a PMP request "did not complete" or "Unexpected PMP device-state reply",
# then: unbind + bind apple_pmp, unbind + bind nvme-apple: bit4 a new "endpoint ready" after the rebind, bit5 nvme0 live afterwards,
# bit6 a 64 KiB direct read of nvme0n1 works afterwards, bit7 the nvme rebind printed "RTKit: Initializing" again
PA=$(echo "$DA" | grep "apple_pmp"); PM=0
echo "$PA" | grep -q "RTKit: Initializing" && PM=$((PM|1)); echo "$PA" | grep -q "endpoint ready" && PM=$((PM|2))
echo "$PA" | grep -q "firmware crashed" && PM=$((PM|4)); echo "$PA" | grep -qE "did not complete|Unexpected PMP device-state" && PM=$((PM|8))
pb 0x600b $PM
# R59E: bits 4..7 now the PMP power cycle (macsmc.pmp_cycle): bit4 "power cycle for system sleep" at probe, bit5 "PMP stopped,
# SRAM saved: 0", bit6 "PMP restarted: 0", bit7 "no boot after sleep"
dmesg | grep -q "power cycle for system sleep" && PM=$((PM|16))
echo "$DA" | grep -q "PMP stopped, SRAM saved: 0" && PM=$((PM|32))
echo "$DA" | grep -q "PMP restarted: 0" && PM=$((PM|64))
echo "$DA" | grep -q "no boot after sleep" && PM=$((PM|128))
pb 0x600b $PM
timeout 30 sh -c "echo 34bcc0000.nvme > $D/nvme-apple/unbind" 2>/dev/null; sleep 1
timeout 60 sh -c "echo 34bcc0000.nvme > $D/nvme-apple/bind" 2>/dev/null; sleep 8
[ "$(cat /sys/class/nvme/nvme0/state 2>/dev/null)" = live ] && PM=$((PM|32))
timeout 10 dd if=/dev/nvme0n1 of=/dev/null bs=4k count=16 iflag=direct 2>/dev/null && PM=$((PM|64))
[ "$(dmesg | grep "nvme" | grep -c "RTKit: Initializing")" -gt "$N0" ] && PM=$((PM|128))
pb 0x600b $PM
# R59I: the first 11 characters of the ANS RTKit crash message ("RTKit: Message (id=..): <text>", "panic: " stripped) into the
# bytes that survive the reset and are free after the wake: 0x6011..0x6019, 0x601d, 0x601e (read back with tools/panic-trace.py MODE=text)
CM=$(echo "$DA" | grep "nvme" | grep -o "RTKit: Message (id=[0-9a-f]*): .*" | tail -1 | sed 's/^RTKit: Message (id=[0-9a-f]*): //; s/^panic: //')
# R59J: else the last ANS RTKit syslog line's text (after "syslog message: <ctx>: "), with a leading '~'; else "none"
[ -z "$CM" ] && CM=$(echo "$DA" | grep "nvme" | grep -o "RTKit: syslog message: .*" | tail -1 | sed 's/^RTKit: syslog message: [^ ]*: /~/')
[ -z "$CM" ] && CM="none"
# R59S: the first USB error line of the resume half (after "Enabling non-boot CPUs"), else of the suspend half:
#   char 0 class (p phy, t tipd/cd321x, x xhci, d dwc3, u other), char 1 half (r resume, s suspend), chars 2..3 the last two errno
#   digits or --, chars 4..9 the message with its device prefix and a leading "Failed to "/"failed to " removed, spaces removed.
RL=$(echo "$DA" | grep -n "Enabling non-boot CPUs" | head -1 | cut -d: -f1)
UF() { grep -iE "usb|dwc3|xhci|phy|tipd|tps6598|cd321" | grep -v "TEST s2r" | grep -iE "err|fail|timeout|timed out|died" | head -1 | sed 's/^\[[^]]*\] *//'; }
UE=""; HF=s
[ -n "$RL" ] && UE=$(echo "$DA" | tail -n +$RL | UF) && [ -n "$UE" ] && HF=r
[ -z "$UE" ] && { UE=$(echo "$DA" | head -n ${RL:-999999} | UF); HF=s; }
if [ -n "$UE" ]; then
    case "$UE" in *tipd*|*tps6598*|*cd321*) c0=t;; *atcphy*|*phy*) c0=p;; *xhci*) c0=x;; *dwc3*) c0=d;; *) c0=u;; esac
    en=$(printf '%s' "$UE" | grep -oE -- '(^|[ =(])-[0-9]+([^0-9a-zA-Z]|$)' | head -1 | tr -cd 0-9 | tail -c 2); en=$(printf '%-2s' "${en:---}" | tr ' ' -)
    mg=$(printf '%s' "$UE" | sed -E 's/^[^ :]+ [^ :]+: //; s/^[^ :]+: //; s/^[Ff]ailed to //' | tr -d ' ' | cut -c1-6)
    CM="$c0$HF$en$mg"
else
    CM="u---noerr"
fi
# R59V: Wi-Fi port retries and the SMC's wake reply, as raw bytes in the text slots (the USB text is dropped; 0x6009 keeps the USB flags):
#   0x6011 = tries made <<4 | try on which port 0 came up (0 none); 0x6012 = PWREN read back per try (bit n-1 = try n read 1, bit 7 = a -1/err)
#   0x6013..16 = MBSE at the wake (from macsmc-reboot "sleep: wake MBSE"); 0x6017 = last port 0 LINKSTS low byte, 0x6019 = its PORT_STATUS low byte
#   0x601d, 0x601e = the first two MBSW bytes
sleep 12   # the S2R work: 1.5 s + up to 3 tries of ~0.5 s + 3 s gaps
DB=$(dmesg | tail -n +$(dmesg | grep -n 'PM: suspend entry (deep)' | tail -1 | cut -d: -f1))
TL=$(echo "$DB" | grep -o "TEST s2r: port 0 try .*")
NT=0; UP=0; PB=0; LK=0; ST=0
while read -r _ _ _ _ _ t _ pw _ lk _ st _ _; do
    [ -z "$t" ] && continue
    NT=$t; [ "$pw" = 1 ] && PB=$((PB | (1 << (t-1)))); case "$pw" in 0|1) ;; *) PB=$((PB|128));; esac
    LK=$((16#$lk)); ST=$((16#$st)); [ $UP = 0 ] && [ $((LK & 1)) = 1 ] && UP=$t
done <<< "$TL"
pb 0x6011 $(( (NT & 15) << 4 | (UP & 15) )); pb 0x6012 $PB; pb 0x6017 $LK; pb 0x6019 $ST
# R59Z: port 0's root-port PHY after the work, against main: 0x6013/14/15 = PHY CTRL (0x59e00c000) bits 7:0 / 15:8 / 31:24
#   (main 0x0f / 0x06 / 0xcc), 0x6016 = PHY +0x4 bits 7:0 (0x35), 0x601d = PHY +0xc bits 7:0 (0x03), 0x601e = PHY IP (0x59e048000) bits 7:0 (0x80)
rd32() { local v; v=$($J/mmio-read $1 1 2>/dev/null | awk '{print $2}'); echo $(( ${v:-0} )); }
P0=$(rd32 0x59e00c000); pb 0x6013 $((P0 & 255)); pb 0x6014 $(((P0 >> 8) & 255)); pb 0x6015 $(((P0 >> 24) & 255))
P1=$(rd32 0x59e00c004); pb 0x6016 $((P1 & 255)); P3=$(rd32 0x59e00c00c); pb 0x601d $((P3 & 255))
PI=$(rd32 0x59e048000); pb 0x601e $((PI & 255))
CM=""
if [ -n "$CM" ]; then
    k=0
    for o in 0x6011 0x6012 0x6013 0x6014 0x6015 0x6016 0x6017 0x6018 0x6019 0x601d 0x601e; do
        c=$(printf '%s' "$CM" | cut -c$((k+1)) ); [ -z "$c" ] && c=" "
        pb $o $(printf '%d' "'$c"); k=$((k+1))
    done
fi
# R60A: the post-wake log channel (owner's go-ahead, 2026-11-20): main's ext4 /boot (OMARCHY_BOOT), only /deeptest/postwake/<label>/.
#   0x6012 bit 6 = written, synced and unmounted.
cat /sys/kernel/debug/macsmc_keys > /run/postwake/smckeys-late.txt 2>/run/postwake/smckeys-late.err  # R60D: about a minute after
PWD_=/run/postwake; dd if=$PMUN of=$PWD_/pmu-post.bin bs=16 count=768 conv=noerror,sync status=none 2>$PWD_/pmu-post.err
regdump $PWD_/regs-post.txt  # R60I
dmesg > $PWD_/dmesg.txt; cat /sys/kernel/debug/gpio > $PWD_/gpio-post.txt 2>/dev/null; lspci -vv > $PWD_/lspci-post.txt 2>&1
cp /run/usbtest/run.log $PWD_/ 2>/dev/null; cat /proc/interrupts > $PWD_/interrupts.txt; cat /proc/cmdline > $PWD_/cmdline.txt
for f in /sys/module/pcie_apple/parameters/*; do echo "$f $(cat $f 2>/dev/null)"; done > $PWD_/pcie-params.txt
BD=$(blkid -L OMARCHY_BOOT 2>/dev/null); WOK=0
# R60A-2: the initramfs sets the device read-only (blockdev --setro) as a guard; lift it only for this write, then set it back
[ -n "$BD" ] && blockdev --setrw "$BD" 2>>$PWD_/mount.err
if [ -n "$BD" ] && mkdir -p /mnt/pwboot && mount -t ext4 -o rw,noatime "$BD" /mnt/pwboot 2>>$PWD_/mount.err; then
    OUT=/mnt/pwboot/deeptest/postwake/$(date +%Y%m%d-%H%M%S)-r60o
    mkdir -p "$OUT" && cp -a $PWD_/. "$OUT"/ && sync && WOK=1
    umount /mnt/pwboot || WOK=0
fi
[ -n "$BD" ] && blockdev --setro "$BD" 2>/dev/null
[ $WOK = 1 ] && pb 0x6012 $((PB | 64))
log "postwake: device ${BD:-none}, written=$WOK"
$J/aura-ctl 0 0 0 > /dev/null 2>&1
