# Aurora-DeepIdle

CPU deep idle and sleep-drain research for the 14" MacBook Pro M2 Pro
(T6020, `apple,j414s`) running the [linux-aurora](https://github.com/omacom/linux-aurora)
kernel, with the measurement tools, the kernel and device tree changes, and
the raw data behind every number.

Start with [docs/status.md](docs/status.md): where everything stands, in one
page. The full write-up is [docs/deep-idle-research.md](docs/deep-idle-research.md),
the plan for real suspend to RAM is [docs/s2r-plan.md](docs/s2r-plan.md), and
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
* **The PMU's RTC alarm wakes the machine from s2idle (test kernel).**
  The alarm macOS uses for its dark wakes is in the PMU beside the RTC
  counter, and Linux had no driver for it. `patches/pmu-rtc-alarm.patch`
  adds it to macsmc-rtc and wires the SPMI controller's interrupt to AIC 724:
  `rtcwake -m freeze -s 30` woke after about 31 s in 3 of 3 cycles
  (`data/deepidle3/`). The register map came from macOS (issue #5) and was
  corrected on the machine: the alarm is in PMU counter seconds, and the PMU
  sets a "fired" bit that must be cleared before the next alarm. This is the
  timed wake unattended S2R tests need.
* **s2idle drains about 1.4 W, and the PMP does not change it.** One
  night with the PMP running (9.6 h, `data/s2idle/`) drained 1.39-1.46 W,
  and a stock suspend on battery 1.41 W: 23% of the battery a night, about
  1.7 days from full with the lid closed. Suspend and resume work with
  the PMP. The 3.2 wakes a second come from the AOP (ambient-light and
  lid-angle sensor reports; those drivers have no suspend hooks) and cost
  milliwatts; the drain is power left on. `harness/s2idle-alloff.sh`
  bounds how much of it driver work could reach.
* **macOS sleeps this machine at 0.24 W, a sixth of Linux's s2idle**
  (issue #3, measured by `tools/macos-agent-prompt.md`): 5.9 h lid closed on
  battery, 98.7% of it in S2R. Awake idle matches Linux with the PMP (SMC
  Total System Power 5.57 W against 5.38 W, SoC 1.22 W on both), so the gap
  is SoC sleep itself. The T6020 PMP runs under `AppleASCWrapV4`, whose CPU
  run bit is the ASC `CPU_CONTROL` bit Linux already uses; the device memory
  thought to be a run register is the PMP firmware. macOS has the SD reader,
  Thunderbolt NHI, ANE and external display pipelines powered down with
  nothing plugged in. The SMC's HDMI and SD rail sensors read 0 W on Linux
  as well, rails on, so they cannot show whether a rail is off
  (`harness/smc-keyread/`).
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
  path. macOS wakes the PMP from IDLE by restarting its CPU: wait for ASC
  `CPU_STATUS & 3`, clear `CPU_CONTROL` RUN, set it again on wake (corrected
  after issue #3). The hook stays off; a fixed one is expected to save
  little, since s2idle drains the same with and without the PMP. Tools in `tools/macos-re/` (no Apple files
  in this repo).
* **The SMC sleep handshake: `slpa` takes the storage away.** Sent in
  s2idle one step at a time (`WKTP`, then `slpw`, then `slpa`, with `waka`
  on resume), the first two are harmless. After `slpa` the Mac resumed but
  every NVMe access failed, and the state survived a warm reboot; only a
  full power off cleared it. So `slpa` means "the SoC is about to lose
  power" and belongs last on a real S2R path.
* **The PMP's wake from IDLE is a power cycle on macOS, and Linux cannot
  restart it yet.** RUN alone woke it 0 of 3 times. Gating its SRAM domain
  did not restart it, and a PMGR reset of `ps_pmp` crashed the whole SoC.
  `ps_pmp` is pinned on by iBoot. What is left to try is macOS's DART and
  outbox steps around RUN.
* **S2R plan and Phase 1** ([docs/s2r-plan.md](docs/s2r-plan.md),
  [docs/psci-efi.md](docs/psci-efi.md)). Phase 1, PSCI CPU_ON and CPU_OFF
  through the PSCI-via-EFI RFC, is built in the kernel, in Aura and in
  U-Boot, and is not booted yet. The macOS sleep trace under the hypervisor
  uses a separate macOS 14.8.3 volume, the pinned guest version (newer XNU
  needs SPTM).
* **The HDMI port's rails cost 0.13 W with nothing plugged in**, outside the
  SoC (12 paired rounds, lower in 12 of 12). The DCP driver never lowers them
  on T6020; `patches/hdmi-rails-off-in-sleep.patch` lowers them in system
  sleep (compile-tested, not booted). An SD reader link left without ASPM L1
  costs 0.37 W, which is how the all-off night (`data/s2idle/`) drained 2.1 W.
  Removing and rescanning PCI devices kills the Wi-Fi chip until a reboot;
  the harness no longer does it.
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
| `docs/status.md` | One-page summary: results, the S2R pieces, what is built but not booted, how testing works |
| `docs/s2r-plan.md` | The phased plan to S2R (PSCI provider in Aura, macOS trace, devices, daily use) |
| `docs/psci-efi.md` | Phase 1: PSCI CPU_ON/CPU_OFF through EFI in the kernel, Aura and U-Boot; the first boot test |
| `tools/macos-hv-testvol.sh` | macOS side: download 14.8.3, add the `macOSTest` volume, open the installer; `setup` mode inside the new system |
| `tools/macos-hv-prep.sh` | macOS side: the `hvsleep=1` sleep job and the data the hypervisor run needs, sent to the controller |
| `tools/im4p-extract.py` | IMG4/IM4P kernelcache to the Mach-O `run_guest.py` loads (needs the `lzfse` tool) |
| `harness/hv/`, `harness/remote/hv-run.sh` | Boot the guest volume once (`asahi-bless`), build the recoveryOS script that installs Aura on it, and the Pi's unattended guest run |
| `harness/overnight/run.sh` | One measured overnight s2idle, woken by the owner; results in `data/overnight/` |
| `harness/mmio/pmp-cycle.c` | Address-limited PMP restart experiments (`reset-cycle` is retired: it crashed the SoC); results in `data/pmp-cycle/` |
| `patches/psci-efi/`, `patches/hvsleep-trace/` | Phase 1 (Aura, U-Boot, the T6020 PSCI DTS) and the Aura hypervisor change for the sleep trace |
| `tools/idle-ab.py` | Paired A/B of cpuidle settings by SMC power (all sensors), with busy time and clocks; settings `default`, `wfi-only`, `pd-always[@cpus]`, `res=US`, `no-eas`, `set:PATH=VALUE[,...]` (any sysfs knob for the window) |
| `tools/wakelat.c` | Wake-up latency probe (timer overshoot, cross-CPU futex wake), SCHED_FIFO |
| `tools/sleep-drain-probe.py` | s2idle drain, wake sources (tracefs), domains left on through a suspend |
| `tools/deep-idle-check.py` | Read-only check after booting a test image: which image, EM, PMP, cpuidle, domains |
| `tools/t6020-cpu-em.py` | Derives T602x CPU `opp-microwatt` from T8112's measurements, writes them into the DT |
| `tools/cpuidle-pd-always.tmpfiles.conf` | Opt-in rule for "PD always" at boot |
| `tools/tests/` | Unit tests for all of the above |
| `tools/mac-power-telemetry` | The owner's battery telemetry, now logging every suspend (logind delay lock, coulomb counter); `tools/mac-power-telemetry-watch.service` |
| `tools/macos-sleep-test.sh` | macOS sleep-drain baseline on the same battery gauge: `curl -fsSL https://raw.githubusercontent.com/JJRPF/Aurora-DeepIdle/main/tools/macos-sleep-test.sh \| bash -s -- arm`, close the lid at least 4 h (overnight is better), then the same with `report`, which opens an issue with the result (`gh`) |
| `tools/macos-s2r-prompt.md` | Prompt for an agent on macOS: live sleep-related device tree and power properties, one timed 3-minute sleep, and what the 15.7.1 kexts do to enter and leave S2R (PMU RTC alarm, PMP, PMGR, PMU quiesce, memory, AIC, SEP, PCIe, CPU wake vector); opens one issue. `claude "$(curl -fsSL https://raw.githubusercontent.com/JJRPF/Aurora-DeepIdle/main/tools/macos-s2r-prompt.md)"` |
| `tools/macos-agent-prompt.md` | Prompt for an agent on macOS: PMP device memory, SMC power switches and wake keys (read only), awake idle power, power states, then the sleep test; opens one issue with all of it when the owner says so |
| `harness/hdmi-power/` | HDMI rails A/B: `smc-pwr-test.ko` (test only) switches `hdmi-pwren` (SMC GPIO 23, gP17) and `dp2hdmi-pwren` (6, gP06), which the DCP driver keeps on, off at run time; `run.sh` measures them with `idle-ab.py`; `s2idle-alloff.sh` turns them off for its lid close too |
| `harness/s2idle-wake/`, `harness/s2idle-ab.sh` | Self-waking s2idle (from before the PMU alarm driver) and one measured suspend per setting, on battery |
| `patches/pmu-rtc-alarm.patch`, `harness/deepidle3/` | The PMU's RTC alarm for Linux (macsmc-rtc alarm, SPMI interrupt 2 on AIC 724, T602x DT): `rtcwake -m freeze` wakes on time. The one-boot test kernel installer and its smoke test; results in `data/deepidle3/` (run 1: the alarm-fired bit bug; run 2: 3 of 3 woke on time) |
| `harness/mmio/` | `pmu-rtc.py` (decode, arm and fire the PMU alarm through the nvmem file, watch the SPMI and AIC lines), `alarm-s2idle.sh` (one s2idle with the alarm and a backup waker), `mmio-read.c` (read only), `mmio-write.c` (limited to the SPMI controller page), `dtb-chain.py` (list, extract or swap the DTBs in an m1n1 image) |
| `harness/awake-ab/run.sh`, `harness/net-guard.sh` | Awake A/B of SD link ASPM and the HDMI rails; a guard that reboots and reopens the session if the network dies |
| `harness/smc-keyread/` | `smc-keyread.ko` (test only, read only): every readable SMC `flt` key starting with P in debugfs; `sample.py` gives the mean, min and max of each over N seconds |
| `harness/remote/mac-ready.sh`, `docs/pi-handoff.md` | Driving the Mac from a Raspberry Pi 5: a read-only check that the Mac can be driven over SSH (key login, `sudo -n`, kernel, PMU RTC, stay-awake), and the handoff for the Pi session (paths, connecting, Aura proxy mode, standing rules, next work) |
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

Three patches stand apart from that series, made against the 11.35 release
tree the test kernels were built from: `deepidle2-pmp-s2idle-idle.patch` (the
PMP s2idle hook), `hdmi-rails-off-in-sleep.patch` and `pmu-rtc-alarm.patch`
(two commits, `git am`).

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
