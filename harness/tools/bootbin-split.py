# Split an m1n1 boot.bin into the m1n1 image, its DTBs and the payload tail.
#   python3 -I bootbin-split.py BOOT.BIN M1N1.BIN [REF.DTB [OUT.DTB INDEX]]
import sys, struct, hashlib
def split(path, m1n1len):
    b = open(path,'rb').read()
    off = m1n1len; dtbs = []
    while b[off:off+4] == b'\xd0\x0d\xfe\xed':
        n = struct.unpack('>I', b[off+4:off+8])[0]
        dtbs.append(b[off:off+n]); off += n
    return b[:m1n1len], dtbs, b[off:]
if __name__ == '__main__':
    path, m1n1 = sys.argv[1], sys.argv[2]
    mb = open(m1n1,'rb').read()
    head, dtbs, tail = split(path, len(mb))
    print('m1n1 prefix matches', m1n1, ':', head == mb)
    print(len(dtbs), 'DTBs; tail', len(tail), 'bytes, starts', tail[:4].hex())
    for i, d in enumerate(dtbs):
        if len(sys.argv) > 3:
            ref = open(sys.argv[3],'rb').read()
            if d == ref: print('DTB #%d == %s' % (i, sys.argv[3]))
    if len(sys.argv) > 4:
        open(sys.argv[4],'wb').write(dtbs[int(sys.argv[5])])
