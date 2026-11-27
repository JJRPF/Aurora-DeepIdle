#!/usr/bin/env python3
"""Replace device trees in a boot.bin's payload chain: swapdtb.py <dtc> <boot.bin> <out> <new.dtb>...
Every blob in the chain whose root compatible[0] equals a new tree's is dropped; the new tree takes the place of
the first one dropped (else it goes at the end of the chain). The Aura image and U-Boot are kept."""
import sys, struct, subprocess, hashlib
MAGIC = b'\xd0\x0d\xfe\xed'
dtc, base, out, *new = sys.argv[1:]
b = open(base, 'rb').read()
def chain(o):
    n = 0
    while b[o:o+4] == MAGIC:
        s = struct.unpack('>I', b[o+4:o+8])[0]
        if not 0x100 < s < 0x200000: break
        n += 1; o += s
    return n, o
start = max((i for i in range(0, len(b)-8, 4) if b[i:i+4] == MAGIC), key=lambda i: chain(i)[0])
def compat(blob):
    p = subprocess.run([dtc, '-I', 'dtb', '-O', 'dts'], input=blob, capture_output=True)
    for l in p.stdout.decode(errors='replace').splitlines():
        l = l.strip()
        if l.startswith('compatible = "'):
            return l.split('"')[1]
    return None
blobs = []; o = start
while b[o:o+4] == MAGIC:
    s = struct.unpack('>I', b[o+4:o+8])[0]
    blobs.append(b[o:o+s]); o += s
tail = b[o:]
want = {}
for f in new:
    d = open(f, 'rb').read()
    # pad to the 4-byte boundary the chain walks by
    d = d[:struct.unpack('>I', d[4:8])[0]]
    want[compat(d)] = d
print('replacing', sorted(want))
res = []; placed = set()
for bl in blobs:
    c = compat(bl)
    if c in want:
        if c not in placed:
            res.append(want[c]); placed.add(c)
        continue
    res.append(bl)
for c, d in want.items():
    if c not in placed: res.append(d)
new_b = b[:start] + b''.join(res) + tail
open(out, 'wb').write(new_b)
print(len(blobs), '->', len(res), 'trees; out sha256', hashlib.sha256(new_b).hexdigest()[:16])
