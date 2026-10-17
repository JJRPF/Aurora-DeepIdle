# s2idle drain

* `2026-10-16-night-pmp.txt`: `sleep-drain-probe.py report` for one lid close, 2026-10-16 23:06 to
  10-17 08:40, on battery. Test kernel, `boot.bin.pmpfix-test`, the PMP bound (`modprobe pmp`).
* `telemetry-sleep-2026-10-10-16.jsonl`: the owner's `mac-power-telemetry` sleep records (battery
  energy from sysfs, sampled every 3 minutes, so each window includes up to 3 minutes awake). The
  2026-10-10 14:16 record is the stock comparison (Aurora kernel, stock image, on battery). The
  2026-10-10 22:53 one ended on AC, so it is only a lower bound. Records starting on AC show no drain.
