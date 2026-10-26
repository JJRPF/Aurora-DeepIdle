#!/bin/bash
# PSCI-via-EFI test, once, after the armed boot (psci-efi-run.service). What it records depends on the
# step in /var/lib/deepidle/psci-efi-armed:
#   step0  stock kernel on the Aura stage 2 (no PSCI): boots, all CPUs online, kernel messages
#   step1a psci-efi-test kernel on the stock boot.bin (spin-table): the kernel build itself boots
#   step1m same image as step1 but maxcpus=1: the kernel only probes the EFI PSCI handler; then each secondary
#          is brought online ONCE from the running system (logged before and after), then as step1
#   step1  psci-efi-test kernel on the Aura + patched U-Boot + PSCI DTB: does the kernel find the
#          EFI PSCI table, are all 10 CPUs online, then every secondary offline/online N times
# Results: /var/lib/deepidle/results-psci-efi-<step>/ (synced as it goes). Never changes anything
# but CPU online state; the stock boot.bin is already back (psci-efi-early.service).
set -u
STEP=$(cat /var/lib/deepidle/psci-efi-armed)
OUT=/var/lib/deepidle/results-psci-efi-$STEP-$(date +%Y%m%d-%H%M)
CYCLES=${CYCLES:-3}
mkdir -p $OUT; chmod 755 $OUT
# every line also goes to the kernel log, so the Pi's live dmesg stream shows the last action even if the
# machine dies before the file reaches the disk
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/run.log; echo "psci-efi-test: $*" > /dev/kmsg; sync; }
sleep 45
log "step $STEP; kernel $(uname -r); booted m1n1 image $(cat /run/psci-efi-booted-sha 2>/dev/null)"
log "online: $(cat /sys/devices/system/cpu/online); nproc $(nproc)"
dmesg > $OUT/dmesg.txt; chmod 644 $OUT/dmesg.txt
grep -iE "psci|smp: |cpu[0-9]+: (failed|boot)|failed to come online|efi:" $OUT/dmesg.txt | tee -a $OUT/key-lines.txt | head -40
sync
# What Aura left in /chosen for U-Boot and the kernel (raw property bytes), and the kernel's iomem view
for pr in /proc/device-tree/chosen/aura,*; do [ -e "$pr" ] && { echo "== $pr"; xxd "$pr"; } ; done > $OUT/chosen-aura.txt 2>&1
cp /proc/iomem $OUT/iomem.txt 2>/dev/null; cat /sys/firmware/efi/systab > $OUT/systab.txt 2>/dev/null
sync
case $STEP in step1|step1m) ;; *) log "$STEP done"; rm -f /var/lib/deepidle/psci-efi-armed; exit 0 ;; esac
if ! grep -qi "PSCIv" $OUT/dmesg.txt; then log "no PSCI version line: table not found, stopping before hotplug"; rm -f /var/lib/deepidle/psci-efi-armed; exit 0; fi
if [ $STEP = step1m ]; then
    for c in $(seq 1 9); do
        f=/sys/devices/system/cpu/cpu$c/online; [ -e $f ] || { log "cpu$c: no online file (not registered)"; continue; }
        log "onlining cpu$c ..."
        echo 1 > $f 2>>$OUT/online-errors.txt; log "cpu$c online -> $(cat $f); online: $(cat /sys/devices/system/cpu/online)"
        dmesg | tail -n 6 > $OUT/last-dmesg-online-cpu$c.txt
    done
fi
if [ "$(nproc)" != 10 ]; then log "not all CPUs online, stopping before hotplug"; rm -f /var/lib/deepidle/psci-efi-armed; exit 0; fi
fail=0
for c in $(ls -d /sys/devices/system/cpu/cpu[0-9]* | sed 's#.*/cpu##' | sort -n); do
    [ "$c" = 0 ] && continue
    f=/sys/devices/system/cpu/cpu$c/online; [ -e $f ] || { log "cpu$c: no online file"; continue; }
    ok=0
    for i in $(seq $CYCLES); do
        log "cpu$c cycle $i: offline ..."
        echo 0 > $f 2>/dev/null; [ "$(cat $f)" = 0 ] || { log "cpu$c cycle $i: offline failed"; fail=1; break; }
        log "cpu$c cycle $i: offline ok, online ..."
        echo 1 > $f 2>/dev/null; [ "$(cat $f)" = 1 ] || { log "cpu$c cycle $i: online failed"; fail=1; break; }
        ok=$i
    done
    log "cpu$c: $ok/$CYCLES cycles ok"
    dmesg | tail -n 5 > $OUT/last-dmesg-cpu$c.txt
    [ $fail = 0 ] || break
done
dmesg > $OUT/dmesg-after.txt; chmod 644 $OUT/*
log "step1 hotplug done, fail=$fail; online $(cat /sys/devices/system/cpu/online)"
rm -f /var/lib/deepidle/psci-efi-armed
