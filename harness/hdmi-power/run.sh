#!/bin/bash
# HDMI power rails A/B: what hdmi-pwren (gP17) and dp2hdmi-pwren (gP06) cost with nothing plugged in.
#   sudo bash ~/Work/deepidle-harness/hdmi-power/run.sh [ROUNDS]
# Loads smc-pwr-test.ko, runs idle-ab.py (default / hdmi off / dp2hdmi off / both off), then unloads
# the module, which turns both rails back on (also on Ctrl-C or an error). About 2.7 min per round.
# Leave the machine alone while it runs; nothing in the HDMI port.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
H=/home/jjr/Work/deepidle-harness/hdmi-power
MOD=$H/mod/smc-pwr-test.ko
P=/sys/module/smc_pwr_test/parameters
ROUNDS=${1:-8}
OUT=/home/jjr/Work/deep-idle-build/hdmi-power-$(date +%Y%m%d-%H%M).txt
want=$(modinfo -F vermagic "$MOD" | cut -d' ' -f1)
[ "$(uname -r)" = "$want" ] || { echo "module built for $want, running $(uname -r)"; exit 1; }
for s in /sys/class/drm/card*-HDMI-A-*/status; do
    [ -e "$s" ] && [ "$(cat "$s")" = connected ] && { echo "HDMI is connected ($s): unplug it first"; exit 1; }
done
lsmod | grep -q '^smc_pwr_test ' || insmod "$MOD" || exit 1
trap 'rmmod smc_pwr_test 2>/dev/null; echo "rails back on: $(grep -E "gpio-(6|23) " /sys/kernel/debug/gpio | tr -s " ")"' EXIT
{
    echo "== HDMI rails A/B $(date '+%F %T'), $(uname -r), $(cat /sys/class/power_supply/macsmc-battery/status)"
    grep -E "gpio-(6|23) " /sys/kernel/debug/gpio
    python3 -I $H/idle-ab.py --rounds "$ROUNDS" --window 30 --settle 10 --log "${OUT%.txt}.jsonl" \
        default "set:$P/hdmi=0" "set:$P/dp2hdmi=0" "set:$P/hdmi=0,$P/dp2hdmi=0"
} 2>&1 | tee "$OUT"
chown jjr:jjr "$OUT" "${OUT%.txt}.jsonl" 2>/dev/null
echo "saved $OUT"
