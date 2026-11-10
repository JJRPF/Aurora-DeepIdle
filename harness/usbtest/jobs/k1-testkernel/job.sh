#!/bin/bash
# K1: the rebuilt PSCI test kernel (7.2.11-psci-efi+) on the stock boot.bin: does the build boot, and are the TEST switches there?
log "K1 kernel $(uname -r); online $(cat /sys/devices/system/cpu/online); mem_sleep $(cat /sys/power/mem_sleep)"
log "psci/efi lines: $(dmesg | grep -iE 'psci|efi: ' | head -6 | cut -c1-110 | tr '\n' '|')"
log "macsmc_reboot params: $(ls /sys/module/macsmc_reboot/parameters 2>/dev/null | tr '\n' ' ')"
log "other TEST params: $(for m in macsmc apple_aop pmp_report apple_pmgr_pwrstate pm_genpd dwc3_apple apple_sart nvme_apple; do [ -d /sys/module/$m/parameters ] && echo -n "$m:[$(ls /sys/module/$m/parameters | tr '\n' ' ')] "; done)"
log "rtc: $(ls /sys/class/rtc/ | tr '\n' ' ') wakealarm $([ -e /sys/class/rtc/rtc0/wakealarm ] && echo yes || echo no)"
log "errors: $(dmesg -l err,crit,alert,emerg | wc -l) lines; first: $(dmesg -l err,crit,alert,emerg | head -4 | cut -c1-100 | tr '\n' '|')"
log "wifi: $(ip -4 -o addr | awk '$2!="lo"{print $2,$4}' | tr '\n' ' ')"
