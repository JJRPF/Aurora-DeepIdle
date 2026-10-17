#!/usr/bin/env python3
"""Extract an IM4P payload (raw / lzfse / lzss-complzss) to a file: im4p.py in out"""
import sys, subprocess
d = open(sys.argv[1], "rb").read()
def tl(p):
    t = d[p]; l = d[p + 1]; p += 2
    if l & 0x80:
        n = l & 0x7f; l = int.from_bytes(d[p:p + n], "big"); p += n
    return t, l, p
t, l, p = tl(0)            # SEQUENCE
fields = []
end = p + l
while p < end and len(fields) < 5:
    t, l, q = tl(p); fields.append((t, d[q:q + l])); p = q + l
tag, payload = fields[3]
print("type", fields[1][1].decode(), "desc", fields[2][1][:40], "payload", len(payload), payload[:4])
if payload[:4] in (b"bvx2", b"bvxn", b"bvx-", b"bvx1"):
    out = subprocess.run(["lzfse", "-decode"], input=payload, capture_output=True, check=True).stdout
elif payload[:8] == b"complzss":
    raise SystemExit("lzss not handled")
else:
    out = payload
open(sys.argv[2], "wb").write(out); print("->", sys.argv[2], len(out))
