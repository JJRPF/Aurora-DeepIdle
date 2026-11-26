#!/bin/bash
# R62Y-s2r73: R62B + load apple-sep (xart_writes=0 provision_keybag=0) so 7.3.0 sep_pm_ops + syscore
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
        OUT=/mnt/pwboot/deeptest/postwake/$(date +%Y%m%d-%H%M%S)-r62y-$tag
        mkdir -p "$OUT" && cp -a $PWD_/. "$OUT"/ && sync && WOK=1
        umount /mnt/pwboot || WOK=0
    fi
    [ -n "$BD" ] && blockdev --setro "$BD" 2>/dev/null
    log "saved r62y-$tag (ok=$WOK)"
}

mkdir -p /run/postwake
V=$(tr -d '\0' < $C/asahi,m1n1-stage2-version 2>/dev/null || echo unknown)
log "R62Y kernel $(uname -r); stage2 $V"
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
# Keep ps_sep untouched by Linux genpd so Aura's PSCI_S2R_SEP gates it atomically at commit
printf %s "afr,gpio,sep" > /sys/module/pmgr_pwrstate/parameters/s2r_sleep_keep 2>/dev/null || true
log "s2r_sleep_keep=$(cat /sys/module/pmgr_pwrstate/parameters/s2r_sleep_keep 2>/dev/null)"
log "pmgr counters: $($J/pmgrcnt enable 2>&1 | tail -1)"
# Verify Aura image 128 default psci_ctl without writing it (read-only check)
log "aura ctl default: $($J/aura-ctl 2>&1 | head -1)"

# Load ramoops into the reserve_mem=1M:2M:oops region so any panic/SError is captured in RAM
modprobe ramoops mem_name=oops record_size=0x20000 console_size=0x20000 max_reason=2 2>&1 || true
log "ramoops: $(dmesg | grep -iE 'ramoops|pstore' | tail -3 | tr '\n' '|')"

# Load apple-sep read-only so 7.3.0 sep_pm_ops + noirq_direct sends SEP SLEEP cleanly at commit
modprobe apple-sep xart_writes=0 provision_keybag=0 2>&1 | tail -2 || true
SB=/sys/bus/platform/drivers/apple_sep/396400000.sep
for i in $(seq 1 25); do [ -e "$SB" ] && break; sleep 1; done
SI=0; for i in $(seq 1 15); do case "$(w 0x290280c00)" in 0x100003?f) SI=$i; break ;; esac; sleep 1; done

# Wait for Bluetooth (hci0) to finish probing before freezing tasks
for i in $(seq 1 15); do [ -e /sys/class/bluetooth/hci0 ] && break; sleep 1; done
log "pre-sleep sep_bound=$([ -e $SB ] && echo yes || echo no) sep_idle=${SI}s ps_sep=$(w 0x290280c00) hci0=$([ -e /sys/class/bluetooth/hci0 ] && echo yes || echo no)"



# Pre-sleep snapshot
PMUN=$(ls /sys/bus/spmi/devices/0-0b/spmi_nvmem*/nvmem 2>/dev/null | head -1)
[ -n "$PMUN" ] && printf '\x00' | dd of=$PMUN bs=1 seek=$((0x6004)) conv=notrunc status=none
lspci -vv > /run/postwake/lspci-pre.txt 2>&1
cat /sys/class/power_supply/*/capacity /sys/class/power_supply/*/charge_now /sys/class/power_supply/*/voltage_now > /run/postwake/battery-pre.txt 2>/dev/null || true
echo "pre p0=$(w 0x594008208) p1=$(w 0x595008208)" > /run/postwake/links.txt
sv pre

# Arm 30 s RTC alarm and enter real S2R
echo 0 > $R/wakealarm 2>/dev/null; echo +20 > $R/wakealarm
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
log "R62Y RESUMED: rc=$rc dur=${DUR}s online=$(cat /sys/devices/system/cpu/online) counters=$($J/pmgrcnt show 2>&1 | tail -1)"
sv wake0

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

# Trigger fbcon unblank + visual display/backlight check for owner
tty_say() { echo "$*" | tee -a /run/usbtest/run.log > /dev/tty1 2>/dev/null || true; }
{
    printf '\033[2J\033[H'
    echo "============================================================"
    echo "   GH-5 R62Y VISUAL & ZERO-UNBIND CHECK (7.3.0-s2r73+)"
    echo "============================================================"
    echo " Zero pre-sleep unbinds (GPU + PCIe + DCP all kept bound!)"
    echo " 1. DISPLAY & BACKLIGHT: ramping 20% -> 100% -> 60%..."
    echo " 2. BLUETOOTH: power on + 15s LE scan..."
    echo " 3. SD CARD: reading inserted card..."
    echo "============================================================"
} > /dev/tty1 2>/dev/null || true

BL=/sys/class/backlight/apple-panel-bl
if [ -d "$BL" ]; then
    MAXB=$(cat "$BL/max_brightness" 2>/dev/null || echo 1000)
    CURB=$(cat "$BL/brightness" 2>/dev/null || echo 0)
    {
        echo "backlight max=$MAXB initial=$CURB actual=$(cat $BL/actual_brightness 2>/dev/null)"
        echo $((MAXB / 5)) > "$BL/brightness" 2>&1; sleep 3
        echo "after 20%: actual=$(cat $BL/actual_brightness 2>/dev/null)"
        echo "$MAXB" > "$BL/brightness" 2>&1; sleep 3
        echo "after 100%: actual=$(cat $BL/actual_brightness 2>/dev/null)"
        echo $((MAXB * 6 / 10)) > "$BL/brightness" 2>&1; sleep 2
        echo "after 60%: actual=$(cat $BL/actual_brightness 2>/dev/null)"
    } > /run/postwake/backlight.txt 2>&1
    tty_say "Backlight ramp done (20% -> 100% -> 60%; max=$MAXB)."
else
    echo "no $BL" > /run/postwake/backlight.txt
    tty_say "WARN: no $BL sysfs entry found."
fi

# Bluetooth check via btmgmt (power on + 15s discovery scan)
tty_say ""
tty_say ">>> BLUETOOTH CHECK (btmgmt le on 2>&1 || true; btmgmt power on + 15s scan)..."
{
    echo "=== btmgmt info (before) ==="
    timeout 10 btmgmt info 2>&1 || true
    echo "=== btmgmt le on 2>&1 || true; btmgmt power on ==="
    timeout 10 btmgmt le on 2>&1 || true; btmgmt power on 2>&1 || true
    echo "=== btmgmt info (after) ==="
    timeout 10 btmgmt info 2>&1 || true
    echo "=== btmgmt find (15s) ==="
    timeout 15 btmgmt find 2>&1 || true
} > /run/postwake/bt.txt 2>&1
BT_FOUND=$(grep -c 'dev_found:' /run/postwake/bt.txt 2>/dev/null || echo 0)
tty_say "Bluetooth check done: found $BT_FOUND device(s)."
log "bt check: found=$BT_FOUND"

# SD card insertion check (wait up to 60s for /dev/mmcblk0)
tty_say ""
tty_say ">>> INSERT SD CARD NOW (waiting up to 60 seconds) <<<"
SD_OK=0
for i in $(seq 1 15); do
    if [ -b /dev/mmcblk0 ]; then
        SD_OK=1
        tty_say "SD CARD DETECTED at t=${i}s! Running lsblk + 1 MB read test..."
        {
            echo "detected_at=${i}s"
            lsblk -o NAME,SIZE,MODEL,FSTYPE /dev/mmcblk0 2>&1
            blkid /dev/mmcblk0* 2>&1 || true
            dd if=/dev/mmcblk0 of=/dev/null bs=1M count=1 iflag=direct 2>&1
        } > /run/postwake/sd.txt 2>&1
        tty_say "SD CARD READ OK! Holding screen for 8s before rebooting to main..."
        log "sd check: detected at ${i}s"
        sleep 8
        break
    fi
    if [ $((i % 10)) -eq 0 ]; then
        tty_say "...still waiting for SD card (${i}/60s)..."
    fi
    sleep 1
done
if [ "$SD_OK" -eq 0 ]; then
    echo "no /dev/mmcblk0 detected within 60s" > /run/postwake/sd.txt
    tty_say "No SD card detected within 60s; saving logs and rebooting to main."
    log "sd check: none detected in 60s"
fi

dmesg | grep -iE "dcp|rtkit|appledrm|pcie|nvme|brcmf|hci_bcm4377|sdhci|mmc|bluetooth|backlight|pmp|sep" | tail -160 > /run/postwake/dcp-pcie.txt

sv wake
sync
reboot -f
