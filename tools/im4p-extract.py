#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Pull the payload out of an IMG4 or IM4P file, such as a macOS kernelcache.

Usage: im4p-extract.py <kernelcache> <out.macho>

The kernelcache in Preboot/<vg>/boot/<hash>/.../kernelcache is an IMG4
wrapping an IM4P whose data is LZFSE ("bvx2") compressed. This does what
`img4tool -ep` then `img4tool -eo` would, with only the `lzfse` command
line tool needed (pacman -S lzfse). Uncompressed payloads are written as is.
"""
import subprocess
import sys


def der(buf, off):
    """Return (tag, content start, content end) of the DER element at off."""
    tag = buf[off]
    n = buf[off + 1]
    off += 2
    if n & 0x80:
        k = n & 0x7F
        n = int.from_bytes(buf[off:off + k], "big")
        off += k
    return tag, off, off + n


def children(buf, start, end):
    while start < end:
        tag, cs, ce = der(buf, start)
        yield tag, cs, ce
        start = ce


def find_im4p(buf):
    """Return (start, end) of the IM4P SEQUENCE content."""
    tag, cs, ce = der(buf, 0)
    if tag != 0x30:
        sys.exit("not a DER SEQUENCE")
    first = next(children(buf, cs, ce))
    magic = bytes(buf[first[1]:first[2]])
    if magic == b"IM4P":
        return cs, ce
    if magic != b"IMG4":
        sys.exit(f"unknown magic {magic!r}")
    for t, s, e in children(buf, cs, ce):
        if t == 0x30:
            inner = next(children(buf, s, e))
            if bytes(buf[inner[1]:inner[2]]) == b"IM4P":
                return s, e
    sys.exit("IMG4 holds no IM4P")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    buf = open(sys.argv[1], "rb").read()
    s, e = find_im4p(buf)
    parts = list(children(buf, s, e))
    # IM4P ::= SEQUENCE { "IM4P", type, description, data, [compression] }
    fourcc = bytes(buf[parts[1][1]:parts[1][2]]).decode()
    desc = bytes(buf[parts[2][1]:parts[2][2]]).decode(errors="replace")
    data = bytes(buf[parts[3][1]:parts[3][2]])
    print(f"IM4P type {fourcc}, {desc}, {len(data)} bytes of data")
    if data[:4] == b"bvx2":
        out = subprocess.run(["lzfse", "-decode"], input=data,
                             capture_output=True, check=True).stdout
        print(f"LZFSE: {len(out)} bytes")
    else:
        out = data
    magic = int.from_bytes(out[:4], "little")
    if magic != 0xFEEDFACF:
        print(f"warning: payload magic {magic:#x} is not a 64-bit Mach-O")
    else:
        filetype = int.from_bytes(out[12:16], "little")
        print(f"Mach-O filetype {filetype}" + (" (fileset)" if filetype == 12 else ""))
    open(sys.argv[2], "wb").write(out)


if __name__ == "__main__":
    main()
