# Deep idle and deep sleep on the M2 Pro (T6020, J414s)

Research notes, 2026-10-14. Machine: MacBook Pro 14" M2 Pro (`apple,j414s`),
kernel `7.1.12-2-11.35-sep-ARCH+`, m1n1 stage 2 `v1.6.1-29-gc6498e6e`, stage 1
`v1.5.2`, system firmware 26.0, OS firmware 13.5. Sources are pinned: XNU
`xnu-12377.1.9`, AsahiLinux/m1n1 `94395adc` (main, 2026-10-13), AsahiLinux/docs
`0d1f891`. Kernel paths are relative to this tree. Anything not verified on this
machine or in source is marked as an unknown.

## Answers in brief

* **CPU deep idle already works.** Asahi's downstream `apple_idle` driver
  ([cpuidle-apple.c](../drivers/cpuidle/cpuidle-apple.c)) runs here with two
  states: WFI (clock gated) and "CPU PD", Apple's deep WFI with state
  retention. Every CPU has both, and s2idle uses only CPU PD; awake, the
  governor almost never picks CPU PD (fourth point). What is missing
  is everything below the cores: cluster power-off without retention, and
  SoC-level sleep.
* **Raw boot mode is enough for the CPU side on T6020; dj is right there.**
  m1n1 marks M1, M2 and M3 cores, M2 Pro included, as having Apple's system
  registers unlocked in raw boot mode. It writes CYC_OVRD and ACC_OVRD
  itself, including the ACC deep-sleep bits. The registers lock from M4 / A18
  Pro on, which is where "needs Mach-O mode" applies (Ryan). Whether iBoot
  sets up the *wake* path the same way for a raw image is not known; nobody
  has slept and woken an Apple SoC from raw mode.
* **What blocks deep sleep (S2R) is the SoC sleep protocol, not the CPU.** No
  public source describes how macOS asks PMGR, SMC, PMP and AOP to put the SoC
  to sleep, or how the PMGR "reconfig engine" restarts the boot CPU on wake.
  That is the macOS-under-hypervisor work. One concrete obstacle sits in
  m1n1's hypervisor: it refuses the CYC_OVRD write XNU makes on its way into
  system sleep.
* **CPU PD on every idle entry saves 0.15-1 W; a 100 µs residency gets
  nearly all of it.** The driver's 10 ms target residency means menu
  almost never picks CPU PD on a busy desktop. Disabling WFI (so every
  idle entry is CPU PD) lowered system power by 0.6-1.1 W at a 6-9 W
  desktop and 1.3-2.5 W under moderate load, in paired A/B runs, with the
  work done and the clocks unchanged; the saving is in the P clusters. On
  a quiet, freshly booted desktop menu already picks CPU PD about 90% of
  the time and the gain is 0.15 W. It costs 10-15 µs per wake-up. With
  `cpuidle_apple.pd_residency_us`, booted in the campaign, a residency of
  100 µs got 94% of the PD always saving under a busy-desktop wake load,
  at the same latency: that is the recommended default.
* **Energy-aware scheduling is off on T602x.** The CPU OPP tables have no
  `opp-microwatt`, so no energy model registers. With values derived from
  M2's measurements at this machine's voltages (E6, booted), the model
  registers, EAS moves light work from the P to the E cores, and idle
  power is 61 mW lower.
* **The largest win is the PMP: 0.9-1.15 W.** The PMP coprocessor (fabric
  and memory power management) is not booted on this machine: the DT is
  built without `APPLE_USE_PMP`. Turning it on stops the boot in m1n1,
  because its 81 tunables need 15,850 bytes of DT space and only 12,936
  bytes of m1n1's headroom are left (upstream m1n1 too). With 160 KiB of
  headroom the boot works, and loading the PMP driver lowered idle power
  by 0.90 W (battery) and 1.06 W (AC, measured at the wall) on a quiet
  desktop, and by 1.15 W under a busy-desktop load, with the same power
  domains on and the same wake latency. Together with PD always, the busy
  desktop went from 7.52 to 5.69 W. Asahi measured 0.5 W on an M1 Pro.
  Tested as a module loaded after boot, about 15 minutes per boot; booting
  it built in and long runs are not tested yet. Suspend and resume with it
  work (one night).
* **s2idle drains about 1.4 W on this machine, with or without the PMP.**
  One night with the PMP running (9.6 h suspended) used 13.98 Wh, 1.39-1.46
  W; a stock suspend on battery from 2026-10-10 (1.7 h, from the owner's
  `mac-power-telemetry` log) drained 1.41 W. That is 23% of the battery's
  60.5 Wh a night, about 1.7 days from full to empty with the lid closed.
  The PMP's 0.9 W awake saving does not carry into s2idle (the driver has
  no suspend hook, so the PMP is never told the system is asleep). The
  0.9 W quoted here before was a J415 figure from elsewhere, not this
  machine.
* **macOS sleeps this machine at 0.24 W, a sixth of Linux's s2idle.**
  macOS 15.7.1, lid closed on battery for 5.9 h (2026-10-17, issue #3):
  1.41 Wh, 0.24 W, 98.7% of the time in S2R ("Deep Idle") with 27 brief dark
  wakes. Awake and idle the two systems match (SMC `PSTR` 5.57 W, `PHPC` 1.22 W
  on macOS; 5.38 W and 1.22 W on Linux with the PMP), so the 1.16 W gap is
  what S2R powers down: the CPUs, DRAM in self-refresh, the SoC clocks. Below,
  under "macOS 15.7.1 live".
* **What wakes s2idle is the AOP; the drain is power left on, not wakes.**
  The SoC woke 3.2 times a second, 61% of the time from the AOP's mailbox
  (`2a6408000`, the always-on processor serving the ambient-light and
  lid-angle sensors and the microphones) and 39% from function-call IPIs that
  its RTKit receive work sends to other CPUs. All that awake time is
  milliwatts. What stays on through every suspend is 13 power domains that
  the kernel may power off: the internal display and both external display
  pipelines (DCP CPU, front end and system domains), because the DCP driver
  marks itself a wakeup path to keep its domains on ("we do not support full
  shutdown properly yet"), even with nothing plugged in, plus PCIe, `afr` and
  `sio`.
* **Awake, four groups of power domains stay on for nothing.** The Neural
  Engine's (its DARTs are pinned by a blanket runtime-PM link to a device
  with no driver), all four USB-C ports' USB blocks with nothing plugged
  in (no runtime PM in the dwc3 glue, PHY and mux), the SD reader (no
  runtime PM for the GL9755) and the external DCPs. Each needs driver
  work; the designs are under Measurements.

## Idle and sleep states on T6020

| Level | Mechanism | Who drives it | Linux on J414s today |
|---|---|---|---|
| Core clock gating | `wfi`, CYC_OVRD WFI_MODE default | kernel | `apple_idle` state 0, "WFI" |
| Core power-down, state kept | `wfi` with CYC_OVRD WFI_MODE=3, retention left on | kernel | `apple_idle` state 1, "CPU PD": every CPU, and every s2idle entry |
| Core power-down, state lost | CYC_OVRD `ok2pwrdn_force_down` + `disWfiRetn`; restart through PMGR CPU-start and RVBAR | kernel + firmware | **missing**: spin-table has no `cpu_die`; m1n1's PSCI branch returns NOT_SUPPORTED for CPU_OFF |
| Cluster / SoC deep sleep | ACC_OVRD `enDeepSleep`, `ok2PwrDnSRM`, `ok2TrDnLnk`, `ok2PwrDnCPM`, L2 flush; all CPUs off first | kernel, then PMGR/SMC/PMP | **missing** |
| SoC sleep (S2R) | PMGR + SMC + PMP + AOP sequence; wake by the PMGR reconfig engine at the boot CPU's RVBAR | macOS kexts (closed) | **unknown protocol**; Linux offers only `s2idle` (`/sys/power/mem_sleep` = `[s2idle]`) |

Register layout from m1n1 (`src/cpu_regs.h` 531-562): CYC_OVRD is
`s3_5_c15_c5_0`, with WFI_MODE in bits 25:24 and DISABLE_WFI_RET in bit 0;
ACC_OVRD is `s3_5_c15_c6_0`. The cpuidle driver sets bits 25:24 (WFI_MODE=3)
and never sets bit 0, so its deep WFI keeps state
([cpuidle-apple.c](../drivers/cpuidle/cpuidle-apple.c) lines 33-46).

## What macOS does (XNU, read only)

* **Idle.** On cores with `HAS_RETENTION_STATE` (H14 = M2 family,
  `pexpert/pexpert/arm64/H14.h` line 41), `cpu_idle()` executes
  `arm64_retention_wfi()` (`osfmk/arm64/cpu.c` line 595). That WFI may lose
  every GPR except sp and pc, and then resumes through `cpu_idle_exit()`
  (`machine_routines_asm.s`, `arm64_retention_wfi`). Which state each idle
  entry uses is chosen through `cpu_idle_notify`, a closed platform callback.
  So macOS's idle-state policy and break-even times are not public.
* **Sleep.** `arm64_prepare_for_sleep()` (`machine_routines_asm.s` from line
  1000) masks IRQ/FIQ in CYC_OVRD for non-final CPUs. On the deep-sleep path
  it sets ACC_OVRD's deep-sleep fields (line 1056), then CYC_OVRD
  `ok2pwrdn_force_down` and `disWfiRetn` (lines 1098-1100), and loops in WFI.
  `__ARM_GLOBAL_SLEEP_BIT__` (H14.h line 86) makes the ACC deep-sleep bit
  global: secondaries stall until CPU0 releases `arm64_stall_sleep`, because a
  normal idle WFI hangs once it is set (`cpu.c`, `ml_arm_sleep`).
* **Wake.** `ml_arm_sleep()` (`cpu.c` lines 1033-1040): "Newer SoC do not go
  through SecureROM/iBoot on the warm boot path. The reconfig engine script
  brings the CPU out of reset at the kernel's reset vector which points to the
  warm boot initialization code." `WITH_CLASSIC_S2R` (the iBoot sleep-token
  path) is not defined for H14 in the public headers. Every core comes back at
  its RVBAR with state lost.

## What constrains Linux in raw boot mode

* **Sysregs.** m1n1's per-core feature table sets `apple_sysregs_unlocked`
  for M2 Pro Avalanche and Blizzard (`src/chickens.c` 82-85, 144-145), and
  leaves it unset for M4 and later (line 112). m1n1 writes ACC_OVRD's
  deep-sleep bits in `cpu_sleep(deep)` (`src/utils.c` 249-277), and
  `run_guest.py` uses that path on every hypervisor boot
  (`smp_stop_secondaries(True)`, line 158). On this machine the kernel writes
  CYC_OVRD on every CPU PD entry (millions of times this boot, below) without
  faulting. T8140 is the exception that proves the rule: there the same
  write is undefined, so this tree limits it to WFI
  ([cpuidle-apple.c](../drivers/cpuidle/cpuidle-apple.c) probe).
* **Reset vector.** iBoot "sets and locks the RVBAR of the boot CPU to be the
  top of the page that the entrypoint lives in. ... presumably after a resume
  from deep sleep, the boot CPU will start executing code here"
  (asahi-docs `docs/fw/macho-boot-protocol.md` line 84). Secondary RVBARs are
  free to change (`docs/hw/cpu/smp.md` line 46). m1n1 writes them and clears
  their lock (`src/smp.c` 185). The next m1n1 stage overwrites m1n1 in place
  (macho-boot-protocol line 126), and kboot reserves m1n1 in the FDT, so the
  locked vector lands in resident, reserved m1n1 code. A wake would therefore
  enter m1n1, which must then hand back to Linux. Sven Peter's
  [PSCI-via-EFI RFC](https://ratatoskr.run/b4-sent/2026/07/17228962/t)
  ([m1n1 branch `psci-via-efi`](https://github.com/AsahiLinux/m1n1/tree/psci-via-efi))
  already keeps m1n1 resident as a PSCI provider and handles RVBAR re-entry
  by MPIDR. Its CPU_SUSPEND covers WFI (0) and deep WFI (1); CPU_OFF returns
  NOT_SUPPORTED; there is no SYSTEM_SUSPEND; the only board wired up is
  T8103.
* **Mach-O mode.** Ryan's statement that deep sleep needs Mach-O boot (and
  Aurora's internal bootloader rework) is consistent with this for M4 and
  later, where raw mode locks the sysregs. For T6020 the remaining unknown is
  iBoot's side: whether it programs the reconfig engine's wake script and
  RVBAR for a raw image as it does for a kernelcache. **Unknown**; only a
  sleep-and-wake attempt will tell (experiment E3 below).

## Measurements on this machine (read only)

Idle residency over 30 s at the desktop, on AC, with browser media and agent
processes running (`/sys/devices/system/cpu/cpu*/cpuidle`):

```
cpu0 WFI  93.1% (1090/s)  PD   1.7% (7/s, above 96%)  busy   5.2%
cpu3 WFI  88.3% (763/s)   PD   6.8% (11/s, above 79%)  busy   4.8%
cpu9 WFI  90.6% (885/s)   PD   5.7% (14/s, above 85%)  busy   3.6%
avg Total System Power (SMC PSTR): 6.55 W
```

The CPUs are about 95% idle, but only 2-7% of the time is CPU PD: each CPU
wakes about 1000 times a second, and the CPU PD state's target residency is
10 ms ([cpuidle-apple.c](../drivers/cpuidle/cpuidle-apple.c) line 114). The
wakes were IPI1 at about 700/s per CPU and the arch timer at about 630/s per
CPU (`/proc/interrupts`, 10 s). The `csd` tracepoint (2 s) put about 99% of
the IPIs on `sched_ttwu_pending`, i.e. remote wakeups of browser media threads
and node processes. This is workload, not a platform defect. The 10 ms
residency is a conservative guess; Sven's RFC uses the same value for
`cpu-deep-wfi`, and nobody has measured its break-even.

s2idle, from this boot's counters (`cpuidle/state1/s2idle/usage`): four
successful suspends, three of them long (9.7 h, 12 h and 16.8 h, about
38.5 h in all). Each CPU logged 0.5-0.7 million CPU PD entries in s2idle and
none in WFI. Four CPUs (0, 4, 6, 7) logged 506,937-506,991, almost the same
number, so most entries are system-wide wakes: about 3.7 per second of
sleep. In that time the debugfs
wakeup sources counted only a few hundred events, so most of these wakes are
not wakeup-source events; the source is **unknown**.

Those wakes are short. The s2idle time counters use the scheduler clock,
which stops only while every CPU sleeps (`tick_freeze()` suspends
timekeeping when the last CPU freezes, `kernel/time/tick-common.c` 519-547).
So a CPU's s2idle time is the time some CPU was awake while it slept: 40-66 s
per CPU over 38.5 h, about 0.05%, or about 130 us per wake. Even at 5 W while
awake that is a few mW on average. **Whatever the drain is, it is power left
on during the sleep, not the wakes.** (An earlier version of this note called
it 0.9 W; that was a J415 figure from elsewhere. The first measurement on this
machine is under the campaign below: 1.46 W with the PMP running.)

What is left on: each power domain's debugfs `idle_states` usage counts its
power-offs. GPU, ANE, NVMe (`ans2`), audio, the USB controllers, SIO's CPU
and the I2C/SPI/UART domains show exactly 4, one per suspend. These domains
are not `apple,always-on` in the PMGR tree and still never powered off in
any of the four suspends (`dptx_phy_ps` is marked always-on by the board,
`t602x-j414-j416.dtsi`, until DCP can sequence it):

```
disp0_cpu0 disp0_fe disp0_sys                internal display (DCP)
dispext0_cpu0 dispext0_fe dispext0_sys       external display 0 (DCP)
dispext1_cpu0 dispext1_fe dispext1_sys       external display 1 (DCP)
dptx_phy_ps                                  DisplayPort PHY
apcie_gp apcie_gpshr_sys                     PCIe (Wi-Fi, SD reader)
atc0_common .. atc3_common                   USB-C PHY common blocks
afr sio
```

The display domains are held on deliberately: `dcp_platform_suspend()` calls
`device_set_wakeup_path()` "which forces its power domains to stay on. We
need this as we do not support full shutdown properly yet"
([dcp.c](../drivers/gpu/drm/apple/dcp.c), around line 2732). That keeps all
three DCPs and their DARTs powered through every suspend, including both
external DCPs, with no external display connected (every DP and HDMI
connector reads `disconnected`). The DCPs do not support runtime PM
(`power/runtime_status` is `unsupported`), so they are also on whenever the
machine is awake: all three DCP firmwares are started at bind
(`dcp_start()` from `apple_drv.c`). How much these domains draw is not
known; the SMC gives only a system total. E4 below measures the two
external ones. Upstream Asahi has the same code, and the PMP variant
does not change it: the DCP is still a wakeup path, so its PMP report
domain stays on as well.

Power domains while awake (`pm_genpd_summary`): the `pmp` and `pms*`
domains are on but the PMP driver is not bound. The `pmp_report` entries
exist as genpd domains with no consumers. The DCP sits on
`ps_disp0_cpu0`, not `pmp_report_disp0`. The live `pmp` node is `disabled`,
with no `apple,tunable-*` properties: m1n1's `dt_set_pmp` (kboot.c 2089-2128)
fills those in only when the DT has a `pmp` alias, which only
`APPLE_USE_PMP` adds.

Who arms the timers while awake (20 s, tracefs `timer` events in an
instance of its own, 2026-10-14, with agent sessions running): 3,939
`hrtimer_wakeup` and 1,629 tick expiries per second across all CPUs. One
user-space process, `agy`, armed 3,263 `hrtimer_wakeup`s per second, about
80% of them (sub-millisecond sleeps in a polling loop). Browser media
threads, mimalloc's `mi-scavenger` (208/s) and `claude` (168/s) follow. No
kernel timer stands out (`delayed_work_timer_fn` 42/s, `process_timeout`
67/s), so there is no driver poller to fix; idle residency while awake is
set by the workload.

Domains left on in s2idle other than the displays are all parents of
domains the device tree keeps always on: `atc*_common` of `atc*_pcie`,
`apcie_gp` of `apcie_gp_sys` ("Breaks things if shut down"), `sio` of `aes`
and `dptx_phy_ps`. `afr` is the parent of `gfx` and `dispext0_sys`, so E4
should free it too. Wi-Fi power save is off on purpose
(`/etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf`, from
omarchy-settings: latency over "a fraction of a watt"), and the Wi-Fi
function is a wakeup device (`power/wakeup` enabled).

CPU PD threshold, A/B on the live machine (2026-10-14, AC, other agent
sessions running, so the load swung by several W). Six rounds rotated three
settings through the cpuidle `disable` files, 20 s each, logging SMC Total
System Power; everything was set back to 0 at the end:

```
setting                     mean W   PD %   WFI %   per-round difference from default
default                     12.48     3.9    84.5
WFI only (PD disabled)      12.81     0.0    87.1   +0.33 W (sd 1.15)
PD always (WFI disabled)    11.59    86.6     0.0   -0.90 W (sd 1.48), lower in 5 of 6
```

A longer repeat, the same day, with the same busy machine: 30 rounds of
15 s windows, which narrows the paired spread instead of needing a quiet
machine:

```
setting                     mean W   PD %   WFI %   paired difference from default
default                      6.69     5.8    86.5
WFI only (PD disabled)       6.72     0.0    92.5   +0.03 W (se 0.17), lower in 14 of 30
PD always (WFI disabled)     5.70    91.9     0.0   -0.99 W (se 0.20), lower in 25 of 30
```

So forcing CPU PD on every idle entry saves about 1 W, 15% of the
machine's power at the desktop, about five standard errors from zero. The
menu governor's choice uses no less than never using CPU PD at all: with a
10 ms target residency and about 1,500 wakes per CPU per second it almost
never picks it.

The cost is wake-up latency. `tools/aurora-sep/wakelat.c` (SCHED_FIFO,
1,000 samples per test at 2 ms, six alternating rounds, medians of the
rounds):

```
test                           default p50 / p99    PD always p50 / p99
timer, E core (cpu1)            8.9 / 17.9 us        18.5 / 39.6 us
timer, P core (cpu9)            8.4 / 14.8 us        18.4 / 34.8 us
futex wake E1 -> E2             8.5 / 19.0 us        17.2 / 30.0 us
futex wake E1 -> P6            12.3 / 21.6 us        20.8 / 34.1 us
```

CPU PD adds about 10 us per wake-up, which matches its declared exit
latency (10 us). At 1,500 wakes per CPU per second that is at most 1.5% of
a CPU's time, too little to explain the power drop by doing less work. The
worst cases did not change beyond noise. CPU PD is also the state XNU idles
in (`arm64_retention_wfi`: deep WFI with retention); m1n1 sets plain WFI to
WFI_MODE 2 at boot (`src/chickens.c` 247-250) and uses the non-retention
power-off only on the way into system sleep (`src/utils.c` 270-277). So the
core-level idle state already matches macOS; the governor's choice did
not.

Later runs, on the same machine under heavier load from other work, with
every SMC power sensor and, in the last, each setting's busy time and
clocks (`idle-ab.py`, paired by round):

```
load    rounds  setting         Total System     Heatpipe (SoC)    lower in
~14 W   12      PD always       -2.55 W (0.93)   -2.03 W (0.95)    10 / 12
~32 W   10      PD always       -6.57 W (2.38)   -5.29 W (2.14)     7 / 10
~32 W   10      PD on E only    +0.21 W (0.99)   +0.10 W (0.90)     6 / 10
~32 W   10      PD on P only    -4.37 W (1.60)   -3.81 W (1.54)     8 / 10
~32 W   10      PD on P0 only   -2.98 W (1.78)   -2.12 W (1.68)     9 / 10
~17 W   12      PD always       -1.34 W (0.91)   -1.88 W (0.77)     9 / 12
~17 W   12      PD on P only    -0.49 W (1.22)   -0.82 W (1.07)     7 / 12
                                (standard errors in brackets)
```

The cleanest run came last, on a quiet machine (about 6.5 W, busy
6.7%), 20 rounds of 20 s:

```
setting        mean W   PD %   WFI %   paired difference from default
default         6.52     5.7    87.0
pd-always       5.61    91.9     0.0   -0.92 W (se 0.12), lower in 20 of 20
Heatpipe Power: default 3.36 W, pd-always 2.55 W (-0.82 W, se 0.12, 18 of 20)
busy 6.7% / 7.4%; mean MHz E/P0/P1 984/871/829 vs 986/861/810
```

Three things follow. The saving is in the SoC package (Heatpipe Power
moves with Total System Power), and it grows with load: a core idling in
WFI is still powered at its cluster's current voltage, so its leakage
rises with the cluster's clock; CPU PD cuts it off. Most of it is in the P
clusters; the E cores show none, within the noise. And it is not bought by
doing less: in the last run the busy time was 28.4% with the default and
30.4% with PD always, and the mean clocks were 1337/2015/1977 MHz (E, P0,
P1) against 1362/2128/1992 MHz, so the work and the clocks did not drop.
What these runs do not give is energy per unit of work on a fixed
workload, which needs a machine nobody else is using.

Until a lower residency is in a kernel,
`echo 1 | sudo tee /sys/devices/system/cpu/cpu*/cpuidle/state0/disable`
reproduces "PD always" at runtime, and `echo 0` undoes it; it does not
survive a reboot. `tools/aurora-sep/cpuidle-pd-always.tmpfiles.conf` makes
it persistent (opt-in, not installed). Its cost is the wake-up latency
measured above, about 10 us per wake-up.

To find the break-even point without a rebuild per value,
`cpuidle-apple.c` now takes `pd_residency_us` (default 10000, unchanged
behaviour). It is a command-line parameter (`cpuidle_apple.pd_residency_us=`)
and writable at runtime: `echo 1000 | sudo tee
/sys/module/cpuidle_apple/parameters/pd_residency_us`. The governors read
the state's `target_residency_ns` on every idle entry, so the change takes
effect at once. Values below the exit latency or above 1 s are refused.
One reboot into a kernel with it allows an A/B over several values (for
example 10000, 2000, 1000, 500, 200) with the same rotating method.

Sensors usable for measurements: SMC "Total System Power" (hwmon
`macsmc_hwmon` power1), "Heatpipe Power" (power4), and the battery's
`energy_now` (`macsmc-battery`).

### Power domains held on while awake

With the display off and nothing plugged in, 116 of the 200 power domains
are on. Most are always-on or are parents of always-on domains, but four
groups are on only because a device never runtime-suspends (genpd keeps a
domain on while any device in it is runtime-active, and a device without
runtime PM counts as active). Read from `pm_genpd_summary`, each device's
`power/runtime_status` and its device links, on the 11.35 kernel after
58 h of uptime:

* **The Neural Engine's domains, held by a device with no driver.**
  `ane_cpu` and its parent `ane_sys` are on, held by two ANE DARTs
  (`285810000.iommu`, `285820000.iommu`) that have been runtime-active for
  the whole uptime. Their only consumer, `284000000.ane`, has no driver
  (this kernel has no accel/ANE driver). `apple_dart_probe_device()`
  links each consumer to its DART with `DL_FLAG_RPM_ACTIVE` (commit
  `727c99ada827`), which takes a runtime reference on the DART for the
  consumer and drops it only when the consumer runtime-suspends, so a
  consumer that never binds a driver keeps its DART, and the DART's domain,
  on for ever. The commit itself carries the question as a TODO ("Does
  this mean devices without bound drivers will keep their DARTs up
  indefinitely?"); this machine answers it: yes. The same commit is in
  mainline. The third ANE DART is in the always-on `pmp` domain, and the
  PMP's DART, which has no consumer, is suspended, as are the AVD and ISP
  DARTs, whose drivers runtime-suspend. The blanket reference is
  there for two kinds of consumer, and a fix has to keep both: a bound
  driver without runtime PM (the DART must not power-cycle under its DMA),
  and a device the boot loader left running before its driver loads (the
  internal DCP scans out the boot framebuffer through a locked DART, and
  `DRM_APPLE` is a module). So "take the reference only when a driver
  binds" is wrong. What would work: at `probe_device`, take it only if one
  of the consumer's streams is live (translation or bypass enabled, or the
  DART locked), which a boot-time device's stream is and the ANE's is not;
  and take it at `BUS_NOTIFY_BOUND_DRIVER` for a consumer whose driver did
  not enable runtime PM (the notifier runs before the probe-time supplier
  reference is dropped, so there is no gap), dropping it at unbind. A
  consumer driver that enables runtime PM is covered by the link itself.
  That is a proposal for upstream, not built. Disabling the ANE node in the
  DT would free the domains now, but would hide the device from an ANE
  driver.
* **All four USB-C ports' USB blocks.** `atc0_usb` .. `atc3_usb` have been
  on since boot with zero idle time, and no USB bus exists (no xHCI host:
  `dwc3-apple` creates one only when a cable is attached). Each domain
  holds the dwc3 glue (`dwc3-apple`), the ATC PHY and its mux, none of
  which implements runtime PM, plus two DARTs that follow the glue through
  the link above. `dwc3-apple` already tears dwc3 down when the cable goes
  (`DWC3_APPLE_NO_CABLE`); runtime PM in the glue, the PHY and the mux,
  suspended in that state and resumed from the Type-C mux/role callbacks,
  would let the four domains go off while nothing is plugged in. That is
  driver work across three drivers; the Type-C controllers (cd321x, I2C)
  keep detecting the plug meanwhile.
* **The SD card reader.** The GL9755 (`0000:02:00.0`) has been in D0 for the
  whole uptime: `sdhci-pci-gli` gives the GL9755 no runtime PM, unlike the
  GL9763E next to it in the same file. Its link idles in L1 (E5 would add
  L1.2). Tens of milliwatts at most.
* **The display coprocessors**, covered above (both external DCPs run with
  nothing attached; E4).

The internal display's mode was also checked: 3024x1964 at a fixed 120 Hz
with VRR off (`hyprctl monitors`). It was DPMS-off during these
measurements, so it did not affect them, but at the desktop a fixed
120 Hz keeps the DCP and the compositor's frame clock at 120 Hz; 60 Hz is
the obvious battery setting until the VRR idle stall (owner's feedback
notes) is fixed.

### Energy-aware scheduling is off: no CPU energy model on T602x

`/sys/kernel/debug/energy_model` is empty on this machine although
`kernel.sched_energy_aware` is 1, every cpufreq policy runs schedutil, and
the E and P cores have different capacities (561 and 1024). The energy
model for the CPUs comes from `opp-microwatt` in their OPP tables
(`cpufreq_register_em_with_opp()`), and `t602x-common.dtsi` has none: its
nine `opp-microwatt` entries are the GPU's. T8103, T600x, T8112 and T8140
all have measured CPU values (James Calligeros, measured with the SMC's
cluster power meter and freqbench), and upstream Asahi's `asahi` branch has
the same gap for T602x. Without an energy model the scheduler places tasks
by capacity and idleness only, so short, light tasks land on idle P cores
as readily as on E cores; with one, as long as no CPU is overutilized, it
places each waking task where the estimated energy is lowest, which for
light tasks is the E cluster (at the bottom OPP, an E core costs about
half of what a P core does per unit of capacity), and leaves the P
clusters in CPU PD.

T8112 (M2) has the same cores, Blizzard and Avalanche, so its measurements
carry over once each OPP's voltage is accounted for. This machine's
voltages are in the ADT (`/arm-io/pmgr` `voltage-states1` for the E
cluster, `voltage-states5` and `-13` for the P clusters; each pair of cells
is (65536000 / MHz, mV)):

```
E   912/612  1284/681  1752/775  2004/834  2256/887  2424/946
P   702/600   948/625  1188/646  1452/687  1704/718  1968/759  2208/793
   2400/825  2568/856  2724/896  2868/931  3000/975  3132/1012
   3264/1056 3360/1056 3408/1056 3504/1056                  (MHz/mV)
```

Fitting T8112's measured power to P = (a + b f) V^2 f at these voltages
gives 5.8% (E) and 6.3% (P) rms error, about the measurements' own
scatter; the implied switching capacitance is flat for E and rises a
little with frequency for P (leakage and heat at the top).
`tools/aurora-sep/t6020-cpu-em.py` does the fit and writes the values into
`t602x-common.dtsi` (`--write`); `tests/test_t6020_cpu_em.py` checks that
the tree carries them. The energy per cycle rises from each OPP to the
next, so the energy model marks no OPP inefficient: cpufreq keeps choosing
among all frequencies as today (an inefficient OPP is skipped by
schedutil), and only task placement changes. The other EAS conditions hold
on the running kernel: asymmetric capacities, no SMT, frequency
invariance (the driver implements `target_index` and `fast_switch`),
schedutil on every policy, and three performance domains well under the
complexity limit.

Not measured: the saving. It shows only when the machine is lightly loaded
(EAS stands aside while any CPU is overutilized), so it needs a quiet
machine after a reboot into the staged image. M2 Pro/Max share the table;
their voltages may differ by a few mV per bin, which moves the values by
a few percent.

## What was built

1. **`arch/arm64/boot/dts/apple/t6020-j414s-pmp.dts`**: `#define
   APPLE_USE_PMP` and the J414s board. The define adds the `pmp` alias and
   moves the DCP, both dcpext, AVD and ISP DART power domains onto their PMP
   report entries. It is deliberately not in the Makefile: it has the same
   compatible as `t6020-j414s.dtb`, and m1n1 boots the last DTB that matches,
   so packaging both would turn the PMP on for every J414s.
   `tools/aurora-sep/tests/test_t6020_pmp.py` compiles both boards and checks
   that the only source differences are the alias and the five
   power-domains lines. It also checks that the PMP node stays disabled until
   m1n1 fills it in, and that the Makefile does not list the variant.
2. **`tools/aurora-sep/sleep-drain-probe.py`**: snapshots the battery
   energy, time suspended (CLOCK_BOOTTIME - CLOCK_MONOTONIC), per-CPU s2idle
   entries, `/proc/interrupts` and, as root, wakeup sources. It compares two
   snapshots, or wraps one `systemctl suspend`. It reports drain in W, wakes
   per suspended second, and the interrupts that fired. It only reads, except
   that `around` asks systemd to suspend. `arm` and `report` bracket a
   suspend taken any way (lid, menu). `arm` also starts a tracefs instance
   of its own, switched on at `machine_suspend` begin and off at the first
   device resume callback, so it holds only what ran in s2idle. `report`
   names the interrupt or IPI that woke the SoC each time, tallies
   interrupts, timers and work items per wake, and lists the power domains
   that are not always-on and stayed on through the suspend. Tests:
   `tools/aurora-sep/tests/test_sleep_drain_probe.py`.
3. **`arch/arm64/boot/dts/apple/t6020-j414s-nodcpext.dts`**: the J414s
   board without its two external DCPs. It removes the `dcpext0`/`dcpext1`
   aliases, so m1n1 leaves them alone (it enables, and carves out memory
   for, only aliased DCPs: `src/kboot.c` 1735-1762). It disables both DCPs,
   their DARTs and mailboxes and the two `dispext` DARTs, and trims the
   display subsystem's `iommus` to the internal DART (an entry for a disabled
   DART fails the node's whole IOMMU setup). It also disables the DCPs'
   six Type-C `route@N` nodes: they carry `mode-switch`, the USB-C
   controllers (cd321x) look their mux up through the graph with
   `fwnode_typec_mux_get()`, and the graph checks only the far node's own
   status (`fwnode_graph_devcon_matches()`), so an enabled route under a
   disabled DCP would defer the USB-C controller probe for ever. Checked in
   the 11.35 source: the
   display driver skips unavailable DCPs, and USB-C display ports are only
   created from a probed DCP's routes, so none are created and none fail.
   fw_devlink ignores disabled suppliers. Not in the Makefile, for the same
   reason as the PMP variant. `tools/aurora-sep/tests/test_t6020_nodcpext.py`
   checks that only those properties change, against the merged sources,
   and that no graph link from an enabled node leads to a node that is
   disabled only through an ancestor. The DP audio controllers of the
   external DCPs stay enabled and log "No audio support" (`audio.c`).
4. **Staged, not installed**: `~/Work/deep-idle-build/boot.bin.pmp-test` is
   the current `/boot/m1n1/boot.bin` with its one J414s DTB (DTB #31 of 113,
   byte-identical to release 11.35's) replaced by the PMP variant, built from
   release 11.35 (`1caa9fdc3745`) to match the running kernel. The m1n1 code
   before it and everything after it, U-Boot included, are byte-identical.
   `~/Work/deep-idle-build/boot.bin.before-pmp-test` is a copy of the current
   image (sha256 `3630adc3...`). `~/Work/deep-idle-build/boot.bin.nodcpext-test`
   (sha256 `b69443cf...`) is the same image with the no-external-DCP DTB
   instead. Both were built from release 11.35's sources with the recipe
   that rebuilds its stock DTB byte for byte, and both keep the DTBs back to
   back (m1n1 walks them by `totalsize`).
5. **CPU energy model** (`t602x-common.dtsi`, see above), and its staged
   image `~/Work/deep-idle-build/boot.bin.em-test` (sha256 `462a289d...`):
   the current image with DTB #31 replaced by release 11.35's J414s DTB
   plus the 23 `opp-microwatt` properties, nothing else (decompiled diff).
   The chain is intact: 113 DTBs, everything before and after identical.
   `boot.bin.pmp-em-test` (sha256 `df7b49ba...`) stacks both: the PMP
   variant's DTB plus the same 23 properties. Each image installs and rolls
   back exactly as in the E1 procedure; test the PMP and the energy model
   one at a time before the combined one.

## Experiments, smallest first

After booting any of them, `sudo tools/aurora-sep/deep-idle-check.py`
names the m1n1 image by its hash and reports whether the change took:
CPU `opp-microwatt` in the live DT and the energy model's domains, the
`pmp` and `dcpext` aliases and whether `apple_pmp` bound, the cpuidle
settings with `pd_residency_us`, and the display, ANE, USB-C and PMP power
domains. It only reads.

* **E1, PMP on J414s** (needs a reboot; owner's go-ahead). Procedure below.
  This is the only change with an expected battery gain today.
* **E2, find the s2idle wake source and what stays on** (needs a suspend;
  owner's go-ahead). On battery: `sudo tools/aurora-sep/sleep-drain-probe.py
  arm`, close the lid for at least 30 minutes, open it, then `sudo
  tools/aurora-sep/sleep-drain-probe.py report`. Run it once on the stock DTB
  and once with E1, so the drain figures compare. The wakes matter less
  than first thought (see Measurements); the domain list and the drain
  matter more.
* **E4, what do the external DCPs cost?** (needs a reboot; owner's
  go-ahead). Boot `boot.bin.nodcpext-test` like E1, with no external display
  attached, and compare the idle power average and an E2 run against stock.
  Expect `dispext*` domains `off` in `pm_genpd_summary` and HDMI/USB-C
  display output gone. If the saving is real, the fix is in the DCP driver:
  start an external DCP only when a display is attached, and power it down
  when the last one leaves.
* **E5, PCIe L1 substates** (no reboot, but owner's go-ahead: a failed
  link drops Wi-Fi until reboot). ASPM L1 is on for the Wi-Fi/Bluetooth
  link (00:00.0 -> 01:00.0/1) and the SD reader link (00:01.0 -> 02:00.0),
  but L1.1 and L1.2 are off on all of them although both ends support ASPM
  L1.1 and L1.2 (`lspci -vv` L1SubCap). The ASPM policy is `default`, which
  keeps what the boot firmware set up. In s2idle the Wi-Fi function sits in
  D3 with its radio off (brcmfmac disassociates and sets MPC when there is
  no WoWLAN, and this chip has none) and the link idles in L1, not L1.2. Try
  the SD reader first, which nothing uses (its link has its own root port):
  `echo 1 | sudo tee /sys/bus/pci/devices/0000:02:00.0/link/l1_2_aspm`,
  then Wi-Fi's (`0000:01:00.0`), and measure with E2: the gain is tens of
  mW at most, invisible in an awake A/B. The pcie-apple driver disables link
  power states only for M3's MediaTek radios (`pcie-apple.c` around 2582).
* **E6, energy-aware scheduling** (needs a reboot; owner's go-ahead).
  Boot `boot.bin.em-test` the way E1 boots its image (same kernel; only the
  DTB changes). Check that the energy model registered: `sudo ls
  /sys/kernel/debug/energy_model` lists three performance domains (cpu0,
  cpu4, cpu7), and `sudo cat
  /sys/kernel/debug/energy_model/cpu0/ps:912000/power` reads 53000. Then,
  with the machine as quiet as it gets (EAS stands aside while any CPU is
  overutilized), `sudo tools/aurora-sep/idle-ab.py --rounds 20 --window 20
  default no-eas` pairs EAS on against EAS off in the same boot, and
  `pd-always` can join the same run. Expect light background work to move
  from the P clusters to the E cluster (busy time per cluster in the log)
  and Total System Power to drop when idle-ish; under load nothing changes.
  Rollback is the same as E1's, or at runtime `echo 0 | sudo tee
  /proc/sys/kernel/sched_energy_aware`.
* **E7, where CPU PD breaks even** (needs a reboot into a test kernel;
  owner's go-ahead). `~/Work/deepidle-11.35/` holds release 11.35's
  source (`git archive 1caa9fdc3745`, the running kernel) with only the
  `pd_residency_us` patch, built with the running config and
  `LOCALVERSION=-deepidle` (release `7.1.12-2-11.35-sep-ARCH-deepidle`), and
  `43_deepidle`, an opt-in GRUB entry modelled on `42_aurora_sep_previous`.
  Installing it touches `/boot` and `/lib/modules`, so the owner runs:

  The build is done and its modules are staged as the user under
  `staging/` (`modules_install INSTALL_MOD_PATH=`, 1,870 modules, 2.0 GB
  like the installed trees; the running tree's extra
  `macsmc-fan-cooling.ko`, not loaded, is not from this source), with the
  image as `staging/boot/vmlinuz-deepidle-test`:

  ```
  cd ~/Work/deepidle-11.35
  sudo cp -a staging/lib/modules/7.1.12-2-11.35-sep-ARCH-deepidle /lib/modules/
  sudo chown -R root:root /lib/modules/7.1.12-2-11.35-sep-ARCH-deepidle
  sudo cp staging/boot/vmlinuz-deepidle-test /boot/
  sudo mkinitcpio -k 7.1.12-2-11.35-sep-ARCH-deepidle -g /boot/initramfs-deepidle-test.img
  sudo install -m 755 43_deepidle /etc/grub.d/43_deepidle
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  ```

  `GRUB_DEFAULT=0` still boots "Omarchy Linux"; pick "Deep idle test" by
  hand, so a failed boot needs only a reboot. In the test kernel, the
  sweep is one paired run: `sudo tools/aurora-sep/idle-ab.py --rounds 20
  --window 20 default res=2000 res=500 res=100 pd-always`, plus
  `wakelat` at the chosen value. Removal: delete the two `/boot` files,
  `/etc/grub.d/43_deepidle` and `/lib/modules/7.1.12-2-11.35-sep-ARCH-deepidle`,
  then `grub-mkconfig` again. No other kernel, nor `boot.bin`, is touched.
* **E3, does a raw-mode SoC wake reach m1n1?** This is the experiment that
  decides raw vs Mach-O for the wake path. It needs a second machine and USB
  m1n1 proxy, and is not for the daily driver without a plan. From the m1n1
  proxy: `p.smp_stop_secondaries(True)`, then `p.sleep(True)` on the boot CPU
  (the ACC deep-sleep path), then press the power key or open the lid. If m1n1
  logs "RVBAR entry on primary CPU" (`src/startup.c`), the reset path works in
  raw mode. Measure power externally (USB-C meter) to see whether the SoC
  actually dropped or only the CPUs did. No reply means the wake script was
  never armed, which is either the missing SMC/PMGR handshake or the raw/Mach-O
  difference. This probably needs the hv trace below to tell those apart.

## Unattended campaign (2026-10-15)

With the owner's go-ahead for reboots, a root runner
(`deepidle-runner.service`, sources in `~/Work/deepidle-harness/`) runs one
step per boot: it records `deep-idle-check.py`, the kernel log and the power
domains, settles for 180 s, runs `idle-ab.py` (15 rounds of 20 s) and
`wakelat` for the step's settings, arms the next step (m1n1 image and GRUB
`next_entry`), and reboots once the session acknowledges it. An early unit
(`deepidle-early-restore.service`) puts the stock `boot.bin` back right
after `/boot` mounts, so each test image boots only once. The order is
stock, E6 energy model, E7 residency kernel, E4 no external DCPs, E1 PMP
(the riskiest, since `apple_pmp` is built in and probes before any
watchdog), then stock again.

* **Step 0, stock** (run in place, no reboot): PD always saved 1.080 W
  of Total System Power (8.61 to 7.53 W, standard error 0.215), lower in
  15 of 15 rounds; Heatpipe 0.70 W. Busy time 6.7% and 6.6%. The
  wake-up probe repeated the IPI cost (+9.5 us p50); timer wakes cost
  more this time (+14 to +18 us p50, against +8 to +10 before).

* **Step 1, E6 energy model** (`boot.bin.em-test`): the energy model
  registered (23 CPU `opp-microwatt` entries; performance domains cpu0,
  cpu4 and cpu7), with no errors. EAS on against off: 61 mW lower
  (standard error 12 mW, lower in 15 of 15), with P-cluster busy time
  0.11% against 0.39% and E-cluster 1.35% against 0.92%, so light work
  moved to the E cores as expected. The fresh boot was much quieter than
  step 0 (6.58 W, 0.6% busy against 8.61 W and 6.7%), and at that wake
  rate menu already picks CPU PD 89% of the time, so PD always saved only
  75 mW (standard error 7 mW). PD always's saving scales with the wake
  rate: about 1 W on a busy desktop, almost nothing on a quiet one.

* **Steps 2 to 5 did not measure.** Booting the test kernel let
  `kernel-modules-hook`'s `linux-modules-cleanup.service` move aside the
  hand-installed Aurora 11.35 module tree, since pacman owns neither it
  nor the test kernel's; its tmpfiles rule deleted both trees at the next
  boot. Later boots had no modules, so `/boot` did not mount, the SMC
  sensors were missing and there was no network, and no step measured.
  The ESP was not touched after step 1. The tree was rebuilt from the
  kernel's own build directory, and a drop-in now makes the cleanup skip
  trees marked `.keep`. Any other hand-installed kernel is exposed to the
  same cleanup whenever a different kernel boots.

* **Run 2, step 0, stock baseline** (fresh boot, on battery, after the
  modules were restored): 7.81 W at 0.6% busy, CPU PD 90% of idle time
  under menu, and PD always 142 mW lower (standard error 7 mW, 15 of 15).
  This is the same picture as step 1: forcing PD pays when wakes are
  frequent, not on a quiet desktop.

* **Run 2, step 1, E7 residency sweep** (test kernel): against menu's
  default 10 ms, Total System Power was 86 mW lower at 2,000 us (standard
  error 18 mW), 147 mW lower at 500 us, 158 mW at 100 us and 157 mW with
  PD always (all 15 of 15), at 6.83 W and 0.7% busy. The wake-up cost
  follows the threshold: the probe's 1 to 2 ms sleeps stay in WFI at
  2,000 us (no cost), and pay the 10 to 15 us PD exit at 500 us and below.
  On a quiet desktop 500 us gets 93% of the saving. The busy desktop,
  where PD always saved about 1 W, still needs the same sweep under a
  reproducible wake load.

* **Run 2, step 2, E4 no external DCPs** (`boot.bin.nodcpext-test`): it
  took effect (no `dcpext` aliases, all six `dispext0/1` domains off).
  It can only be compared across boots: Heatpipe (SoC) power was 2.08 W,
  against 2.00 W and 2.01 W in the stock and test-kernel boots, and Total
  System Power moves about 1 W between fresh boots. So idle external DCPs
  cost nothing measurable here (at most about 0.1 W). Starting them on
  demand is not worth it for awake idle power; s2idle is untested.

* **Run 2, step 3, E1 PMP** (`boot.bin.pmp-test`): **the boot stopped in
  m1n1**, before GRUB. Stage 2 printed `FDT: failed to transfer pmp
  tunable`, `Failed to prepare FDT!` and `No valid payload found`, then sat
  in USB proxy mode until the owner restored a `boot.bin` from recoveryOS.
  This is m1n1's own `dt_set_pmp` (`src/kboot.c`), which the PMP DTB's
  `pmp` alias switches on. It copies every property of the ADT's
  `/arm-io/pmp/iop-pmp-nub` into the `pmp` node as `apple,tunable-*` and
  fails the whole boot on the first `fdt_setprop` error. The likeliest
  error is running out of DT space: kboot leaves 96 KiB of headroom and the
  T6020 PMP nub is large. That is not confirmed, since reading the ADT
  needs root. A draft m1n1 change (`m1n1-pmp-tunable-nonfatal.patch` in
  the build directory; it builds) prints the property, the libfdt error
  and the free space, and leaves the PMP disabled instead, so a retry can
  only lose the PMP. The PMP's 0.5 W stays unmeasured on T602x.
* **Asahi kernel** (7.1.13-3-2-ARCH, the boot after the PMP hang, stock
  image): PD always was 535 mW lower (standard error 181 mW, 15 of 15) at
  2.8% busy, with PD residency 76% under menu. The effect is the same
  outside Aurora.
* **Lessons for the harness.** A hand-installed kernel's modules need
  the `.keep` drop-in before any other kernel boots. An unattended step
  must stop, not continue, when a boot is unhealthy or the session does
  not return. And a `boot.bin` test needs the stock copy on the ESP
  itself, where recoveryOS can reach it.

* **Run 3, step 0, calibration under a synthetic wake load** (Aurora
  kernel, stock image, `wakeload 10 650 15`: ten threads that sleep an
  exponential time with a 650 µs mean and then spin for 15 µs; 5–6% busy,
  about 1,700 idle entries per CPU per second, like the busy desktop of
  run 1). Menu picked PD for only 8% of idle time (WFI 86%), against about
  90% on a quiet boot. PD always was **713 mW lower** (standard error
  133 mW, lower in 15 of 15 rounds, median 594 mW), and SoC (Heatpipe)
  power was 600 mW lower (14 of 15). The owner used the machine during
  one round; the quiet rounds alone give 550–640 mW each. Wake latency
  p50 went from 7 to 20–24 µs, p99 at most 37 µs. So the load reproduces
  the busy-desktop saving, and the residency sweep (step 1) can be run
  under it.

* **Run 3, step 1, residency sweep under the same load** (test kernel).
  Paired against default, median of the 12 rounds without owner
  activity (all-15-round means in brackets):

  | Setting | PD % of idle | Total System | SoC (Heatpipe) | Timer wake p50 |
  |---|---|---|---|---|
  | default (10 ms) | 11 | 8.68 W | 3.32 W | 7.4 µs |
  | res=2000 | 19 | −53 mW (+79) | −40 mW | 7.6 µs |
  | res=500 | 57 | −330 mW (−307) | −271 mW | 21.3 µs |
  | res=200 | 80 | −526 mW (−291) | −478 mW | 20.3 µs |
  | res=100 | 88 | −591 mW (−362) | −554 mW | 24.4 µs |
  | PD always | 93 | −628 mW (−433) | −564 mW | 24.6 µs |

  The saving grows roughly linearly with the share of idle time spent in
  PD, about 7 mW per percentage point at this load. Wake latency jumps
  once PD is used at all and then stays the same (p99 at most 37 µs), so
  a longer residency buys nothing on latency. **A target residency of
  100 µs is the recommended default**: 94% of the PD always saving, the
  same latency, and WFI is still chosen for idles predicted shorter than
  100 µs. 2 ms, the earlier candidate, does almost nothing under load.

* **Run 3, step 2, why E1 stopped in m1n1** (`boot.bin.pmpdiag-test`: a
  diagnostic m1n1 that measures the PMP tunables, records the result in
  `/chosen/asahi,pmp-tunables-diag` and never enables the PMP, plus the
  J414s DTB with only the `pmp` alias added). Linux booted normally with
  the PMP node disabled. The record: 81 tunable properties, none with the
  ADT size flag, the largest 3,348 bytes, **15,850 bytes needed and only
  12,936 free**. m1n1 gives the DT 96 KiB of headroom, and the functions
  that run before `dt_set_pmp` (display, GPU, SEP and others) use all but
  about 13 KiB of it. The stock loop therefore failed with
  `-FDT_ERR_NOSPACE` most of the way through and failed the whole boot.
  Upstream m1n1 (AsahiLinux main, 2026-10-16) has the same headroom and
  the same bail. Fix: more headroom (160 KiB) and a copy that cannot fail
  the boot. The idle A/B on this boot (3% busy, owner active) gave PD
  always −449 mW (standard error 174 mW, 14 of 15).

* **Run 4, the PMP, loaded mid-boot.** To keep a PMP problem from
  looping the boot, the test kernel was rebuilt with `CONFIG_APPLE_PMP=m`
  and the module's autoload blacklisted. The runner measures, runs
  `modprobe pmp`, waits 60 s and measures again in the same boot. The m1n1
  build has 160 KiB of DT headroom and copies the tunables only when they
  fit, enabling the PMP node only when all of them were copied. Step 0
  (stock image, nothing loaded) measured the drift between the two
  measurements: at most 80 mW (Total System) and 40 mW (SoC).

  Step 1 (`boot.bin.pmpfix-test`): m1n1 copied all 81 tunables (62 KB of
  the DT buffer still free) and Linux booted normally. The driver bound
  (`RTKit: Initializing (protocol version 12)`, `PMP started`; it does
  not know one tunable, `fast-die-ctrl-ce-map`), with no kernel warnings
  afterwards. About 90 s after the PMP started, idle power stepped down
  and stayed down:

  | Quiet desktop, on battery | Before modprobe | After | Change |
  |---|---|---|---|
  | Total System Power | 6.28 W | 5.38 W | **−0.90 W** |
  | SoC (Heatpipe) | 1.99 W | 1.22 W | **−0.77 W** |

  The power domains were the same before and after (116 on), so this is
  the PMP's own fabric and memory power management, not domains being
  switched off. PD always still saves another 105 mW on top. Wake latency
  did not change. This is about 14% of idle system power, more than
  Asahi's 0.5 W on an M1 Pro.

  Step 2 repeated it on another boot, this time on AC with the battery
  held at its charge limit, so AC Input Power (measured at the wall side)
  equals Total System Power and serves as an independent check. Before
  and after the modprobe: AC Input 6.67 → 5.61 W (**−1.06 W**), SoC
  2.11 → 1.41 W (−0.70 W) with menu, and 1.98 → 1.14 W (−0.83 W) with PD
  always.

  Step 3 did it again under the busy-desktop wake load (`wakeload 10 650
  15`, 4-5% busy, on AC). AC Input with menu went from 7.52 to 6.36 W
  (**−1.15 W**) and with PD always from 6.81 to 5.69 W (−1.11 W); SoC
  power from 2.83 to 1.87 W and 2.26 to 1.28 W. The two savings add up:
  PD always plus the PMP took this load from 7.52 to 5.69 W, 24% less.
  Wake latency was unchanged in all three PMP boots (p50 within 0.5 µs,
  except the E→P IPI, 2-4 µs slower), the driver logged no
  warnings, and the desktop, Wi-Fi and this session kept working.

  Not covered yet: the PMP built in and enabled from boot (as it would be
  by default), the full E1 DTB with the display and media power domains
  moved onto PMP report entries, and runs longer than about 25 minutes.

### Overnight s2idle with the PMP (2026-10-17)

The boot of run 4's step 3 (test kernel, `boot.bin.pmpfix-test`, `modprobe
pmp` done) stayed up after the campaign. After 1.7 h awake, the owner
unplugged the charger, ran `sleep-drain-probe.py arm` and closed the lid
overnight; `report` the next morning
(`~/Work/deep-idle-build/s2idle-pmp-night1.txt`):

| | |
|---|---|
| Window | 9.58 h, of it 9.56 h suspended, one suspend |
| Battery | 48.19 → 34.21 Wh, 13.98 Wh used |
| Average drain | **1.458 W** |
| Whole-SoC wakes | 111,238 (3.2 per second) |
| First interrupt of a wake | AOP mailbox `2a6408000` 61.3%, function-call IPI 38.5% |
| Wakeup-source events | battery 6, AC 6, USB-C PD 2, SMC input 2; none woke the machine |

Suspend and resume worked with the PMP running: the machine woke on lid
open, the display, Wi-Fi and the session came back, and the PMP was still
bound. The 1.46 W includes the 1.5 min awake around the lid close, and
the window began on AC (status "Not charging" at arm), so if anything the
suspended drain is slightly higher.

The wakes come from the AOP, the always-on coprocessor. Its mailbox fires
about 6 times a second awake and 3.6 times a second in s2idle, and each
message runs `apple_rtkit_rx_work`, which then wakes another CPU with a
function-call IPI. The AOP serves the ambient-light sensor (the driver
arms it at a 200 ms report interval, `aop_als.rs`), the lid-angle sensor
and the microphones, and none of these drivers, nor `aop.rs`, has a
suspend hook, so the sensors keep reporting through the night. At about
130 µs per wake this is milliwatts, not the drain; stopping the reports
in suspend is a small, cheap fix.

The same 13 power domains stayed on as in the earlier counters: the three
DCPs (`disp0_*`, `dispext0_*`, `dispext1_*`), `apcie_gp`,
`apcie_gpshr_sys`, `afr` and `sio`. That makes E4 (external DCPs off) the
next lead for the drain.

Stock, for comparison: the owner's `mac-power-telemetry` timer
(`~/.local/bin/mac-power-telemetry`, every 3 minutes, battery energy
from sysfs) logs every suspend. Most of them were on AC and show nothing.
Two stock suspends on the Aurora kernel and stock `boot.bin` were on
battery:

| Suspend (journal) | Hours | Energy | Drain |
|---|---|---|---|
| 2026-10-10 14:17-16:01 | 1.74 | 36.64 → 33.98 Wh, less ~0.2 Wh awake before the lid closed | **1.41 W** |
| 2026-10-10 22:55 - 10-11 08:36 | 9.68 | 47.76 → 44.32 Wh, ended on AC ("Not charging") | ≥ 0.35 W (charger plugged in at an unknown time) |
| 2026-10-16 23:06 - 10-17 08:40, PMP | 9.56 | 48.19 → 34.21 Wh (probe) | **1.39-1.46 W** |

So the PMP does not change the s2idle drain, as far as one short stock
sample can say: about 1.4 W either way. The gauge updates slowly after a
resume (two readings a second apart differ by 0.08 Wh), so short windows
carry an error of a few hundred mW. The PMP's awake saving does not
carry over: whatever it trims while awake is already idle in s2idle, or the
PMP does not act because nothing tells it the system is suspended.

What 1.4 W is made of is not known. The next lid close stacks every
optional block off (`~/Work/deepidle-harness/s2idle-alloff.sh`: Wi-Fi and
Bluetooth blocked, the AOP sensor drivers unloaded, the SD reader removed)
to bound what driver work could reach; if that stays near 1.4 W, the
floor is the SoC itself (CPUs in retention, fabric and DRAM awake), which
only the SoC sleep protocol (S2R) can lower.

## What macOS 13.5 does to sleep the SoC (static analysis, 2026-10-17)

Source: the public macOS 13.5 (22G74) restore image for Mac14,9 (J414s),
the release whose coprocessor firmware this machine runs (OS firmware 13.5).
Only `kernelcache.release.mac14j`, `DeviceTree.j414sap` and the PMP and AOP
firmware were fetched, by HTTP range request. The kexts in this kernelcache
keep their symbol tables (241,499 symbols), so functions are named. Read
with Ghidra and objdump under Aurora Silicon's policy, which allows
decompiling public macOS releases. Apple's files stay local
(`~/Work/macos-re`, never committed); everything below is a description.
The kernel side of sleep is in XNU's open source (`xnu-8796.141.3`:
`IOCPU.cpp`, `IOPlatformActions.cpp`, `osfmk/arm64/cpu.c`).

**The order.** `IOCPUSleepKernel` runs, after every driver's
`setPowerState(0)`: the platform *sleep* actions, lowest priority first;
then it halts the secondary CPUs; then the boot CPU's `haltCPU` runs the
*quiesce* actions, lowest first, and `ml_arm_sleep`. Wake runs the *active*
and *wake* actions highest first. The priorities, from the kexts'
`IOPlatform*Action` properties, for the drivers that match T6020:

| Sleep actions | Quiesce actions (boot CPU, last) |
|---|---|
| 100 AVD, ProRes | 250 SoC hot sensor |
| 200 AppleSMCPMU, 300 AppleSMC (`MBSE` = `slpa`) | 1000 GPIO |
| 350 watchdog | 4000 PCIe (`apcie`, `apcie-ge`) |
| 400 Dialog SPMI PMU | 80000 watchdog, SmartIO (SIO) |
| 500 CLPC | 88000 SoC tuner, 89000 MCC, error handler |
| 590 SmartIO (SIO) | 89999 SEP |
| 600 PMGR (freezes perf-state changes) | 90000 PMGR `quiesceHW` |
| 610 PMP (RTKit IDLE) | 97000 AIC |
| 80000 DART | 98000 Dialog SPMI PMU |

**SMC.** `MBSE` is written `slpw` when the system leaves full capability on
its way to sleep (`AppleSMCPMU::handleSystemPowerStateChange`; `offw` and
`rest` for power off and restart, as Linux's macsmc-reboot already does).
`AppleSMC::setPowerState(0)` writes `WKTP` = 2 (1 byte) where enabled. The
sleep action waits for the SMC to go idle, writes `MBSE` = `slpa` (`hiba`
when hibernating) and sends nothing more. On wake it reads `MBSE` (a wake
result byte) and `MBSW` (8 bytes, a wake-source bitmap), then writes `MBSE` =
`waka`. Linux's driver comment lists `susp`; macOS 13.5 does not write it on
this path.

**PMP.** The PMP's sleep action is one call, `RTBuddy::setPowerState(0)`,
which sends the RTKit IOP power state `0x201` (IDLE, state kept) with the AP
power state `0x201`. The v2 driver's own power-state handler does nothing. In
Linux s2idle the PMP is never told the system sleeps, which fits the PMP
saving nothing in s2idle (above). Wake is not a message (corrected after
deepidle2, below). `RTBuddy::_setManagedStateGated` for sleep: request the
state, wait for the ack, `enableMailboxInterrupts(false)`, then the provider's
`stopCPU()`. For wake it calls the provider's `startCPUWithOptions(fw,
wasQuiesced)` and sends IOP `0x220` (INIT, `RTBMgmt_wakeQuiesced`) only when
the previous state was QUIESCED. After IDLE, the IOP reports its own state
once its CPU runs again, and RTBuddy then signals AP `0x20` (ON). The
provider is `AppleASCWrapV4`, which matches the PMP's `iop,ascwrap-v4`
(corrected after issue #3: `AppleA7IOPV4PMP`, read here first, matches only
`iop-pmp,t8015`, the A11, and is not loaded on T6020). `AppleASCWrapV4`
inherits `AppleA7IOPV4::_runCPU(bool)`: read ASC `CPU_CONTROL` (0x44), set or
clear bit 4 (RUN), write it back, the bit Linux's `pmp.rs` sets at probe.
`AppleA7IOP::stopCPU` first polls `_isIdle` every 1 ms; `AppleASCWrapV4::_isIdle`
reads ASC `CPU_STATUS` (0x48) and calls the CPU idle when `status & 3` is
non-zero. `startCPUWithOptions` sets RUN again. Device memory index 2 of the
PMP is 0x28e700000, which the live macOS names as the pre-loaded PMP firmware
(`region-base`, `__TEXT;__DATA`): it is no CSR, and nothing was written there.

**PMGR.** `quiesceHW` (T6020) quiesces the GPU's PMGR (`AGX_PMGR` + 0x100),
gates clocks in `PMGR_SOC_EAST` and the SoC clock generator, sets PLL-off
modes, and last calls `startS2RTimer`: one write of 1 to `MPMGR_AON` +
0x4000. `MPMGR_AON` is PMGR `reg` index 38, 0x29e5c0000 (0x14000 long),
absent from Linux's device tree and m1n1. `setSOCSleepState` is an empty stub
on T6020. The device tree's PMGR `events` name the system states the
reconfig engine knows: `SLP_DDR`, `AWAKE`, `SLP_S2R`, `DEEP_WAIT`,
`SYS_AWAKE`, `SYS_S2R_AOP`, `SYS_SLP_DDR`, `DDR_WK_TIME`, `S2R_WK_TIME`.

**Wake sources** (PMGR `ap-wake-sources`): `AOP.GPIO.IRQ4/6`,
`AOP.OutboxNotEmpty`, `AOP.CPUWakeupAP`, `NUB.WakeupAP`, `NUB.GPIO.IRQ2`,
`NUB.APWatchdog`, `NUB.APWakeupTime`, `NUB.SPMI0Sw0/1/3IRQ`,
`SMC.CPUWakeupAP`, `SMC.OutboxNotEmpty`, `MTP.DOCK.CHANNELS.AP0.IRQ` (keyboard
and trackpad), and `ATC0-3.CIOWakeup/USBWakeup`. In S2R the application
processor is off and PMGR restarts it on one of these.

**Device tree platform functions** that matter for sleep: the PMU's
`function-external_standby` is an SMC write of `MBSE`; its
`function-suspend_helper` is PMGR's `S2RT` (start the S2R timer); PMGR's
`function-mcc_ctrl` goes to the memory cache controller; both PCIe bridges
carry `manual-enable-s2r`. Some power switches are plain SMC GPIO keys,
usable from Linux awake or asleep: SD reader power `gP16`, DP-to-HDMI
converter power `gP06` and HDMI power `gP17`, Wi-Fi `reg_on` `gP0d`.

**What this changes for Linux.** Three pieces can be tried now, in s2idle,
without the S2R wake path: (1) tell the PMP (RTKit IDLE in the s2idle
platform prepare, wake in restore; built as `deepidle2`, below); (2) the SMC
`slpw`/`slpa`/`waka` handshake, whose effect in s2idle is unknown and risky
(the SMC may expect the SoC to go down); (3) SMC GPIO power-off of the unused
SD reader and HDMI converter. Real S2R additionally needs every quiesce
action above, the CPUs powered off (CPU_OFF), and m1n1 to hand the boot CPU's
reset-vector wake back to Linux (`_cpu_reset_c` re-enters `m1n1_main` today).

### deepidle2: the PMP told about s2idle (booted: idle works, wake does not)

`pmp-sleep.c` (built in) registers `platform_s2idle_ops`: `prepare`, which
runs after every device's `suspend_late` with interrupts still on, calls
`apple_rtkit_idle()` on the PMP; `restore`, after `resume_noirq`, calls
`apple_rtkit_wake()`. A failure is logged and never blocks the suspend.
`apple_pmp_sleep.s2idle_idle=0` turns it off. `rust/kernel/soc/apple/rtkit.rs`
gains `idle()`; `pmp.rs` registers the two callbacks at probe. Patch:
`~/Work/deepidle-11.35/pmp-s2idle-idle.patch` (Aurora-DeepIdle
`patches/`). Release `7.1.12-2-11.35-sep-ARCH-deepidle2`, its own GRUB entry
(never the default). The first boot runs a smoke test: three s2idle cycles
with `pm_test=platform`, which run the hooks without sleeping. Then one lid
close on battery compares against the 1.46 W PMP night.

**Result (2026-10-17, smoke test).** All three cycles suspended and resumed
(about 7.5 s each). Cycle 1: the PMP acked AP and IOP IDLE in 399 us. The wake
in `restore` then timed out after 1 s (`-ETIME`, -62) waiting for the IOP's
power-state ack to INIT. Cycles 2 and 3: the AP IDLE request itself timed out.
After IDLE the PMP answers nothing, and it stays that way until a reboot. No
RTKit crash was reported, nothing hung, and the boot.bin restore and the
one-boot arming worked. `ps_pmp` is `apple,always-on`, so genpd does not cut
the PMP's power in noirq. The cause is the wake method: Linux's
`apple_rtkit_wake()` (INIT, then wait for the boot handshake) is macOS's
wake-from-QUIESCED path. macOS wakes the PMP from IDLE by restarting its CPU
(`_runCPU(1)`, above) and sends no INIT. Nothing else in Linux uses
`apple_rtkit_idle()`, so this path was untested. The lid-close test is
dropped: with the PMP stuck in IDLE it would measure the PMP-off case. The
wake that fits macOS (corrected above): after the IDLE ack, mask the mailbox
interrupts, wait for `CPU_STATUS & 3`, clear `CPU_CONTROL` RUN; on resume, set
RUN, wait for the IOP's own power-state report, set AP ON. Not built
(`deepidle3`); its expected value is small, because the PMP night and a night
without the PMP drained the same 1.4 W. Until then the hook stays off: as
built it loses the PMP's awake saving after the first suspend.

## macOS 15.7.1 live on this machine (issue #3, 2026-10-17)

An agent on macOS 15.7.1 (24G231) collected these from the running system
with read-only tools (`ioreg`, a user-space SMC reader limited to read
commands, `powermetrics`, `pmset`, `log show`), then ran
`tools/macos-sleep-test.sh` across a lid close. Full tables in Aurora-DeepIdle
issue #3; what matters for Linux:

**Sleep: 0.24 W.** 5.90 h on battery, lid closed, Wi-Fi associated
(`tcpkeepalive` on, Wake-on-WLAN): 118 mAh, 1.413 Wh, 0.240 W over the whole
window. 28 sleeps totalling 5.82 h in S2R ("Deep Idle"), 27 dark wakes of a few
seconds each (the Dialog PMU's RTC, `NUB.SPMI0Sw3IRQ`, for SleepService),
8.8% of the battery a day. The sleep script's "asleep 0.02 h" line was a bug:
it took the `Wake Requests` line that follows each `Sleep` line in `pmset -g
log` as a wake. Fixed; the wall-time 0.240 W is the figure.

**Awake idle matches Linux.** On battery, display at 50% (`PDBR` 1.75 W),
120 s at 1 Hz: `PSTR` mean 5.57 W (median 5.19 W, min 4.60 W), `PHPC` 1.22 W
(median 0.76 W). Linux with the PMP: 5.38 W and 1.22 W. `powermetrics`: CPU +
GPU + ANE 0.58 W; the P1 cluster 29% down, P0 11% down, the E cluster never.
So macOS has no awake-idle advantage left to find here; the gap is sleep.

**The sleep sequence** (kernel log, first lid close): DCPs off, Wi-Fi to
associated sleep, `AppleSMCEmbedded` writes `WKTP` = 2, NVMe shutdown, then
`IOCPUSleepKernel`: sleep actions for the PMU RTC, CLPC, PMGR, `ApplePMPv2`
(62 ms, the longest), `AppleSMCPMU`, then `AppleSMCKeysEndpoint` writes `MBSE`
= `slpa` and reports "now quiesced". The quiesce actions then run on the boot
CPU: PCIe, SoC tuner, memory cache controller, SEP, PMGR ("Starting S2R
timer"), AIC, Dialog PMU. Wake runs them in reverse; `MBSW` read
`0001000000000000` after the lid wake, and `WKTP` = 0 is written. This
matches the 13.5 static order above.

**PMP.** The driver stack is `AppleASCWrapV4` -> `iop-pmp-nub` (`AppleA7IOPNub`,
`rtbuddy-v2`, `firmware-name` t6020pmp, `pre-loaded`, `no-shutdown`,
`user-power-managed`) -> `RTBuddy(PMP)` -> `PMPEndpoint1` (endpoint 33) ->
`ApplePMPv2`. Device memory: 0 = 0x28ec00000 (ASC, mailbox), 1 = 0x28e850000,
2 = 0x28e700000 (the firmware, 1 MiB), 3 = 0x28e3d0000 (PTD update registers,
`ptd-update-reg-index`), then the four die windows and three PMGR telemetry
windows (0x210e70000, 0x211e70000, 0x212e70000). The PMP probe script
(`harness/pmp-run/toggle.sh`, which would have stored 0 and 1 to
0x28e700000) is withdrawn: it would have overwritten the firmware's first
instruction.

**SMC GPIO power switches.** All `gP` keys are function keys (attribute 0xf0);
a plain SMC read returns 0 for every one of them, on or off, so their live
state is not readable from user space. Bindings on J414s: `gP06`
dp2hdmi_pwr_en, `gP08` dp2hdmi reset, `gP09` Wi-Fi pmu_ext_on, `gP0d` amfm
reg_on, `gP10` hdmi_cec_en, `gP11` bt_wake, `gP16` sd_pwr_en, `gP17`
hdmi_pwr_en, `gP19` trackpad PMU reset, `gP1a` keyboard STM reset; the rest
unbound. With nothing plugged in, macOS has the SD reader's port and device
in power state 0 of 3 (`SDXC Powered` = No), the Thunderbolt NHI and its
bridge at 0 of 3, the ANE at 0 of 1, `dcpext0` and `dcpext1` at
`DCPPowerState` 0 (their RTBuddy stays at 2 of 2), and no HDMI hot-plug. The
agent read the HDMI rail sensors `PH0R`, `PH1R`, `PHDR` and the SD reader's
`PSDR` as 0 W and took that as the rails being off. Linux reads the same four
keys as 0 W with `gP06`, `gP16` and `gP17` high (`harness/smc-keyread`,
below), so these sensors say nothing about the rails. Whether macOS lowers
the GPIOs is still unproven; the awake A/B (`harness/hdmi-power`) measures
what they cost.

**Linux SMC power keys** (`harness/smc-keyread`: a read-only module listing
every readable `flt` key starting with P, and `sample.py`). 79 keys on this
machine; 38 read 0 throughout a minute, among them `PSDR`, `PH0R`, `PH1R`,
`PHDR`, `PMVR`, the Thunderbolt and USB `PU1R`/`PU2R`, `PKBC`. The non-zero
ones besides `PSTR` and `PHPC` include `PDBR` (backlight), `PMVC`, `PSVR`,
`PPBR`, `Pb0f` and per-rail `PP*`/`PR*` keys, unlabelled; a quiet-desktop
comparison with macOS for the same keys is the next read.

**What this means for Linux.** Awake, the PMP closed the gap. Asleep, 1.16 W
separates s2idle from S2R. How much of it s2idle can reach is tonight's
all-off run (`harness/s2idle-alloff.sh`, now also with the HDMI rails off):
radios, AOP sensor drivers, SD reader and HDMI rails off, one lid close. The
remainder needs S2R (the quiesce actions, CPU power-off, DRAM self-refresh,
the PMGR S2R timer, and m1n1 handing the wake back to Linux).

## s2idle suspects one at a time (2026-10-18)

**The all-off night drained more, not less.** Radios blocked, the AOP
ambient-light and lid-angle drivers unloaded, the SD reader removed from PCI,
the HDMI rails off, one lid close: 9.78 h suspended, 2.108 W against the
1.4 W baseline. The AOP still caused 70% of 158,040 SoC wakes (3.6/s), so
those two drivers are not its traffic.

**Removing the SD reader is what cost.** It leaves the SD port's link up
with ASPM off. Awake, the SD link with `l1_aspm` = 0 draws +0.374 W (6
paired rounds, higher in 6 of 6, se 0.03 W), about half of the night's
excess. The rest is probably the Wi-Fi chip blocked rather than asleep
associated; that was not measured (below).

**It also broke Wi-Fi, three times.** A PCI rescan to bring the SD reader
back, whole-bus or only its port (00:01.0), killed the Wi-Fi firmware two
seconds later (`brcmf_msgbuf_query_dcmd` timeouts) until a reboot. A dead
chip then fails every suspend (`brcmf_pcie_pm_enter_D3` -5) and logind
retries: 4,655 failed suspends in one lid-closed boot, the machine awake at
4-5 W. The harness no longer removes, rescans or rfkills anything
(`harness/s2idle-alloff.sh` retired), and risky tests run under
`harness/net-guard.sh`, which reboots and reopens the session if the
network dies.

**HDMI rails: 0.130 W.** `hdmi-pwren` and `dp2hdmi-pwren` off, nothing
plugged in: -0.130 W of system power (12 rounds, lower in 12 of 12, se
0.011), with SoC power unchanged, so it is the converter. The DCP driver
raises both at probe and on T6020 never lowers them (the resume re-setup
that touches them is T6030-only). `patches/hdmi-rails-off-in-sleep.patch`
lowers them in system suspend, after the output is disconnected, and
raises them first thing on resume; compile-tested, not booted. Lowering
them while awake needs HPD to keep working, which needs a display to test.
A per-rail split was too noisy to use.

**SD link L1 substates: nothing.** Both PCIe links (Wi-Fi and SD) support
ASPM L1.1 and L1.2 at both ends and run with all substates off (the DT
default enables L0s and L1 only). On the SD link, L1.1 measured -0.096 W in
6 rounds and +0.008 W (se 0.016) in a 12-round confirm: no measurable
effect. The Wi-Fi link was not touched.

**Self-waking s2idle.** `harness/s2idle-wake` ends a suspend after N
seconds (a CLOCK_BOOTTIME hrtimer from PM_SUSPEND_PREPARE that calls
`pm_system_wakeup()`, checked on the SoC's own s2idle wakes), since
macsmc-rtc has no alarm. `harness/s2idle-ab.sh` runs one per setting on
battery and reads the SMC coulomb counter (`BAAC`, mA*s). It needs the
charger out: the battery driver offers `inhibit-charge` but no
force-discharge.

## Unblocking deep sleep: what to trace with macOS under m1n1 hv

1. **The CYC_OVRD veto.** m1n1 refuses a guest CYC_OVRD write with
   DISABLE_WFI_RET or the FIQ mask ("don't let macOS disable WFI ret (when
   going into systemwide sleep), since that breaks things", `src/hv/hv_exc.c`
   344-350). That is the first write of XNU's `arm64_prepare_for_sleep`
   above. Log it with the vCPU number instead of failing, then let the
   physical core power off. On wake, catch the RVBAR entry in m1n1 (the boot
   CPU's locked RVBAR points there), restore EL2 state and chicken bits, and
   restart the guest at its own reset vector (the RVBAR it saw).
2. **ACC_OVRD / ACC_CFG** writes on each CPU around sleep, to confirm the
   per-cluster deep-sleep fields on T6020 (XNU `machine_routines_asm.s`
   1049-1092).
3. **PMGR MMIO** (`proxyclient/hv/trace_pmgr.py`): PS register writes during
   the sleep transition, the CPU-start block (offset 0x28000 on M2 Pro/Max,
   asahi-docs `hw/cpu/smp.md`), and any writes that look like a reconfig
   sequence. Record what is programmed before sleep and what fires on wake.
4. **SMC** (`trace_smc.py`): the keys written in the last seconds before
   sleep and the first after wake (system state, sleep request, wake reason),
   and which SMC events are wake sources.
5. **PMP** (`trace_pmp.py`): messages and report-SRAM changes across sleep and
   wake. This goes with E1: the PMP is part of the sleep sequence and is not
   running under Linux today.
6. **AOP and the CPU secondaries' RVBAR writes** (cpu-impl-reg MMIO), so the
   Linux side knows where each core restarts.

What the owner could contribute without new tooling: run E1 and E2 and post
the numbers, measure macOS's own sleep drain on this machine for a baseline
(the macOS install is still on nvme0n1p2), and, once E1 works, the
`trace_pmp.py` output of a macOS boot under hv on a T6020, which nobody has
posted.

## Starting the external DCPs on demand (design, not built)

If E4 shows a saving worth having, the driver fix is to start an external
DCP only when a display is attached. Not built yet, for three reasons:

1. **The saving needs the domains off before the first start, and that is
   untested.** Deferring only the start leaves the domains on and saves
   just the firmware's idle loop. Powering a dispext domain off and on
   before the coprocessor first runs means its iBoot-preloaded state must
   survive: the ASC's boot configuration, and the DCP DART, which iBoot
   locks with its own page tables (`apple-dart.c` reads `locked` from the
   hardware at probe). The M3 path in this tree does not answer it either:
   `dcpext_check_power()` refuses to start unless the domain's floor is
   already active. Nobody has power-cycled a halted DCP and then booted it.
2. **The T6020 path assumes a running DCP in many places.** At HEAD the
   classic (13.5 firmware) path runs the CPU and wakes RTKit in
   `dcp_comp_bind()`, then opens the endpoints in `dcp_start()` from the DRM
   bind. The HDMI hot-plug interrupt is enabled only once the DCP is active
   (`dcp_wait_ready()` -> `dcp_enable_dp2hdmi_hpd()`), and the Type-C fabric
   checks `dcp->active` and the firmware's DPTX services when it picks and
   reconnects pipelines (`dcp-fabric.c` 1031, 1287, 2190, 2855). Every
   attach funnels into `dcp_dptx_connect()`, which is the right hook: start
   the processor there, return `-EAGAIN` the way the M3 path does
   (`external_native`), and replay the connect once it runs.
3. **Suspend has to change with it.** The firmware's own sleep sequence
   exists in the driver (`iomfb_sleep()`: abort swaps, last client close,
   `setPowerState(0)`) but is unused (`dcp_sleep()` is `__maybe_unused`),
   because resuming from it did not work; it would not power the domains
   off in any case. A never-started DCP need not be a
   wakeup path, so its domains could go off in s2idle, which is the same
   power-cycle question as (1). Once started it stays as today, since the
   firmware cannot be restarted.

Order: run E4 for the upper bound. If it is worth it, answer (1) with the
smallest experiment: let the domains power off, then power them on and
start one DCP, from a debug module or the m1n1 proxy. Only then write the
driver change, against the branch HEAD, test it with HDMI and USB-C
displays and a dock, and carry it in Aurora's tree (Aurora Silicon policy: nothing goes upstream).

## Overlap with hibernation (#50)

The missing CPU lifecycle is shared. Hibernation needs CPUs that can leave
the kernel (`cpu_die`). Deep sleep needs the same non-retention power-off,
plus a restart at RVBAR through code that reapplies chicken bits (m1n1 does
this on RVBAR entry: `_cpu_reset_c`, then `init_cpu`). The natural home for
both is PSCI CPU_OFF in Sven's resident m1n1, not a Linux-only
spin-table hack: m1n1 already owns the reset vector and the chicken-bit
tables.

## Unknowns

* What the PMP's `vlpm-threshold`, `vlpm-timer-limit` and
  `disable-vlpm-feature` (0) tunables control. The other PMP tunables are
  bandwidth thresholds for fabric (`afr-*`, `afnc*`), memory controller
  (`dcs-*`), GPU and ANE DVFS, so VLPM is plausibly a very-low-power mode
  of the memory or the SoC that the PMP enters when bandwidth stays low.
  No Linux code manages memory controller power states on Apple; if the
  PMP owns them, the PMP (E1) matters for s2idle as well as idle.
  The full property list of the ADT's PMP node points the same way:
  besides the bandwidth thresholds and DVFS filters per client (`agx-*`,
  `ane0-*`, `ioa*-*`, `afi-*`, `dcs-*`), it has memory controller
  command and quota counters (`mc_cmd_ptd_count`, `mc_quota_req_ptd_count`),
  a die temperature control loop (`fast-die-ctrl-loop`,
  `fast-die-ctrl-ts-avg-temp`, `sochot-sensors`), `dvfs-domain`,
  `user-power-managed` and `no-shutdown`. So the PMP is the SoC's fabric
  and memory DVFS controller; without it those stay where the boot loader
  left them, which is the likeliest reason for Asahi's 0.5 W.

* Answered later the same night: an idle P cluster does not keep its
  clock. With the machine quieter, in 300 windows of 200 ms the P clusters
  had no busy jiffies 29 times, and `scaling_cur_freq` (the hardware status
  register, `APPLE_DVFS_STATUS`) read 702 MHz, the lowest pstate, in 28 of
  them; the E cluster read 912 MHz in 6 of 7. That fits m1n1's "APSC
  Snooze" setup (cluster base + 0x200f8, bit 40, with the cluster reset to
  APSC pstate 1; `src/cpufreq.c` `cpufreq_init_cluster()`), though for
  T602x m1n1 does not copy the snooze pstate into the slot it fills on
  T8103/T8112. So the "PD always" saving is not leakage of whole idle
  clusters at a high clock: it is the idle cores of busy clusters, which
  sit at the voltage their busy siblings set, and that is why it grows with
  load.

* Whether iBoot arms the wake path (reconfig engine, boot CPU RVBAR) for a
  raw image as it does for a kernelcache.
* The SMC/PMGR/PMP/AOP sleep handshake: the order, the SMC keys and the PMP
  message are now known from macOS 13.5 (above). Still unknown: what the
  reconfig engine runs on `SLP_S2R`, what each quiesce action writes, and
  macOS's sleep drain on this machine.
* The source of the ~3.7 wakes per second in s2idle (cheap, but unknown).
* How much the display domains left on in s2idle draw, and whether a DCP
  with nothing connected (both dcpext) can be shut down and restarted.
* CPU PD's real break-even residency (the A/B above suggests well below
  10 ms) and exit latency; macOS chooses its idle state in closed code.
* Whether the T6020 PMP firmware acknowledges every report ID in the DT (see
  the E1 checks).
* Whether the boot CPU's RVBAR is actually locked in raw mode on this
  machine; m1n1 checks before writing (`src/smp.c` 445-448). It is readable
  through cpu-impl-reg, whose address is in the ADT (readable now, see the
  E1 pre-check).

## E1 test procedure and rollback

Pre-check, done 2026-10-14 without a reboot. m1n1 leaves the ADT in a
reserved-memory region labelled `adt` (`flash@10002f74000`, 0x78000 bytes).
The `phram` module that would expose it is not installed, but the region is
not `no-map`, so it was copied read-only from `/proc/kcore` and filtered with
`tools/aurora-sep/aurora-adt-extract.py`. Everything `dt_set_pmp`
(m1n1 `src/kboot.c` 2116-2156) needs is there: `/chosen` `board-id` and
`dram-vendor-id`, and `/arm-io/pmp/iop-pmp-nub` with `dram-capacity`, and
`firmware-name` `t6020pmp`, `pre-loaded` 1 (iBoot loaded the firmware). So
m1n1 will not refuse to boot Linux over the PMP. In this tree T602x uses
the upstream path: the PMP Rust driver (`drivers/soc/apple/pmp.rs`,
compatible `apple,t6000-pmp-v2`, built in) boots it, and the report driver's
own start sequence is only for T6030/T6031/T8122 (`starts_pmp`). Still
unknown: whether the T6020 firmware acknowledges every report ID.

Before (stock), on battery, screen on at a fixed brightness, desktop idle:
average SMC power over 5 minutes:

```
for i in $(seq 300); do cat /sys/class/hwmon/hwmon1/power1_input; sleep 1; done |
  awk '{s+=$1} END {printf "%.3f W\n", s/NR/1e6}'
```

Then run E2 once, on the stock DTB.

Install (touches `/boot`; the owner runs it):

```
sudo cp /boot/m1n1/boot.bin /boot/m1n1/boot.bin.before-pmp-test
sudo cp ~/Work/deep-idle-build/boot.bin.pmp-test /boot/m1n1/boot.bin
sync
```

Note: `update-m1n1` (run by kernel package upgrades) rebuilds `boot.bin`
from the packaged DTBs and silently undoes this. Do not upgrade the kernel
during the test.

After reboot, check:

```
journalctl -k -b | grep -iE 'pmp|pmp_report|dcp' | head -50
ls /sys/bus/platform/drivers/apple_pmp/         # expect 28e700000.pmp
ls /sys/firmware/devicetree/base/soc/pmp@28e700000/ | grep tunable
sudo cat /sys/kernel/debug/pm_genpd/pm_genpd_summary | grep -A3 pmp-disp0
```

Watch for `-ETIMEDOUT` from a PMP report entry. That means the PMP is up but
does not acknowledge that ID; the display or video decoder on that entry
would fail. Then repeat the power average and E2, and test the internal
display, an external display, video playback and lid sleep/wake.

Rollback:

* Booted, any problem: `sudo cp /boot/m1n1/boot.bin.before-pmp-test
  /boot/m1n1/boot.bin && sync`, then reboot.
* m1n1 does not boot Linux (unlikely after the pre-check, but a hang in
  the PMP driver would look the same): hold the power key, open Options, and in
  recoveryOS's Terminal mount the ESP (`diskutil list`, then `diskutil mount`
  the `EFI - OMARC` partition, nvme0n1p4 under Linux). Copy
  `m1n1/boot.bin.before-pmp-test` over `m1n1/boot.bin`; that copy must have
  been made on the ESP first (the install step above does it). This is the
  path the 2026-10-15 test needed: m1n1 stopped at `failed to transfer pmp
  tunable` and ran its USB proxy. Booting macOS works as well.

The fallback kernels share `boot.bin`, so they get the PMP DTB too: they are
not a fallback for this test. The fallback is the `boot.bin` copy.

## Sources

* Asahi progress report, Linux 7.0 (PMP, about 0.5 W):
  https://asahilinux.org/2026/04/progress-report-7-0/
* Asahi progress report, Linux 7.2 (retention, PSCI conduit, M4 locking):
  https://asahilinux.org/2026/08/progress-report-7-2/
* Sven Peter, "[PATCH RFC 0/6] PSCI-via-EFI ...", 2026-07-08:
  https://ratatoskr.run/b4-sent/2026/07/17228962/t ;
  http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1146599.html
* AsahiLinux/docs `0d1f891`: `docs/fw/macho-boot-protocol.md`,
  `docs/hw/cpu/smp.md`, `docs/platform/feature-support/m2.md` ("cpuidle
  situation")
* AsahiLinux/m1n1 `94395adc`: `src/chickens.c`, `src/smp.c`, `src/utils.c`,
  `src/kboot.c`, `src/hv/hv_exc.c`, `src/cpu_regs.h`,
  `proxyclient/tools/run_guest.py`, `proxyclient/hv/trace_*.py`; branch
  `psci-via-efi` (`src/psci.c`)
* apple-oss-distributions/xnu `xnu-12377.1.9`: `osfmk/arm64/cpu.c`,
  `osfmk/arm64/machine_routines_asm.s`, `osfmk/arm64/start.s`,
  `pexpert/pexpert/arm64/H14.h`
* This tree: [cpuidle-apple.c](../drivers/cpuidle/cpuidle-apple.c),
  [pmp-report.c](../drivers/pmdomain/apple/pmp-report.c),
  [pmp.rs](../drivers/soc/apple/pmp.rs),
  [t602x-die0.dtsi](../arch/arm64/boot/dts/apple/t602x-die0.dtsi),
  [HIBERNATION.md](../tools/aurora-sep/HIBERNATION.md); issues #50, #24, #59,
  #85
