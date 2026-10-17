#!/bin/bash
# macOS sleep-drain baseline for the Aurora deep idle work (same battery and gauge Linux reads).
#
#   curl -fsSL https://raw.githubusercontent.com/JJRPF/Aurora-DeepIdle/main/tools/macos-sleep-test.sh | bash -s -- arm
#     unplug the charger, close the lid, leave it closed (at least 4 h, ideally overnight)
#   curl -fsSL https://raw.githubusercontent.com/JJRPF/Aurora-DeepIdle/main/tools/macos-sleep-test.sh | bash -s -- report
#     right after opening the lid; opens an issue with the result, with gh
#
# Reads only: ioreg AppleSmartBattery, pmset settings and log, sw_vers, sysctl. Changes no settings,
# needs no sudo or Python. Keeps everything in ~/Library/Logs/AuroraDeepIdle/.
# The issue goes to $DEEPIDLE_REPO (default JJRPF/Aurora-DeepIdle), a public repo: battery figures,
# macOS version, model, pmset settings and sleep/wake log lines. DEEPIDLE_POST=0 skips it.
# Energy is the gauge's raw remaining capacity (mAh) times the mean battery voltage, the same
# method Linux's mac-power-telemetry uses with the SMC coulomb counter.
set -u
DIR="$HOME/Library/Logs/AuroraDeepIdle"
REPO="${DEEPIDLE_REPO:-JJRPF/Aurora-DeepIdle}"
POST="${DEEPIDLE_POST:-1}"
STATE="$DIR/sleep-test.state"

[ "$(uname -s)" = Darwin ] || { echo "run this on macOS"; exit 1; }
mkdir -p "$DIR"

bat() { ioreg -rn AppleSmartBattery | awk -v k="\"$1\"" '$1 == k && $2 == "=" { print $3; exit }'; }

snapshot() {
    raw=$(bat AppleRawCurrentCapacity); [ -n "$raw" ] || raw=$(bat RawCurrentCapacity)
    mv=$(bat Voltage); [ -n "$mv" ] || mv=$(bat AppleRawBatteryVoltage)
    pct=$(bat CurrentCapacity); ext=$(bat ExternalConnected); chg=$(bat IsCharging)
    rawmax=$(bat AppleRawMaxCapacity); nom=$(bat NominalChargeCapacity); design=$(bat DesignCapacity)
    cyc=$(bat CycleCount); temp=$(bat Temperature)
    now=$(date +%s)
}

case "${1:-}" in
arm)
    snapshot
    if [ -z "$raw" ] || [ -z "$mv" ]; then echo "could not read the battery gauge (ioreg AppleSmartBattery)"; exit 1; fi
    {
        echo "t0=$now"; echo "raw0=$raw"; echo "mv0=$mv"; echo "pct0=$pct"
        echo "rawmax=$rawmax"; echo "nom=$nom"; echo "design=$design"; echo "cyc=$cyc"; echo "temp0=$temp"
    } > "$STATE"
    {
        echo "== armed $(date '+%Y-%m-%d %H:%M:%S %z')"
        sw_vers; echo "model: $(sysctl -n hw.model)"
        echo "battery: ${raw} mAh, ${mv} mV, ${pct}%, external=${ext}, charging=${chg}, cycles=${cyc}"
        echo "== pmset -g"; pmset -g
        echo "== pmset -g assertions"; pmset -g assertions
    } > "$DIR/sleep-test-arm.txt" 2>&1
    echo "Armed: ${raw} mAh at ${mv} mV (${pct}%)."
    if [ "$ext" = Yes ] || [ "$chg" = Yes ]; then
        echo "WARNING: the charger is connected. Unplug it, then run 'arm' again."
        exit 1
    fi
    echo "Now close the lid and leave it closed: at least 4 h, ideally overnight."
    echo "Keep USB devices and external displays unplugged. Then open the lid and run: ... | bash -s -- report"
    ;;
report)
    [ -f "$STATE" ] || { echo "not armed: run 'arm' first"; exit 1; }
    . "$STATE"
    snapshot
    OUT="$DIR/sleep-test-report-$(date -r "$t0" +%Y%m%d-%H%M).txt"
    # Sleep/Wake/DarkWake events since arming: total time asleep, wake count, wake reasons.
    pmset -g log | awk '$1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ && ($4 == "Sleep" || $4 == "Wake" || $4 == "DarkWake")' > "$DIR/.events"
    asleep=0; nsleep=0; nwake=0; ndark=0; sleep_t=""
    : > "$DIR/.events-since"
    while IFS= read -r line; do
        set -- $line
        t=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$1 $2 $3" +%s 2>/dev/null) || continue
        [ "$t" -ge "$t0" ] || continue
        echo "$line" >> "$DIR/.events-since"
        case "$4" in
        Sleep) sleep_t=$t; nsleep=$((nsleep + 1)) ;;
        Wake|DarkWake)
            [ "$4" = Wake ] && nwake=$((nwake + 1)) || ndark=$((ndark + 1))
            if [ -n "$sleep_t" ]; then asleep=$((asleep + t - sleep_t)); sleep_t=""; fi ;;
        esac
    done < "$DIR/.events"
    {
        echo "== Aurora DeepIdle macOS sleep test"
        echo "armed:    $(date -r "$t0" '+%Y-%m-%d %H:%M:%S %z')"
        echo "reported: $(date -r "$now" '+%Y-%m-%d %H:%M:%S %z')"
        echo "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n hw.model)"
        awk -v t0="$t0" -v t1="$now" -v as="$asleep" -v r0="$raw0" -v r1="$raw" -v v0="$mv0" -v v1="$mv" \
            -v p0="$pct0" -v p1="$pct" -v ns="$nsleep" -v nw="$nwake" -v nd="$ndark" -v nom="$nom" 'BEGIN {
            wall = (t1 - t0) / 3600; slp = as / 3600; dq = r0 - r1; v = (v0 + v1) / 2000
            e = dq * v / 1000
            printf "wall time:      %.2f h\n", wall
            printf "asleep:         %.2f h (%d sleeps, %d full wakes, %d dark wakes)\n", slp, ns, nw, nd
            printf "charge used:    %d mAh (%d -> %d), %s%% -> %s%%\n", dq, r0, r1, p0, p1
            printf "energy used:    %.3f Wh (mean %.3f V)\n", e, v
            if (wall > 0) printf "mean power, wall time: %.3f W\n", e / wall
            if (slp > 0)  printf "mean power, asleep:    %.3f W (all drain charged to sleep, dark wakes included)\n", e / slp
            if (nom > 0 && wall > 0) printf "per 24 h:       %.1f%% of a %d mAh full charge\n", 100 * dq / nom * 24 / wall, nom
            if (slp < 4) print "NOTE: under 4 h asleep; the gauge resolution makes this a rough figure"
            if (dq < 30) print "NOTE: under 30 mAh used; leave it asleep longer for a usable number"
            print "Linux s2idle on this machine: about 1.4 W (2026-10-17)"
        }'
        echo "== sleep/wake events since arming (last 60)"
        tail -60 "$DIR/.events-since"
        echo "== wake reasons"
        awk '$4 ~ /Wake$/ { for (i = 5; i <= NF; i++) if ($i == "due" && $(i + 1) == "to") { r = ""; for (j = i + 2; j <= NF && $j != "Using"; j++) r = r " " $j; print r; break } }' \
            "$DIR/.events-since" | sort | uniq -c | sort -rn | head -20
        echo "== pmset -g (now)"; pmset -g
    } > "$OUT" 2>&1
    rm -f "$DIR/.events" "$DIR/.events-since"
    sed -n '1,/^== sleep\/wake events/p' "$OUT" | sed '$d'
    echo "Full report: $OUT"
    if [ "$POST" = 0 ]; then
        echo "DEEPIDLE_POST=0: no issue opened."
    elif ! command -v gh >/dev/null 2>&1; then
        echo "gh not found: open an issue in $REPO with $OUT by hand."
    else
        BODY="$DIR/sleep-test-issue.md"
        {
            echo "**macOS sleep baseline** (\`tools/macos-sleep-test.sh report\`)"
            echo
            echo '```'
            sed '/^== pmset -g (now)/,$d' "$OUT"
            echo '```'
            echo
            echo "<details><summary>pmset -g at arm and at report</summary>"
            echo
            echo '```'
            sed -n '/^== pmset -g$/,/^== pmset -g assertions/p' "$DIR/sleep-test-arm.txt" | sed '$d'
            sed -n '/^== pmset -g (now)/,$p' "$OUT"
            echo '```'
            echo
            echo "</details>"
        } > "$BODY"
        watts=$(awk '/^mean power, asleep:/ { print $4; exit }' "$OUT")
        TITLE="macOS sleep baseline: ${watts:-?} W asleep ($(date -r "$t0" +%Y-%m-%d), $(sysctl -n hw.model))"
        if URL=$(gh issue create -R "$REPO" --title "$TITLE" --body-file "$BODY"); then
            echo "Opened $URL"
        else
            echo "Opening the issue failed: open one in $REPO with $BODY by hand (or rerun report)."
        fi
    fi
    ;;
*)
    echo "usage: macos-sleep-test.sh arm | report   (see the comments at the top of the script)"
    exit 1 ;;
esac
