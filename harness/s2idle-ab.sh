#!/bin/bash
# s2idle drain per setting, unattended: one self-waking suspend per setting (s2idle-wake.ko).
#   sudo bash ~/Work/deepidle-harness/s2idle-ab.sh [MINUTES] [SETTING ...]
# Default 15 min each: base hdmi aop base. On battery: the coulomb counter (BAAC). On the charger
# with the battery held ("Not charging"): the SMC accumulator of adapter-supplied system power
# (zSPa/zSPc, smc-keyread.ko); it agreed with the battery to 7% (2.11 vs 1.98 W, 2026-10-18).
# Not in force-discharge on the charger: the accumulator then reads only the adapter's share.
#   base  nothing changed
#   hdmi  HDMI rails gP17 and gP06 off (smc-pwr-test.ko; nothing in the HDMI port)
#   aop   AOP ambient-light and lid-angle drivers unloaded
# Wi-Fi is left on, and the SD reader is not touched: removing it from PCI and rescanning
# (the whole bus or only its port) kills the Wi-Fi chip until a reboot (2026-10-18).
# Omarchy stay-awake is turned off only for each suspend and back on right after it.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
MIN=${1:-15}; shift 2>/dev/null
SETTINGS=${*:-base hdmi aop base}
H=/home/jjr/Work/deepidle-harness
WAKE=$H/s2idle-wake/s2idle-wake.ko
HMOD=$H/hdmi-power/mod/smc-pwr-test.ko
B=/sys/class/power_supply/macsmc-battery
OUT=/home/jjr/Work/deep-idle-build/s2idle-ab-$(date +%Y%m%d-%H%M).txt
awake() { sudo -u jjr env HOME=/home/jjr omarchy-toggle-idle "$1" >/dev/null; }

for m in "$WAKE" "$HMOD"; do
    [ "$(modinfo -F vermagic "$m" | cut -d' ' -f1)" = "$(uname -r)" ] || { echo "$m is not built for $(uname -r)"; exit 1; }
done
ACC="python3 -I $H/smc-keyread/smc-acc.py"
T=$(mktemp -d)
case "$(cat $B/status)" in
Discharging) MODE=battery ;;
"Not charging"|Full) MODE=smc
    lsmod | grep -q '^smc_keyread ' || insmod $H/smc-keyread/smc-keyread.ko || exit 1 ;;
*) echo "battery says $(cat $B/status): unplug the charger, or wait until it holds (Not charging)"; exit 1 ;;
esac
for s in /sys/class/drm/card*-HDMI-A-*/status; do
    [ -e "$s" ] && [ "$(cat "$s")" = connected ] && { echo "HDMI connected: unplug it"; exit 1; }
done

undo() {
    case "$1" in
    hdmi) lsmod | grep -q '^smc_pwr_test ' && rmmod smc_pwr_test ;;
    aop)  modprobe aop_als; modprobe aop_las ;;
    esac
}
cleanup() {
    awake stay-awake
    undo hdmi; undo aop
    rmmod s2idle_wake 2>/dev/null
    chown jjr:jjr "$OUT" 2>/dev/null
    echo "restored; stay-awake on; results in $OUT"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
lsmod | grep -q '^s2idle_wake ' || insmod "$WAKE" seconds=$((MIN * 60)) || exit 1
echo $((MIN * 60)) > /sys/module/s2idle_wake/parameters/seconds

aopirq() { awk '/2a6408000.mbox-recv/ { s = 0; for (i = 2; i <= 11; i++) s += $i; print s }' /proc/interrupts; }
s2u() { cat /sys/devices/system/cpu/cpu0/cpuidle/state*/s2idle/usage 2>/dev/null | awk '{ s += $1 } END { print s + 0 }'; }

exec > >(tee "$OUT") 2>&1
echo "== s2idle A/B $(date '+%F %T'), $(uname -r), ${MIN} min per setting: $SETTINGS; measured by $MODE"
printf '%-6s %8s %8s %7s %8s %7s %s\n' setting susp_s mAh W aop/s wakes/s "wifi after"
for s in $SETTINGS; do
    case "$s" in
    base) ;;
    hdmi) lsmod | grep -q '^smc_pwr_test ' || insmod "$HMOD"; echo 0 > /sys/module/smc_pwr_test/parameters/hdmi
          echo 0 > /sys/module/smc_pwr_test/parameters/dp2hdmi ;;
    aop)  modprobe -r aop_als aop_las ;;
    *)    echo "unknown setting $s"; continue ;;
    esac
    sleep 30
    st0=$(cat $B/status)
    case "$MODE/$st0" in battery/Discharging|"smc/Not charging"|smc/Full) ;;
    *) echo "$s: battery status $st0 in $MODE mode, stopping"; break ;; esac
    q0=$(cat $B/charge_counter); v0=$(cat $B/voltage_now); a0=$(aopirq); w0=$(s2u)
    [ $MODE = smc ] && $ACC snap $T/a.json
    t0=$(date +%s.%N)
    awake allow-idle
    echo freeze > /sys/power/state
    awake stay-awake
    t1=$(date +%s.%N); q1=$(cat $B/charge_counter); v1=$(cat $B/voltage_now); a1=$(aopirq); w1=$(s2u)
    smcw=0; [ $MODE = smc ] && { $ACC snap $T/b.json; smcw=$($ACC diff $T/a.json $T/b.json | awk '{ print $(NF-1) }'); }
    st=$(cat $B/status)
    sleep 5
    wifi=$(nmcli -t -f DEVICE,STATE dev 2>/dev/null | awk -F: '$1 == "wlan0" { print $2 }')
    undo "$s"
    awk -v mode="$MODE" -v smcw="$smcw" -v st0="$st0" -v s="$s" -v t0="$t0" -v t1="$t1" -v q0="$q0" -v q1="$q1" -v v0="$v0" -v v1="$v1" \
        -v want="$((MIN * 60))" -v a="$((a1 - a0))" -v w="$((w1 - w0))" -v wifi="${wifi:-?}" -v st="$st" 'BEGIN {
        d = t1 - t0; mah = (q0 - q1) / 3600; W = (q0 - q1) / 1000 * (v0 + v1) / 2e6 / d
        if (mode == "smc") W = smcw
        printf "%-6s %8.0f %8.1f %7.3f %8.2f %7.2f %s%s\n", s, d, mah, W, a / d, w / d, wifi,
            (st == st0 ? "" : "  (status " st0 " -> " st ": invalid)") (d < 0.95 * want ? "  (woken early)" : "")
    }'
    sleep 20
done
