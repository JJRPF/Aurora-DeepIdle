#!/usr/bin/env python3
"""Dump C strings of one fileset entry with their vm addresses: kstrings.py kc entry"""
import sys, re
sys.path.insert(0, __import__("os").path.dirname(__file__))
import fileset as fs
for n, vm, fo in fs.entries():
    if n == sys.argv[2]:
        for seg, sect, addr, size, off in fs.sections(fo):
            if sect in ("__cstring", "__os_log", "__const") and seg.startswith("__TEXT"):
                blob = fs.kc[off:off + size]
                for m in re.finditer(rb"[\x20-\x7e\t\n]{4,}", blob):
                    print(f"{addr + m.start():#x} {sect} {m.group().decode()!r}")
