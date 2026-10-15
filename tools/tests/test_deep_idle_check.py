"""deep-idle-check.py: image names, device tree, energy model, PMP, cpuidle and domains."""

from pathlib import Path
import hashlib
import importlib.util
import os
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("deep_idle_check", ROOT / "deep-idle-check.py")
check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check)

GENPD = """domain                          status          children        performance
    /device                         runtime status                  managed by
------------------------------------------------------------------------------
dispext0_sys                    on                              0
    289c00000.dcp                   unsupported                 0           SW
ane_cpu                         off-0                           0
atc0_usb                        on                              0
pmp                             on                              0
gfx                             on                              0
"""


def machine(root, *, image=b"m1n1", em=False, pmp=False, residency=None):
    def write(path, text):
        path = root / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    (root / check.BOOT_BIN).parent.mkdir(parents=True)
    (root / check.BOOT_BIN).write_bytes(image)
    write("proc/sys/kernel/osrelease", "7.1.12-test\n")
    write(check.EAS, "1\n")
    write(check.CMDLINE, "root=x quiet" + (f" cpuidle_apple.pd_residency_us={residency}" if residency else "") + "\n")
    for n in range(2):
        for i, name in enumerate(("WFI", "CPU PD")):
            state = f"{check.CPUS}/cpu{n}/cpuidle/state{i}"
            write(f"{state}/name", name + "\n")
            write(f"{state}/disable", "1\n" if (i == 0 and n == 0) else "0\n")
            write(f"{state}/time", "0\n")
    write(f"{check.DT}/aliases/dcpext0", "/soc/dcp")
    if em:
        for opp in ("opp02", "opp03"):
            write(f"{check.DT}/opp-table-0/{opp}/opp-microwatt", "x")
        write(f"{check.DT}/opp-table-gpu/opp00/opp-microwatt", "x")
        for cpu in ("cpu0", "cpu4"):
            (root / check.ENERGY_MODEL / cpu).mkdir(parents=True)
    else:
        (root / check.ENERGY_MODEL).mkdir(parents=True)
    if pmp:
        write(f"{check.DT}/aliases/pmp", "/soc/pmp")
    driver = root / check.PMP_DRIVER
    driver.mkdir(parents=True)
    (driver / "bind").write_text("")
    if pmp:
        os.symlink(root, driver / "28e700000.pmp")
    if residency:
        write(check.RESIDENCY, f"{residency}\n")
    write(check.GENPD_SUMMARY, GENPD)


class DeepIdleCheckTest(unittest.TestCase):
    def test_names_a_staged_image_by_its_hash(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            machine(root, image=b"staged")
            digest = hashlib.sha256(b"staged").hexdigest()[:16]
            self.assertIn("not a staged image", check.image(root))
            check.IMAGES[digest] = "E6 test"
            try:
                self.assertEqual(check.image(root), f"{digest} E6 test")
            finally:
                del check.IMAGES[digest]
        self.assertEqual(len(set(check.IMAGES.values())), len(check.IMAGES))

    def test_stock_machine(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            machine(root)
            text = "\n".join(check.report(root, 2, sleep=lambda s: None, clock=iter([0, 2]).__next__))
            self.assertIn("CPU opp-microwatt entries: 0", text)
            self.assertIn("pmp alias: no", text)
            self.assertIn("dcpext aliases: dcpext0", text)
            self.assertIn("energy model domains: none", text)
            self.assertIn("apple_pmp bound: nothing", text)
            self.assertIn("WFI: disable 0/1 on 2 CPUs", text)
            self.assertIn("pd_residency_us: not in this kernel", text)
            self.assertIn("power domains: dispext0_sys=on ane_cpu=off-0 atc0_usb=on pmp=on", text)
            self.assertNotIn("gfx", text)

    def test_energy_model_pmp_and_residency(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            machine(root, em=True, pmp=True, residency=500)
            text = "\n".join(check.report(root, 2, sleep=lambda s: None, clock=iter([0, 2]).__next__))
            self.assertIn("CPU opp-microwatt entries: 2", text)
            self.assertIn("pmp alias: yes", text)
            self.assertIn("energy model domains: cpu0 cpu4", text)
            self.assertIn("apple_pmp bound: 28e700000.pmp", text)
            self.assertIn("pd_residency_us: 500 (command line 500)", text)

    def test_residency_share_over_the_window(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            machine(root)
            states = root / check.CPUS
            for n in range(2):
                (states / f"cpu{n}/cpuidle/state1/time").write_text("1000000\n")
            (states / "cpu1/cpuidle/state0/time").write_text("200000\n")

            def sleep(seconds):
                for n in range(2):
                    (states / f"cpu{n}/cpuidle/state1/time").write_text("2500000\n")
                (states / "cpu1/cpuidle/state0/time").write_text("700000\n")
            lines = check.cpuidle(root, 2, sleep=sleep, clock=iter([10, 12]).__next__)
            self.assertIn("time over 2s: WFI 12.5%, CPU PD 75.0%", lines)

    def test_empty_eas_read_means_eas_impossible(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            machine(root)
            (root / check.EAS).write_text("")
            self.assertIn("sched_energy_aware: empty (EAS not possible)", check.energy_model(root))

    def test_debugfs_without_root(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            machine(root)
            (root / check.GENPD_SUMMARY).chmod(0)
            (root / check.ENERGY_MODEL).chmod(0)
            try:
                if os.geteuid() == 0:
                    self.skipTest("root reads anything")
                self.assertEqual(check.domains(root), ["power domains: needs root"])
                self.assertIn("energy model: needs root", check.energy_model(root))
            finally:
                (root / check.ENERGY_MODEL).chmod(0o755)


if __name__ == "__main__":
    unittest.main()
