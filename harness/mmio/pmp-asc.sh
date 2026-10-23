#!/bin/bash
# Read-only: the PMP's ASC CPU and mailbox state (after a failed wake: is the IOP running?).
# ASC 0x28ec00000: CPU_CONTROL 0x44 (RUN bit 4), CPU_STATUS 0x48 (& 3 = 3: idle/WFI).
# Mailbox 0x28ec08000 (ASC mailbox v4): A2I_CONTROL 0x110, I2A_CONTROL 0x114
# (bit 17 FULL, bit 18 EMPTY). Only while pmp is bound: its power domain must be on.
#   sudo bash /home/jjr/Work/deepidle-harness/mmio/pmp-asc.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
[ -e /sys/bus/platform/drivers/apple_pmp/28e700000.pmp ] || { echo "pmp not bound: power domain may be off, not reading"; exit 1; }
R=/home/jjr/Work/deepidle-harness/mmio/mmio-read
c=$($R 0x28ec00044 | awk '{print $2}'); s=$($R 0x28ec00048 | awk '{print $2}')
a=$($R 0x28ec08110 | awk '{print $2}'); i=$($R 0x28ec08114 | awk '{print $2}')
echo "CPU_CONTROL $c (RUN $(( ($c >> 4) & 1 ))), CPU_STATUS $s (&3 = $(( $s & 3 )))"
echo "A2I_CONTROL $a (full $(( ($a >> 17) & 1 )) empty $(( ($a >> 18) & 1 ))), I2A_CONTROL $i (full $(( ($i >> 17) & 1 )) empty $(( ($i >> 18) & 1 )))"
