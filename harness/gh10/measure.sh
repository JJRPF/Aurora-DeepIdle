#!/bin/bash
# GH-10: one boot's idle measurement.   sudo measure.sh NAME [ROUNDS]
# Records the boot state, then samples the SMC sensors with idle-ab.py (one setting, ROUNDS windows of
# 30 s after 180 s settle) into data/idle_erikwb/boot-NAME/. Leave the machine alone while it runs.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
N=$1; R=${2:-16}
REPO=/home/jjr/dev/Aurora-DeepIdle/GH-10-IdleErikwb
O=$REPO/data/idle_erikwb/boot-$N; mkdir -p $O
{ date '+%F %T'; uname -r; cat /proc/cmdline; sha256sum /boot/m1n1/boot.bin | cut -c1-16; tail -3 /var/lib/gh10/log 2>/dev/null
  echo "sched_energy_aware=$(cat /proc/sys/kernel/sched_energy_aware)"
  echo "cpuidle state0 disable: $(cat /sys/devices/system/cpu/cpu*/cpuidle/state0/disable | sort | uniq -c | tr '\n' ' ')"
  echo "energy_model domains: $(ls /sys/kernel/debug/energy_model 2>/dev/null | wc -l)"
  cat /sys/class/power_supply/macsmc-battery/status /sys/class/power_supply/macsmc-ac/online
  echo "load: $(cat /proc/loadavg)"
} > $O/boot.txt 2>&1
cat /sys/kernel/debug/pm_genpd/pm_genpd_summary > $O/genpd.txt 2>&1
dmesg > $O/dmesg.txt 2>&1
for t in $(seq 1 36); do sleep 5; done   # settle 180 s
python3 -I $REPO/tools/idle-ab.py --rounds $R --window 30 --settle 0 --log $O/ab.jsonl default > $O/ab.txt 2>&1
cat /sys/kernel/debug/pm_genpd/pm_genpd_summary > $O/genpd-after.txt 2>&1
echo done > $O/DONE
chown -R jjr:jjr $O
