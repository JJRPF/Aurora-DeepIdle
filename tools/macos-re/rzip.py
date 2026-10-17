#!/usr/bin/env python3
"""Remote zip over HTTP Range: list | get <name> <out>. Only fetches the bytes needed."""
import sys, struct, zlib, urllib.request
URL = sys.argv[1]
def rng(a, b):
    r = urllib.request.Request(URL, headers={"Range": f"bytes={a}-{b}"})
    with urllib.request.urlopen(r, timeout=120) as f:
        return f.read()
def size():
    r = urllib.request.Request(URL, method="HEAD")
    with urllib.request.urlopen(r, timeout=60) as f:
        return int(f.headers["Content-Length"])
def cdir():
    n = size()
    tail = rng(n - 65536 - 22, n - 1)
    i = tail.rfind(b"PK\x05\x06")
    eocd = tail[i:]
    cd_size, cd_off = struct.unpack("<II", eocd[12:20])
    if cd_off == 0xFFFFFFFF or cd_size == 0xFFFFFFFF:
        j = tail.rfind(b"PK\x06\x06")
        cd_size, cd_off = struct.unpack("<QQ", tail[j + 40:j + 56])
    cd = rng(cd_off, cd_off + cd_size - 1)
    ents, p = [], 0
    while cd[p:p + 4] == b"PK\x01\x02":
        meth, = struct.unpack("<H", cd[p + 10:p + 12])
        csz, usz = struct.unpack("<II", cd[p + 20:p + 28])
        nl, xl, cl = struct.unpack("<HHH", cd[p + 28:p + 34])
        off, = struct.unpack("<I", cd[p + 42:p + 46])
        name = cd[p + 46:p + 46 + nl].decode()
        x = cd[p + 46 + nl:p + 46 + nl + xl]
        q = 0
        while q < len(x):
            hid, hl = struct.unpack("<HH", x[q:q + 4])
            if hid == 1:
                vals = x[q + 4:q + 4 + hl]; k = 0
                if usz == 0xFFFFFFFF: usz, = struct.unpack("<Q", vals[k:k + 8]); k += 8
                if csz == 0xFFFFFFFF: csz, = struct.unpack("<Q", vals[k:k + 8]); k += 8
                if off == 0xFFFFFFFF: off, = struct.unpack("<Q", vals[k:k + 8]); k += 8
            q += 4 + hl
        ents.append((name, meth, csz, usz, off))
        p += 46 + nl + xl + cl
    return ents
ents = cdir()
if sys.argv[2] == "list":
    for e in ents: print(f"{e[3]:>12} {e[0]}")
else:
    name, out = sys.argv[3], sys.argv[4]
    e = next(e for e in ents if e[0] == name)
    _, meth, csz, usz, off = e
    h = rng(off, off + 29)
    nl, xl = struct.unpack("<HH", h[26:30])
    data = rng(off + 30 + nl + xl, off + 30 + nl + xl + csz - 1)
    if meth == 8: data = zlib.decompress(data, -15)
    assert len(data) == usz, (len(data), usz)
    open(out, "wb").write(data); print(f"{name}: {usz} bytes -> {out}")
