"""t6020-cpu-em.py and the T602x CPU energy model (opp-microwatt) it derives."""

from pathlib import Path
import importlib.util
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("cpu_em", ROOT / "t6020-cpu-em.py")
cpu_em = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cpu_em)

# capacity-dmips-mhz of the two core types in t602x-common.dtsi.
CAPACITY = {"blizzard_opp": 756, "avalanche_opp": 1024}


@unittest.skipUnless(cpu_em.T8112.exists(), "needs a kernel tree (AURORA_TREE)")
class T6020CpuEmTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.t8112 = cpu_em.T8112.read_text()
        cls.t602x = cpu_em.T602X.read_text()
        cls.derived = cpu_em.derive(cls.t8112)

    def test_the_tree_carries_the_derived_values(self):
        self.assertEqual(cpu_em.apply(self.t602x, self.derived), self.t602x)

    def test_every_cpu_opp_has_a_power_that_rises_with_frequency(self):
        for label, volts in (("blizzard_opp", cpu_em.T6020_E), ("avalanche_opp", cpu_em.T6020_P)):
            with self.subTest(label=label):
                table = cpu_em.opp_table(self.t602x, label)
                self.assertEqual([mhz for mhz, _ in table], [mhz for mhz, _ in volts])
                powers = [uw for _, uw in table]
                self.assertNotIn(None, powers)
                self.assertEqual(powers, sorted(set(powers)))

    def test_no_opp_is_inefficient(self):
        # An inefficient OPP is skipped by cpufreq: the model must not change
        # which frequencies schedutil can pick.
        # cpu_capacity reads 561 for the E cores and 1024 for the P cores on a J414s.
        for label, capacity in (("blizzard_opp", 561), ("avalanche_opp", 1024)):
            with self.subTest(label=label):
                table = cpu_em.opp_table(self.t602x, label)
                self.assertEqual(cpu_em.inefficient(table, capacity), [])
        self.assertEqual(cpu_em.inefficient([(100, 10000), (200, 15000), (300, 40000)]), [100])
        # Equal cost per cycle at two OPPs: the slower one is inefficient.
        self.assertEqual(cpu_em.inefficient([(512, 1000), (1024, 2000)]), [512])

    def test_the_fit_follows_the_t8112_measurements(self):
        for label, (coef, rms, _) in self.derived.items():
            with self.subTest(label=label):
                self.assertLess(rms, 0.07)
                self.assertGreater(coef[0], 0)

    def test_e_cores_are_cheaper_per_unit_of_capacity_at_the_bottom(self):
        cost = {}
        for label, scale in CAPACITY.items():
            table = cpu_em.opp_table(self.t602x, label)
            mhz, uw = table[0]
            cost[label] = uw / (scale * mhz)
        self.assertLess(cost["blizzard_opp"] * 2, cost["avalanche_opp"])

    def test_points_use_the_next_t6020_voltage_and_stay_in_range(self):
        volts = [(700, 600), (900, 650), (1000, 700)]
        measured = [(600, 1), (700, 2), (800, 3), (1000, 4), (1100, 5)]
        self.assertEqual(cpu_em.points(measured, volts), [(700, 600, 2), (800, 650, 3), (1000, 700, 4)])

    def test_apply_refuses_a_table_that_does_not_match(self):
        broken = self.t602x.replace("<912000000>", "<600000000>", 1)
        with self.assertRaisesRegex(ValueError, "blizzard_opp"):
            cpu_em.apply(broken, self.derived)


if __name__ == "__main__":
    unittest.main()
