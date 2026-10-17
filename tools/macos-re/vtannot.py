#!/usr/bin/env python3
"""vtannot.py <vtable dump> < in.s > out.s : name 'mov x17,#slot; add x16,x16,x17' and
'ldr xN, [x16, #slot]' virtual calls (assumes this-class = the dumped vtable's class)."""
import sys, re, subprocess
vt = {}
for l in open(sys.argv[1]):
    off, addr, name = l.split(" ", 2)
    vt[int(off, 16)] = name.strip()
dem = dict(zip(vt.values(), subprocess.run(["c++filt"], input="\n".join(vt.values()), capture_output=True, text=True).stdout.split("\n")))
lines = sys.stdin.read().split("\n")
for i, l in enumerate(lines):
    m = re.search(r"mov x17, #0x([0-9a-f]+)", l)
    if m and i + 1 < len(lines) and "add x16, x16, x17" in lines[i + 1]:
        s = int(m.group(1), 16)
        if s in vt:
            l += f"  ; VCALL {dem.get(vt[s], vt[s])}"
    m = re.search(r"ldr x\d+, \[x16, #(\d+)\]", l)
    if m and int(m.group(1)) in vt and "autda x16" in "".join(lines[max(0, i - 3):i]):
        l += f"  ; VCALL {dem.get(vt[int(m.group(1))], '')}"
    print(l)
