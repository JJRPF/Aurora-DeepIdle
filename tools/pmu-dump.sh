#!/bin/bash
# Dumps the PMU's whole SPMI register space (0x0000-0xfffe) through its nvmem file, one 16-byte row per line:
# "<addr>: <hex bytes>", "<addr>: unreadable" for a row the PMU does not answer. Read-only. sudo bash tools/pmu-dump.sh > file
N=$(ls /sys/bus/nvmem/devices/spmi_nvmem*/nvmem 2>/dev/null | head -1)
[ -r "$N" ] || { echo "no PMU nvmem (run with sudo)" >&2; exit 1; }
for ((a = 0; a < 0x10000; a += 16)); do
    n=16; [ $a -eq $((0xfff0)) ] && n=15
    h=$(dd if=$N bs=1 skip=$a count=$n 2>/dev/null | xxd -p -c16)
    printf '%04x: %s\n' $a "${h:-unreadable}"
done
