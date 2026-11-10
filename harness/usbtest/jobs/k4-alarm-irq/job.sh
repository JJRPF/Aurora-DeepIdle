#!/bin/bash
# K4: which interrupt does the PMU alarm raise? K3: the PMU drops the alarm enable bit at the alarm time (it fired),
# but Linux's handler on SPMI interrupt 2 never ran (count 0) and event 0x14c0 bit 0 stayed 0; 0x14c1 read 0x02.
# Here: the SPMI controller's mask (0x20..) and pending/ack (0x60..) words and the PMU's 0x14c0.. bytes around one
# alarm, then a write-1 to 0x14c1 bit 1 and a second alarm. Awake, NO suspend.
J=/run/usbtest/job; R=/sys/class/rtc/rtc0; NV=$(ls /sys/bus/spmi/devices/0-0b/spmi_nvmem*/nvmem 2>/dev/null | head -1)
reg() { dd if=$NV bs=1 skip=$(($1)) count=${2:-1} 2>/dev/null | xxd -p; }
put() { printf "\\x$2" | dd of=$NV bs=1 seek=$(($1)) count=1 conv=notrunc 2>/dev/null; }
ctl() { echo "mask $($J/mmio-read 0x29e114020 9 2>&1 | tr -s ' \n' ' ' | cut -c1-150) pend $($J/mmio-read 0x29e114060 9 2>&1 | tr -s ' \n' ' ' | cut -c1-150)"; }
pmu() { echo "ctrl=$(reg 0x1401) ev 0x14c0..=$(reg 0x14c0 8) aic724=$(grep -E '^ *[0-9]+:.* 724 ' /proc/interrupts | tr -s ' ' | cut -c1-60) spmi2=$(grep macsmc-rtc /proc/interrupts | awk '{s=0; for(i=2;i<=11;i++) s+=$i; print s}')"; }
log "K4 start: $(pmu)"
log "K4 start: $(ctl)"
log "interrupt lines: $(grep -iE 'spmi|724' /proc/interrupts | tr -s ' ' | cut -c1-110 | tr '\n' '|')"
for n in 1 2; do
    echo 0 > $R/wakealarm 2>/dev/null; echo "+6" > $R/wakealarm
    log "alarm $n armed: $(pmu)"
    sleep 9
    log "alarm $n +9 s: $(pmu)"
    log "alarm $n +9 s: $(ctl)"
    if [ $n = 1 ]; then put 0x14c1 02; log "after write 0x02 to 0x14c1: $(pmu)"; log "after write: $(ctl)"; fi
done
put 0x14c0 01; log "after write 0x01 to 0x14c0: $(pmu)"
log "end: $(ctl)"
