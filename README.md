# Aurora-DeepIdle

CPU deep idle and sleep-drain research for the 14" MacBook Pro M2 Pro
(T6020, `apple,j414s`) running the [linux-aurora](https://github.com/omacom/linux-aurora)
kernel, with the measurement tools, the kernel and device tree changes, and
the raw data behind every number.

The full write-up is [docs/deep-idle-research.md](docs/deep-idle-research.md).
[docs/worklog.md](docs/worklog.md) is the running log of what was run on the
machine and what it showed.

## Findings

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
* **A residency of 500 us gets most of it.** With the
  `cpuidle_apple.pd_residency_us` patch, 500 us captured 93% of PD
  always's saving on a quiet desktop. Idle intervals shorter than the
  threshold stay in WFI and pay no latency. The busy-desktop sweep is
  still to do.
* **Energy-aware scheduling is off on T602x.** The CPU OPP tables have no
  `opp-microwatt`, so no energy model registers, and upstream Asahi has
  the same gap. This repo derives values from M2's (T8112, same cores)
  measured power at this machine's own per-OPP voltages, taken from the
  ADT. Booted: the model registers, EAS moves light work from the P to the
  E cores, and idle power is 61 mW lower (15 of 15 rounds).
* **The PMP is not booted on J414s, and turning it on stops the boot in
  m1n1.** The PMP is the fabric and memory DVFS controller; Asahi measured
  about 0.5 W saved by booting it on an M1 Pro. With the PMP DTB, m1n1's
  `dt_set_pmp` fails to copy the ADT's PMP tunables into the DT (likely
  out of DT space) and refuses to boot. `m1n1/pmp-tunable-nonfatal.patch`
  makes that failure name its cause and boot without the PMP.
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
(`harness/`, results in `data/campaign/`). The write-up has each result,
and what went wrong on the way.

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
| `tools/idle-ab.py` | Paired A/B of cpuidle settings by SMC power (all sensors), with busy time and clocks; settings `default`, `wfi-only`, `pd-always[@cpus]`, `res=US`, `no-eas` |
| `tools/wakelat.c` | Wake-up latency probe (timer overshoot, cross-CPU futex wake), SCHED_FIFO |
| `tools/sleep-drain-probe.py` | s2idle drain, wake sources (tracefs), domains left on through a suspend |
| `tools/deep-idle-check.py` | Read-only check after booting a test image: which image, EM, PMP, cpuidle, domains |
| `tools/t6020-cpu-em.py` | Derives T602x CPU `opp-microwatt` from T8112's measurements, writes them into the DT |
| `tools/cpuidle-pd-always.tmpfiles.conf` | Opt-in rule for "PD always" at boot |
| `tools/tests/` | Unit tests for all of the above |
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
