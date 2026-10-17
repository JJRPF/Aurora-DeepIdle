#!/usr/bin/env python3
"""Mach-O fileset helper. fileset.py <kc> list | sections <entry-substr>"""
import sys, struct
import os
kc = open(os.environ.get("KC") or sys.argv[1], "rb").read()
def lcs(off):
    magic, cpu, sub, ft, ncmds, sz, flags, _ = struct.unpack_from("<IiiIIIII", kc, off)
    p = off + 32
    for _ in range(ncmds):
        cmd, csz = struct.unpack_from("<II", kc, p)
        yield cmd, p, csz
        p += csz
def entries():
    for cmd, p, csz in lcs(0):
        if cmd == 0x80000035:
            vm, fo, eid = struct.unpack_from("<QQI", kc, p + 8)
            name = kc[p + eid:p + csz].split(b"\0")[0].decode()
            yield name, vm, fo
def sections(fo):
    for cmd, p, csz in lcs(fo):
        if cmd == 0x19:
            seg = kc[p + 8:p + 24].rstrip(b"\0").decode()
            vm, vs, foff, fs = struct.unpack_from("<QQQQ", kc, p + 24)
            ns, = struct.unpack_from("<I", kc, p + 64)
            for i in range(ns):
                s = p + 72 + i * 80
                sect = kc[s:s + 16].rstrip(b"\0").decode()
                addr, size, off = struct.unpack_from("<QQI", kc, s + 32)
                yield seg, sect, addr, size, off
if __name__ == "__main__":
    if sys.argv[2] == "list":
        for n, vm, fo in entries(): print(f"{vm:#x} {fo:#x} {n}")
    else:
        for n, vm, fo in entries():
            if sys.argv[3] in n:
                print(n)
                for s in sections(fo): print(f"  {s[0]:<16}{s[1]:<20}{s[2]:#x} size {s[3]:#x} off {s[4]:#x}")
