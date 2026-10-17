# Aurora-DeepIdle

CPU deep idle and sleep-drain research for the 14" MacBook Pro M2 Pro
(T6020, `apple,j414s`) running the [linux-aurora](https://github.com/omacom/linux-aurora)
kernel, with the measurement tools, the kernel and device tree changes, and
the raw data behind every number.

The full write-up is [docs/deep-idle-research.md](docs/deep-idle-research.md).
[docs/worklog.md](docs/worklog.md) is the running log of what was run on the
machine and what it showed.

## Findings

* **Booting the PMP saves 0.9-1.15 W, the largest single win.** The PMP
  is the fabric and memory power controller (Asahi measured about 0.5 W
  on an M1 Pro). J414s does not boot it today, and enabling it stops the
  boot in m1n1: `dt_set_pmp` copies the ADT's 81 PMP tunables, which need
  15,850 bytes, and only 12,936 of m1n1's 96 KiB DT headroom are left by
  then (measured with `m1n1/pmp-diag.patch`; upstream m1n1 is the same).
  With 160 KiB of headroom (`m1n1/pmp-fix-test.patch`) every tunable fits
  and Linux boots. Loading the PMP driver mid-boot lowered a quiet desktop
  by 0.90 W (6.28 to 5.38 W, on battery) and 1.06 W (6.67 to 5.61 W, on
  AC, measured at the wall), and a busy desktop by 1.15 W (7.52 to
  6.36 W). SoC power fell 0.7-1.0 W. The same power domains stayed on,
  wake latency did not change, and nothing logged a warning. With PD
  always as well, the busy desktop went from 7.52 to 5.69 W (24% less).
  A control boot with nothing loaded drifted at most 80 mW.
* **s2idle drains about 1.4 W, and the PMP does not change it.** One
  night with the PMP running (9.6 h, `data/s2idle/`) drained 1.39-1.46 W,
  and a stock suspend on battery 1.41 W: 23% of the battery a night, about
  1.7 days from full with the lid closed. Suspend and resume work with
  the PMP. The 3.2 wakes a second come from the AOP (ambient-light and
  lid-angle sensor reports; those drivers have no suspend hooks) and cost
  milliwatts; the drain is power left on. `harness/s2idle-alloff.sh`
  bounds how much of it driver work could reach.
* **macOS tells the PMP when the system sleeps; Linux never does.** Read
  from the public macOS 13.5 J414s kernelcache (symbols intact) and device
  tree: the full order of the platform sleep and quiesce actions, the SMC's
  `MBSE` handshake (`slpw`, `slpa`, wake `waka` with an `MBSW` wake bitmap),
  PMGR's last step (a write to an always-on PMGR block Linux does not map),
  and the PMP's sleep action: RTKit IDLE (0x201), which is Linux's unused
  `apple_rtkit_idle()`. `deepidle2`
  (`patches/deepidle2-pmp-s2idle-idle.patch`, `harness/deepidle2/`) adds it
  to s2idle. Smoke test (`data/deepidle2/`): the PMP acks IDLE in 399 us but
  never answers again, because Linux's INIT wake is macOS's wake-from-QUIESCED
  path. macOS wakes the PMP from IDLE by restarting its CPU
  (`AppleA7IOPV4PMP::_runCPU`), through a register not yet identified. The
  hook must stay off until then. Tools in `tools/macos-re/` (no Apple files
  in this repo).
* **CPU PD on every idle entry saves up to about 1 W, depending on the
  wake rate.** The `apple_idle` driver's "CPU PD" state (deep WFI with
  retention, the state macOS idles in) has a 10 ms target residency, so on
  a busy desktop (about 1,500 wakes per CPU per second) the menu governor
  almost never picks it. Disabling WFI makes every idle entry CPU PD. On
  a long-running desktop (6.5-8.6 W) Total System Power dropped by
  0.9-1.1 W, lower in every paired round. Under load the saving grows:
  1.3-2.5 W at 14-17 W. Busy time and clocks stayed the same, so it is
  idle power, and it comes from the P clusters. On a fresh, quiet boot menu
  already picks CPU PD 90% of the time and the gain is only 0.1-0.15 W.
  The Asahi kernel behaves the same (0.54 W at 2.8% busy). The cost is
  10-15 us of extra wake-up latency.
* **A target residency of 100 us gets nearly all of it.** With the
  `cpuidle_apple.pd_residency_us` patch and a synthetic busy-desktop wake
  load (`harness/wakeload.c`, 5-6% busy, about 1,700 wakes per CPU per
  second), the saving grows with the share of idle time in CPU PD: 2 ms
  saves 53 mW, 500 us 330 mW, 200 us 526 mW, 100 us 591 mW and PD always
  628 mW. Wake latency rises to about 20-25 us p50 as soon as PD is used
  at all and does not depend on the threshold (p99 at most 37 us), so
  100 us is the recommended default: 94% of the saving, with WFI kept for
  idles predicted shorter than that. The quiet-desktop sweep agrees.
* **Energy-aware scheduling is off on T602x.** The CPU OPP tables have no
  `opp-microwatt`, so no energy model registers, and upstream Asahi has
  the same gap. This repo derives values from M2's (T8112, same cores)
  measured power at this machine's own per-OPP voltages, taken from the
  ADT. Booted: the model registers, EAS moves light work from the P to the
  E cores, and idle power is 61 mW lower (15 of 15 rounds).
* **Power domains stay on for nothing.** In s2idle, every display
  coprocessor's domains stay on, the external ones included with nothing
  attached. Awake, the Neural Engine's domains stay on because its DARTs
  are pinned by a blanket runtime-PM link to a device with no driver. The
  four USB-C ports' USB blocks have no runtime PM, nor does the SD reader.
* **Idle P clusters do drop to their lowest pstate.** The saving comes from
  idle cores inside busy clusters, which sit at the voltage their busy
  siblings set.

* **The external display coprocessors cost nothing measurable at idle**
  with nothing attached (E4: SoC power within 0.1 W across boots).

The energy model (E6), the residency kernel (E7), the no-external-DCP DTB
(E4) and the PMP DTB (E1) were all booted in an unattended campaign
(three runs, 2026-10-15/16)
(`harness/`, results in `data/campaign/`). The write-up has each result,
and what went wrong on the way.

## Recommended changes

1. m1n1: more DT headroom (160 KiB here), and a PMP tunable copy that
   leaves the PMP disabled instead of failing the boot when it does not
   fit (`m1n1/pmp-tunable-nonfatal.patch`). An upstream issue.
2. J414s (and likely the other T602x boards): enable the PMP in the DT,
   once 1 is in. Still to test: the PMP enabled from boot with the driver
   built in, and long runs. s2idle and resume work (one night).
3. `cpuidle-apple`: a CPU PD target residency of 100 us instead of 10 ms.
4. The T602x CPU energy model (`opp-microwatt`), so EAS runs: 61 mW at
   idle, more for light loads.

## Try the main result now (no reboot)

```
echo 1 | sudo tee /sys/devices/system/cpu/cpu*/cpuidle/state0/disable   # PD always
echo 0 | sudo tee /sys/devices/system/cpu/cpu*/cpuidle/state0/disable   # back to default
```

It does not survive a reboot. `tools/cpuidle-pd-always.tmpfiles.conf`
makes it persistent: copy it to `/etc/tmpfiles.d/`.

## Layout

| Path | What |
|---|---|
| `docs/deep-idle-research.md` | The research: states, what macOS does, measurements, designs, experiments, unknowns |
| `docs/worklog.md` | Session log: every live run, its settings and results |
| `tools/idle-ab.py` | Paired A/B of cpuidle settings by SMC power (all sensors), with busy time and clocks; settings `default`, `wfi-only`, `pd-always[@cpus]`, `res=US`, `no-eas`, `set:PATH=VALUE[,...]` (any sysfs knob for the window) |
| `tools/wakelat.c` | Wake-up latency probe (timer overshoot, cross-CPU futex wake), SCHED_FIFO |
| `tools/sleep-drain-probe.py` | s2idle drain, wake sources (tracefs), domains left on through a suspend |
| `tools/deep-idle-check.py` | Read-only check after booting a test image: which image, EM, PMP, cpuidle, domains |
| `tools/t6020-cpu-em.py` | Derives T602x CPU `opp-microwatt` from T8112's measurements, writes them into the DT |
| `tools/cpuidle-pd-always.tmpfiles.conf` | Opt-in rule for "PD always" at boot |
| `tools/tests/` | Unit tests for all of the above |
| `tools/mac-power-telemetry` | The owner's battery telemetry, now logging every suspend (logind delay lock, coulomb counter); `tools/mac-power-telemetry-watch.service` |
| `tools/macos-sleep-test.sh` | macOS sleep-drain baseline on the same battery gauge: `curl -fsSL https://raw.githubusercontent.com/JJRPF/Aurora-DeepIdle/quick-Campaign/tools/macos-sleep-test.sh \| bash -s -- arm`, close the lid at least 4 h (overnight is better), then the same with `report`, which posts the result to PR #2 with `gh` |
| `harness/hdmi-power/` | HDMI rails A/B: `smc-pwr-test.ko` (test only) switches `hdmi-pwren` (SMC GPIO 23, gP17) and `dp2hdmi-pwren` (6, gP06), which the DCP driver keeps on, off at run time; `run.sh` measures them with `idle-ab.py` |
| `harness/pmp-run/toggle.sh` | Probe of macOS's PMP run store (`AppleA7IOPV4PMP::_runCPU`, 0x28e700000+0): SRAM or a run register; restores the word |
| `tools/macos-re/` | Reading a public macOS kernelcache: remote IPSW extraction, IM4P, chained-pointer fixups, fileset kexts, vtables, Ghidra headless scripts |
| `dts/` | The opt-in J414s variants: PMP on, and no external DCPs (copies; they live in the kernel tree) |
| `patches/` | The kernel tree changes as a `git format-patch` series |
| `data/` | Raw A/B and latency runs (JSON lines and reports), see `data/README.md`; `data/campaign/` holds the booted experiments |
| `harness/` | The unattended reboot-per-step test harness, as run (machine-specific) |
| `m1n1/` | Draft m1n1 change: a PMP tunable failure leaves the PMP off instead of stopping the boot |

## The kernel changes

`patches/` is the whole `GH-1-DeepIdle` branch of linux-aurora: 44 commits
on `integration/aurora` at `cadfb30a447f72cc8b10e0c6ef64cbdb6894fd05`. They
add the T602x CPU energy model (`t602x-common.dtsi`), the
`cpuidle_apple.pd_residency_us` parameter, the two J414s DTS variants, the
tools under `tools/aurora-sep/`, and the write-up.

```
git clone https://github.com/omacom/linux-aurora && cd linux-aurora
git switch -c deep-idle cadfb30a447f72cc8b10e0c6ef64cbdb6894fd05
git am /path/to/Aurora-DeepIdle/patches/*.patch
```

The DTS variants are deliberately not in the kernel Makefile. They share the
stock board's compatible, and m1n1 boots the last matching DTB. Build them
by name and splice the result into m1n1's stage 2; the write-up explains
how.

## Tests

```
python3 -m unittest discover -s tools/tests -v
```

The T602x DT and energy-model tests need a linux-aurora tree with the
patches applied, plus `cpp` and the kernel's `dtc` for Apple's
floating-point cells. Set `AURORA_TREE=/path/to/linux-aurora` and
`DTC=/path/to/build/scripts/dtc/dtc`. Without a tree, those tests skip.

## Safety

The tools only read, except for the following, which restore everything on
exit:

* `idle-ab.py` writes the cpuidle `disable` files, `pd_residency_us` and
  `sched_energy_aware`.
* `sleep-drain-probe.py` manages its own tracefs instance and can ask
  systemd to suspend.

The tools install nothing. Installing a kernel, touching `/boot` or
m1n1's `boot.bin`, and rebooting are left to the machine's owner, step by
step, in the write-up. The exception is `harness/`, which does all of
those as root once installed; read its README first.

## License

The patches and DTS files are kernel changes, under the kernel's licenses
(GPL-2.0; the DTS files are `GPL-2.0+ OR MIT`, as their SPDX lines say).
The tools come from linux-aurora's `tools/aurora-sep/` under the same terms
as that tree.
