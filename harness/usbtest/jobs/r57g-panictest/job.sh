#!/bin/bash
# R57G: does ramoops capture a panic across a normal warm reset? (no sleep). Loads ramoops at 0x10790000000, writes a pattern at +1 MB,
# stamps PMU scratch 0x6010 (pattern write ok = 5a) and 0x6011 (ramoops module loaded and registered = 5a), then sysrq-c after 5 s.
# On main: read-phys.py 0x10790000000 (dmesg-ramoops records, "sysrq" text) and 0x10790100000 (pattern R57GSURVIVE).
N=$(ls /sys/bus/nvmem/devices/spmi_nvmem*/nvmem 2>/dev/null | head -1)
stamp() { [ -w "$N" ] && printf "\\x$2" | dd of="$N" bs=1 seek=$(($1)) count=1 conv=notrunc 2>/dev/null; }
modprobe ramoops mem_address=0x10790000000 mem_size=0x100000 record_size=0x20000 console_size=0 ftrace_size=0 pmsg_size=0 max_reason=2 2>&1 | head -2
dmesg | grep -qi 'ramoops: using\|pstore: Registered ramoops' && stamp 0x6011 5a
log "R57G ramoops: $(dmesg | grep -i 'ramoops\|pstore' | tail -3 | tr '\n' '|' | cut -c1-300)"
OUT=$(python3 - <<'PY' 2>&1 | head -3
import mmap,os
fd=os.open('/dev/mem',os.O_RDWR|os.O_SYNC)
m=mmap.mmap(fd,0x1000,offset=0x10790100000)
m[0:16]=b'R57GSURVIVE0123'+b'\n'
m.flush(); print('ok', bytes(m[0:8]))
PY
)
log "R57G pattern: $OUT"
case "$OUT" in ok*) stamp 0x6010 5a ;; esac
sync; sleep 5
echo c > /proc/sysrq-trigger
