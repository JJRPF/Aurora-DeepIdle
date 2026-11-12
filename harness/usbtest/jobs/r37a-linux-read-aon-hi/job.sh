#!/bin/bash
# R37A: do pages 8 to 10 of MPMGR_AON (0x29e5c8000 and up), which stop the Aura observer core, answer a plain read from the test
# Linux (/dev/mem, O_SYNC = Device-nGnRnE, as wakemask)? Each address is pushed BEFORE it is read, so a hang or an SError panic
# (panic=10, then the watchdog) leaves the last "about to read" as the culprit. Addresses in ./addrs, lowest risk first.
# No suspend, no write. A dead access ends the boot at the 120 s watchdog.
J=/run/usbtest/job
PUSH_TRIES=8
log "R37A kernel $(uname -r); stage2 $(tr -d '\0' < /proc/device-tree/chosen/asahi,m1n1-stage2-version 2>/dev/null)"
push "R37A start" "reading $(wc -l < $J/addrs) addresses from the test Linux, one at a time"
for a in $(cat $J/addrs); do
    push "R37A about to read" "$a"
    v=$(timeout 8 $J/mmio-read $a 1 2>&1 | head -1); rc=$?
    log "R37A $a -> $v (rc $rc)"
    push "R37A read" "$a -> $v"
done
push "R37A done" "all addresses answered"
