#!/bin/bash
# R62D-s2r73: R62B + load apple-sep (xart_writes=0 provision_keybag=0) so 7.3.0 sep_pm_ops + syscore
# sends SEP SLEEP at commit and wakes SEP cleanly after S2R.
J=/run/usbtest/job; C=/proc/device-tree/chosen; R=/sys/class/rtc/rtc0; M=/sys/module
log() { echo "$(date '+%F %T') $*" | tee -a /run/usbtest/run.log; echo "usbtest-run: $*" > /dev/kmsg; curl -sS -m 2 -o /dev/null -H "Title: log" --data-binary "$*" http://192.168.1.112:8765/ 2>/dev/null || true; }
w() { $J/mmio-read $1 1 2>/dev/null | awk '{print $2}'; }
sv() {
    local tag="$1" PWD_=/run/postwake BD WOK=0 OUT
    dmesg > $PWD_/dmesg.txt
    cp /run/usbtest/run.log $PWD_/ 2>/dev/null
    BD=$(blkid -L OMARCHY_BOOT 2>/dev/null)
    [ -n "$BD" ] && blockdev --setrw "$BD" 2>>$PWD_/mount.err
    if [ -n "$BD" ] && mkdir -p /mnt/pwboot && mount -t ext4 -o rw,noatime "$BD" /mnt/pwboot 2>>$PWD_/mount.err; then
        OUT=/mnt/pwboot/deeptest/postwake/$(date +%Y%m%d-%H%M%S)-r62d-$tag
        mkdir -p "$OUT" && cp -a $PWD_/. "$OUT"/ && sync && WOK=1
        umount /mnt/pwboot || WOK=0
    fi
    [ -n "$BD" ] && blockdev --setro "$BD" 2>/dev/null
    log "saved r62d-$tag (ok=$WOK)"
}

mkdir -p /run/postwake
V=$(tr -d '\0' < $C/asahi,m1n1-stage2-version 2>/dev/null || echo unknown)
log "R62D kernel $(uname -r); stage2 $V"
case "$V" in *1b39fee5*) ;; *) log "stage 2 is not Aura image 128 (1b39fee5): $V — stopping"; return 0 ;; esac
[ -e $R/wakealarm ] && grep -q deep /sys/power/mem_sleep || { log "no wakealarm or no deep, stopping"; return 0; }

# Point firmware_class at job dir so appledrm loads apple/dcp-fw.macho cleanly
printf %s "$J" > /sys/module/firmware_class/parameters/path 2>/dev/null
log "firmware_class.path=$(cat /sys/module/firmware_class/parameters/path 2>/dev/null)"

# SIO axi2af tunables (macOS figs_1, T6020)
AX=0x39a000000
for t in "0x0 0x3 0x1" "0xc 0xfffff 0xd" "0x10 0xfffff 0xc" "0x14 0xfff 0x1" "0x18 0xfff 0x1" "0x1c 0xfff 0x3" "0x20 0xfff 0x3" "0x24 0xfff 0x3" "0x28 0xfff 0x3" "0x2c 0xfff 0x3" \
         "0x108 0x3 0x1" "0x10c 0xfffff 0xd" "0x110 0xfffff 0xc" "0x114 0xfff 0x1" "0x118 0xfff 0x1" "0x11c 0xfff 0x3" "0x120 0xfff 0x3" "0x124 0xfff 0x3" "0x128 0xfff 0x3" "0x12c 0xfff 0x3" \
         "0x400 0xc00103ff 0xc0010010" "0xa00 0x1ffffff 0x1ffffff"; do
    set -- $t; a=$(printf '0x%x' $((AX+$1))); old=$(w $a)
    [ -n "$old" ] || continue
    new=$(printf '0x%x' $(( ((old & ~$2) | $3) & 0xffffffff )))
    $J/mmio-write $a $new >/dev/null 2>&1 || true
done

# Disable USB-C wakeup so genpd powers them down cleanly
for dev in 702280000.usb b02280000.usb f02280000.usb; do
    for f in /sys/bus/platform/devices/$dev/power/wakeup /sys/bus/platform/devices/$dev/xhci-hcd.*/power/wakeup; do
        [ -e "$f" ] && echo disabled > "$f"
    done
done

echo deep > /sys/power/mem_sleep
echo 27 > /proc/sys/kernel/panic
log "pmgr counters: $($J/pmgrcnt enable 2>&1 | tail -1)"
# Verify Aura image 128 default psci_ctl without writing it (read-only check)
log "aura ctl default: $($J/aura-ctl 2>&1 | head -1)"

# Load apple-sep read-only so 7.3.0 sep_pm_ops + syscore sends SEP SLEEP cleanly at commit
modprobe apple-sep xart_writes=0 provision_keybag=0 2>&1 | tail -2 || true
SB=/sys/bus/platform/drivers/apple_sep/396400000.sep
for i in $(seq 1 25); do [ -e "$SB" ] && break; sleep 1; done
SI=0; for i in $(seq 1 60); do case "$(w 0x290280c00)" in 0x100003?f) SI=$i; break ;; esac; sleep 1; done

# Wait for Bluetooth (hci0) to finish probing before freezing tasks
for i in $(seq 1 15); do [ -e /sys/class/bluetooth/hci0 ] && break; sleep 1; done
log "pre-sleep sep_bound=$([ -e $SB ] && echo yes || echo no) sep_idle=${SI}s ps_sep=$(w 0x290280c00) hci0=$([ -e /sys/class/bluetooth/hci0 ] && echo yes || echo no)"

# Unbind aurora GPU (7.3.0 aurora sleep_prepare returns -EBUSY on non-G17 until G14S GPU S2R is wired)
if [ -e /sys/bus/platform/drivers/aurora/406400000.gpu ]; then
    echo 406400000.gpu > /sys/bus/platform/drivers/aurora/unbind 2>/dev/null || true
    log "unbound aurora 406400000.gpu: still_bound=$([ -e /sys/bus/platform/drivers/aurora/406400000.gpu ] && echo yes || echo no)"
fi

# Pre-sleep snapshot
PMUN=$(ls /sys/bus/spmi/devices/0-0b/spmi_nvmem*/nvmem 2>/dev/null | head -1)
[ -n "$PMUN" ] && printf '\x00' | dd of=$PMUN bs=1 seek=$((0x6004)) conv=notrunc status=none
lspci -vv > /run/postwake/lspci-pre.txt 2>&1
cat /sys/class/power_supply/*/capacity /sys/class/power_supply/*/charge_now /sys/class/power_supply/*/voltage_now > /run/postwake/battery-pre.txt 2>/dev/null || true
echo "pre p0=$(w 0x594008208) p1=$(w 0x595008208)" > /run/postwake/links.txt
sv pre

# Arm 30 s RTC alarm and enter real S2R
echo 0 > $R/wakealarm 2>/dev/null; echo +30 > $R/wakealarm
T0=$(date +%s.%N)
log "echo mem at $(date -u +%T.%N | cut -c1-12) UTC"
echo mem > /sys/power/state; rc=$?
T1=$(date +%s.%N)
DUR=$(echo "$T1 $T0" | awk '{printf "%.1f", $1-$2}')

# Stamp PMU 0x601f = 0xaa ONLY when echo mem succeeded (rc=0)
N=$(ls /sys/bus/nvmem/devices/spmi_nvmem*/nvmem 2>/dev/null | head -1)
if [ -w "$N" ]; then
    [ "$rc" -eq 0 ] && printf '\xaa' | dd of="$N" bs=1 seek=$((0x601f)) count=1 conv=notrunc 2>/dev/null
    printf "\\x$(printf '%02x' $((rc & 0xff)))" | dd of="$N" bs=1 seek=$((0x6014)) count=1 conv=notrunc 2>/dev/null
    NCPU=$(nproc 2>/dev/null || echo 0)
    printf "\\x$(printf '%02x' $((NCPU & 0xff)))" | dd of="$N" bs=1 seek=$((0x600c)) count=1 conv=notrunc 2>/dev/null
fi
log "R62D RESUMED: rc=$rc dur=${DUR}s online=$(cat /sys/devices/system/cpu/online) counters=$($J/pmgrcnt show 2>&1 | tail -1)"

# Wait for PCIe relink + DCP restart + iwd
sleep 15
systemctl restart iwd 2>/dev/null || true
sleep 10

echo "wake p0=$(w 0x594008208) p1=$(w 0x595008208)" >> /run/postwake/links.txt
lspci -vv > /run/postwake/lspci-wake.txt 2>&1
cat /sys/class/power_supply/*/capacity /sys/class/power_supply/*/charge_now /sys/class/power_supply/*/voltage_now > /run/postwake/battery-wake.txt 2>/dev/null || true
{
    date
    echo "=== NVMe ==="
    cat /sys/class/nvme/nvme0/state 2>/dev/null
    timeout 10 dd if=/dev/nvme0n1 of=/dev/null bs=4k count=16 iflag=direct 2>&1 | tail -2
    echo "=== USB ==="
    lsusb 2>/dev/null
    echo "=== Radio / BT / SD ==="
    ip -br link
    iw dev
    ip link set wlan0 up 2>/dev/null || true
    sleep 2
    timeout 20 iw dev wlan0 scan > /run/scan.raw 2>&1
    echo "scan rc $? bss $(grep -cE '^BSS' /run/scan.raw)"
    grep -E 'signal:' /run/scan.raw | sort -t: -k2 -n | head -3
    rm -f /run/scan.raw
    ls /sys/class/bluetooth 2>/dev/null
    ls /sys/class/mmc_host 2>/dev/null
} > /run/postwake/radio.txt 2>&1

# Trigger fbcon unblank for internal DCP display check
echo 4 > /sys/class/graphics/fb0/blank 2>/dev/null || true
sleep 1
echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null || true
sleep 5
dmesg | grep -iE "dcp|rtkit|appledrm|pcie|nvme|brcmf|hci_bcm4377|sdhci" | tail -120 > /run/postwake/dcp-pcie.txt

sv wake
sync
reboot -f
