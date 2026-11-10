#!/bin/bash
# K3: the PMU RTC alarm on the test chain (device tree with the alarm cells), awake, NO suspend: does it fire?
# C2 slept 4 h 23 min because the alarm did not wake the Mac and Aura's heartbeat keeps the watchdog fed.
R=/sys/class/rtc/rtc0; NV=$(ls /sys/bus/spmi/devices/0-0b/spmi_nvmem*/nvmem 2>/dev/null | head -1)
reg() { dd if=$NV bs=1 skip=$(($1)) count=${2:-1} 2>/dev/null | xxd -p; }
regs() { echo "ctrl 0x1401=$(reg 0x1401) time 0x1400..=$(reg 0x1400 12) alarm 0x140c=$(reg 0x140c 6) event 0x14c0=$(reg 0x14c0 2) mask 0x14c2=$(reg 0x14c2 2)"; }
log "K3 kernel $(uname -r); stage2 $(tr -d '\0' < /proc/device-tree/chosen/asahi,m1n1-stage2-version); rtc $(cat $R/name 2>/dev/null) wakealarm $([ -e $R/wakealarm ] && echo yes || echo no) nvmem ${NV:-none}"
log "rtc dmesg: $(dmesg | grep -iE 'rtc|spmi' | tail -6 | cut -c1-120 | tr '\n' '|')"
log "before: $(regs)"
irq0=$(grep -iE 'rtc|spmi|pmic|pmu' /proc/interrupts | tr -s ' ' | cut -c1-130 | tr '\n' '|')
echo 0 > $R/wakealarm 2>/dev/null; echo +10 > $R/wakealarm; rc=$?
log "set +10 s rc=$rc; wakealarm=$(cat $R/wakealarm 2>&1) since_epoch=$(cat $R/since_epoch); $(grep -E 'alrm|alarm' /proc/driver/rtc | tr -s '\t ' ' ' | tr '\n' '|')"
log "armed: $(regs)"
sleep 5; log "at 5 s: $(regs)"
sleep 10; log "at 15 s: $(regs)"
log "wakealarm now '$(cat $R/wakealarm 2>&1)'; $(grep -E 'alrm|alarm' /proc/driver/rtc | tr -s '\t ' ' ' | tr '\n' '|')"
log "irq before: $irq0"
log "irq after:  $(grep -iE 'rtc|spmi|pmic|pmu' /proc/interrupts | tr -s ' ' | cut -c1-130 | tr '\n' '|')"
log "new dmesg: $(dmesg | tail -6 | cut -c1-120 | tr '\n' '|')"
