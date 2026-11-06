#!/usr/bin/env python3
"""Put a new Aura image in front of a boot.bin's payload chain (DTBs etc.): swapimg.py <boot.bin> <aura.bin> <out>."""
import sys, struct, hashlib
MAGIC = b'\xd0\x0d\xfe\xed'
base, img, out = sys.argv[1:4]
b = open(base, 'rb').read()
def chain(o):
    n = 0
    while b[o:o+4] == MAGIC:
        s = struct.unpack('>I', b[o+4:o+8])[0]
        if not 0x100 < s < 0x200000: break
        n += 1; o += s
    return n, o
start = max((i for i in range(0, len(b)-8, 4) if b[i:i+4] == MAGIC), key=lambda i: chain(i)[0])
new = open(img, 'rb').read() + b[start:]
print('image', start, '->', len(new) - (len(b) - start), 'B; old image sha', hashlib.sha256(b[:start]).hexdigest()[:16], 'new image sha', hashlib.sha256(open(img,'rb').read()).hexdigest()[:16])
open(out, 'wb').write(new)
print('out sha256', hashlib.sha256(new).hexdigest()[:16])
