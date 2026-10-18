#!/bin/bash
# One self-waking s2idle on the charger with the battery force-discharged (charge limit lowered,
# CHLS force-discharge), reading the battery coulomb counter (BAAC) and the SMC system-power
# accumulator (zSPa/zSPc) together, to calibrate the accumulator.
#   sudo bash ~/Work/deepidle-harness/s2idle-calib.sh [SECONDS]
# Restores the charge limit and Omarchy stay-awake on any exit.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
SEC=${1:-900}
B=/sys/class/power_supply/macsmc-battery
H=/home/jjr/Work/deepidle-harness
ACC="python3 -I $H/smc-keyread/smc-acc.py"
T=$(mktemp -d)
OUT=/home/jjr/Work/deep-idle-build/s2idle-calib-$(date +%Y%m%d-%H%M).txt
OLD=$(cat $B/charge_control_end_threshold)
awake() { sudo -u jjr env HOME=/home/jjr omarchy-toggle-idle "$1" >/dev/null; }
cleanup() {
    echo "$OLD" > $B/charge_control_end_threshold
    awake stay-awake
    rmmod s2idle_wake 2>/dev/null
    echo "charge limit back to $(cat $B/charge_control_end_threshold), stay-awake on"
    chown jjr:jjr "$OUT" 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
exec > >(tee "$OUT") 2>&1
lsmod | grep -q '^smc_keyread ' || insmod $H/smc-keyread/smc-keyread.ko || exit 1
lo=$(( $(cat $B/capacity) - 15 )); [ $lo -lt 20 ] && lo=20
echo "== s2idle calibration $(date '+%F %T'): limit $OLD -> $lo (force discharge), ${SEC}s"
echo $lo > $B/charge_control_end_threshold
for i in $(seq 1 24); do
    [ "$(cat $B/status)" = Discharging ] && break; sleep 5
done
echo "status $(cat $B/status), current $(cat $B/current_now) uA"
[ "$(cat $B/status)" = Discharging ] || { echo "did not start discharging"; exit 1; }
sleep 20
insmod $H/s2idle-wake/s2idle-wake.ko seconds=$SEC || exit 1
q0=$(cat $B/charge_counter); v0=$(cat $B/voltage_now); $ACC snap $T/a.json
awake allow-idle
echo freeze > /sys/power/state
awake stay-awake
q1=$(cat $B/charge_counter); v1=$(cat $B/voltage_now); $ACC snap $T/b.json
echo "status after: $(cat $B/status)"
$ACC diff $T/a.json $T/b.json
python3 -I - "$T/a.json" "$T/b.json" "$q0" "$q1" "$v0" "$v1" <<'P'
import json, sys
a, b = (json.load(open(f)) for f in sys.argv[1:3])
q0, q1, v0, v1 = map(int, sys.argv[3:7])
dt = b["t"] - a["t"]
w = (q0 - q1) / 1000 * (v0 + v1) / 2e6 / dt
print(f"battery (BAAC): {q0 - q1} mA*s over {dt:.1f} s at {(v0 + v1) / 2e6:.3f} V: {w:.3f} W")
P
