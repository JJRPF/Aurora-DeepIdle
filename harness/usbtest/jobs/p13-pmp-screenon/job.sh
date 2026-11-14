#!/bin/bash
# P13A / P13B (PR 933 follow-up): power with the display ON at a fixed backlight, PMP vs no PMP, same kernel (7.3.0-pr933+) and
# same stage 2 (m1n1 with PR 63, edcd9a66). P13A = the rebased PR 933 DTB (PMP), P13B = the same tree without APPLE_USE_PMP (control).
# After a settle time: 16 windows of 30 s, SMC power sensors once a second (Total System Power, Heatpipe Power), mean per window.
# Chain boot, no results drive: everything that matters is pushed as text. No S2R, no MMIO writes.
J=/run/usbtest/job; O=/run/usbtest/results; mkdir -p $O; PUSH_TRIES=8
C=/proc/device-tree/chosen
V=$(tr -d '\0' < $C/asahi,m1n1-stage2-version 2>/dev/null)
P=$(ls -d /proc/device-tree/soc/pmp@* 2>/dev/null | head -1)
ST=$(tr -d '\0' < $P/status 2>/dev/null || echo "none")
NT=$(ls $P 2>/dev/null | grep -c '^apple,tunable')
[ "$NT" -gt 0 ] && L=P13A || L=P13B
log "$L kernel $(uname -r); stage2 $V; pmp node ${P:-absent} status=$ST tunables=$NT"
case "$V" in *edcd9a66*) ;; *) log "stage 2 is not m1n1 edcd9a66: stopping"; push "$L wrong stage 2" "$V"; return 0 ;; esac
case "$(uname -r)" in 7.3.0-pr933*) ;; *) log "kernel is not 7.3.0-pr933: stopping"; push "$L wrong kernel" "$(uname -r)"; return 0 ;; esac
modprobe macsmc-hwmon 2>/dev/null; modprobe macsmc_hwmon 2>/dev/null
HW=""; for h in /sys/class/hwmon/hwmon*; do [ "$(cat $h/name 2>/dev/null)" = macsmc_hwmon ] && HW=$h; done
log "hwmon: ${HW:-none}: $(for l in $HW/power*_label; do printf '%s=%s ' $(basename $l _label) "$(cat $l)"; done 2>/dev/null | cut -c1-300)"
[ -n "$HW" ] || { push "$L no smc hwmon" "$(ls /sys/class/hwmon | tr '\n' ' ')"; return 0; }
TOT=""; HP=""
for l in $HW/power*_label; do n=$(cat $l); i=$(basename $l _label); case "$n" in *"Total System"*) TOT=$HW/${i}_input ;; *Heatpipe*) HP=$HW/${i}_input ;; esac; done
[ -n "$TOT" ] || { push "$L no total power sensor" "$(for l in $HW/power*_label; do printf '%s=%s ' $(basename $l _label) "$(cat $l)"; done)"; return 0; }
# display on, fixed backlight (about 40% of max), no console blanking
echo 0 > /sys/module/kernel/parameters/consoleblank 2>/dev/null
B=$(ls -d /sys/class/backlight/* 2>/dev/null | head -1)
if [ -n "$B" ]; then mx=$(cat $B/max_brightness); echo $(( mx * 40 / 100 )) > $B/brightness; log "backlight $(cat $B/brightness)/$mx"; fi
dsp=$(for c in /sys/class/drm/card*-eDP*; do printf '%s/%s' $(cat $c/status 2>/dev/null) $(cat $c/enabled 2>/dev/null); done); log "display $dsp"
echo "settle 120 s" > /dev/console 2>/dev/null; sleep 120
rd() { cat "$1" 2>/dev/null || echo 0; }
echo "win|total_W|heatpipe_W|busy%" > $O/windows.txt
for w in $(seq 1 16); do
    s1=0; s2=0; n=0; b0=$(awk '/^cpu /{print $2+$3+$4+$7+$8, $2+$3+$4+$5+$6+$7+$8}' /proc/stat)
    for k in $(seq 1 30); do a=$(rd $TOT); b=$([ -n "$HP" ] && rd $HP || echo 0); s1=$((s1 + a)); s2=$((s2 + b)); n=$((n+1)); sleep 1; done
    b1=$(awk '/^cpu /{print $2+$3+$4+$7+$8, $2+$3+$4+$5+$6+$7+$8}' /proc/stat)
    busy=$(echo "$b0 $b1" | awk '{d=$4-$2; printf "%.1f", d>0 ? 100*($3-$1)/d : 0}')
    echo "$w|$(echo $s1 $n | awk '{printf "%.3f", $1/$2/1e6}')|$(echo $s2 $n | awk '{printf "%.3f", $1/$2/1e6}')|$busy" >> $O/windows.txt
done
S=$(awk -F'|' 'NR>1{t+=$2;h+=$3;b+=$4;n++} END{printf "mean total %.3f W, heatpipe %.3f W, busy %.1f%% over %d windows", t/n, h/n, b/n, n}' $O/windows.txt)
log "$L $S"
push "$L power (display on, backlight ~40%)" "$V, $(uname -r), pmp tunables=$NT: $S | windows: $(tail -n +2 $O/windows.txt | tr '\n' ' ')"
dmesg -l warn,err,crit,alert,emerg | sed -E 's/^\[ *[0-9.]+\] //' | cut -c1-160 | head -20 > $O/warn.txt
push "$L warnings" "$(cat $O/warn.txt)"
