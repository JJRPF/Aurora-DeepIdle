#!/usr/bin/env python3
"""Assemble a test boot.bin from the stock one: a new stage-2 image, one replaced DTB, a new U-Boot.
  bootbin-build.py STOCK.BIN NEW_IMAGE.BIN INDEX NEW.DTB NEW_UBOOT_NODTB.BIN OUT.BIN
Layout (as Asahi/Aurora ship it): stage-2 image, then DTBs back to back (big-endian totalsize at +4),
then the U-Boot raw binary gzipped. The image is placed as is: the stage 2 finds its payloads right
after its own end. Nothing is installed; prints what differs from the stock file."""
import sys, struct, gzip, hashlib
MAGIC = b'\xd0\x0d\xfe\xed'
stock, image, idx, dtbf, ubf, out = sys.argv[1:7]
b = open(stock, 'rb').read()
def chain(o):
    sizes = []
    while b[o:o + 4] == MAGIC:
        s = struct.unpack('>I', b[o + 4:o + 8])[0]
        if not 0x100 < s < 0x200000: break
        sizes.append(s); o += s
    return sizes, o
start = max((i for i in range(0, len(b) - 8, 4) if b[i:i + 4] == MAGIC), key=lambda i: len(chain(i)[0]) * 0 + len(chain(i)[0]))
sizes, end = chain(start)
dtbs, o = [], start
for s in sizes: dtbs.append(b[o:o + s]); o += s
idx = int(idx); new = open(dtbf, 'rb').read()
assert struct.unpack('>I', new[4:8])[0] == len(new), 'DTB totalsize mismatch'
print(f'stock: image {start} B, {len(dtbs)} DTBs, tail {len(b) - end} B; replacing DTB #{idx} ({len(dtbs[idx])} -> {len(new)} B)')
dtbs[idx] = new
img = open(image, 'rb').read()
tail = gzip.compress(open(ubf, 'rb').read(), 9, mtime=0)
open(out, 'wb').write(img + b''.join(dtbs) + tail)
print(f'out: image {len(img)} B, DTBs {sum(map(len, dtbs))} B, tail {len(tail)} B, total {len(img) + sum(map(len, dtbs)) + len(tail)} B, sha256 {hashlib.sha256(open(out, "rb").read()).hexdigest()[:16]}')
