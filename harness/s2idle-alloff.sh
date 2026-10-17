#!/bin/bash
# s2idle with everything optional off, to bound what is reachable without SoC sleep.
#   sudo bash ~/Work/deepidle-harness/s2idle-alloff.sh arm      then unplug and close the lid
#   sudo bash ~/Work/deepidle-harness/s2idle-alloff.sh report   after opening it: report + restore
#   sudo bash ~/Work/deepidle-harness/s2idle-alloff.sh restore  restore only
# Off: Wi-Fi and Bluetooth (rfkill), the AOP ambient-light and lid-angle sensor drivers (the
# s2idle wakes come from the AOP), and the unused SD reader (PCI device removed; rescan brings
# it back). Everything else is as it was. Reversible at runtime; a reboot also restores it all.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
PROBE=/home/jjr/dev/linux-aurora/GH-1-DeepIdle/tools/aurora-sep/sleep-drain-probe.py
OUT=/home/jjr/Work/deep-idle-build/s2idle-alloff-$(date +%Y%m%d-%H%M).txt
SD=0000:02:00.0

restore() {
    rfkill unblock all
    modprobe aop_als; modprobe aop_las
    [ -e /sys/bus/pci/devices/$SD ] || echo 1 > /sys/bus/pci/rescan
    sleep 2
    echo "restored: $(rfkill list | grep -c 'Soft blocked: yes') radios blocked;" \
        "$(lsmod | grep -cE '^aop_(als|las) ') of 2 sensor drivers loaded;" \
        "SD reader $([ -e /sys/bus/pci/devices/$SD ] && echo present || echo MISSING)"
}

case "${1:-}" in
arm)
    rfkill block all
    modprobe -r aop_als aop_las
    [ -e /sys/bus/pci/devices/$SD ] && echo 1 > /sys/bus/pci/devices/$SD/remove
    sleep 2
    echo "off: $(rfkill list | grep -c 'Soft blocked: yes') radios blocked;" \
        "$(lsmod | grep -cE '^aop_(als|las) ') of 2 sensor drivers loaded;" \
        "SD reader $([ -e /sys/bus/pci/devices/$SD ] && echo still present || echo removed)"
    echo "battery: $(cat /sys/class/power_supply/macsmc-battery/status)" \
        "(must say Discharging before the lid closes)"
    python3 "$PROBE" arm ;;
report)
    python3 "$PROBE" report > "$OUT" 2>&1
    sed -n 1,3p "$OUT"; echo "full report: $OUT"
    restore ;;
restore) restore ;;
*) sed -n 2,8p "$0"; exit 1 ;;
esac
