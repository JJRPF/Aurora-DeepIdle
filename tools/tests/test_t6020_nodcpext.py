"""J414s (MacBook Pro 14" M2 Pro) test tree without the external DCPs (t6020-j414s-nodcpext.dts).

Set DTC to this kernel's built scripts/dtc/dtc for Apple floating-point cells.
"""

from pathlib import Path
import importlib.util
import shutil
import subprocess
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("pmp_test", HERE / "test_t6020_pmp.py")
pmp_test = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pmp_test)

DTS, DTC = pmp_test.DTS, pmp_test.DTC
parse, phandles = pmp_test.parse, pmp_test.phandles

# The external DCPs and everything only they use.
DISABLED = (
    "/soc/dcp@289c00000",      # dcpext0
    "/soc/iommu@28930c000",    # dcpext0_dart
    "/soc/mbox@289c08000",     # dcpext0_mbox
    "/soc/iommu@289304000",    # dispext0_dart
    "/soc/dcp@315c00000",      # dcpext1
    "/soc/iommu@31530c000",    # dcpext1_dart
    "/soc/mbox@315c08000",     # dcpext1_mbox
    "/soc/iommu@315304000",    # dispext1_dart
)
# The Type-C routes inside them: the USB-C controllers' mode-switch providers.
ROUTES = tuple(f"{dcp}/typec-routes/route@{n}" for dcp in DISABLED[0::4] for n in range(3))
DISPLAY = "/soc/display-subsystem"


def merged(board):
    """The board's tree after dtc merges its overrides, references kept as &label."""
    dump = subprocess.run([DTC, "-q", "-I", "dts", "-O", "dts"], input=pmp_test.preprocess(board),
                          check=True, capture_output=True, text=True)
    return parse(dump.stdout)
DISP0_DART = "/soc/iommu@389304000"


@unittest.skipUnless(shutil.which("cpp") and shutil.which(DTC) and DTS.is_dir(),
                     "requires cpp, dtc and a kernel tree (AURORA_TREE)")
class J414sNoDcpextTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="aurora-t6020-nodcpext-")
        cls.addClassCleanup(cls.temp.cleanup)
        compile_board = pmp_test.J414sPmpTest.compile_board.__func__
        cls.stock = compile_board(cls, "t6020-j414s")
        cls.variant = compile_board(cls, "t6020-j414s-nodcpext")

    def test_m1n1_finds_no_external_dcp(self):
        # m1n1 enables and carves out memory for the DCPs named by an alias.
        self.assertIn("dcpext0", self.stock["/aliases"])
        self.assertIn("dcpext1", self.stock["/aliases"])
        self.assertNotIn("dcpext0", self.variant["/aliases"])
        self.assertNotIn("dcpext1", self.variant["/aliases"])
        for alias in ("dcp", "disp0", "disp0_piodma"):
            self.assertEqual(self.variant["/aliases"][alias], self.stock["/aliases"][alias])

    def test_external_dcps_and_their_darts_and_mailboxes_are_off(self):
        for path in DISABLED:
            with self.subTest(path=path):
                self.assertEqual(self.stock[path].get("status"), '"okay"')
                self.assertEqual(self.variant[path]["status"], '"disabled"')

    def test_no_mode_switch_is_left_enabled_under_a_disabled_node(self):
        # fwnode_typec_mux_get() follows the connector's graph and checks only
        # the remote node's own status: an enabled mode-switch with no driver
        # behind it defers the USB-C controller's probe for ever.
        self.assertEqual(len(ROUTES), 6)
        for path, props in self.variant.items():
            if "mode-switch" not in props or props.get("status") == '"disabled"':
                continue
            parts = path.split("/")
            ancestors = ["/".join(parts[:i]) for i in range(2, len(parts))]
            with self.subTest(path=path):
                for ancestor in ancestors:
                    self.assertNotEqual(self.variant[ancestor].get("status"), '"disabled"')
        for path in ROUTES:
            with self.subTest(path=path):
                self.assertIn("mode-switch", self.variant[path])
                self.assertEqual(self.variant[path]["status"], '"disabled"')

    def test_no_graph_link_leads_into_a_disabled_node(self):
        # The same holds for any graph link: the far side's port parent must
        # be disabled itself, not only through an ancestor.
        nodes, handles = self.variant, phandles(self.variant)

        def off(path):
            parts = path.split("/")
            return any(nodes.get("/".join(parts[:i]) or "/", {}).get("status") == '"disabled"'
                       for i in range(2, len(parts) + 1))

        for path, props in nodes.items():
            if "remote-endpoint" not in props or off(path):
                continue
            remote = handles[int(props["remote-endpoint"].strip("<>"), 16)]
            parent = remote.split("/")[:-2]
            if parent[-1] == "ports":
                parent = parent[:-1]
            parent = "/".join(parent)
            with self.subTest(path=path, remote=parent):
                self.assertFalse(off(remote) and nodes[parent].get("status") != '"disabled"')

    def test_display_keeps_only_the_internal_dart(self):
        cells = self.variant[DISPLAY]["iommus"].strip("<>").split()
        self.assertEqual(len(cells), 2)
        self.assertEqual(phandles(self.variant)[int(cells[0], 16)], DISP0_DART)
        self.assertEqual(len(self.stock[DISPLAY]["iommus"].strip("<>").split()), 6)

    def test_no_enabled_device_uses_a_dispext_domain(self):
        handles = phandles(self.variant)
        dispext = {handle for handle, path in handles.items()
                   if "power-controller" in path and
                   self.variant[path].get("label", "").startswith('"dispext')}
        self.assertEqual(len(dispext), 6)
        for path, props in self.variant.items():
            if "power-controller" in path or "pmp_report" in path:
                continue
            if props.get("status", '"okay"') != '"okay"' or "power-domains" not in props:
                continue
            cells = {int(cell, 16) for cell in props["power-domains"].strip("<>").split()}
            with self.subTest(path=path):
                self.assertFalse(cells & dispext)

    def test_only_those_properties_differ(self):
        # dtc numbers phandles in a different order for each tree; compare the
        # merged sources instead, which keep references as &label.
        stock, variant = (merged(board) for board in ("t6020-j414s", "t6020-j414s-nodcpext"))
        self.assertEqual(set(stock), set(variant))
        changed = {(path, name) for path in stock
                   for name in (set(stock[path]) | set(variant[path])) - {"phandle"}
                   if stock[path].get(name) != variant[path].get(name)}
        expected = {(path, "status") for path in DISABLED + ROUTES}
        expected |= {("/aliases", "dcpext0"), ("/aliases", "dcpext1"), (DISPLAY, "iommus")}
        self.assertEqual(changed, expected)

    def test_variant_is_not_built_by_default(self):
        makefile = (DTS / "Makefile").read_text()
        self.assertIn("t6020-j414s.dtb", makefile)
        self.assertNotIn("t6020-j414s-nodcpext", makefile)


if __name__ == "__main__":
    unittest.main()
