#!/usr/bin/env python3
# dtb-chain.py: list, extract or swap the DTBs appended to an m1n1 boot.bin.
#   dtb-chain.py list IMAGE
#   dtb-chain.py extract IMAGE INDEX OUT.dtb
#   dtb-chain.py swap IMAGE INDEX NEW.dtb OUT.bin
# m1n1 payloads are concatenated after m1n1 itself; each DTB is self-sized
# (FDT header totalsize). A DTB is accepted only with a sane header, so magic
# constants inside m1n1's code are skipped.
import struct, sys

MAGIC = b"\xd0\x0d\xfe\xed"


def fdt_at(buf, off):
    if buf[off:off + 4] != MAGIC or off + 40 > len(buf):
        return None
    (_, size, o_struct, o_strings, o_rsv, ver, last, _, sz_strings,
     sz_struct) = struct.unpack(">10I", buf[off:off + 40])
    if ver != 17 or last != 16 or not 40 < size <= len(buf) - off:
        return None
    if not (o_rsv < size and o_struct < size and o_strings < size and
            o_struct + sz_struct <= size and o_strings + sz_strings <= size):
        return None
    return size


def model(dtb):
    i = dtb.find(b"compatible\x00")
    j = dtb.find(b"apple,j")
    return dtb[j:j + 16].split(b"\x00")[0].decode() if j >= 0 else "?"


def chain(buf):
    out, off = [], 0
    while True:
        off = buf.find(MAGIC, off)
        if off < 0:
            return out
        size = fdt_at(buf, off)
        if size:
            out.append((off, size))
            off += size
        else:
            off += 4


def main():
    cmd, img = sys.argv[1], open(sys.argv[2], "rb").read()
    dtbs = chain(img)
    if cmd == "list":
        for n, (off, size) in enumerate(dtbs):
            print(f"#{n:3d} @0x{off:08x} {size:7d} {model(img[off:off + size])}")
        last = dtbs[-1][0] + dtbs[-1][1]
        print(f"{len(dtbs)} DTBs, prefix {dtbs[0][0]} bytes, tail {len(img) - last} bytes")
    elif cmd == "extract":
        off, size = dtbs[int(sys.argv[3])]
        open(sys.argv[4], "wb").write(img[off:off + size])
    elif cmd == "swap":
        off, size = dtbs[int(sys.argv[3])]
        new = open(sys.argv[4], "rb").read()
        assert fdt_at(new, 0) == len(new), "new DTB header bad"
        open(sys.argv[5], "wb").write(img[:off] + new + img[off + size:])
    else:
        sys.exit("unknown command")


if __name__ == "__main__":
    main()
