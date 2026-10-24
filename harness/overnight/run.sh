#!/bin/bash
# Overnight s2idle drain test on the running kernel: arm the drain probe (root, harness sudo rule),
# allow idle, suspend, and after the owner wakes the Mac (lid / key) report, then stay-awake again.
#   overnight/run.sh [delay seconds before suspending, default 120]
# Results: ~/Work/deepidle-harness/overnight/results-<stamp>/
set -u
H=$HOME/Work/deepidle-harness
R=$H/overnight/results-$(date +%Y%m%d-%H%M%S)
mkdir -p "$R"
B=/sys/class/power_supply/macsmc-battery
state() {
    echo "== $(date '+%F %T') $1"
    for f in status capacity charge_now energy_now current_now voltage_now charge_behaviour \
             charge_control_start_threshold charge_control_end_threshold; do
        echo "$f=$(cat $B/$f 2>/dev/null)"
    done
    echo "ac_online=$(cat /sys/class/power_supply/macsmc-ac/online)"
    for i in 1 2 4; do
        h=/sys/class/hwmon/hwmon2
        echo "$(cat $h/power${i}_label)=$(cat $h/power${i}_input)"
    done
    echo "suspend success=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail)"
    awk '{print "boottime-monotonic: " $0}' /proc/uptime
}
restore() { omarchy-toggle-idle stay-awake >> "$R/run.log" 2>&1 && echo "$(date '+%T') stay-awake back on" >> "$R/run.log"; }
trap restore EXIT
state before > "$R/state.txt"
sleep "${1:-120}"
state "before suspend" >> "$R/state.txt"
sudo -n python3 -I $H/sleep-drain-probe.py arm > "$R/arm.txt" 2>&1 || { echo "probe arm failed" >> "$R/run.log"; exit 1; }
n0=$(cat /sys/power/suspend_stats/success)
omarchy-toggle-idle allow-idle >> "$R/run.log" 2>&1
echo "$(date '+%F %T') suspending (success count $n0)" >> "$R/run.log"
systemctl suspend >> "$R/run.log" 2>&1
# This loop is frozen while the Mac sleeps and goes on after the wake.
for _ in $(seq 2880); do
    [ "$(cat /sys/power/suspend_stats/success)" != "$n0" ] && break
    [ "$(cat /sys/power/suspend_stats/fail)" != "0" ] && { echo "suspend failed" >> "$R/run.log"; break; }
    sleep 5
done
echo "$(date '+%F %T') resumed" >> "$R/run.log"
sleep 20
state after >> "$R/state.txt"
sudo -n python3 -I $H/sleep-drain-probe.py report > "$R/report.txt" 2>&1
journalctl -b --no-pager -o short-monotonic --since "-12h" -g "PM: suspend|s2idle|wake|Freezing|Restarting" \
    > "$R/journal-pm.txt" 2>&1 || true
echo "$(date '+%F %T') done" >> "$R/run.log"
