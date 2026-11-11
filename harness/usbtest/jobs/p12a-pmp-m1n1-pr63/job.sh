#!/bin/bash
# P12A (issue #12, steps 1, 3, 4): stage 2 = m1n1 PR 63 (pmp-tunables-fit, 2c324f27), DTB = t6020-j414s.dtb built from
# linux PR 933 (8f590c4d, PMP enabled). Records: the PMP node as m1n1 left it (status, tunables, FDT headroom), the
# kernel's PMP lines and pmp-* power domains, warnings and errors, then 10 s2idle cycles (RTC alarm, 20 s each) with
# display, Wi-Fi and USB checked after each. No S2R step, no MMIO writes. A failed boot ends at the 120 s watchdog.
J=/run/usbtest/job; C=/proc/device-tree/chosen; R=/sys/class/rtc/rtc0; O=/run/usbtest/results; mkdir -p $O
PUSH_TRIES=8
V=$(tr -d '\0' < $C/asahi,m1n1-stage2-version 2>/dev/null)
log "P12A kernel $(uname -r); stage2 $V; mem_sleep $(cat /sys/power/mem_sleep); cmdline $(cut -c1-200 /proc/cmdline)"
case "$V" in *2c324f27*) ;; *) log "stage 2 is not m1n1 PR 63: stopping"; push "P12A wrong stage 2" "$V"; return 0 ;; esac
P=$(ls -d /proc/device-tree/soc/pmp@* 2>/dev/null | head -1)
ST=$(tr -d '\0' < $P/status 2>/dev/null || echo "(no status property = okay)")
NT=$(ls $P 2>/dev/null | grep -c '^apple,tunable'); BT=$(cat $P/apple,tunable* 2>/dev/null | wc -c)
FDT=$(od -An -tx1 -N40 /sys/firmware/fdt | tr -d ' \n')
be() { printf '%d' 0x$(echo $FDT | cut -c$(( $1*8+1 ))-$(( $1*8+8 ))); }
TOT=$(be 1); OSTR=$(be 3); SSTR=$(be 8); USED=$(( OSTR + SSTR ))
log "pmp node $P status=$ST tunables=$NT ($BT bytes of values); FDT totalsize $TOT, used $USED (strings end), free $(( TOT - USED ))"
ls $P > $O/pmp-node-props.txt 2>/dev/null
dmesg | grep -iE 'pmp|pmgr-misc|pmgr_misc' > $O/dmesg-pmp.txt
log "pmp dmesg: $(grep -c . $O/dmesg-pmp.txt) lines: $(grep -iE 'firmware and endpoint ready|manages fabric|will not be powered off' $O/dmesg-pmp.txt | cut -c1-140 | tr '\n' '|')"
D=/sys/kernel/debug; mountpoint -q $D || mount -t debugfs none $D 2>/dev/null
grep -iE 'pmp' $D/pm_genpd/pm_genpd_summary > $O/genpd-pmp.txt 2>/dev/null
log "pmp domains: $(awk '{print $1"="$2}' $O/genpd-pmp.txt | tr '\n' ' ')"
dmesg -l warn,err,crit,alert,emerg > $O/dmesg-warn-boot.txt
log "boot warnings+errors: $(wc -l < $O/dmesg-warn-boot.txt) lines"
att() { echo "usb $(ls /sys/bus/usb/devices 2>/dev/null | grep -vc ':'), wifi $(ip -4 -o addr | awk '$2!="lo"{print $2, $4}' | tr '\n' ' '), drm $(for c in /sys/class/drm/card*-*; do printf '%s:%s/%s ' $(basename $c) $(cat $c/status 2>/dev/null) $(cat $c/enabled 2>/dev/null); done), bl $(cat /sys/class/backlight/*/brightness 2>/dev/null | tr '\n' ' ')"; }
A0=$(att); log "attached before: $A0"
push "P12A booted" "stage2 $V, pmp status=$ST tunables=$NT/$BT B, FDT free $(( TOT - USED )). $(grep -c 'firmware and endpoint ready' $O/dmesg-pmp.txt) ready line. Now 10 s2idle cycles (about 7 min)."
[ -e $R/wakealarm ] && grep -q s2idle /sys/power/mem_sleep || { log "no wakealarm or no s2idle, stopping"; return 0; }
echo s2idle > /sys/power/mem_sleep
WDT_P=/sys/module/apple_wdt/parameters/suspend_timeout; [ -e $WDT_P ] && echo 120 > $WDT_P
echo "cycle|asleep_s|rc|display|wifi_ping|usb|new_warn_lines" > $O/cycles.txt
for i in 1 2 3 4 5 6 7 8 9 10; do
    n0=$(dmesg -l warn,err,crit,alert,emerg | wc -l)
    echo 0 > $R/wakealarm 2>/dev/null; echo +20 > $R/wakealarm
    t0=$(date +%s.%N); echo mem > /sys/power/state; rc=$?; t1=$(date +%s.%N)
    dur=$(echo "$t1 $t0" | awk '{printf "%.1f", $1-$2}')
    ok=no; for k in 1 2 3 4 5 6 7 8 9 10; do ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && { ok="yes(${k})"; break; }; sleep 2; done
    n1=$(dmesg -l warn,err,crit,alert,emerg | wc -l)
    dmesg -l warn,err,crit,alert,emerg | tail -n $(( n1 - n0 )) > $O/cycle$i-new.txt 2>/dev/null
    dsp=$(for c in /sys/class/drm/card*-eDP*; do printf '%s/%s' $(cat $c/status 2>/dev/null) $(cat $c/enabled 2>/dev/null); done)
    line="$i|$dur|$rc|$dsp bl=$(cat /sys/class/backlight/*/brightness 2>/dev/null | head -1)|$ok|$(ls /sys/bus/usb/devices | grep -vc ':')|$(( n1 - n0 ))"
    echo "$line" >> $O/cycles.txt; log "cycle $line; s2idle: $(dmesg | grep -E 'PM: suspend (entry|exit)' | tail -2 | cut -c1-60 | tr '\n' '|')"
    [ $rc = 0 ] || break
    sleep 5
done
dmesg | grep -iE 'pmp|rtkit' | tail -40 > $O/dmesg-pmp-after.txt
grep -iE 'pmp' $D/pm_genpd/pm_genpd_summary > $O/genpd-pmp-after.txt 2>/dev/null
log "after: pmp domains $(awk '{print $1"="$2}' $O/genpd-pmp-after.txt | tr '\n' ' '); rtkit/pmp errors $(dmesg -l err,crit | grep -ciE 'pmp|rtkit'); attached: $(att)"
push "P12A s2idle done" "$(cat $O/cycles.txt | tr '\n' ' ') | after: $(awk '{print $1"="$2}' $O/genpd-pmp-after.txt | tr '\n' ' ')"
