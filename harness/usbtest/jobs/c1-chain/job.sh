#!/bin/bash
# C1: first boot of the rebuilt test chain (Aura image 62 on the reconstructed base, PSCI device tree with the
# PMP, patched U-Boot) through the one-shot loader. No suspend: is PSCI there, are all CPUs up, is `deep` offered?
C=/proc/device-tree/chosen
log "C1 kernel $(uname -r); stage2 $(tr -d '\0' < $C/asahi,m1n1-stage2-version) u-boot $(tr -d '\0' < $C/u-boot,version | cut -c1-40)"
log "online $(cat /sys/devices/system/cpu/online) of $(cat /sys/devices/system/cpu/present); mem_sleep $(cat /sys/power/mem_sleep)"
log "psci node $([ -d /proc/device-tree/psci ] && echo yes || echo no); psci/efi lines: $(dmesg | grep -iE 'psci|efi: ' | head -8 | cut -c1-110 | tr '\n' '|')"
log "watchdog: $(cat /sys/class/watchdog/watchdog0/state 2>/dev/null) timeleft $(cat /sys/class/watchdog/watchdog0/timeleft 2>/dev/null); wakealarm $([ -e /sys/class/rtc/rtc0/wakealarm ] && echo yes || echo no)"
log "pmp: $(dmesg | grep -i pmp | head -3 | cut -c1-110 | tr '\n' '|')"
log "errors: $(dmesg -l err,crit,alert,emerg | wc -l) lines; first: $(dmesg -l err,crit,alert,emerg | head -5 | cut -c1-100 | tr '\n' '|')"
