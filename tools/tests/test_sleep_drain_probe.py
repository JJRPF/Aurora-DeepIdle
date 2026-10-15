"""sleep-drain-probe.py: counter parsing and the drain report."""

from pathlib import Path
import importlib.util
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("probe", ROOT / "sleep-drain-probe.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)

INTERRUPTS = """\
           CPU0       CPU1
 36:        100        200   AIC-FIQ   0 Level     arch_timer
103:          5          0   AIC2 67368 Level     nvme-apple
IPI1:        10         20   Function call interrupts
"""

SOURCES = """\
name\t\tactive_count\tevent_count\twakeup_count\texpire_count
macsmc-input\t10\t\t10\t\t0\t\t0
macsmc-battery\t137\t\t387\t\t0\t\t0
"""


TRACE = """\
# tracer: nop
#
# entries-in-buffer/entries-written: 9/9   #P:10
#
          <idle>-0       [000] d..1. 100.000001: suspend_resume: timekeeping_freeze[0] begin
          <idle>-0       [004] d..1. 100.000002: suspend_resume: timekeeping_freeze[4] end
          <idle>-0       [004] d.h1. 100.000003: irq_handler_entry: irq=103 name=nvme-apple
          <idle>-0       [004] d.h1. 100.000004: hrtimer_expire_entry: hrtimer=00000000 function=tick_nohz_handler now=1
          <idle>-0       [000] d.h1. 100.000005: irq_handler_entry: irq=36 name=arch_timer
          <idle>-0       [006] d..1. 100.000006: suspend_resume: timekeeping_freeze[6] end
          <idle>-0       [006] d.h1. 100.000007: irq_handler_entry: irq=1 name=IPI
          <idle>-0       [006] d.h1. 100.000008: ipi_entry: (Function call interrupts)
    kworker/6:1-90       [006] ..... 100.000009: workqueue_execute_start: work struct 00000000: function vmstat_update
"""


def snap(boottime, monotonic, energy, pd, timer, status="Discharging", genpd=None):
    return {
        "wall": 0, "monotonic": monotonic, "boottime": boottime,
        "battery": {"status": status, "energy_uwh": energy, "capacity": 80},
        "cpus": {"cpu0": {"WFI": 0, "CPU PD": pd}},
        "interrupts": {"36 AIC-FIQ 0 Level arch_timer": timer},
        "wakeup_sources": {"macsmc-input": {"events": 3, "wakeups": 0}},
        "suspend_success": 1, "mem_sleep": "[s2idle]",
        "genpd": genpd, "always_on": ["afi"],
    }


class ProbeTest(unittest.TestCase):
    def test_interrupts_sum_each_line_over_cpus(self):
        self.assertEqual(probe.interrupts(INTERRUPTS), {
            "36 AIC-FIQ 0 Level arch_timer": 300,
            "103 AIC2 67368 Level nvme-apple": 5,
            "IPI1 Function call interrupts": 30,
        })

    def test_wakeup_sources_keep_event_and_wakeup_counts(self):
        self.assertEqual(probe.wakeup_sources(SOURCES), {
            "macsmc-input": {"events": 10, "wakeups": 0},
            "macsmc-battery": {"events": 387, "wakeups": 0},
        })

    def test_snapshot_reads_a_sysfs_tree(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            battery = root / probe.BATTERY
            battery.mkdir(parents=True)
            (battery / "status").write_text("Discharging\n")
            (battery / "energy_now").write_text("47731800\n")
            state = root / probe.CPUS / "cpu0/cpuidle/state1"
            (state / "s2idle").mkdir(parents=True)
            (state / "name").write_text("CPU PD\n")
            (state / "s2idle/usage").write_text("506937\n")
            (root / "proc").mkdir()
            (root / "proc/interrupts").write_text(INTERRUPTS)
            taken = probe.snapshot(root)
        self.assertEqual(taken["battery"]["energy_uwh"], 47731800)
        self.assertEqual(taken["cpus"], {"cpu0": {"CPU PD": 506937}})
        self.assertIsNone(taken["wakeup_sources"])
        self.assertIsNone(taken["genpd"])
        self.assertEqual(len(taken["interrupts"]), 3)

    def test_genpd_counts_power_offs_and_dt_marks_always_on(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name, usage, state in (("gfx", "4", "off-0"), ("disp0_cpu0", "0", "on")):
                domain = root / probe.GENPD / name
                domain.mkdir(parents=True)
                (domain / "idle_states").write_text(
                    "State  Time(ms)       Usage      Rejected   Above      Below      S2idle\n"
                    f"S0     0              {usage}          0          0          0          0\n")
                (domain / "current_state").write_text(state + "\n")
            pmgr = root / probe.PMGR / "power-management@28e080000"
            for reg, label, fixed in (("100", "afi", True), ("200", "gfx", False)):
                node = pmgr / f"power-controller@{reg}"
                node.mkdir(parents=True)
                (node / "label").write_text(label + "\0")
                if fixed:
                    (node / "apple,always-on").write_text("")
            self.assertEqual(probe.genpd(root), {
                "disp0_cpu0": {"off": 0, "state": "on"},
                "gfx": {"off": 4, "state": "off"},
            })
            self.assertEqual(probe.always_on(root), ["afi"])

    def test_report_lists_domains_that_stayed_on_through_the_suspend(self):
        before = {"gfx": {"off": 3, "state": "on"}, "disp0_cpu0": {"off": 0, "state": "on"},
                  "afi": {"off": 0, "state": "on"}, "isp_sys": {"off": 1, "state": "off"}}
        after = {"gfx": {"off": 4, "state": "on"}, "disp0_cpu0": {"off": 0, "state": "on"},
                 "afi": {"off": 0, "state": "on"}, "isp_sys": {"off": 1, "state": "off"}}
        a = snap(1000, 1000, 50_000_000, 0, 0, genpd=before)
        b = snap(37000, 1060, 41_000_000, 35940, 71880, genpd=after)
        b["suspend_success"] = 2
        report = "\n".join(probe.compare(a, b))
        self.assertIn("stayed on through a suspend (1; 1 always-on domains not listed):\n"
                      "  disp0_cpu0", report)

    def test_trace_names_what_woke_the_soc(self):
        report = "\n".join(probe.analyse_trace(TRACE))
        self.assertIn("s2idle trace: 2 whole-SoC wakes", report)
        self.assertIn("       1  50.0%  nvme-apple", report)
        self.assertIn("       1  50.0%  IPI Function call interrupts", report)
        self.assertIn("       1    0.50  vmstat_update", report)
        self.assertNotIn("arch_timer\n", report.split("interrupts while")[0])
        self.assertNotIn("buffer filled", report)

    def test_trace_warns_when_the_buffer_filled(self):
        report = "\n".join(probe.analyse_trace(TRACE.replace("9/9", "9/50")))
        self.assertIn("kept the first 9 of 50 events", report)

    def test_report_gives_drain_and_wakes_per_suspended_second(self):
        # 10 h window, 10 h minus 60 s suspended; 9 Wh used; 36000 wakes.
        a = snap(boottime=1000, monotonic=1000, energy=50_000_000, pd=0, timer=0)
        b = snap(boottime=37000, monotonic=1060, energy=41_000_000, pd=35940, timer=71880)
        report = "\n".join(probe.compare(a, b))
        self.assertIn("suspended 9.98 h", report)
        self.assertIn("average drain over the window: 0.900 W", report)
        self.assertIn("cpu0:     1.00/s", report)
        self.assertIn("(2.00 per suspended s)", report)
        self.assertNotIn("warning", report)

    def test_report_warns_when_on_ac(self):
        a = snap(1000, 1000, 50_000_000, 0, 0, status="Not charging")
        b = snap(2000, 1500, 50_000_000, 0, 0, status="Not charging")
        report = "\n".join(probe.compare(a, b))
        self.assertIn("warning: the battery was not discharging", report)
        self.assertIn("note: the awake time", report)


if __name__ == "__main__":
    unittest.main()
