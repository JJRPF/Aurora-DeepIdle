# Raw runs

All taken on one J414s (M2 Pro, 10 cores) on 2026-10-14/15. The kernel was
linux-aurora release 11.35, and other work was running on the machine, so
the load differs between runs. Each window is one JSON line. `.txt` is the
report `idle-ab.py` printed.

| File | Tool | Settings | Rounds x window | Load |
|---|---|---|---|---|
| `idle_ab1.jsonl` | first scratch version of idle-ab | default, wfi-only, pd-always | 6 x 15 s | ~11-13 W |
| `idle_ab2.jsonl` | first scratch version of idle-ab | default, wfi-only, pd-always | 30 x 15 s | ~6.7 W |
| `idle_ab3.jsonl/.txt` | `tools/idle-ab.py`, all SMC sensors | default, pd-always | 12 x 20 s | ~14 W |
| `idle_ab4.jsonl/.txt` | per-CPU settings | default, pd-always on E (0-3), P (4-9), one P cluster (4-6), all | 10 x 20 s | ~32 W |
| `idle_ab5.jsonl/.txt` | with busy time and clocks | default, pd-always, pd-always on P | 12 x 20 s | ~17 W |
| `idle_ab6.jsonl/.txt` | with busy time and clocks | default, pd-always | 20 x 20 s | ~6.5 W, quiet |
| `wakelat_ab.jsonl` | `tools/wakelat.c`, SCHED_FIFO | default, pd-always; timer on cpu1 (E) and cpu9 (P), futex wake E1->E2 and E1->P6 | 6 rounds, 1,000 samples at 2 ms | not recorded |

The first two runs and the latency run came from scratch scripts that
preceded `tools/idle-ab.py`. Their records use `config` where later ones
use `setting`. Their logs ended with a "restored" status line, removed here.
Every run left all cpuidle `disable` files at 0.

## Folders

Later runs each have their own folder.

| Folder | What |
|---|---|
| `campaign/` | The booted experiments of the unattended campaign (E1, E4, E6, E7), 2026-10-15/16 |
| `s2idle/` | Lid-closed nights: with the PMP running, and with everything optional off |
| `deepidle2/`, `deepidle3/` | Smoke tests of the PMP s2idle hook and of the PMU RTC alarm |
| `awake-ab/` | Awake A/B of the SD link ASPM and the HDMI rails |
| `smc-power-keys/` | SMC power sensor readouts |
| `pmp-cycle/` | 2026-10-23: the PMP SRAM gate cycle (no restart) and the reads around it; the `ps_pmp` reset that crashed the SoC left no file |
| `overnight/` | 2026-10-23/24: 8.33 h of s2idle on the default kernel. `report.txt` is `sleep-drain-probe.py`'s report. The battery figure is a lower bound only: the charger was connected and the charge limit held the battery at 80% |
