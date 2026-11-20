#!/usr/bin/env python3
"""Minimal Apple Device Tree (ADT) reader, no dependencies.

adt-dump.py <adt> node <path-suffix>      print every property of the nodes ending in <path-suffix>
adt-dump.py <adt> reg <path-suffix>       print a node's reg entries (u64 addr, u64 size), unmapped
adt-dump.py <adt> func <substring>        print function-* properties whose node path or name matches
"""
import struct
import sys


def parse(d):
    nodes = {}

    def node(o, path):
        nprops, nchild = struct.unpack_from('<II', d, o)
        o += 8
        props = {}
        for _ in range(nprops):
            name = d[o:o + 32].split(b'\0')[0].decode()
            size = struct.unpack_from('<I', d, o + 32)[0] & 0x7fffffff
            props[name] = d[o + 36:o + 36 + size]
            o += 36 + ((size + 3) & ~3)
        p = path + '/' + props.get('name', b'?').split(b'\0')[0].decode()
        nodes[p] = props
        for _ in range(nchild):
            o = node(o, p)
        return o

    node(0, '')
    return nodes


def text(v):
    s = v.rstrip(b'\0')
    if s and all(32 <= c < 127 or c == 0 for c in s):
        return s.replace(b'\0', b' | ').decode()
    return v[:64].hex()


def main():
    d = open(sys.argv[1], 'rb').read()
    mode, arg = sys.argv[2], sys.argv[3]
    nodes = parse(d)
    phandles = {struct.unpack('<I', p['AAPL,phandle'][:4])[0]: n
                for n, p in nodes.items() if len(p.get('AAPL,phandle', b'')) >= 4}
    for path, props in nodes.items():
        if mode == 'node' and path.endswith(arg):
            print('==', path)
            for k, v in props.items():
                print('  ', k, len(v), text(v))
        elif mode == 'reg' and path.endswith(arg):
            v = props.get('reg', b'')
            for i in range(0, len(v) - 15, 16):
                a, s = struct.unpack_from('<QQ', v, i)
                print(path, i // 16, hex(a), hex(s))
        elif mode == 'func':
            for k, v in props.items():
                if k.startswith('function-') and (arg in path or arg in k) and len(v) >= 8:
                    tgt = phandles.get(struct.unpack('<I', v[:4])[0], '?')
                    print(path, k, '->', tgt, v[4:8][::-1].decode('latin1'), v[8:].hex())


if __name__ == '__main__':
    main()
