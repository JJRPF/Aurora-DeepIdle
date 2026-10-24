#!/bin/bash
# Read-only: the PMGR power-state registers of the PMP's two power gates (ADT power-gates 73, 74):
# ps_pmp 0x28e080000 + 0x2c8 and ps_pms_sram + 0x2d0 (target bits 3:0, actual bits 7:4; 0xf on,
# 0x4 clock-gated, 0x0 power-gated). macOS AppleA7IOP::_disablePower gates both after stopCPU.
#   sudo bash /home/jjr/Work/deepidle-harness/mmio/pmp-ps.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
R=/home/jjr/Work/deepidle-harness/mmio/mmio-read
for n in pmp:0x28e0802c8 pms_sram:0x28e0802d0; do
    v=$($R ${n#*:} | awk '{print $2}')
    echo "ps_${n%%:*} $v target $(( v & 0xf )) actual $(( (v >> 4) & 0xf ))"
done
