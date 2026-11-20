#!/bin/bash
# R58A-hello: no sleep. Stamp PMU 0x601f = bb the moment the job starts (proves the kernel and root booted, even without a network), push the facts, end (normal reboot).
N=$(ls /sys/bus/nvmem/devices/spmi_nvmem*/nvmem 2>/dev/null | head -1)
[ -w "$N" ] && printf '\xbb' | dd of="$N" bs=1 seek=$((0x601f)) count=1 conv=notrunc 2>/dev/null
PUSH_TRIES=10
push "R58A hello" "kernel $(uname -r) $(uname -v | cut -c1-60); stage2 $(tr -d '\0' < /proc/device-tree/chosen/asahi,m1n1-stage2-version); wifi $(ip -4 -o addr | awk '$2!="lo"{print $2,$4}' | tr '\n' ' '); errors: $(dmesg | grep -iE 'error|fail|panic|oops' | tail -5 | cut -c1-120 | tr '\n' '|')"
