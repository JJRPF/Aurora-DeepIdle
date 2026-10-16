#!/bin/bash
# Deep idle unattended test runner: one step of /var/lib/deepidle/plan per boot.
# Started by deepidle-runner.service as root. Results go to /var/lib/deepidle/results/<n>-<name>/,
# world-readable, for the resumed Claude session to analyse. Stop it any time with
# `touch /home/jjr/.local/state/deepidle/stop` (restores stock, does not reboot).
set -u
LIB=/usr/local/lib/deepidle
VAR=/var/lib/deepidle
CTL=/home/jjr/.local/state/deepidle
WORK=/home/jjr/Work/deep-idle-build
STOCK=$WORK/boot.bin.before-pmp-test
STOCK_SHA=3630adc3b3be173c
umask 022
mkdir -p $VAR/results
log() { echo "$(date '+%F %T') $*" | tee -a $VAR/runner.log; echo "$*" > $VAR/status; }

restore_stock() {
    if [ "$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)" != "$STOCK_SHA" ]; then
        cp $STOCK /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync
        log "restored stock boot.bin ($(sha256sum /boot/m1n1/boot.bin | cut -c1-16))"
    fi
}

finish() {
    mountpoint -q /boot || mount /boot
    restore_stock
    grub-editenv /boot/grub/grubenv unset next_entry
    rm -f $VAR/plan $CTL/resume
    log "FINISHED: $1"
    exit 0
}

[ -f $VAR/plan ] || exit 0
[ -e $CTL/stop ] && finish "stop requested"
n=$(cat $VAR/current 2>/dev/null || echo 0)
line=$(sed -n "$((n + 1))p" $VAR/plan)
[ -n "$line" ] || finish "plan done"
read -r name image entry settings load <<< "$line"
dir=$VAR/results/$n-$name
mkdir -p $dir

# A step that started on an earlier boot and never finished means that boot hung or
# reset (watchdog, power cycle): record it and move on rather than retry for ever.
if [ -e $dir/started ] && [ ! -e $dir/done ]; then
    log "step $n $name did not finish on its last boot: skipped"
    echo "interrupted on an earlier boot" > $dir/done
    echo $((n + 1)) > $VAR/current
    restore_stock
    exec $0
fi
date '+%F %T' > $dir/started
# A boot that is not healthy measures nothing useful: stop the campaign instead of moving on.
problems=""
mountpoint -q /boot || problems="$problems /boot-not-mounted"
[ -e /usr/lib/modules/$(uname -r)/modules.dep ] || problems="$problems no-module-tree"
grep -qx 'Total System Power' /sys/class/hwmon/hwmon*/power*_label 2>/dev/null || problems="$problems no-smc-power-sensor"
if [ -n "$problems" ]; then
    echo "unhealthy:$problems" > $dir/done
    finish "step $n $name: unhealthy boot ($problems)"
fi
# GRUB clears next_entry itself; clear it again in case its save_env failed.
grub-editenv /boot/grub/grubenv unset next_entry
booted=$(cat /run/deepidle-booted-sha 2>/dev/null || sha256sum /boot/m1n1/boot.bin | cut -c1-16)
echo "$booted" > $dir/booted-sha.txt
log "step $n $name: booted boot.bin $booted kernel $(uname -r)"
# The test image only had to boot this once: put the stock one back first.
restore_stock
python3 -I $LIB/deep-idle-check.py --seconds 5 > $dir/check.txt 2>&1
journalctl -k -b > $dir/dmesg.txt 2>&1
cat /proc/cmdline > $dir/cmdline.txt
cp /sys/kernel/debug/pm_genpd/pm_genpd_summary $dir/genpd.txt 2>/dev/null
# What m1n1 left for the PMP (the diagnostic m1n1 records its tunable copy in /chosen).
DTB=/sys/firmware/devicetree/base
{ for f in $DTB/chosen/asahi,pmp-tunables-*; do [ -e "$f" ] && { echo "== ${f##*/}"; od -An -tx1 "$f"; }; done
  echo "== pmp node"; ls $DTB/soc/pmp@28e700000/ 2>&1; cat $DTB/soc/pmp@28e700000/status 2>/dev/null; echo
  echo "== tunable bytes: $(cat $DTB/soc/pmp@28e700000/apple,tunable-* 2>/dev/null | wc -c)"; } > $dir/pmp-dt.txt 2>&1

log "step $n $name: settling 180 s"
sleep 180
log "step $n $name: measuring ($settings)"
IFS=, read -r -a args <<< "$settings"
loadpid=""
if [ -n "${load:-}" ]; then
    $LIB/wakeload ${load//:/ } &
    loadpid=$!
    echo "wakeload ${load//:/ }" > $dir/load.txt
    sleep 5
fi
nice -n 19 python3 -I $LIB/idle-ab.py --rounds ${ROUNDS:-15} --window 20 --log $dir/idle-ab.jsonl "${args[@]}" \
    > $dir/idle-ab.txt 2>&1
echo "exit $?" >> $dir/idle-ab.txt
[ -n "$loadpid" ] && kill $loadpid
if [ -e $VAR/wakelat ]; then
    for s in "${args[@]}"; do
        python3 -I $LIB/apply-setting.py "$s" && for t in "timer 1 1000 2000" "timer 9 1000 2000" "ipi 1 2 1000 2000" "ipi 1 6 1000 2000"; do
            echo "$s $t: $($LIB/wakelat $t)"
        done
    done > $dir/wakelat.txt 2>&1
    python3 -I $LIB/apply-setting.py default
fi
cat /sys/devices/system/cpu/cpu*/cpuidle/state*/disable | sort | uniq -c > $dir/disable-after.txt
date '+%F %T' > $dir/done
log "step $n $name: done"

# Arm the next step, then wait for the Claude session's acknowledgement before rebooting.
next=$((n + 1))
echo $next > $VAR/current
nline=$(sed -n "$((next + 1))p" $VAR/plan)
if [ -z "$nline" ]; then
    finish "plan done after step $n"
fi
read -r nname nimage nentry nsettings <<< "$nline"
if [ "$nimage" != stock ]; then
    cp $WORK/boot.bin.$nimage /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync
fi
if [ "$nentry" != default ]; then
    grub-editenv /boot/grub/grubenv set next_entry=$nentry
fi
log "step $next $nname armed: boot.bin $(sha256sum /boot/m1n1/boot.bin | cut -c1-16), grub next_entry=$nentry; waiting for ack-$n"
for i in $(seq 180); do
    [ -e $CTL/ack-$n ] && break
    [ -e $CTL/stop ] && finish "stop requested before step $next"
    sleep 10
done
# No acknowledgement means the session did not come back (no network, no login): do not go on blind.
[ -e $CTL/ack-$n ] || finish "no ack-$n within 30 min, step $next $nname not run"
log "rebooting into step $next $nname"
systemctl reboot
