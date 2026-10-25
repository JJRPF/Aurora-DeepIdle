"""harness/tools/bootbin-build.py: a synthetic boot.bin goes in, the same layout comes out with one DTB, the image and the U-Boot replaced."""

from pathlib import Path
import gzip
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "harness" / "tools" / "bootbin-build.py"
MAGIC = b"\xd0\x0d\xfe\xed"


def dtb(tag, size=0x120):
    body = MAGIC + struct.pack(">I", size) + tag * ((size - 8) // len(tag))
    return body.ljust(size, b"\0")


class BootBinBuild(unittest.TestCase):
    def test_layout_and_replacement(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            dtbs = [dtb(bytes([65 + i])) for i in range(5)]
            old_u = b"OLD-UBOOT" * 50
            (d / "stock.bin").write_bytes(b"\x11" * 0x1000 + b"".join(dtbs) + gzip.compress(old_u))
            new_dtb = dtb(b"Z", 0x150)
            (d / "img.bin").write_bytes(b"\x22" * 0x2000)
            (d / "new.dtb").write_bytes(new_dtb)
            (d / "u.bin").write_bytes(b"NEW-UBOOT" * 70)
            subprocess.run([sys.executable, "-I", str(SCRIPT), d / "stock.bin", d / "img.bin", "2", d / "new.dtb", d / "u.bin", d / "out.bin"],
                           check=True, capture_output=True)
            out = (d / "out.bin").read_bytes()
            self.assertEqual(out[:0x2000], b"\x22" * 0x2000)
            expect = dtbs[:2] + [new_dtb] + dtbs[3:]
            self.assertEqual(out[0x2000:0x2000 + sum(map(len, expect))], b"".join(expect))
            self.assertEqual(gzip.decompress(out[0x2000 + sum(map(len, expect)):]), b"NEW-UBOOT" * 70)

    def test_rejects_wrong_dtb_size(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "stock.bin").write_bytes(b"\x11" * 0x1000 + dtb(b"A") + gzip.compress(b"x"))
            (d / "img.bin").write_bytes(b"\x22" * 16)
            (d / "bad.dtb").write_bytes(MAGIC + struct.pack(">I", 999) + b"x" * 20)
            (d / "u.bin").write_bytes(b"u")
            r = subprocess.run([sys.executable, "-I", str(SCRIPT), d / "stock.bin", d / "img.bin", "0", d / "bad.dtb", d / "u.bin", d / "out.bin"],
                               capture_output=True)
            self.assertNotEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
