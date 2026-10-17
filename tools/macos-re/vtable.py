#!/usr/bin/env python3
"""KEXT=<kext substring> vtable.py <class mangled len+name e.g. 14AppleT6020PMGR> [slot-hex ...]: dump vtable slots"""
import sys, struct, os
d = open(os.path.join(os.path.dirname(__file__), "../13.5-22G74/kc.fixed.bin"), "rb").read()
B = 0xfffffe0007004000
syms, addr = {}, None
for l in open(os.path.join(os.path.dirname(__file__), "../13.5-22G74/syms-demangled.txt"), encoding="latin1"):
    a, k, n = l.rstrip("\n").split(" ", 2)
    syms.setdefault(int(a, 16), n)
raw = {}
for l in open(os.path.join(os.path.dirname(__file__), "../13.5-22G74/syms-all.txt"), encoding="latin1"):
    a, k, n = l.rstrip("\n").split(" ", 2)
    raw[(k, n)] = int(a, 16)
kext = os.environ.get("KEXT", "")
vt = next(v for (k, n), v in raw.items() if n == "__ZTV" + sys.argv[1] and kext in k) + 16
want = [int(x, 16) for x in sys.argv[2:]]
for off in (want or range(0, 0x1000, 8)):
    v, = struct.unpack_from("<Q", d, vt + off - B)
    if not want and not (0xfffffe0008408000 <= v < 0xfffffe000b3d0000):
        break
    print(f"{off:#06x} {v:#x} {syms.get(v, '?')}")
