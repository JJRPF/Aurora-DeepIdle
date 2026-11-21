#!/usr/bin/env python3
"""Check a macOS .pkg (xar) signature on Linux, without macOS.

xar-sigcheck.py <file.pkg> [--full]

1. Reads the xar header and the zlib table of contents (TOC).
2. Checks the TOC checksum (SHA-1 or SHA-256 of the compressed TOC) against the one stored in the heap.
3. Verifies the RSA signature over that checksum with the first certificate in the TOC.
4. Verifies the certificate chain with openssl, the last certificate (the root) as the only trust anchor,
   and prints each subject, so "Apple Root CA" can be checked by eye and by the exit code.
5. Prints the version from the package's PackageInfo (or Distribution) file.
6. With --full, hashes every file stored in the heap against its archived-checksum in the signed TOC,
   so the whole package (not only the TOC) is shown to be Apple's.
Exit 0 only if every step passes and the root is Apple's.
"""
import base64
import hashlib
import re
import struct
import subprocess
import sys
import tempfile
import zlib

# Apple Root CA (the 2006 RSA root), SHA-256 of its DER encoding
APPLE_ROOT_SHA256 = 'b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024'


def main(path):
    f = open(path, 'rb')
    magic, hsize, ver, tocc, tocu, algo = struct.unpack('>4sHHQQI', f.read(28))
    if magic != b'xar!':
        sys.exit('not a xar archive')
    f.seek(hsize)
    ctoc = f.read(tocc)
    toc = zlib.decompress(ctoc).decode('utf-8', 'replace')
    heap = hsize + tocc

    m = re.search(r'<checksum style="(\w+)">\s*<offset>(\d+)</offset>\s*<size>(\d+)</size>', toc)
    if not m:
        sys.exit('no TOC checksum')
    style, coff, csize = m.group(1), int(m.group(2)), int(m.group(3))
    f.seek(heap + coff)
    stored = f.read(csize)
    h = hashlib.new(style.replace('sha', 'sha'), ctoc).digest()
    print(f'TOC checksum ({style}): {"OK" if h == stored else "MISMATCH"}')
    if h != stored:
        return 1

    s = re.search(r'<signature style="RSA">\s*<offset>(\d+)</offset>\s*<size>(\d+)</size>(.*?)</signature>', toc, re.S)
    if not s:
        sys.exit('no RSA signature in the TOC')
    soff, ssize = int(s.group(1)), int(s.group(2))
    certs = [base64.b64decode(re.sub(r'\s', '', c)) for c in re.findall(r'<X509Certificate>(.*?)</X509Certificate>', s.group(3), re.S)]
    f.seek(heap + soff)
    sig = f.read(ssize)
    print(f'signature: {ssize} bytes, {len(certs)} certificates')

    with tempfile.TemporaryDirectory() as d:
        pems = []
        for i, c in enumerate(certs):
            der = f'{d}/c{i}.der'
            open(der, 'wb').write(c)
            pem = f'{d}/c{i}.pem'
            subprocess.run(['openssl', 'x509', '-inform', 'DER', '-in', der, '-out', pem], check=True)
            subj = subprocess.run(['openssl', 'x509', '-in', pem, '-noout', '-subject'], capture_output=True, text=True).stdout.strip()
            print(f'  cert {i}: {subj}')
            pems.append(pem)
        root_ok = hashlib.sha256(certs[-1]).hexdigest() == APPLE_ROOT_SHA256
        print(f'root is Apple Root CA (by SHA-256): {"yes" if root_ok else "NO"}')

        # The signature is PKCS#1 v1.5 over the TOC checksum (a DigestInfo of the checksum's algorithm).
        open(f'{d}/sig', 'wb').write(sig)
        open(f'{d}/hash', 'wb').write(stored)
        subprocess.run(['openssl', 'x509', '-in', pems[0], '-pubkey', '-noout', '-out', f'{d}/pub.pem'], check=True)
        r = subprocess.run(['openssl', 'pkeyutl', '-verify', '-pubin', '-inkey', f'{d}/pub.pem', '-in', f'{d}/hash',
                            '-sigfile', f'{d}/sig', '-pkeyopt', f'digest:{style}'], capture_output=True, text=True)
        sig_ok = r.returncode == 0
        print(f'RSA signature over the TOC checksum: {"OK" if sig_ok else "FAILED " + (r.stdout + r.stderr).strip()}')

        chain = f'{d}/chain.pem'
        open(chain, 'w').write(''.join(open(p).read() for p in pems[1:-1]))
        args = ['openssl', 'verify', '-x509_strict', '-partial_chain', '-CAfile', pems[-1]]
        if len(pems) > 2:
            args += ['-untrusted', chain]
        args += ['-purpose', 'any', pems[0]]
        r = subprocess.run(args, capture_output=True, text=True)
        chain_ok = r.returncode == 0
        print(f'certificate chain: {"OK" if chain_ok else "FAILED"} ({(r.stdout + r.stderr).strip()})')

    files = []
    for blk in re.findall(r'<file id="\d+">(.*?)</file>', toc, re.S):
        blk = re.sub(r'<ea id="\d+">.*?</ea>', '', blk, flags=re.S)
        n = re.search(r'<name>([^<]*)</name>', blk)
        d = re.search(r'<data>(.*?)</data>', blk, re.S)
        if n and d:
            files.append((n.group(1), d.group(1)))
    for name, data in files:
        if name in ('Distribution', 'PackageInfo'):
            off = int(re.search(r'<offset>(\d+)</offset>', data).group(1))
            ln = int(re.search(r'<length>(\d+)</length>', data).group(1))
            f.seek(heap + off)
            raw = f.read(ln)
            if 'x-gzip' in data:
                raw = zlib.decompress(raw)
            t = raw.decode('utf-8', 'replace')
            v = re.search(r'<key>VERSION</key>\s*<string>([^<]+)', t) or re.search(r'<pkg-info[^>]*\sversion="([^"]+)"', t)
            b = re.search(r'<key>BUILD</key>\s*<string>([^<]+)', t)
            print(f'{name}: version {v and v.group(1)}' + (f' build {b.group(1)}' if b else ''))
    files_ok = True
    if '--full' in sys.argv:
        for name, data in files:
            off = int(re.search(r'<offset>(\d+)</offset>', data).group(1))
            ln = int(re.search(r'<length>(\d+)</length>', data).group(1))
            ac = re.search(r'<archived-checksum style="(\w+)">([0-9a-f]+)</archived-checksum>', data)
            hh = hashlib.new(ac.group(1))
            f.seek(heap + off)
            left = ln
            while left:
                b = f.read(min(left, 1 << 24))
                if not b:
                    break
                hh.update(b)
                left -= len(b)
            ok = hh.hexdigest() == ac.group(2) and left == 0
            files_ok &= ok
            print(f'  {name}: {ln} bytes, {ac.group(1)} {"OK" if ok else "MISMATCH"}')
        print(f'all files match the signed TOC: {"yes" if files_ok else "NO"}')
    return 0 if (root_ok and sig_ok and chain_ok and files_ok) else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
