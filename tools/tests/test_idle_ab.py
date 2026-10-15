"""idle-ab.py: settings, a fake sysfs run that restores every knob, the paired report."""

from pathlib import Path
import importlib.util
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("idle_ab", ROOT / "idle-ab.py")
idle_ab = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(idle_ab)


def fake_machine(root, residency=True, cpus=2):
    for n in range(cpus):
        for i in range(2):
            state = root / idle_ab.CPUS / f"cpu{n}/cpuidle/state{i}"
            state.mkdir(parents=True)
            (state / "disable").write_text("0\n")
            (state / "time").write_text("0\n")
    hwmon = root / idle_ab.HWMON / "hwmon1"
    hwmon.mkdir(parents=True)
    (hwmon / "name").write_text("macsmc_hwmon\n")
    (hwmon / "power1_label").write_text("Heatpipe Power\n")
    (hwmon / "power1_input").write_text("1250000\n")
    (hwmon / "power2_label").write_text("Total System Power\n")
    (hwmon / "power2_input").write_text("6550000\n")
    other = root / idle_ab.HWMON / "hwmon4"
    other.mkdir(parents=True)
    (other / "name").write_text("tas2764\n")
    (other / "power1_label").write_text("Speaker\n")
    for policy, mhz in (("policy0", 912000), ("policy4", 3264000)):
        (root / idle_ab.POLICIES / policy).mkdir(parents=True)
        (root / idle_ab.POLICIES / policy / "scaling_cur_freq").write_text(f"{mhz}\n")
    (root / "proc/sys/kernel").mkdir(parents=True)
    (root / idle_ab.EAS).write_text("1\n")
    (root / idle_ab.STAT).write_text("cpu  9 0 0 9 0 0 0 0 0 0\n"
                                     "cpu0 3 0 1 4 2 0 0 0 0 0\ncpu1 1 0 0 9 0 0 0 0 0 0\nintr 5\n")
    if residency:
        param = root / idle_ab.RESIDENCY
        param.parent.mkdir(parents=True)
        param.write_text("10000\n")


class IdleAbTest(unittest.TestCase):
    def test_settings(self):
        self.assertEqual(idle_ab.parse_setting("default"), (0, 0, None, None, None))
        self.assertEqual(idle_ab.parse_setting("wfi-only"), (0, 1, None, None, None))
        self.assertEqual(idle_ab.parse_setting("pd-always"), (1, 0, None, None, None))
        self.assertEqual(idle_ab.parse_setting("res=500"), (0, 0, 500, None, None))
        self.assertEqual(idle_ab.parse_setting("pd-always@4-6,9"), (1, 0, None, {4, 5, 6, 9}, None))
        self.assertEqual(idle_ab.parse_setting("wfi-only@1"), (0, 1, None, {1}, None))
        self.assertEqual(idle_ab.parse_setting("no-eas"), (0, 0, None, None, 0))
        for bad in ("res=0", "res=", "res=x", "fast", "default@1", "pd-always@", "pd-always@3-1",
                    "pd-always@a", "pd-always@1,", "res=5@1", "no-eas@1", "eas"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                idle_ab.parse_setting(bad)

    def test_run_applies_each_setting_and_restores_everything(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fake_machine(root)
            machine = idle_ab.Machine(root)
            self.assertEqual(list(machine.sensors), ["Total System Power", "Heatpipe Power"])
            seen = []
            real_apply = machine.apply

            def apply(setting):
                real_apply(setting)
                seen.append(((root / idle_ab.CPUS / "cpu1/cpuidle/state0/disable").read_text(),
                             (root / idle_ab.CPUS / "cpu1/cpuidle/state1/disable").read_text(),
                             (root / idle_ab.RESIDENCY).read_text()))
            machine.apply = apply
            with mock.patch.object(idle_ab.time, "sleep"), \
                    mock.patch.object(idle_ab.time, "monotonic", side_effect=range(1000)):
                rows = idle_ab.run(machine, ["default", "pd-always", "res=500"], 2, 2, 0)
            self.assertEqual([r["setting"] for r in rows],
                             ["default", "pd-always", "res=500", "res=500", "pd-always", "default"])
            self.assertEqual(seen[1], ("1\n", "0\n", "10000\n"))
            self.assertEqual(seen[2], ("0\n", "0\n", "500\n"))
            # A setting without a residency runs with the one found, also after res=.
            self.assertEqual(seen[4], ("1\n", "0\n", "10000\n"))
            self.assertEqual(rows[0]["watts"], 6.55)
            self.assertEqual(rows[0]["mhz"], {"policy0": 912, "policy4": 3264})
            self.assertEqual(machine.busy(), {0: (4, 10), 1: (1, 10)})
            self.assertEqual(rows[0]["busy_pct"], 0.0)
            self.assertEqual(rows[0]["busy_pct_by_cpu"], {0: 0.0, 1: 0.0})

    def test_busy_time_is_the_difference_over_the_window(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fake_machine(root)
            machine = idle_ab.Machine(root)
            stat = root / idle_ab.STAT

            def sleep(seconds):
                if seconds == 1:  # a sampling sleep, after the window's first snapshot
                        stat.write_text("cpu0 9 0 1 4 2 0 0 0 0 0\ncpu1 1 0 0 19 0 0 0 0 0 0\n")
            with mock.patch.object(idle_ab.time, "sleep", side_effect=sleep), \
                    mock.patch.object(idle_ab.time, "monotonic", side_effect=range(1000)):
                rows = idle_ab.run(machine, ["default"], 1, 2, 0)
            # cpu0: 6 more busy jiffies of 6; cpu1: none of 10.
            self.assertEqual(rows[0]["busy_pct_by_cpu"], {0: 100.0, 1: 0.0})
            self.assertEqual(rows[0]["busy_pct"], 37.5)
            self.assertEqual(rows[0]["sensors"], {"Total System Power": 6.55,
                                                  "Heatpipe Power": 1.25})
            self.assertEqual(sorted({p.read_text() for p in machine.saved}), ["0\n", "1\n", "10000\n"])
            for path, value in machine.saved.items():
                self.assertEqual(path.read_text(), value)
            self.assertEqual((root / idle_ab.RESIDENCY).read_text(), "10000\n")

    def test_a_cpu_list_sets_only_those_cpus(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fake_machine(root, cpus=11)
            machine = idle_ab.Machine(root)
            self.assertEqual(machine.numbers(), list(range(11)))
            states = []
            real_apply = machine.apply

            def apply(setting):
                real_apply(setting)
                states.append([(root / idle_ab.CPUS / f"cpu{n}/cpuidle/state{i}/disable")
                               .read_text().strip() for n in range(11) for i in (0, 1)])
            machine.apply = apply
            with mock.patch.object(idle_ab.time, "sleep"), \
                    mock.patch.object(idle_ab.time, "monotonic", side_effect=range(1000)):
                rows = idle_ab.run(machine, ["pd-always@1,10", "wfi-only@0-1"], 1, 2, 0)
            pd = ["0"] * 22
            pd[2] = pd[20] = "1"
            self.assertEqual(states[0], pd)
            self.assertEqual(states[1], ["0", "1", "0", "1"] + ["0"] * 18)
            self.assertEqual(sorted(rows[0]["pd_pct_by_cpu"]), list(range(11)))
            for path in machine.saved:
                expected = "0\n" if "disable" in str(path) else "1\n" if path == root / idle_ab.EAS \
                    else "10000\n"
                self.assertEqual(path.read_text(), expected)

    def test_a_missing_cpu_is_refused_before_anything_is_written(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fake_machine(root)
            machine = idle_ab.Machine(root)
            machine.apply = mock.Mock()
            with self.assertRaisesRegex(ValueError, "no CPU 2"):
                idle_ab.run(machine, ["default", "pd-always@1-2"], 1, 1, 0)
            machine.apply.assert_not_called()

    def test_no_eas_turns_eas_off_only_for_its_window(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fake_machine(root)
            machine = idle_ab.Machine(root)
            seen = []
            real_apply = machine.apply

            def apply(setting):
                real_apply(setting)
                seen.append((root / idle_ab.EAS).read_text())
            machine.apply = apply
            with mock.patch.object(idle_ab.time, "sleep"), \
                    mock.patch.object(idle_ab.time, "monotonic", side_effect=range(1000)):
                idle_ab.run(machine, ["default", "no-eas", "pd-always"], 1, 2, 0)
            self.assertEqual(seen, ["1\n", "0\n", "1\n"])
            self.assertEqual((root / idle_ab.EAS).read_text(), "1\n")

    def test_eas_is_not_written_unless_a_setting_uses_it(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fake_machine(root)
            (root / idle_ab.EAS).chmod(0o444)
            machine = idle_ab.Machine(root)
            with mock.patch.object(idle_ab.time, "sleep"), \
                    mock.patch.object(idle_ab.time, "monotonic", side_effect=range(1000)):
                idle_ab.run(machine, ["default", "pd-always"], 2, 2, 0)
            self.assertNotIn(root / idle_ab.EAS, machine.written)

    def test_restores_after_an_error(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fake_machine(root)
            machine = idle_ab.Machine(root)
            with mock.patch.object(idle_ab.time, "sleep", side_effect=KeyboardInterrupt), \
                    self.assertRaises(KeyboardInterrupt):
                idle_ab.run(machine, ["pd-always", "res=200"], 1, 5, 1)
            self.assertEqual((root / idle_ab.CPUS / "cpu0/cpuidle/state0/disable").read_text(),
                             "0\n")
            self.assertEqual((root / idle_ab.RESIDENCY).read_text(), "10000\n")

    def test_residency_setting_needs_the_parameter(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fake_machine(root, residency=False)
            machine = idle_ab.Machine(root)
            with mock.patch.object(idle_ab.time, "sleep"), \
                    self.assertRaises(FileNotFoundError):
                idle_ab.run(machine, ["res=500"], 1, 1, 0)

    def test_report_pairs_by_round(self):
        rows = [{"round": n, "setting": s, "watts": w, "pd_pct": 1.0, "wfi_pct": 2.0,
                 "sensors": {"Total System Power": w, "Heatpipe Power": w / 4},
                 "busy_pct": 40.0 if s == "default" else 30.0,
                 "mhz": {"policy0": 912, "policy4": 1000 + n}}
                for n, base in enumerate((12.0, 8.0, 10.0))
                for s, w in (("default", base), ("pd-always", base - 0.5))]
        report = "\n".join(idle_ab.report(rows, ["default", "pd-always"]))
        total, heatpipe = report.split("Heatpipe Power:")
        self.assertIn("default         10.00", total)
        self.assertIn("pd-always        9.50", total)
        self.assertIn("-0.500 W (sd 0.00, se 0.000, lower in 3 of 3)", total)
        self.assertIn("pd-always        2.38", heatpipe)
        self.assertIn("-0.125 W", heatpipe)
        clocks = report.split("Busy time and clocks:")[1]
        self.assertIn("default        40.0       912      1001", clocks)
        self.assertIn("pd-always      30.0       912      1001", clocks)


if __name__ == "__main__":
    unittest.main()
