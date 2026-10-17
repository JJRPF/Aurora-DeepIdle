#!/usr/bin/env python3
"""fourcc.py < file.s: per function, 32-bit constants built by mov/movk that read as FourCCs."""
import sys, re
fn, regs, out = None, {}, {}
for l in sys.stdin:
    if l.startswith("0x"):
        fn = l.split("<")[1].rstrip(">:\n"); regs = {}; continue
    m = re.search(r"(mov|movk) w(\d+), #0x([0-9a-f]+)(?:, lsl #(\d+))?", l)
    if not m:
        continue
    op, r, v, sh = m.group(1), m.group(2), int(m.group(3), 16), int(m.group(4) or 0)
    if op == "mov":
        regs[r] = v
    elif r in regs:
        regs[r] = (regs[r] & ~(0xffff << sh)) | (v << sh)
        x = regs[r]
        cc = x.to_bytes(4, "big")
        if all(0x20 <= c < 0x7f for c in cc) and sum(chr(c).isalnum() for c in cc) >= 3:
            out.setdefault(fn, []).append(cc.decode())
for f, ks in out.items():
    print(f"{f}: {' '.join(dict.fromkeys(ks))}")
