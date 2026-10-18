#!/bin/bash
# s2idle with everything optional off, to bound what is reachable without SoC sleep.
#   sudo bash ~/Work/deepidle-harness/s2idle-alloff.sh arm      then unplug and close the lid
#   sudo bash ~/Work/deepidle-harness/s2idle-alloff.sh report   after opening it: report + restore
#   sudo bash ~/Work/deepidle-harness/s2idle-alloff.sh restore  restore only
# Off: Wi-Fi and Bluetooth (rfkill), the AOP ambient-light and lid-angle sensor drivers (the
# s2idle wakes come from the AOP), the unused SD reader (PCI device removed; rescan brings
# it back), and the HDMI port's two power rails, gP17 and gP06 (smc-pwr-test.ko; macOS keeps
# them off with nothing plugged in). Everything else is as it was. Reversible at runtime; a
# reboot also restores it all. Nothing in the HDMI port.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
PROBE=/home/jjr/dev/linux-aurora/GH-1-DeepIdle/tools/aurora-sep/sleep-drain-probe.py
OUT=/home/jjr/Work/deep-idle-build/s2idle-alloff-$(date +%Y%m%d-%H%M).txt
SD=0000:02:00.0
HMOD=/home/jjr/Work/deepidle-harness/hdmi-power/mod/smc-pwr-test.ko
HP=/sys/module/smc_pwr_test/parameters
rails() { grep -E "gpio-(6|23) " /sys/kernel/debug/gpio | awk '{ printf "%s %s; ", substr($3, 2), $NF }'; }

restore() {
    rfkill unblock all
    lsmod | grep -q '^smc_pwr_test ' && rmmod smc_pwr_test
    modprobe aop_als; modprobe aop_las
    [ -e /sys/bus/pci/devices/$SD ] || echo 1 > /sys/bus/pci/rescan
    sleep 2
    echo "restored: $(rfkill list | grep -c 'Soft blocked: yes') radios blocked;" \
        "$(lsmod | grep -cE '^aop_(als|las) ') of 2 sensor drivers loaded;" \
        "SD reader $([ -e /sys/bus/pci/devices/$SD ] && echo present || echo MISSING);" \
        "HDMI rails: $(rails)"
}

case "${1:-}" in
arm)
    for s in /sys/class/drm/card*-HDMI-A-*/status; do
        [ -e "$s" ] && [ "$(cat "$s")" = connected ] && { echo "HDMI is connected ($s): unplug it first"; exit 1; }
    done
    [ "$(modinfo -F vermagic "$HMOD" | cut -d' ' -f1)" = "$(uname -r)" ] || { echo "$HMOD is not built for $(uname -r)"; exit 1; }
    rfkill block all
    modprobe -r aop_als aop_las
    [ -e /sys/bus/pci/devices/$SD ] && echo 1 > /sys/bus/pci/devices/$SD/remove
    lsmod | grep -q '^smc_pwr_test ' || insmod "$HMOD"
    echo 0 > $HP/hdmi; echo 0 > $HP/dp2hdmi
    sleep 2
    echo "off: $(rfkill list | grep -c 'Soft blocked: yes') radios blocked;" \
        "$(lsmod | grep -cE '^aop_(als|las) ') of 2 sensor drivers loaded;" \
        "SD reader $([ -e /sys/bus/pci/devices/$SD ] && echo still present || echo removed);" \
        "HDMI rails: $(rails)"
    echo "battery: $(cat /sys/class/power_supply/macsmc-battery/status)" \
        "(must say Discharging before the lid closes)"
    python3 "$PROBE" arm ;;
report)
    python3 "$PROBE" report > "$OUT" 2>&1
    sed -n 1,3p "$OUT"; echo "full report: $OUT"
    restore ;;
restore) restore ;;
*) sed -n 2,10p "$0"; exit 1 ;;
esac
