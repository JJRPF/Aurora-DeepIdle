#!/usr/bin/env python3
"""Resolve DYLD_CHAINED_PTR_64_KERNEL_CACHE pointers: kcfixups.py in out. Prints counts."""
import sys, struct
kc = bytearray(open(sys.argv[1], "rb").read())
BASE = 0xfffffe0007004000
ncmds, = struct.unpack_from("<I", kc, 16)
p = 32
for _ in range(ncmds):
    cmd, csz = struct.unpack_from("<II", kc, p)
    if cmd == 0x80000034:
        doff, dsz = struct.unpack_from("<II", kc, p + 8)
    p += csz
starts_off, = struct.unpack_from("<I", kc, doff + 4)
img = doff + starts_off
seg_count, = struct.unpack_from("<I", kc, img)
fmts, n = {}, 0
for s in range(seg_count):
    so, = struct.unpack_from("<I", kc, img + 4 + 4 * s)
    if so == 0:
        continue
    seg = img + so
    size, page_size, fmt, seg_off, maxp, page_count = struct.unpack_from("<IHHQIH", kc, seg)
    fmts[fmt] = fmts.get(fmt, 0)
    for pg in range(page_count):
        start, = struct.unpack_from("<H", kc, seg + 22 + 2 * pg)
        if start == 0xFFFF:
            continue
        off = seg_off + pg * page_size + start
        while True:
            v, = struct.unpack_from("<Q", kc, off)
            target = v & 0x3FFFFFFF
            nxt = (v >> 51) & 0xFFF
            struct.pack_into("<Q", kc, off, BASE + target)
            n += 1; fmts[fmt] += 1
            if nxt == 0:
                break
            off += nxt * 4
open(sys.argv[2], "wb").write(kc)
print("resolved", n, "pointers; formats", fmts)
