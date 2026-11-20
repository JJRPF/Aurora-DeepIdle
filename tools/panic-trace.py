#!/usr/bin/env python3
"""Decode Aura image 106's panic stack record in PMU scratch 0x6040 (run as root on main):
panic-trace.py [System.map]  (default ~/Work/src/linux-aurora/System.map of the test kernel, no KASLR)."""
import bisect, glob, os, sys
smap = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~jjr/Work/src/linux-aurora/System.map')
nv = sorted(glob.glob('/sys/bus/spmi/devices/0-0b/spmi_nvmem*/nvmem'))[0]
f = open(nv, 'rb', buffering=0)
def rd(a, n):  # byte reads: block reads of this range can fail with EIO
    out = b''
    for i in range(n):
        f.seek(a + i); out += f.read(1)
    return out
h = rd(0x6040, 4)
print('header', h.hex(), '(50 = record, frames, cpu aff0|aff1<<4, RVBAR entries)')
if h[0] != 0x50:
    sys.exit('no record')
syms = []
for l in open(smap):
    a, t, n = l.split()[:3]
    if t in 'tTwW':
        syms.append((int(a, 16), n))
syms.sort(); keys = [s[0] for s in syms]
raw = rd(0x6044, 4 * h[1])
for i in range(h[1]):
    lo = int.from_bytes(raw[4*i:4*i+4], 'little')
    a = 0xffff800000000000 | lo
    j = bisect.bisect_right(keys, a) - 1
    print(f'{i:2} {a:#x} {syms[j][1]}+{a - syms[j][0]:#x}' if j >= 0 else f'{i:2} {a:#x} ?')
