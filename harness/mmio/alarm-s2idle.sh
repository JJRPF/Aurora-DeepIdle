#!/bin/bash
# One s2idle with the PMU alarm armed (+ALARM s) and s2idle-wake.ko as a backup waker
# (+BACKUP s); PMU and SPMI state read just before and just after. Run as root.
set -u
ALARM=${1:-30}; BACKUP=${2:-90}; KO=${3:?s2idle-wake.ko}
H=/home/jjr/Work/deepidle-harness/mmio
R=$(dirname $(grep -l macsmc-rtc /sys/class/rtc/rtc*/name))
awake() { sudo -u jjr env HOME=/home/jjr XDG_RUNTIME_DIR=/run/user/1001 /usr/share/omarchy/bin/omarchy-toggle-idle "$1" >/dev/null 2>&1; }
irq() { grep macsmc-rtc /proc/interrupts | awk '{s=0; for(i=2;i<=11;i++) s+=$i; print s}'; }
insmod $KO seconds=$BACKUP || exit 1
trap 'awake stay-awake; rmmod s2idle_wake 2>/dev/null' EXIT
echo 0 > $R/wakealarm; echo +$ALARM > $R/wakealarm
echo "irq before $(irq); wakealarm $(cat $R/wakealarm) now $(date +%s)"
python3 -I $H/pmu-rtc.py show
awake allow-idle
t0=$(date +%s.%N); echo freeze > /sys/power/state; rc=$?; t1=$(date +%s.%N)
python3 -I $H/pmu-rtc.py show
echo "suspend rc $rc, $(echo "$t1 - $t0" | bc) s; irq after $(irq); wakeup_irq $(cat /sys/power/pm_wakeup_irq 2>&1)"
journalctl -k -n 25 --no-pager | grep -v -i "usb\|bluetooth" | tail -12
