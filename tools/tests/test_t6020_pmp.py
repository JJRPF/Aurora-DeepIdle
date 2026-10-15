"""J414s (MacBook Pro 14" M2 Pro) opt-in PMP device tree (t6020-j414s-pmp.dts).

Set DTC to this kernel's built scripts/dtc/dtc for Apple floating-point cells.
"""

from pathlib import Path
import difflib
import os
import shutil
import subprocess
import tempfile
import unittest


# The kernel tree: this test's own, or AURORA_TREE when run from a copy outside it.
ROOT = Path(os.environ.get("AURORA_TREE") or Path(__file__).resolve().parents[3])
DTS = ROOT / "arch/arm64/boot/dts/apple"
DTC = os.environ.get("DTC", "dtc")

PMP = "/soc/pmp@28e700000"
REPORT = "/soc/pmp_report@28e3c0000"
# Consumers that APPLE_USE_PMP moves from a PMGR domain to a PMP report entry.
CONSUMERS = {
    "/soc/dcp@389c00000": REPORT + "/report@d",
    "/soc/dcp@289c00000": REPORT + "/report@e",
    "/soc/dcp@315c00000": REPORT + "/report@f",
    "/soc/avd@286000000": REPORT + "/report@11",
    "/soc/iommu@3860e8000": REPORT + "/report@c",
}


def parse(text):
    """Map each node path of a dtc -O dts dump to its {property: raw value}."""
    nodes, stack = {}, []
    for line in text.splitlines():
        line = line.strip()
        if line.endswith("{"):
            name = line[:-1].strip().split(":")[-1].strip()
            stack.append(name)
            path = "/" + "/".join(stack[1:]) if len(stack) > 1 else "/"
            nodes[path] = {}
        elif line == "};":
            stack.pop()
        elif stack and line.endswith(";"):
            path = "/" + "/".join(stack[1:]) if len(stack) > 1 else "/"
            name, _, value = line[:-1].partition(" = ")
            nodes[path][name] = value
    return nodes


def preprocess(board):
    """The board's source after cpp, one statement per line, indentation dropped."""
    pp = subprocess.run(["cpp", "-P", "-nostdinc", "-undef", "-D__DTS__", "-x",
                         "assembler-with-cpp", "-I", str(ROOT / "include"),
                         "-I", str(DTS), str(DTS / f"{board}.dts")],
                        check=True, capture_output=True, text=True)
    return "\n".join(line.strip() for line in pp.stdout.splitlines() if line.strip())


def phandles(nodes):
    return {int(props["phandle"].strip("<>"), 16): path
            for path, props in nodes.items() if "phandle" in props}


@unittest.skipUnless(shutil.which("cpp") and shutil.which(DTC) and DTS.is_dir(),
                     "requires cpp, dtc and a kernel tree (AURORA_TREE)")
class J414sPmpTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="aurora-t6020-pmp-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.stock = cls.compile_board("t6020-j414s")
        cls.pmp = cls.compile_board("t6020-j414s-pmp")

    @classmethod
    def compile_board(cls, board):
        dtb = Path(cls.temp.name) / f"{board}.dtb"
        subprocess.run([DTC, "-q", "-I", "dts", "-O", "dtb", "-o", str(dtb)],
                       input=preprocess(board), check=True, capture_output=True, text=True)
        dump = subprocess.run([DTC, "-q", "-I", "dtb", "-O", "dts", str(dtb)],
                              check=True, capture_output=True, text=True)
        return parse(dump.stdout)

    def domain(self, nodes, path):
        cells = nodes[path]["power-domains"].strip("<>").split()
        return phandles(nodes)[int(cells[0], 16)]

    def test_stock_board_keeps_the_pmp_off(self):
        self.assertNotIn("pmp", self.stock["/aliases"])
        for consumer in CONSUMERS:
            with self.subTest(consumer=consumer):
                self.assertNotIn("pmp_report", self.domain(self.stock, consumer))

    def test_pmp_board_names_the_pmp_for_m1n1(self):
        # m1n1 (kboot dt_set_pmp) finds the node through this alias, copies
        # the ADT values onto it and only then sets it okay.
        self.assertEqual(self.pmp["/aliases"]["pmp"], f'"{PMP}"')
        self.assertEqual(self.pmp[PMP]["status"], '"disabled"')
        self.assertEqual(self.pmp[PMP]["compatible"],
                         '"apple,t6020-pmp-v2", "apple,t6000-pmp-v2"')

    def test_pmp_board_reports_consumer_power_to_the_pmp(self):
        for consumer, entry in CONSUMERS.items():
            with self.subTest(consumer=consumer):
                self.assertEqual(self.domain(self.pmp, consumer), entry)
                self.assertNotEqual(self.pmp[entry].get("status"), '"disabled"')
                # The entry still powers the consumer's own PMGR domain.
                self.assertIn("power-controller", self.domain(self.pmp, entry))

    def test_only_the_pmp_wiring_differs(self):
        self.assertEqual(set(self.stock), set(self.pmp))
        for prop in ("compatible", "model"):
            self.assertEqual(self.stock["/"][prop], self.pmp["/"][prop])
        # Compare the sources by label, before dtc numbers the phandles.
        stock = preprocess("t6020-j414s").splitlines()
        pmp = preprocess("t6020-j414s-pmp").splitlines()
        diff = [line for line in difflib.unified_diff(stock, pmp, lineterm="", n=0)
                if line[:1] in "+-" and line[:3] not in ("+++", "---")]
        self.assertEqual(sorted(diff), sorted([
            "+pmp = &pmp;",
            "-power-domains = <&ps_disp0_cpu0>;",
            "+power-domains = <&pmp_report_disp0>;",
            "-power-domains = <&ps_dispext0_cpu0>;",
            "+power-domains = <&pmp_report_dispext0>;",
            "-power-domains = <&ps_dispext1_cpu0>;",
            "+power-domains = <&pmp_report_dispext1>;",
            "-power-domains = <&ps_avd_sys>;",
            "+power-domains = <&pmp_report_avd_sys>;",
            "-power-domains = <&ps_isp_sys>;",
            "+power-domains = <&pmp_report_isp_sys>;",
        ]))

    def test_variant_is_not_built_by_default(self):
        # Same compatible as t6020-j414s.dtb: m1n1 boots the last match, so a
        # packaged copy would turn the PMP on for every J414s.
        makefile = (DTS / "Makefile").read_text()
        self.assertIn("t6020-j414s.dtb", makefile)
        self.assertNotIn("t6020-j414s-pmp", makefile)


if __name__ == "__main__":
    unittest.main()
