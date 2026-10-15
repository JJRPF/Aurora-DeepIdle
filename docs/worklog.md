# Deep idle work log (GH-1-DeepIdle)

Copied from the machine's `~/Work/deep-idle-build/WORKLOG.md`. Paths under `~/Work` are
that machine's build and staging directories; `idle_ab*` files are in `data/`.

Running log of what was run on the live machine, what it changed, and results.
Nothing here installs, reboots, or writes hardware registers. Times are local.

## Before this log (summary)
- PD-always A/B (30 rounds x 15 s): -0.99 W total system (se 0.20), lower in 25/30.
- wakelat: PD-always adds ~10 us p50, ~15-20 us p99 wake latency.
- Commits up to 8c24afae476b; staged boot.bin.pmp-test, boot.bin.nodcpext-test (not installed).

## 2026-10-14 22:07:40
- Committed doc edits (E5 PCIe L1 substates, iomfb_sleep note, VLPM unknown): f22760c6e990
- idle_ab3 (12 rounds x 20 s, default vs pd-always, all SMC sensors) running in background, 20/24 windows done.

## idle_ab3 done (files idle_ab3.txt / .jsonl copied here)
- 12 rounds x 20 s, default vs pd-always, machine under heavy load (~14 W).
- Total System -2.55 W (se 0.93, lower 10/12); AC Input -2.66 W; Heatpipe (SoC) -2.03 W (se 0.95, 9/12).
- So the saving is in the SoC package, and it is larger under load (at ~6.7 W it was -1 W).
  Plausible: WFI keeps a core powered at the cluster's current voltage, so its leakage grows with DVFS state.
- Caveat to keep: power at equal time, not energy per unit of work. +10 us wakes should cost
  little throughput, but not measured with a fixed workload (no heavy load allowed on this machine).
- All cpuidle disable files read 0 after the run.
- idle-ab.py: added CPU-list settings (pd-always@4-9), per-CPU PD residency in the log; 7 tests pass.

## Finding: EAS is off on M2 Pro (no CPU energy model)
- /sys/kernel/debug/energy_model is empty; sched_energy_aware=1, schedutil on all policies.
- Cause: t602x-common.dtsi CPU OPP tables have no opp-microwatt (only the GPU has).
  T8103/T600x/T8112/T8140 have measured values. Upstream AsahiLinux/linux branch `asahi` lacks them too
  (checked raw t602x-common.dtsi: 9 opp-microwatt, all GPU).
- ADT voltages decoded (cells = 65536000/MHz, mV): E 912/612 .. 2424/946; P 702/600 .. 3504/1056.
  P cluster 1 (voltage-states13) within 6 mV of cluster 0.
- Derivation: T8112 (same cores) measured uW fitted to P=(a+b f)V^2 f at T6020 voltages:
  E rms 5.8%, P rms 6.3%, no OPP inefficient (cpufreq frequency choices unchanged).
- Tool tools/aurora-sep/t6020-cpu-em.py (--write), tests test_t6020_cpu_em.py (7, mutation-checked).
- Staged ~/Work/deep-idle-build/boot.bin.em-test (sha256 462a289d4ba0a2df...): current boot.bin with DTB #31
  replaced by rel-11.35 j414s + 23 opp-microwatt lines only. Chain: 113 DTBs, prefix/tail identical.
  NOT installed. Needs a reboot to test (owner approval).
- Scratch dtb_chain.py hung on a size-0 magic constant inside m1n1 code (tool bug, not image). Rewrote inline.
## idle_ab4: which cores carry the PD saving (files idle_ab4.*)
- 10 rounds x 20 s; machine at ~32 W (other sessions compiling), so se 1-2.4 W.
- Total System vs default: pd@E(0-3) +0.21 W; pd@P(4-9) -4.37 W (8/10 lower); pd@one P cluster(4-6) -2.98 W (9/10);
  pd-always -6.57 W (7/10). Heatpipe (SoC) follows: +0.10, -3.81, -2.12, -5.29 W.
- Reading: the saving is in the P clusters (a P core idling in WFI at high DVFS voltage leaks), E cores ~0.
  One P cluster gives about 2/3 of both P clusters' saving: not obviously "whole cluster must be down".
- Open: under heavy load, does PD-always change frequency or work done? Adding per-cluster freq and
  busy% to idle-ab rows before trusting heavy-load numbers. The 6.7 W (light load) -1 W result stands.
- All cpuidle disable files 0 after the run.
- Survey: no device has runtime PM forced on. GL9755 SD reader (02:00.0) runtime-active for all 58 h:
  sdhci-pci-gli gives GL9755 no runtime PM (GL9763E has it). Tens of mW at most; low priority.
- Full test discovery: running (some by-path runs fail on imports; test_m3_flow has 1 failure, M3 Limine, unrelated).
## Runtime-held power domains (read-only survey, display DPMS-off, nothing plugged)
- 116/200 genpd domains on. Held only by non-suspending devices:
  - ane_cpu + ane_sys: ANE DARTs 285810000/285820000 runtime-active 58 h; consumer 284000000.ane has NO driver.
    Cause: apple_dart_probe_device() device_link_add(... DL_FLAG_RPM_ACTIVE) (commit 727c99ada827, in mainline too),
    whose own TODO asks whether driverless consumers keep DARTs up for ever. Confirmed: yes.
    PMP DART (no consumer), AVD and ISP DARTs (drivers runtime-suspend) are suspended. DART0 is in always-on pmp domain.
  - atc0..3_usb: on since boot, 0 ms idle; no USB bus exists (no cable, no xHCI). dwc3-apple, atcphy, mux have no runtime PM.
  - GL9755 SD reader: no runtime PM in sdhci-pci-gli (GL9763E has it).
- Display: eDP 120 Hz fixed, VRR off; DPMS was off during the A/Bs.
- Doc section "Power domains held on while awake" added (uncommitted at time of writing).
## idle_ab5: PD-always with busy time and clocks (files idle_ab5.*)
- 12 rounds x 20 s, ~17 W load. Total System: pd-always -1.34 W (se 0.91, 9/12), AC Input -1.53 W (10/12),
  Heatpipe (SoC) -1.88 W (se 0.77, 10/12). pd@P(4-9): -0.49 W total (se 1.22), -0.82 W SoC: noisier than idle_ab4.
- Busy % default 28.4, pd-always 30.4, pd@P 33.3; mean MHz E/P0/P1 default 1337/2015/1977, pd-always 1362/2128/1992.
  => PD-always does not lower power by doing less work or running slower clocks. It is idle power.
- Across 4 runs pd-always is lower in 75-83% of pairs: -1.0 W at 6.7 W load, -1.3 to -2.5 W at 14-17 W, more at 30 W.
- All cpuidle disable files 0 after the run.
## Kernel build for the residency sweep (started)
- Source: git archive 1caa9fdc3745 (release 11.35, the running kernel) -> ~/Work/deepidle-11.35/src,
  plus cpuidle-pd-residency.patch (from d2ad90efc993, cpuidle-apple.c only; hunk 2 fuzz 1, reviewed).
- Config: /proc/config.gz; LOCALVERSION=-deepidle -> 7.1.12-2-11.35-sep-ARCH-deepidle. O=~/Work/deepidle-11.35/build.
- nice -n 19 make -j2 Image modules. Not installed.
- Full test discovery: 3 failures, all M3 (test_m3_flow limine uninstall, test_m3_pro_perf opt-out: both fail on integration/aurora too; test_m3_max ctrl-c: flaky, passes alone twice). Branch adds files only.
## Staged images (all verified with the fixed scratch dtb_chain.py: 113 DTBs, only #31 differs, = intended DTB)
- boot.bin.before-pmp-test 3630adc3b3be173c (copy of live /boot/m1n1/boot.bin, still unchanged)
- boot.bin.pmp-test        f09e39a996084b4b (E1: PMP)
- boot.bin.nodcpext-test   b69443cf3d9946f6 (E4: no external DCPs)
- boot.bin.em-test         462a289d4ba0a2df (E6: CPU energy model)
- boot.bin.pmp-em-test     df7b49ba67743af5 (E1+E6; PMP DTB + 23 opp-microwatt, nothing else)
- Unknown noted: does an idle P cluster keep its clock/voltage? Needs a quiet machine (no P cluster fully idle 200 ms in 30 s now).
## More read-only checks
- EM costs recomputed with em_compute_costs() integer math (E cap 561, P 1024): no inefficient OPP; P turbo
  costs 23252/23435/23517/23671 strictly rising. E at 912 MHz costs 2511 vs P at 702 MHz 6000 per unit.
  Tool now uses the kernel formula (commit 09b3d78ec11f), mutation-checked.
- m1n1 enables "APSC Snooze" (cluster+0x200f8 bit 40) on T602x but, unlike T8103/T8112, does not copy the APSC
  pstate entry into a snooze slot; same upstream. Open question, documented.
- DART RPM_ACTIVE fix: "hold only at bind" is unsafe (boot DCP framebuffer through locked DART before DRM_APPLE loads).
  Proposal (live-stream check at probe_device + BOUND_DRIVER hold for no-runtime-PM drivers) documented, not built.
- Radios (owner settings, not changed): Bluetooth powered with nothing connected; Wi-Fi power_save off, txpower 31 dBm.
- Apple NVMe (ANS2): no runtime PM in the driver (system sleep only).
- DRAFTS.md: upstream/Discord drafts for EM, DART hold, PD-always.
- 2026-10-14 22:55:51 deep-idle-check.py committed (44fc40eb0671): read-only post-reboot checker; live run on stock names image 3630adc3 stock, 0 opp-microwatt, EM none, PMP nothing. 6 tests, 4 mutations caught.
- Paused own build 40 s (SIGSTOP/CONT on its pgid) to sample idle-cluster clocks: still no P cluster idle for 200 ms
  (other sessions keep P at a median 3264 MHz); one <5%-busy window read 702 MHz. Inconclusive. Build resumed.
- Checked OPP core: EM registers when the lowest OPP has opp-microwatt (dev_pm_opp_of_register_em), same as M2 without opp-microvolt.
- Doc: E7 procedure (residency kernel install/rollback), stale latency note fixed, summary updated.
- Draft GRUB entry ~/Work/deepidle-11.35/43_deepidle (not installed).
## Residency test kernel built (E7), not installed
- ~/Work/deepidle-11.35/build: exit 0, release 7.1.12-2-11.35-sep-ARCH-deepidle; vmlinux has __param_pd_residency_us,
  pd_residency_set/get; Image 30329344 bytes (same size as the installed 11.35 Image).
- Modules: 1,870, same set as the running tree except macsmc-fan-cooling.ko (installed separately 2026-10-04,
  not loaded, not in any branch). Staged with INSTALL_MOD_PATH=~/Work/deepidle-11.35/staging (2.0 GB, like installed trees).
- staging/boot/vmlinuz-deepidle-test sha256 047c14dbd4732f28. Install/rollback steps in doc E7.
- Idle-cluster clock answered: fully idle P clusters read 702 MHz in 28/29 windows (E 912 in 6/7). PD saving = idle cores in busy clusters.
## idle_ab6: default vs PD always, 20 rounds x 20 s, quiet machine (~6.5 W) (files idle_ab6.*)
- Total System -0.92 W (se 0.12), lower 20/20. AC Input -0.91 W. Heatpipe -0.82 W (se 0.12), 18/20.
- Busy 6.7% vs 7.4%; clocks 984/871/829 vs 986/861/810 MHz. Work and clocks unchanged.
- All cpuidle disable files 0 after the run.
