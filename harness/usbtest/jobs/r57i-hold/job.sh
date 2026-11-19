#!/bin/bash
# R57I: R57G with unconditional PMU crumbs (pushes do not arrive from the test boot with the current cmdline).
PUSH_TRIES=3
# 0x6010: 01 job started, 0x6011: modprobe exit code, 0x6012: number of ramoops/pstore dmesg lines (hex),
# 0x6013: pattern write result (5a ok, else 0xee), 0x601d: 77 = about to sysrq-c. Then sysrq-c; main reads DRAM at 0x10790000000/0x10790100000.
for i in $(seq 1 60); do N=$(ls /sys/bus/nvmem/devices/spmi_nvmem*/nvmem 2>/dev/null | head -1); [ -n "$N" ] && break; sleep 1; done
log "R57I nvmem: ${N:-NONE} after $i s"
stamp() { [ -w "$N" ] && printf "\\x$2" | dd of="$N" bs=1 seek=$(($1)) count=1 conv=notrunc 2>/dev/null; }
stamp 0x6010 01
modprobe ramoops mem_address=0x10790000000 mem_size=0x100000 record_size=0x20000 console_size=0 ftrace_size=0 pmsg_size=0 max_reason=2 >/dev/null 2>&1
stamp 0x6011 $(printf '%02x' $(( $? & 255 )))
stamp 0x6012 $(printf '%02x' $(( $(dmesg | grep -ci 'ramoops\|pstore') & 255 )))
log "R57I ramoops dmesg: $(dmesg | grep -i 'ramoops\|pstore' | tail -4 | tr '\n' '|' | cut -c1-400)"
python3 - >/tmp/pat.out 2>&1 <<'PY'
import mmap,os
fd=os.open('/dev/mem',os.O_RDWR|os.O_SYNC)
m=mmap.mmap(fd,0x1000,offset=0x10790100000)
m[0:16]=b'R57ISURVIVE0123'+b'\n'
m.flush(); print('ok')
PY
grep -q '^ok' /tmp/pat.out && stamp 0x6013 5a || stamp 0x6013 ee
log "R57I pattern: $(head -c 200 /tmp/pat.out)"
log "R57I: holding the test boot (keep); ssh in as root"
push "R57I hold" "test boot up: $(ip -4 -o addr | awk '$2!="lo"{print $4}' | tr '\n' ' ')"
