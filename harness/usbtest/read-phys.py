#!/usr/bin/env python3
"""GH-5: read physical RAM through /proc/kcore (/dev/mem refuses System RAM here).
   sudo python3 read-phys.py <phys addr> <length> [out file]   prints the hex of the first 64 bytes, writes the rest to out."""
import sys, struct
phys = int(sys.argv[1], 0); n = int(sys.argv[2], 0); out = sys.argv[3] if len(sys.argv) > 3 else None
f = open('/proc/kcore', 'rb')
h = f.read(64)
assert h[:4] == b'\x7fELF'
phoff, = struct.unpack_from('<Q', h, 32); phentsize, phnum = struct.unpack_from('<HH', h, 54)
for i in range(phnum):
    f.seek(phoff + i * phentsize)
    t, fl, off, va, pa, fsz, msz, al = struct.unpack('<IIQQQQQQ', f.read(56))
    if t == 1 and pa != 0xffffffffffffffff and pa <= phys and phys + n <= pa + fsz:
        f.seek(off + (phys - pa)); d = f.read(n); break
else:
    sys.exit('physical %#x not in a kcore segment' % phys)
print(d[:64].hex())
if out: open(out, 'wb').write(d)
