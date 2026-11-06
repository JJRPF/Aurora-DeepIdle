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
# LOGF moves to /run while the filesystems are forced read-only (slpa runs) and is appended afterwards.
LOGF=$OUT/run.log
log() { echo "$(date '+%F %T') $*" | tee -a $LOGF; echo "psci-efi-test: $*" > /dev/kmsg; sync; }
sleep 45
log "step $STEP; kernel $(uname -r); booted m1n1 image $(cat /run/psci-efi-booted-sha 2>/dev/null)"
log "online: $(cat /sys/devices/system/cpu/online); nproc $(nproc)"
# The PMU's record of the last power-off and boot (spmi_nvmem cells): how did the previous boot end?
NV=$(ls -d /sys/bus/nvmem/devices/spmi_nvmem*/cells | head -1)   # spmi_nvmem2 on the default kernel, 0 on the test kernel
log "pmu: $(for c in boot-stage@6001,0 boot-error-count@6002,0 boot-error-stage@6003,0 panic-count@6002,4 shutdown-flag@600f,3 fault-shadow@867b,0; do printf '%s=%s ' ${c%%@*} $(xxd -p $NV/$c 2>/dev/null | tr -d '\n'); done)"
dmesg > $OUT/dmesg.txt; chmod 644 $OUT/dmesg.txt
grep -iE "psci|smp: |cpu[0-9]+: (failed|boot)|failed to come online|efi:" $OUT/dmesg.txt | tee -a $OUT/key-lines.txt | head -40
sync
# What Aura left in /chosen for U-Boot and the kernel (raw property bytes), and the kernel's iomem view
for pr in /proc/device-tree/chosen/aura,*; do [ -e "$pr" ] && { echo "== $pr"; xxd "$pr"; } ; done > $OUT/chosen-aura.txt 2>&1
cp /proc/iomem $OUT/iomem.txt 2>/dev/null; cat /sys/firmware/efi/systab > $OUT/systab.txt 2>/dev/null
sync
if [ $STEP = suspend ] || [ $STEP = suspendall ]; then
    # Phase 2a: one system suspend on the boot CPU alone (maxcpus=1, nothing is ever offlined). Aura waits 3 s and
    # resumes the kernel. Filesystems go read-only first so a hang cannot leave them dirty.
    log "mem_sleep: $(cat /sys/power/mem_sleep); state: $(cat /sys/power/state); online $(cat /sys/devices/system/cpu/online)"
    if [ "$(cat /run/psci-efi-booted-sha 2>/dev/null)" = 76f850895fed53d1 ]; then
        log "booted the default image, not the test image: not suspending"
    elif grep -q "deep" /sys/power/mem_sleep; then
        sync
        for m in $(findmnt -rno TARGET -t ext4,btrfs,vfat | sort -r); do mount -o remount,ro "$m" 2>&1 | head -1; done
        log "filesystems ro: $(findmnt -rno TARGET,OPTIONS -t ext4,btrfs,vfat | grep -c '\bro\b') of $(findmnt -rno TARGET -t ext4,btrfs,vfat | wc -l)"
        NCYC=$(cat /var/lib/deepidle/suspend-cycles 2>/dev/null || echo ${SUSPEND_CYCLES:-3})
        SUSPEND_ALARM=$(cat /var/lib/deepidle/suspend-alarm 2>/dev/null || echo ${SUSPEND_ALARM:-10})
        # Dead-man switch (deadman.sh): after each wake it reads the NVMe directly and resets the Mac if the
        # disk is gone (what `slpa` did on 2026-11-04). Everything it needs lives in RAM.
        DM=/run/psci-deadman; mkdir -p $DM; cp /usr/bin/dd $(dirname $0)/deadman.sh $DM/; cp $(dirname $0)/mmio-read-static $DM/mmio-read 2>/dev/null; [ -p $DM/fifo ] || mkfifo $DM/fifo
        python3 -c 'import json;print(json.load(open("/home/jjr/.config/agent-notify/config.json"))["ntfy_topic"])' > $DM/topic 2>/dev/null; chmod 600 $DM/topic
        getent ahostsv4 ntfy.sh | awk 'NR==1{print $1}' > $DM/ntfy-ip
        # for the dead-man switch's snapshot after a resume with the disk gone (2026-11-05 15:22): the PMGR
        # counters and Aura's psci_dbg words, read by RAM-resident static tools
        [ -e /var/lib/deepidle/pmgr-counters ] && cp /usr/local/lib/deepidle/pmgrcnt $DM/ 2>/dev/null
        cp /usr/local/lib/deepidle/scan-magic-static $DM/scan-magic 2>/dev/null
        SLPA=0; DS=$(grep -o 'deep_steps=[0-9]*' /proc/cmdline | cut -d= -f2); [ -n "$DS" ] && [ $(( DS & 4 )) != 0 ] && SLPA=1
        grep -q 'macsmc.pmp_sleep=1' /proc/cmdline && SLPA=1   # the PMP's own sleep: the disk may not come back either
        [ -e /var/lib/deepidle/force-ro ] && SLPA=1   # to test the read-only mode without slpa
        if [ $SLPA = 1 ]; then
            # slpa can take the disk away while btrfs is still writable (remount ro fails while the desktop
            # holds files open). Force every filesystem read-only (sysrq u) for the cycles.
            sync; echo u > /proc/sysrq-trigger; sleep 2
            LOGF=/run/psci-efi-run-ro.log
            log "slpa run: emergency read-only remount: superblock ro $(findmnt -rno TARGET,FS-OPTIONS -t ext4,btrfs,vfat | grep -c '\bro\b') of $(findmnt -rno TARGET -t ext4,btrfs,vfat | wc -l)"
        fi
        # /var/lib/deepidle/poke-wakemask: write macOS's PMGR AP wake-source mask while awake (after the read-only
        # remount, kmsg still streaming), read it back after 10 s and put the old words back, before any cycle
        W=/usr/local/lib/deepidle/wakemask
        if [ -e /var/lib/deepidle/poke-wakemask ] && [ -x $W ]; then
            OLD=$($W show | sed -n 's/^before mask \([0-9a-f ]*\); .*/\1/p')
            log "wakemask: old $OLD; writing macOS's value"
            log "wakemask: $($W macos | tail -1)"
            sleep 10
            log "wakemask: 10 s later $($W show | sed 's/^before //')"
            log "wakemask: restore: $($W write $OLD | tail -1)"
        fi
        # /var/lib/deepidle/pmgr-counters: turn on the PMGR's system-state counters (SLP_S2R and the rest) before the
        # cycles and log them after each one
        PC=""
        if [ -e /var/lib/deepidle/pmgr-counters ] && [ -x /usr/local/lib/deepidle/pmgrcnt ]; then
            PC=/usr/local/lib/deepidle/pmgrcnt
            log "pmgr counters: before $($PC show)"
            log "pmgr counters: enabled $($PC enable)"
            sleep 2
            log "pmgr counters: 2 s later $($PC show)"
        fi
        # Modes from /var/lib/deepidle/sleep-modes (default deep), e.g. "deep s2idle" for a drain A/B on one boot.
        # In s2idle Aura is not involved, so nothing would pet the test kernel's watchdog: its suspend arm is off then.
        BAT=/sys/class/power_supply/macsmc-battery
        # On battery with the charger in: /var/lib/deepidle/discharge asks for the SMC's force-discharge
        # (charge_behaviour resets to auto at every boot; the thresholds persist and set where it stops)
        if [ -e /var/lib/deepidle/discharge ]; then
            echo auto-discharge > $BAT/charge_behaviour; sleep 30
            log "discharge on: $(cat $BAT/status), limit $(cat $BAT/charge_control_end_threshold)%, capacity $(cat $BAT/capacity)%"
        fi
        # /var/lib/deepidle/trace-cpuhp: trace the CPU hotplug steps (they run on the incoming core too), saved after
        # each cycle, to see where a secondary that does not come back stops
        T=/sys/kernel/tracing
        if [ -e /var/lib/deepidle/trace-cpuhp ] && [ -d $T/events/cpuhp ]; then
            echo 8192 > $T/buffer_size_kb; echo > $T/trace; echo 1 > $T/events/cpuhp/enable; echo 1 > $T/tracing_on
            log "cpuhp tracing on: $(cat $T/events/cpuhp/enable)"
        fi
        aopirq() { awk '/2a6408000.mbox-recv/ { s = 0; for (i = 2; i <= NF && $i ~ /^[0-9]+$/; i++) s += $i; print s }' /proc/interrupts; }
        for MODE in $(cat /var/lib/deepidle/sleep-modes 2>/dev/null || echo deep); do
        echo $MODE > /sys/power/mem_sleep
        WDT_P=/sys/module/apple_wdt/parameters/suspend_timeout
        [ -e $WDT_P ] && { [ $MODE = s2idle ] && echo 0 > $WDT_P || echo 120 > $WDT_P; }
        log "mode $MODE: mem_sleep $(cat /sys/power/mem_sleep); apple_wdt suspend_timeout $(cat $WDT_P 2>/dev/null)"
        # /var/lib/deepidle/pmp-release-modes "<modes>": in those modes the PMP's always-on display requests are
        # withdrawn for sleep (test kernel pmp_report.test_release_aon), as macOS has them at slpa; off in the others.
        REL_P=/sys/module/pmp_report/parameters/test_release_aon
        if [ -e /var/lib/deepidle/pmp-release-modes ] && [ -e $REL_P ]; then
            if grep -qw $MODE /var/lib/deepidle/pmp-release-modes; then echo 1 > $REL_P; else echo 0 > $REL_P; fi
            log "pmp release for sleep: $(cat $REL_P); requests $(/usr/local/lib/deepidle/mmio-read 0x28e3c2000 1 | awk '{print $2}') ack $(/usr/local/lib/deepidle/mmio-read 0x28e3c2080 1 | awk '{print $2}')"
        fi
        for i in $(seq $NCYC); do
            # Phase 2b: with SUSPEND_ALARM=<s> an RTC alarm is armed first; Aura's poll should end the wait on that wake
            # line (elapsed ~ alarm) instead of its 30 s timeout. Without it the wait runs the full timeout.
            { rtcwake -m no -s ${SUSPEND_ALARM:-10} 2>&1 | head -1; log "alarm: $(cat /sys/class/rtc/rtc0/wakealarm 2>&1)"; }
            log "battery: $(cat /sys/class/power_supply/macsmc-battery/status) charge_now $(cat /sys/class/power_supply/macsmc-battery/charge_now) ac $(cat /sys/class/power_supply/macsmc-ac/online); cmdline steps: $(grep -o -E 'deep_steps=[0-9]*|pmp_sleep=[0-9]' /proc/cmdline | tr '\n' ' ')"
            # /var/lib/deepidle/aura-ctl <value>: Aura's S2R steps for this suspend (image 52, harness/mmio/aura-ctl.c;
            # 1 the PMGR's S2R timer, 2 every core into macOS's deep sleep, 0x80 a marker that changes nothing)
            [ -e /var/lib/deepidle/aura-ctl ] && log "aura ctl: $(/usr/local/lib/deepidle/aura-ctl $(cat /var/lib/deepidle/aura-ctl) 2>&1)"
            t0=$(date +%s.%N); e0=$(cat $BAT/energy_now); q0=$(aopirq)
            setsid $DM/deadman.sh $DM/resumed-$MODE-$i $(( ${SUSPEND_ALARM:-10} + 300 )) < /dev/null > /dev/null 2>&1 &
            DMPID=$!
            log "suspend $MODE $i: echo mem ... (energy_now $e0 uWh, $(cat $BAT/status), behaviour $(sed 's/.*\[\(.*\)\].*/\1/' $BAT/charge_behaviour))"
            if [ -e /var/lib/deepidle/suspend-via-systemd ]; then
                # the real path: runs the /etc/systemd/system-sleep hooks (radios off/on, fprintd) around the suspend
                systemctl suspend -i; rc=$?
                log "radios after resume: $(nmcli radio | tail -1); rfkill: $(rfkill -n -o TYPE,SOFT | tr '\n' ' ')"
                log "sleep hooks: $(journalctl -b --no-pager -o cat -u systemd-suspend.service -n 12 | tr '\n' '|' | cut -c1-400)"
            else
                echo mem > /sys/power/state; rc=$?
            fi
            t1=$(date +%s.%N); e1=$(cat $BAT/energy_now); q1=$(aopirq)
            : > $DM/resumed-$MODE-$i
            wait $DMPID; dmrc=$?
            log "dead-man switch: rc=$dmrc; $(tail -1 $DM/log)"
            # Aura's debug words (psci_dbg, ELF symbol 0x1472c8 from the image base): magic, HCR_EL2, DAIF, exit (1 wake line, 2 timeout), last ISR_EL1, ticks
            AB=$(xxd -p /proc/device-tree/chosen/aura,psci-runtime-code | cut -c1-16)
            log "aura dbg (words, low/high pairs): $(/usr/local/lib/deepidle/mmio-read $((0x$AB + 0x1472c8)) 16 | awk '{printf "%s ", $2}')"
            log "aura dbg scan: $(/usr/local/lib/deepidle/scan-magic 0xA0AA0001 64 | head -3 | tr '\n' ';')"
            # Aura's shared SMP state (psci_cpu_state at +0xc0000, spin_table
            # at +0xc01b0, 0x40 per CPU: mpidr, flag (entries taken), target): where a core that did not come back is
            # image base = the DT's aura,psci-runtime-code - 0x10000 (images 53, 54); psci_cpu_state is at +0xc0000 in both
            AB0=$(xxd -p /proc/device-tree/chosen/aura,psci-runtime-code | cut -c1-16)
            if [ -n "$AB0" ]; then
                SB=$(( 0x$AB0 - 0x10000 + 0xc0000 ))
                log "aura cpu states (0 parked, 1 on, 2 off): $(/usr/local/lib/deepidle/mmio-read $SB 3 | awk '{printf "%s ", $2}'); spin flag/target: $(for c in 1 2 3 4 5 6 8 9 10; do o=$(( SB + 0x1b0 + c * 0x40 )); printf '%s:%s/%s ' $c $(/usr/local/lib/deepidle/mmio-read $(( o + 8 )) 1 | awk '{print $2}') $(/usr/local/lib/deepidle/mmio-read $(( o + 16 )) 1 | awk '{print $2}'); done)"
            fi
            log "battery after: $(cat /sys/class/power_supply/macsmc-battery/status) charge_now $(cat /sys/class/power_supply/macsmc-battery/charge_now); smc: $(dmesg | grep -E 'macsmc-reboot.*sleep:|SetAPPower' | grep -v psci-efi-test | tail -4 | sed 's/^\[[ 0-9.]*\] //' | tr '\n' '|')"
            [ -n "$PC" ] && log "pmgr counters after $MODE $i: $($PC show)"
            # the AOP's mailbox interrupts over the cycle (its outbox is an AP wake source), and the test kernel's
            # SetAPPower to the AOP around the sleep (apple_aop.sleep_ap_idle)
            log "aop mbox irqs over the cycle: $(( q1 - q0 )); als $(timeout 5 cat /sys/bus/iio/devices/iio:device*/in_illuminance_input 2>&1 | head -1), lid angle $(timeout 5 cat /sys/bus/iio/devices/iio:device*/in_angl_raw 2>&1 | head -1); $(dmesg | grep 'TEST SetAPPower' | tail -2 | sed 's/^\[[ 0-9.]*\] //' | tr '\n' '|')"
            log "suspend $MODE $i: back, rc=$rc, elapsed $(echo "$t1 - $t0" | bc); online $(cat /sys/devices/system/cpu/online); energy $e0 -> $e1 uWh: $(echo "scale=3; ($e0 - $e1) * 3.6 / ($t1 - $t0) / 1000" | bc) W average over the cycle"
            [ -e /var/lib/deepidle/pmp-release-modes ] && log "pmp requests after resume: $(/usr/local/lib/deepidle/mmio-read 0x28e3c2000 1 | awk '{print $2}') ack $(/usr/local/lib/deepidle/mmio-read 0x28e3c2080 1 | awk '{print $2}')"
            if [ -e /var/lib/deepidle/trace-cpuhp ] && [ -e $T/trace ]; then
                mkdir -p /run/psci-cpuhp; TF=/run/psci-cpuhp/cpuhp-$MODE-$i.txt; cp $T/trace $TF; echo > $T/trace
                log "cpuhp trace $MODE $i: $(grep -c cpuhp $TF) events; last on cpu1: $(grep -E '\[001\]' $TF | tail -2 | sed 's/^ *//' | cut -c1-150 | tr '\n' '|')"
            fi
            [ $rc = 0 ] || break
            sleep 2
        done
        [ $rc = 0 ] || break
        done
        [ -e $WDT_P ] && echo 120 > $WDT_P
        if [ -e /var/lib/deepidle/discharge ]; then
            # the file may name the thresholds to put back: "<end> <start>", e.g. "80 75"
            read -r DE DS2 < /var/lib/deepidle/discharge || true
            echo auto > $BAT/charge_behaviour
            [ -n "${DS2:-}" ] && { echo $DE > $BAT/charge_control_end_threshold; echo $DS2 > $BAT/charge_control_start_threshold; }
            log "discharge off: $(cat $BAT/status), limit $(cat $BAT/charge_control_end_threshold)/$(cat $BAT/charge_control_start_threshold)"
        fi
    else
        log "no deep sleep offered; not suspending"
    fi
    for m in $(findmnt -rno TARGET -t ext4,btrfs,vfat | sort); do mount -o remount,rw "$m" 2>&1 | head -1; done
    if [ "${SLPA:-0}" = 1 ]; then cat $LOGF >> $OUT/run.log; LOGF=$OUT/run.log; log "filesystems rw again: superblock rw $(findmnt -rno TARGET,FS-OPTIONS -t ext4,btrfs,vfat | grep -c '\brw\b') of $(findmnt -rno TARGET -t ext4,btrfs,vfat | wc -l)"; fi
    [ -d /run/psci-cpuhp ] && cp /run/psci-cpuhp/* $OUT/ 2>/dev/null
    dmesg > $OUT/dmesg-after.txt; chmod 644 $OUT/*; sync
    log "summary: $(grep -c 'back, rc=0' $OUT/run.log) cycles back with rc=0; device errors after the first suspend: $(sed -n '/PM: suspend entry/,$p' $OUT/dmesg-after.txt | grep -i -E 'error|fail|timeout|warning:|\bbug:' | grep -v -E 'audit|psci-deadman|psci-efi-test|Endpoint 0x20 is not running|Failed to send command|brcmf_p2p|p2p_disc|add iface p2p|join_pref|Util_Reset_FailGeom|set affinity failed\(-38\)' | wc -l)"
    log "suspend step done; online $(cat /sys/devices/system/cpu/online)"
    rm -f /var/lib/deepidle/psci-efi-armed
    exit 0
fi
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
