#!/bin/bash
# K2: the PMU RTC alarm port (T602x cells, nub-spmi0 interrupt) on the stock boot.bin: does an alarm fire awake?
log "K2 kernel $(uname -r); online $(cat /sys/devices/system/cpu/online); mem_sleep $(cat /sys/power/mem_sleep)"
R=/sys/class/rtc/rtc0
log "rtc: name $(cat $R/name 2>/dev/null) wakealarm $([ -e $R/wakealarm ] && echo yes || echo no); rtc dmesg: $(dmesg | grep -iE 'rtc|spmi' | tail -5 | cut -c1-110 | tr '\n' '|')"
if [ -e $R/wakealarm ]; then
    irq0=$(grep -iE 'rtc|spmi' /proc/interrupts | tr -s ' ' | cut -c1-120 | tr '\n' '|')
    echo 0 > $R/wakealarm 2>/dev/null; echo +12 > $R/wakealarm; rc=$?
    log "set +12 s rc=$rc; wakealarm=$(cat $R/wakealarm) since_epoch=$(cat $R/since_epoch); alarm: $(grep -E 'alrm|alarm' /proc/driver/rtc | tr -s '\t ' ' ' | tr '\n' '|')"
    sleep 16
    log "after 16 s: wakealarm='$(cat $R/wakealarm)' alarm: $(grep -E 'alrm|alarm' /proc/driver/rtc | tr -s '\t ' ' ' | tr '\n' '|')"
    log "irq before: $irq0"
    log "irq after:  $(grep -iE 'rtc|spmi' /proc/interrupts | tr -s ' ' | cut -c1-120 | tr '\n' '|')"
fi
log "errors: $(dmesg -l err,crit,alert,emerg | wc -l) lines; first: $(dmesg -l err,crit,alert,emerg | head -4 | cut -c1-100 | tr '\n' '|')"
