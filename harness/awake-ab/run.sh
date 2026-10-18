#!/bin/bash
# Awake A/B of the s2idle suspects that need no PCI remove or rescan:
#   default | SD reader link ASPM L1 off (the state a PCI remove leaves its port in) | HDMI rails off.
#   sudo bash ~/Work/deepidle-harness/awake-ab/run.sh [ROUNDS]
# idle-ab.py restores every path it wrote; unloading smc-pwr-test turns the HDMI rails back on.
# Works on the charger (SMC Total System Power). Nothing in the HDMI port; leave the machine alone.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
H=/home/jjr/Work/deepidle-harness
MOD=$H/hdmi-power/mod/smc-pwr-test.ko
P=/sys/module/smc_pwr_test/parameters
L=/sys/bus/pci/devices/0000:02:00.0/link/l1_aspm
ROUNDS=${1:-6}
OUT=/home/jjr/Work/deep-idle-build/awake-ab-$(date +%Y%m%d-%H%M).txt
[ "$(modinfo -F vermagic "$MOD" | cut -d' ' -f1)" = "$(uname -r)" ] || { echo "$MOD not built for $(uname -r)"; exit 1; }
[ -e "$L" ] || { echo "no $L"; exit 1; }
for s in /sys/class/drm/card*-HDMI-A-*/status; do
    [ -e "$s" ] && [ "$(cat "$s")" = connected ] && { echo "HDMI connected: unplug it"; exit 1; }
done
lsmod | grep -q '^smc_pwr_test ' || insmod "$MOD" || exit 1
trap 'rmmod smc_pwr_test 2>/dev/null; echo "rails on, SD link l1_aspm=$(cat $L)"; chown jjr:jjr "$OUT" "${OUT%.txt}.jsonl" 2>/dev/null' EXIT
trap 'exit 130' INT TERM HUP
exec > >(tee "$OUT") 2>&1
echo "== awake A/B $(date '+%F %T'), $(uname -r), battery $(cat /sys/class/power_supply/macsmc-battery/status)"
python3 -I $H/hdmi-power/idle-ab.py --rounds "$ROUNDS" --window 30 --settle 10 --log "${OUT%.txt}.jsonl" \
    default "set:$L=0" "set:$P/hdmi=0,$P/dp2hdmi=0"
