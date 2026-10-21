#!/bin/bash
# PMP run-register probe, on a boot where the deepidle2 hook left the PMP stuck in RTKit IDLE.
#   sudo bash ~/Work/deepidle-harness/pmp-run/toggle.sh
# macOS wakes the PMP from IDLE with AppleA7IOPV4PMP::_runCPU(1): a 32-bit store of 1 to offset 0 of
# PMP device memory index 2, which is 0x28e700000 (and _runCPU(0), a store of 0, after IDLE).
# A read there returns 0x14000095, the PMP firmware's first instruction. This does exactly
# macOS's two stores, 0 then 1, reading back after each, to tell SRAM (reads back what was written)
# from a write-only run register (still reads 0x14000095), and logs any RTKit power-state message
# the PMP sends afterwards (dynamic debug on rtkit.c). It always writes the original word back.
# Writes nothing else. Results: /home/jjr/Work/deep-idle-build/pmp-run-toggle-<time>.txt
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
OUT=/home/jjr/Work/deep-idle-build/pmp-run-toggle-$(date +%Y%m%d-%H%M).txt
lsmod | grep -q '^smc_pwr_test ' && { echo "the HDMI test is loaded; finish it first"; exit 1; }
[ -e /sys/bus/platform/drivers/apple_pmp/28e700000.pmp ] || { echo "PMP driver not bound"; exit 1; }
{
    echo "== PMP run toggle $(date '+%F %T'), $(uname -r)"
    dmesg | grep -E "apple-pmp-sleep" | tail -3
    echo 'file rtkit.c +p' > /sys/kernel/debug/dynamic_debug/control
    mark=$(dmesg | wc -l)
    python3 -I - <<'PY'
import mmap, os, time
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x4000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x28e700000)
w = memoryview(m).cast("I")          # 32-bit accesses only
orig = w[0]
print(f"word0 before: {orig:#010x}")
try:
    w[0] = 0                          # _runCPU(0)
    a = w[0]; print(f"after store 0: {a:#010x}")
    time.sleep(0.05)
    w[0] = 1                          # _runCPU(1)
    b = w[0]; print(f"after store 1: {b:#010x}")
    verdict = ("SRAM (reads back what was written)" if (a, b) == (0, 1) else
               "write-only/side-effect register (reads unchanged)" if a == b == orig else
               "something else")
    print("verdict:", verdict)
    time.sleep(2)
finally:
    if w[0] != orig:
        w[0] = orig
    print(f"word0 restored: {w[0]:#010x}")
PY
    sleep 1
    echo "== kernel messages since the stores"
    dmesg | tail -n +$((mark + 1)) | grep -vE "apple-dcp|nvme-apple" | tail -40
    echo 'file rtkit.c -p' > /sys/kernel/debug/dynamic_debug/control
} 2>&1 | tee "$OUT"
chown jjr:jjr "$OUT"
