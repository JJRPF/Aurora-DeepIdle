#!/bin/bash
# Run pmp-cycle (pmp-cycle.c) as root and keep its output. Only while pmp is bound and the
# s2idle hook is off: the tool writes the PMP's power and RUN registers behind the driver.
#   sudo bash /home/jjr/Work/deepidle-harness/mmio/pmp-cycle.sh read | sram-cycle | reset-cycle
set -eu
# reset-cycle (PMGR reset of ps_pmp) killed the whole SoC at once on 2026-10-23 15:15:53 with no
# log; the Mac came back by itself about 45 s later. It stays in pmp-cycle.c as a record only.
[ "${1:-read}" = reset-cycle ] && { echo "reset-cycle is retired: it crashes the SoC (worklog 2026-10-23)"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
D=/home/jjr/Work/deepidle-harness/mmio
[ -e /sys/bus/platform/drivers/apple_pmp/28e700000.pmp ] || { echo "pmp not bound: not touching it"; exit 1; }
[ "$(cat /sys/module/apple_pmp_sleep/parameters/s2idle_idle 2>/dev/null)" = N ] || { echo "s2idle hook on: turn it off first"; exit 1; }
OUT=/var/lib/deepidle/pmp-cycle-$(date +%Y%m%d-%H%M%S)-${1:-read}.txt
sync
$D/pmp-cycle "${1:-read}" 2>&1 | tee $OUT
chmod a+r $OUT
