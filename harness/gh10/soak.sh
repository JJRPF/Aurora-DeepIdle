#!/bin/bash
# GH-10: 1 h idle soak.  sudo soak.sh NAME   (idle-ab 120 x 30 s windows + ping loss + dmesg growth)
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
N=$1; REPO=/home/jjr/dev/Aurora-DeepIdle/GH-10-IdleErikwb; O=$REPO/data/idle_erikwb/soak-$N; mkdir -p $O
dmesg > $O/dmesg-start.txt; cat /sys/kernel/debug/pm_genpd/pm_genpd_summary > $O/genpd-start.txt
( ping -i 1 -w 3700 1.1.1.1 > $O/ping.txt 2>&1 ) &
( while :; do echo "$(date +%T) $(cat /proc/loadavg | cut -d' ' -f1-3) cpu0=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)" >> $O/health.txt; sleep 60; done ) &
HB=$!
python3 -I $REPO/tools/idle-ab.py --rounds 120 --window 30 --settle 0 --log $O/ab.jsonl default > $O/ab.txt 2>&1
kill $HB 2>/dev/null; wait
dmesg > $O/dmesg-end.txt; cat /sys/kernel/debug/pm_genpd/pm_genpd_summary > $O/genpd-end.txt
echo done > $O/DONE; chown -R jjr:jjr $O
