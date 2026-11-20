#!/usr/bin/env python3
"""Decode Aura image 112's panic stack record in PMU scratch (run as root on main):
0x6004 = 0x50 marker, 0x6005 = frames, 3-byte slots ((lr - _text) >> 2) at 0x6006 0x6009 0x600c 0x6011 0x6014
0x6017 0x601a 0x6020 0x6025. panic-trace.py [System.map] (default the test kernel's, no KASLR)."""
import bisect, glob, os, sys
smap = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~jjr/Work/src/linux-aurora/System.map')
nv = sorted(glob.glob('/sys/bus/spmi/devices/0-0b/spmi_nvmem*/nvmem'))[0]
f = open(nv, 'rb', buffering=0)
def rd(a, n):  # byte reads: block reads of this range can fail with EIO
    out = b''
    for i in range(n):
        f.seek(a + i); out += f.read(1)
    return out
m, n = rd(0x6004, 2)
print(f'0x6023 apcie re-init: {rd(0x6023, 1)[0]:#04x} (a0 done, a1 started and never finished, af error; image 116+)')
print(f'0x601d ps_sep at wake: {rd(0x601d, 1)[0]:#04x} (cN = on, actual N; bN = timeout; image 117+)')
print(f'0x601f userspace resumed: {rd(0x601f, 1)[0]:#04x} (aa = Linux resumed to userspace)')
print(f'marker {m:#04x} (0x50 = record), frames {n}')
if m != 0x50:
    sys.exit('no record')
syms = []
for l in open(smap):
    a, t, s = l.split()[:3]
    if t in 'tTwW':
        syms.append((int(a, 16), s))
syms.sort(); keys = [s[0] for s in syms]
slots = [0x6006, 0x6009, 0x600c, 0x6011, 0x6014, 0x6017, 0x601a, 0x6020, 0x6025]
SKIP = int(os.environ.get('SKIP', '8'))  # image 113 skips 8 frames and keeps ESR in slot 9 (SKIP=0 for image 112)
MODE = os.environ.get('MODE', '115')
PTREGS = MODE in ('114', '115')
if MODE == '115':
    pa = int.from_bytes(rd(slots[6], 3) + rd(slots[7], 3), 'little')
    print(f'FAR: {pa:#014x} ' + ('(VA: AT failed)' if pa & (1 << 47) else '(physical)'))  # image 114: slot 0 = interrupted pc, 1 = its lr, then frames
if SKIP:
    e = int.from_bytes(rd(slots[8], 3), 'little')
    print(f'ESR: EC {e >> 18:#x} ISS {e & 0x3ffff:#07x} (EC 0x2f = SError; ISS bit 24 not kept)')
for i in range(min(n, 6 if MODE == '115' else 8 if SKIP else 9)):
    v = int.from_bytes(rd(slots[i], 3), 'little')
    a = 0xffff800080000000 + 4 * v
    j = bisect.bisect_right(keys, a) - 1
    lab = ('pc' if i == 0 else 'lr' if i == 1 else f'f{i}') if PTREGS else str(i + SKIP)
    print(f'{lab} {a:#x} {syms[j][1]}+{a - syms[j][0]:#x}' if j >= 0 and v != 0xffffff else f'{lab} {a:#x} ?')
