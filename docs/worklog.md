# Deep idle work log (GH-1-DeepIdle)

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
## 2026-10-15: moved to its own repo
- https://github.com/JJRPF/Aurora-DeepIdle (public, standalone: JJRPF/linux is already this account's one fork in the
  linux-aurora network). Commit 423826d: docs, worklog, tools+tests, dts, data, patches/ (37 format-patch commits on
  integration/aurora cadfb30a; applied in a sparse worktree, tree identical to the branch).
- Branch commit 4b97e612e91f added AURORA_TREE so tools/tests run from the copy (skip without a tree).
- SSH push failed (agent signing refused); pushed once over HTTPS with gh's credential helper, no git config changed.
- grove add-repo: ~/dev/Aurora-DeepIdle/main, local config.json entry (personal, github tracker, default quick).

## 2026-10-15 18:1x: unattended test harness installed (owner allowed reboots)
- LUKS: owner added /crypto_keyfile.bin (own keyslot) + FILES via /etc/mkinitcpio.conf.d/deepidle-keyfile.conf; verified with
  cryptsetup --test-passphrase; in initramfs-linux-aurora.img and initramfs-deepidle-test.img.
- Root runner /usr/local/lib/deepidle/runner.sh via deepidle-runner.service (WantedBy graphical.target, only while
  /var/lib/deepidle/plan exists). One plan step per boot: restore stock boot.bin first, clear grub next_entry, check,
  settle 180 s, idle-ab 15 rounds x 20 s, wakelat per setting, arm next step, wait <=30 min for ack, reboot.
  A step that started but never finished is skipped (no loops). `touch ~/.local/state/deepidle/stop` aborts + restores stock.
- Plan: 0 stock | 1 em (boot.bin.em-test) | 2 kernel (deepidle-test-kernel, res sweep) | 3 pmp | 4 nodcpext | 5 final stock.
- Test kernel installed: /lib/modules/7.1.12-2-11.35-sep-ARCH-deepidle, /boot/vmlinuz-deepidle-test, initramfs-deepidle-test.img.
- GRUB: /etc/grub.d/43_deepidle (ids deepidle-test-kernel, deepidle-stock-panic; both panic=10); default entry unchanged
  (diffed), backup /boot/grub/grub.cfg.before-deepidle; grubenv writable (probe set/unset).
- Watchdog: /etc/systemd/system.conf.d/90-deepidle-watchdog.conf (RuntimeWatchdogSec=60s), active from next boot.
- Resume: ~/.config/hypr/autostart.lua -> ~/.local/bin/deepidle-resume (only while ~/.local/state/deepidle/resume exists)
  -> ghostty: claude --continue --permission-mode bypassPermissions "<prompt.txt>". Launch path probed OK.
- Harness sources: ~/Work/deepidle-harness/ (autostart.lua.before = original).

## 2026-10-15 18:13-18:28: campaign step 0 (stock), run by the root runner without a reboot
- Added deepidle-early-restore.service (sysinit, after /boot mounts): records the booted boot.bin sha in
  /run/deepidle-booted-sha and puts stock back at once, so a test DTB that freezes later in boot (watchdog reset)
  or needs a power cycle does not boot again. Stock copy at /var/lib/deepidle/boot.bin.stock (3630adc3).
  apple_pmp is built in (=y) and probes before the root fs: a freeze there still needs recoveryOS (doc E1
  rollback), so pmp moved to step 4, after nodcpext. Plan: 0 stock 1 em 2 kernel 3 nodcpext 4 pmp 5 final.
- Step 0, 15 rounds x 20 s, default vs pd-always, desktop idle with this session waiting:
  Total System 8.61 -> 7.53 W, -1.080 W (se 0.215), lower in 15/15; Heatpipe -0.698 W (se 0.160), 13/15.
  PD residency 4.7% -> 92.6%; busy 6.7 / 6.6%; clocks 980/796/826 vs 1018/857/883 MHz.
- wakelat p50 default -> pd-always: timer E cpu1 8.2 -> 26.5, timer P cpu9 7.8 -> 22.3, ipi E1->E2 8.1 -> 17.6,
  ipi E1->P6 12.0 -> 21.6 us. IPIs match the earlier run (+9.5); timers cost more this time (+14..18 vs +8..10).
- Step 1 (em) armed: boot.bin 462a289d, grub next_entry=deepidle-stock-panic.

## 2026-10-15 18:29-18:51: campaign step 1 (E6 energy model, boot.bin.em-test), first unattended reboot
- Reboot, early restore (booted 462a289d -> stock at 18:29:50), runner and the resumed session all worked.
- check: 23 CPU opp-microwatt, energy model domains cpu0 cpu4 cpu7, sched_energy_aware 1. No EM errors in dmesg.
- 15 rounds x 20 s, default (EAS on) vs no-eas vs pd-always. Fresh boot, much quieter than step 0:
  Total System default 6.58 W; no-eas +0.061 W (se 0.012, higher in 15/15); pd-always -0.075 W (se 0.007, 15/15).
  Heatpipe: no-eas -0.024 (se 0.069, noise), pd-always -0.085 (se 0.058).
  Busy E/P cluster: default 1.35/0.11%, no-eas 0.92/0.39%, pd-always 1.39/0.12%: EAS moves light work from P to E.
  PD residency default 88.9% (step 0: 4.7%): with this few wakes menu already picks CPU PD, so PD always gains little.
- So PD always's ~1 W (step 0, earlier runs) needs the busier desktop (6.7% busy, ~1,500 wakes/CPU/s); its value
  scales with the wake rate. The final stock step (5) is a fresh boot too and gives the like-for-like baseline.
- wakelat p50 default/no-eas/pd-always: timer E 7.0/7.0/20.0, timer P 7.2/7.0/19.6, ipi E-E 7.3/7.5/16.7, ipi E-P 11.5/12.3/18.7.
- Step 2 (kernel, residency sweep) armed: stock boot.bin, grub next_entry=deepidle-test-kernel.

## 2026-10-15 18:52-21:48: steps 2-5 broke the Aurora kernel's modules (incident)
- Owner: after the step 2 reboot the machine came up without Wi-Fi, Bluetooth, full GPU; owner booted the Asahi
  fallback (7.1.13-3-2-ARCH) at 21:48.
- Cause: kernel-modules-hook's linux-modules-cleanup.service (WantedBy basic.target) moves every
  /usr/lib/modules/<rel> that is neither the running kernel nor owned by pacman into /usr/lib/modules/.old, and
  its tmpfiles rule `R! /usr/lib/modules/.old/*` deletes that at the next boot. 7.1.12-2-11.35-sep-ARCH+ is
  hand-installed (no package). Booting the test kernel (step 2, 18:53:46) moved it; the step 3 boot deleted it.
  The test kernel's tree is gone too. Every later boot of the Aurora kernel had no modules: no nls -> /boot did not
  mount, no macsmc-hwmon -> idle-ab failed, no brcmfmac -> no network -> the resumed sessions could not run and
  never acked; the runner's 30 min timeout then rebooted through steps 3-5 blind.
- Nothing on the ESP changed after step 1: with /boot unmounted the runner could not copy test images
  (boot.bin is stock 3630adc3, next_entry empty). Steps 2-5 have no measurements (check.txt only). Step 1 is valid.
- The same cleanup would have removed the 11.35 tree the first time any other kernel booted (the Asahi fallback
  included): the owner's aurora-sep-fallback-modules.service protects only the Asahi tree.
- Recovery staged (no sudo now): ~/Work/aurora-linux is the exact build of the running 11.35 kernel (UTS #8
  Sun Oct 4 09:26:13, Image.gz byte-identical to /boot/vmlinuz-linux-aurora; apple-sep.ko rebuilt 12:43:58, just
  before the 12:44 install). `make modules_install INSTALL_MOD_PATH=~/Work/aurora-modules-restore` (no signing,
  no compression, no rebuild): 1871 modules, 2.0 GB.
- ~/Work/deepidle-harness/recover.sh (owner, sudo): copies it back, marks it .keep, installs
  linux-modules-cleanup.service.d/keep-pinned.conf (same loop plus `[[ -e $i/.keep ]]`; its exact ExecStart was
  run as a user unit on scratch dirs: running and .keep trees kept, a stray tree moved).
- Runner hardened (installed by rearm.sh): stops on an unhealthy boot (/boot, module tree or SMC power sensor
  missing) and stops instead of rebooting when no ack comes within 30 min.
- ~/Work/deepidle-harness/rearm.sh (optional, after recover.sh): reinstalls the test kernel's tree with .keep and
  re-arms: 0 baseline, 1 kernel, 2 nodcpext, 3 pmp, 4 final.

## 2026-10-15 22:1x: Asahi stock kernel 7.1.13-3-2-ARCH, read only (no sudo; recover.sh not run yet)
- Same apple_idle driver and menu governor, WFI 1/1 us, CPU PD 10/10000 us; no pd_residency_us; schedutil.
- 20 s: WFI 88.3%, CPU PD 7.2%. 60 s on battery, desktop with this session: Total System 6.93 W, Heatpipe 3.70 W,
  busy 3.4%, 995 idle entries/CPU/s. Same picture as Aurora: PD seldom chosen at ~1,000 wakes/s.
- 22:14 owner ran recover.sh + rearm.sh (pkexec): 11.35 tree back (1871 modules, .keep), deepidle tree back (.keep), drop-in active, plan re-armed (0 baseline 1 kernel 2 nodcpext 3 pmp 4 final). Rebooting into default.

## 2026-10-15 22:15-22:30: run 2 step 0 (baseline, stock, fresh boot, on battery)
- Healthy boot (Wi-Fi, modules; the Asahi tree moved aside as the owner's design expects).
- Total System 7.81 W default; pd-always -0.142 W (se 0.007, 15/15). Heatpipe +0.002 (noise). Busy 0.6%.
  PD residency 89.8% default -> 99.3%. Clocks 926/710/804 vs 938/719/825.
- wakelat p50 default -> pd-always: timer E 7.3 -> 24.0, timer P 7.3 -> 19.7, ipi E-E 7.3 -> 16.5, ipi E-P 10.6 -> 18.9.
- Agrees with run 1 step 1: on a fresh, quiet desktop menu already uses PD ~90%, so forcing it buys 0.1 W.

## 2026-10-15 22:31-23:04: run 2 step 1 (E7 residency sweep, test kernel 11.35-deepidle, stock boot.bin)
- Booted the test kernel with all three module trees intact (.keep drop-in worked); pd_residency_us 10000.
- 15 rounds x 20 s, Total System, paired vs default (6.83 W, PD 89.8%, busy 0.7%):
  res=2000 -0.086 (se 0.018, 13/15, PD 95.7%); res=500 -0.147 (se 0.014, 15/15, PD 98.9%);
  res=100 -0.158 (se 0.014, 15/15); pd-always -0.157 (se 0.016, 15/15). Heatpipe -0.07..-0.09 (se ~0.06).
- wakelat p50 (timer E/P, ipi E-E/E-P): default 7.4/7.3/7.4/10.8; res=2000 7.4/7.1/7.3/18.1;
  res=500 22.4/16.6/16.5/18.8; res=100 and pd-always ~24.5/19.4/16.6/18.9. The probe sleeps 1-2 ms, so
  intervals under the threshold stay in WFI and pay nothing; the cost appears once the threshold is under them.
- On a quiet desktop, 500 us captures ~93% of PD always. The busy-desktop case (run 1 step 0: ~1 W) is not
  swept yet; it needs a reproducible wake load (next idea: a synthetic ~1,500 wakes/CPU/s load under each setting).

## 2026-10-15 23:05-23:20: run 2 step 2 (E4 no external DCPs, boot.bin.nodcpext-test)
- Took effect: no dcpext aliases; dispext0/1 _cpu0/_fe/_sys all off-0. Internal DCP (389c00000) up as usual.
- Same-boot: default 6.71 W, pd-always -0.143 (se 0.017, 15/15); Heatpipe -0.127 (se 0.035).
- Across fresh boots (default setting, ~0.7% busy, on battery): Heatpipe 2.00 (stock), 2.01 (test kernel),
  2.08 (nodcpext); Total System 7.81, 6.83, 6.71. Total varies ~1 W between boots, Heatpipe ~0.1 W: E4 shows
  no SoC saving beyond that, so the external DCPs idle cheaply when nothing is attached. Not worth the
  on-demand DCP start (design in the doc) for idle power; it may still matter for s2idle (E2, not testable here).

## 2026-10-15 23:21 -> 2026-10-16 17:29: run 2 step 3 (E1 PMP, boot.bin.pmp-test): boot hang
- Rebooted into the PMP image at 23:21 (next_entry deepidle-stock-panic = Aurora 11.35 + panic=10). No journal
  entry at all for that boot: it hung before the root fs mounted (apple_pmp is built in, probes early; no
  watchdog that early; no panic, or panic=10 would have rebooted). Sat hung until the owner intervened.
- Owner, recoveryOS, 2026-10-16 13:25: renamed the ESP's boot.bin to boot.bin.pmp-broken (f09e39a9 = the PMP
  image) and copied boot.bin.old (062e1579, Oct 3) to boot.bin. Then 17:27 a boot of 7.1.9-aurora-sep+ (/boot
  failed, forced power-off), 17:29 the aurora-sep-previous entry (Asahi 7.1.13-3-2-ARCH) with 062e1579; the early
  unit replaced that with stock 3630adc3. boot.bin.old is untouched on the ESP.
- My miss: the doc's recoveryOS rollback names m1n1/boot.bin.before-pmp-test on the ESP, but the campaign kept the
  stock copy in /var/lib/deepidle and ~/Work only. Any future boot.bin test should first put the stock copy on the
  ESP under that name.
- Result E1: booting the PMP on J414s with this tree (pmp.rs, apple,t6000-pmp-v2, built in) hangs the boot. It
  needs a serial/m1n1 proxy console to see where; not something to retry unattended.
- Campaign stopped (stop file). The runner's step 3 is measuring on the Asahi kernel with stock boot.bin: a
  default vs pd-always A/B on the Asahi kernel, then it finishes without a reboot.

## 2026-10-16 17:3x: what the PMP boot actually did (owner's photo of the screen)
- It was m1n1 stage 2, not the kernel: "FDT: GPU: AFR leakage table: 161.000 / FDT: failed to transfer pmp
  tunableFailed to prepare FDT! / No valid payload found / ... Running proxy...". m1n1's own dt_set_pmp
  (src/kboot.c 2116-2157; runs because the PMP DTB has the pmp alias) copies every property of the ADT's
  /arm-io/pmp/iop-pmp-nub into the pmp node as apple,tunable-*, and bails on the first fdt_setprop error; then
  kboot refuses the payload and m1n1 sits in USB proxy mode. m1n1 was stock (~/Work/m1n1 clean at c6498e6e,
  m1n1.bin built 2026-09-29): an external assistant's guess that m1n1 was edited or update-m1n1 run is wrong.
- Likeliest error: -FDT_ERR_NOSPACE. kboot gives the DT 96 KiB of headroom (dt_bufsize += 6 * SZ_16K) and the
  T6020 PMP nub has many properties (thresholds and DVFS filters per client, MC counters, die temp loop). Not
  confirmed: reading the ADT again needs root. My pre-check confirmed the properties exist, not that they fit.
- Draft fix (not applied): ~/Work/deep-idle-build/m1n1-pmp-tunable-nonfatal.patch prints the property, the libfdt
  error and the free bytes, and leaves the pmp disabled instead of failing the boot. Builds clean (scratch copy).
  With it, a PMP test boot can only lose the PMP, and its message says whether to raise the headroom.
- Asahi kernel 7.1.13-3-2-ARCH, stock boot.bin, runner step "3-pmp" (in fact an Asahi A/B), 2.8% busy:
  Total System 7.96 W, pd-always -0.535 W (se 0.181, 15/15); Heatpipe -0.301 (se 0.126, 12/15). PD residency
  75.6% -> 97.3%. wakelat timer p50 7.5/7.3 -> 24.4/19.9. PD always helps on the Asahi kernel too.
- Campaign over: runner FINISHED (stop), plan and resume marker removed, boot.bin stock, next_entry empty.

## 2026-10-16 18:0x-18:2x: run 3 prepared (owner: "clear to continue and reboot")
- Busy-desktop residency sweep needs a reproducible load: ~/Work/deepidle-harness/wakeload.c (threads sleep an
  exponential time, then spin). 10 threads, mean 650 us, 15 us work: 5.8% busy, 1,722 idle entries/CPU/s
  (busy desktop of run 1 step 0: 6.7%, ~1,500). Idle machine: 1.3%, 275/CPU/s. Runner: optional 5th plan field.
- PMP diagnosis without risk to Linux: m1n1 rebuilt from ~/Work/m1n1 (unpatched rebuild is byte-identical to the
  installed m1n1.bin) with m1n1-pmp-diag.patch: dt_set_pmp measures the tunables (count, flagged sizes with the ADT
  high bit, max size, bytes needed, free DT space before/after), copies them only if they fit with 16K spare,
  records it all in /chosen asahi,pmp-tunables-diag (+ -failed), and never enables the PMP.
  DTB: rel-11.35 t6020-j414s plus only `aliases { pmp = &pmp; }` (dtc diff: that one line); the stock recipe
  (cpp + kernel dtc, no -@) reproduces t6020-j414s.dtb byte for byte. boot.bin.pmpdiag-test 225043d007b0cbc2 =
  diag m1n1 + stock chain with DTB #31 swapped (113 DTBs, U-Boot tail unchanged).
- Found while writing it: in an opened libfdt tree fdt_totalsize() is the buffer size, so the free space is
  totalsize - off_dt_strings - size_dt_strings; the earlier draft's "bytes free" would always print 0 (fixed below).
- rearm3.sh also copies the stock image to the ESP as m1n1/boot.bin.before-pmp-test (recoveryOS fallback).
- 2026-10-16 18:25:07 run 3 armed by owner (rearm3.sh via pkexec); ESP has m1n1/boot.bin.before-pmp-test (3630adc3). Rebooting into default.

## 2026-10-16 18:25-18:41: run 3 step 0 calib (Aurora 11.35, stock image, wakeload 10:650:15)
- Healthy boot (booted-sha 3630adc3, module tree, SMC hwmon, /boot mounted). Owner started using the machine
  during the measurement (round 7: 14-17% busy, both settings; round 8 slightly busy); the rest ran at 4-6%.
- Total System: default 7.94 W, pd-always 7.23 W, paired -0.713 W (sd 0.51, se 0.133, lower in 15/15);
  median -0.594. Rounds 9-14 (quiet owner): -0.55 to -0.64 each. Heatpipe (SoC) -0.600 (se 0.096, 14/15).
- Under the synthetic wake load menu picks PD only 8.2% of idle (WFI 85.7%), against ~90% on a quiet boot:
  that is why PD always saves ~0.6-0.7 W here and ~0.15 W idle. The load reproduces the busy-desktop result.
- Busy 5.2% -> 6.3% (WFI exit is cheaper, so the same work shows as more busy time in PD). Clocks barely move.
- wakelat p50 timer 1: 7.4 -> 24.3 us; ipi 1->6: 12.0 -> 19.5; p99 at most 37 us.
- Owner (18:3x): "I am going to start actively using the computer, so DO NOT REBOOT! Send me a notification via
  agent-notify". Notified at 18:41 (agent-notify send). No ack-0: if none by 19:10:44 the runner FINISHES (restores
  stock, unsets next_entry=deepidle-test-kernel, no reboot) and step 1/2 need a re-arm.
- 18:42 owner: "Good to reboot!" (one-time). Resume prompt step 4 now requires an agent-notify + owner go before each ack. ack-0 touched.

## 2026-10-16 18:42-19:21: run 3 step 1 loadsweep (test kernel 7.1.12-2-11.35-sep-ARCH-deepidle, stock image, wakeload 10:650:15)
- Healthy boot. Rounds 0, 1, 9 had owner activity (max busy 8-14%); the other 12 ran at 5.3-5.6%.
- Total System, paired vs default (all 15 rounds mean / quiet 12 rounds median):
  res=2000 +0.079 / -0.053 (PD 19%); res=500 -0.307 / -0.330 (PD 57%); res=200 -0.291 / -0.526 (PD 80%);
  res=100 -0.362 / -0.591 (PD 88%); pd-always -0.433 / -0.628 (PD 93%). Default: 8.68 W, PD 10.7%.
- Heatpipe (SoC), quiet median: -0.04, -0.27, -0.48, -0.55, -0.56. Cleaner than Total System (se 0.07-0.09).
- Saving ~ linear in PD residency: about 7 mW per percentage point of idle moved from WFI to PD at this load.
- wakelat timer-1 p50: default 7.4, res=2000 7.6, res=500 21.3, res=200 20.3, res=100 24.4, pd-always 24.6 us;
  p99 at most 37 us everywhere. ipi p50 rises to 16-20 us from res=2000 on. Latency cost is the same for any
  residency <= 500 us, so it does not argue for a longer one.
- Busy 4.5 -> 6.1% (PD exit costs show up as busy time); clocks flat.
- Recommendation: pd_residency 100 us. It gets 94% of PD always on quiet rounds (-0.59 vs -0.63 W), the same
  latency as PD always, and keeps WFI for predicted idles below 100 us. 2000 us (an earlier candidate) does nothing
  under load. Run 2's quiet sweep agrees (res=100 -158 mW vs PD always -157).
- 19:21 step 2 pmpdiag armed (ESP boot.bin = 225043d0, next_entry=deepidle-stock-panic). Owner notified 19:21;
  waiting for their go before ack-1. Deadline 19:51 (runner then restores stock, no reboot).
- 19:27 owner: "Good to reboot!" (one-time). ack-1 touched -> step 2 pmpdiag.
- 19:31 owner: "After this test, commit your findings to the GH repo, and start doing that whenever you have significant findings. you can now reboot as needed without asking."

## 2026-10-16 19:28-19:43: run 3 step 2 pmpdiag (diag m1n1 + pmp-alias DTB, Aurora kernel via deepidle-stock-panic)
- Booted 225043d0 (early restore put stock back), healthy; check.txt: pmp alias yes, apple_pmp bound nothing,
  pmp node status "disabled", no apple,tunable-* properties (as designed: the diag build never enables the PMP).
- /chosen asahi,pmp-tunables-diag: ret 1 (skipped), 81 properties, 0 with the ADT high-bit flag, largest 3,348
  bytes, 0 written, need 15,850 bytes, free 12,936 before and after. No -failed property (nothing attempted).
- So E1's m1n1 stop is confirmed as DT space: the 81 tunables need 15,850 bytes and only 12,936 of the 96 KiB
  headroom are left when dt_set_pmp runs (dt_set_display, _gpu, _sep etc. run first and use the rest). The stock
  loop failed with -FDT_ERR_NOSPACE about 80% of the way through. Upstream AsahiLinux/m1n1 main (fetched
  2026-10-16) and aurora/main have the same 6 * SZ_16K headroom and the same bail: still unfixed.
- Fix: raise the headroom (10 * SZ_16K) and keep the copy non-fatal. pmpfix build next.
- Quiet A/B on this boot (owner using the machine, 3.0% busy, default PD 73%): pd-always -0.449 W (se 0.174,
  14/15), Heatpipe -0.495 (se 0.164, 15/15). wakelat p50 timer 7.3 -> 23.7 us.
- Runner FINISHED (plan done after step 2); ESP boot.bin stock 3630adc3, next_entry unset.
- Owner 19:3x: reboots allowed as needed again; commit findings to the GitHub repo whenever significant.

## 2026-10-16 19:45-20:0x: run 4 prepared (the PMP, safely)
- GitHub: Aurora-DeepIdle quick-Campaign cb0d686 pushed, PR #1 (repo policy: no direct push).
- m1n1-pmp-fix-test.patch (scratch build m1n1fix, m1n1.bin 5d4c3553): the diag patch plus 10 * SZ_16K DT headroom
  (was 6), and `status = "okay"` only when every tunable was copied. boot.bin.pmpfix-test db84dd49f4095e96 =
  that m1n1 + the pmp-alias-only J414s DTB (chain after m1n1 identical to pmpdiag-test).
- The E1 DTB (t6020-j414s-pmp.dts) also moves the ISP, disp0, AVD and dispext0/1 power domains onto pmp-report
  entries; left out for now (display risk). pmp_report@28e3c0000 is a separate node, unaffected by the alias.
- PMP driver (drivers/soc/apple/pmp.rs) probe: patch_bootargs (BDID/DCAP/DVID), RtKit new, CPU_RUN, wake, start
  endpoint. Built in (=y), it probes before early-restore can put stock back, so any hang there loops the PMP
  image. So: test kernel rebuilt with CONFIG_APPLE_PMP=m (only config change; LOCALVERSION=-deepidle given on the
  command line as before: the first rebuild without it produced 7.1.12-2-11.35-sep-ARCH and was redone), pmp.ko,
  `blacklist pmp` in /etc/modprobe.d/deepidle-no-pmp.conf (also in the initramfs; pmp.ko itself is not in it).
- Runner: optional 6th plan field. "modprobe:<mod>": idle-ab (-before), modprobe (timeout 120), 60 s, idle-ab
  (-after), modprobe.txt/dmesg-modprobe.txt/genpd-after.txt. "control": the same without the modprobe. A load
  field of "-" means none. An interrupted modprobe step stops the campaign. Dry-run with stubs: OK.
- rearm4.sh (pkexec, owner typed the password 19:52): kernel overwritten in place (/boot 17M free), modules with
  .keep, depmod, blacklist, mkinitcpio, runner, run3 results archived to /var/lib/deepidle/run3, plan:
  0 pmpctl stock control; 1 pmpload pmpfix-test; 2 pmpload2 pmpfix-test; 3 pmpbusy pmpfix-test 10:650:15.
  All on deepidle-test-kernel; next_entry set. Rebooting.

## 2026-10-16 19:53-20:20: run 4 step 0 pmpctl (test kernel PMP=m, stock image, control: nothing loaded)
- Healthy boot, very quiet (0.6-0.7% busy, default PD 89.5%).
- before: Total 6.72 W default / 6.54 pd-always (-0.181, se 0.014, 15/15); Heatpipe 2.16 / 2.00.
- after (12 min later): Total 6.64 / 6.49 (-0.150, 15/15); Heatpipe 2.14 / 1.96.
- Drift after-before with nothing loaded: Total -0.08 (default) / -0.05 (pd-always) W; Heatpipe -0.02 / -0.04 W.
  So a PMP effect has to be well beyond ~0.05-0.08 W to count.

## 2026-10-16 20:21-20:49: run 4 step 1 pmpload (pmpfix-test image, test kernel PMP=m): THE PMP WORKS, ~0.9 W
- m1n1 with 160K headroom: /chosen asahi,pmp-tunables-diag ret 0, 81/81 written, need 15,850, free 78,472 ->
  62,622 (= 12,936 + 64 KiB, as expected). pmp status okay, 11,896 tunable value bytes. Boot normal.
- Before modprobe: pmgr "sync_state() pending due to 28e700000.pmp" (the enabled node with no driver yet).
- modprobe pmp 20:36:22: exit 0; "RTKit: Initializing (protocol version 12)", "unknown property
  apple,tunable-fast-die-ctrl-ce-map", "RTKit: syslog message: io.cpp:41: PMP started". Bound 28e700000.pmp.
  No kernel warnings or errors afterwards. Desktop, Wi-Fi and this session fine.
- Quiet (0.6-1.0% busy), on battery. before -> after, mean of all rounds:
  Total System 6.284 -> 5.381 W (-0.90 W); Heatpipe (SoC) 1.986 -> 1.217 W (-0.77 W).
  default: Total 6.36 -> 5.43, Heatpipe 1.99 -> 1.24; pd-always: 6.21 -> 5.33, 1.98 -> 1.20.
  Control (step 0) drift over the same interval: -0.08/-0.05 Total, -0.02/-0.04 Heatpipe.
- Per round (default): before 6.28-6.55 every round; after round 0 6.15, rounds 1-14 5.35-5.43. The drop lands
  ~80-100 s after "PMP started" and stays flat.
- genpd: identical before/after (116 domains on), only the pmp device added. So it is the PMP's own fabric/memory
  power management, not domains switched off by a sync_state.
- PD always still helps on top (-0.105 W, 15/15). wakelat unchanged (p50 timer 7.4/7.5, ipi 1->6 10.9/14.5 default).
- Busy 0.6 -> 0.9% (RTKit traffic?). AC Input 0.12 (on battery: Total System comes from the battery side).
- Unrelated, found here: aurora-fand.service fails every 5 s since at least 2026-10-03 (226/NAMESPACE: its
  ReadWritePaths=/run/aurora-fand does not exist; the unit needs RuntimeDirectory=aurora-fand). Not touched.
- 20:51 pushed Aurora-DeepIdle 7503c29 (PR #1). batlog.sh added (battery gauge every 10 s) for steps 2-3. ack-1.

## 2026-10-16 20:52-21:19: run 4 step 2 pmpload2 (repeat): replicated, on AC this time
- Owner plugged in at ~20:52; battery at its 80% limit, "Not charging": AC Input Power == Total System Power
  (wall-side SMC sensor), so the battery gauge log is useless here (killed) and AC Input is the independent check.
- Same m1n1 record (81/81, free 78,472 -> 62,622), modprobe 21:06:52 exit 0, same three PMP log lines, bound.
- before -> after, means: default Total 6.666 -> 5.606 (-1.06), AC Input 6.668 -> 5.605 (-1.06), Heatpipe
  2.111 -> 1.413 (-0.70); pd-always Total 6.524 -> 5.468 (-1.06), Heatpipe 1.976 -> 1.144 (-0.83). Busy 0.65-0.77%.
- Heatpipe per round is noisier after (1.18-2.21, mostly 1.2-1.35) than before (1.91-2.56): PMP DVFS moving.
- Two boots, battery and AC: -0.90 and -1.06 W Total, -0.77 and -0.70/-0.83 W SoC. Control drift <= 0.08 W.

## 2026-10-16 21:21-21:49: run 4 step 3 pmpbusy (PMP under wakeload 10:650:15, on AC): -1.15 W
- Same m1n1 record, modprobe 21:36:06 exit 0, bound, same three log lines.
- before -> after: default AC Input 7.516 -> 6.364 (-1.15), Heatpipe 2.833 -> 1.873 (-0.96); pd-always
  6.807 -> 5.695 (-1.11), Heatpipe 2.256 -> 1.283 (-0.97). Busy 3.75/4.59 -> 3.86/4.72%; PD 7%/94%; clocks flat.
- PD always + PMP: 7.52 -> 5.69 W (-1.82 W, -24%). Additive.
- wakelat p50 unchanged except ipi 1->6 default 12.3 -> 14.2 (step 1: 10.9 -> 14.5; pd-always 18.8-19.1 -> 21.2).
- FINISHED: plan done after step 3. ESP boot.bin stock 3630adc3, next_entry unset, plan removed.

## 2026-10-17 s2idle night 1 (PMP running)

- Boot of run 4 step 3 kept (test kernel, pmpfix-test image, pmp bound). Owner: probe arm 23:05, lid closed 23:05:57, opened 08:39:55; report in `s2idle-pmp-night1.txt`.
- 9.58 h window, 9.56 h suspended; 48.19 -> 34.21 Wh; 1.458 W (telemetry log: 48.188 -> 34.667 over 9.61 h incl. ~2.5 min awake, ~1.39 W suspended).
- Wakes 111,238 (3.2/s): first irq AOP mbox 2a6408000 61.3%, IPI function call 38.5%. apple_rtkit_rx_work 0.8/wake. AOP mbox awake 6/s. aop_als arms a 200 ms interval; aop_als/aop_las/aop.rs have no suspend hooks.
- Domains on through suspend: same 13 (disp0_*, dispext0_*, dispext1_*, apcie_gp, apcie_gpshr_sys, afr, sio).
- Resume fine: pmp still bound, Wi-Fi reconnected. Bluetooth "hci0: command 0x0c01 tx timeout" x2 on resume; also seen on 5 of 24 earlier boots with resumes (stock), so not the PMP.
- Correction: the 0.9 W s2idle figure was a J415 number from elsewhere, not this machine.
- Stock comparison from ~/.local/share/mac-power-telemetry/sleep.jsonl (3-min sysfs energy ticks): 2026-10-10 14:17-16:01 (Aurora kernel, stock image, on battery) 36.64 -> 33.98 Wh, ~1.41 W after the awake minute. 10-10 night 22:55-08:36 ended on AC: >= 0.35 W only. Others on AC.
- => PMP does not change s2idle drain (~1.4 W either way). macsmc-rtc has no wakealarm: suspend tests need lid closes.
- Next: harness/s2idle-alloff.sh (rfkill all, rmmod aop_als aop_las, remove SD reader 02:00.0) for one lid close.

## 2026-10-17 macOS 13.5 sleep path (static) and deepidle2 (PMP s2idle hook)
- Telemetry: ~/.local/bin/mac-power-telemetry now has `watch` (mac-power-telemetry-watch.service, logind delay
  lock): pre/post-suspend snapshots, coulomb counter (charge_counter is mA*s), suspended time, context, top IRQs.
  /etc/systemd/system-sleep hooks never run on systemd 261 (only /usr/lib/systemd/system-sleep).
- Policy: Aurora Silicon (not Asahi): decompiling public macOS OK; never contact upstream.
- macOS 13.5 22G74 J414s files in ~/Work/macos-re (local only). Kexts have symtabs. Tools: rzip.py, im4p.py,
  kcfixups.py (chained ptrs), fileset.py, kdis.py, vtable.py; Ghidra 12.1.4 (decompiler built for arm64),
  light project gproj3 + ghidra-run3.sh.
- Findings in docs: sleep/quiesce action order; SMC slpw/WKTP/slpa/waka + MBSW; PMP = RTKit IDLE 0x201 / INIT
  0x220 (= apple_rtkit_idle/wake, unused for PMP in Linux); PMGR quiesceHW ends with MPMGR_AON(0x29e5c0000)+0x4000=1.
- deepidle2 built (~/Work/deepidle-11.35, LOCALVERSION=-deepidle2, patch pmp-s2idle-idle.patch), staged in
  staging-deepidle2. Owner installs: sudo bash ~/Work/deepidle-harness/deepidle2/install.sh (arms one boot with
  boot.bin.pmpfix-test + next_entry; early unit restores stock; smoke unit runs 3 pm_test=platform cycles).

## 2026-10-17 11:22 deepidle2 smoke test: PMP idle works, wake does not
- Booted 7.1.12-2-11.35-sep-ARCH-deepidle2 with boot.bin db84dd49 (PMP); early unit restored stock 3630adc3,
  next_entry unset, armed flag gone. Smoke: 3 pm_test=platform cycles, all exit 0 (~7.5 s).
- Cycle 1: "PMP idle in 399 us" (AP+IOP IDLE acked), then "wake failed (-62)": 1 s timeout (dmesg 107.10 -> 108.19)
  waiting for the IOP ack to INIT 0x220. Cycles 2, 3: "idle failed (-62)" - AP IDLE unanswered. PMP silent after IDLE.
  No crashlog. ps_pmp is apple,always-on (genpd not the cause). Hook turned off at runtime (s2idle_idle=0).
- macOS (decomp/rtb.c, dis/a7iop.s): wake from IDLE = provider startCPUWithOptions -> AppleA7IOPV4PMP::_runCPU(1),
  a 32-bit store of 1 to _pmsCSRMappedRegs+0 (provider device memory index 2); INIT 0x220 only from QUIESCED
  (RTBMgmt_wakeQuiesced). Sleep = IDLE ack, enableMailboxInterrupts(0), stopCPU -> _runCPU(0).
- Static ADT pmp reg[2] = 0x28e700000 (1 MiB) = Linux "pmp" region; word 0 reads 0x14000095 = the PMP firmware's
  first __TEXT instruction (fw __TEXT vm 0x1000000). So the CSR is unresolved (live ADT order? fw reuses word 0?).
  Nothing written. Lid-close test with deepidle2 dropped.

## 2026-10-17 22:20 macOS 15.7.1 live findings (issue #3) and follow-ups
- Agent run on macOS (tools/macos-agent-prompt.md) opened JJRPF/Aurora-DeepIdle#3. Sleep 5.90 h lid closed on
  battery: 1.413 Wh, 0.240 W (98.7% S2R, 27 dark wakes). Awake idle PSTR 5.57 W / PHPC 1.22 W = Linux with PMP.
- macos-sleep-test.sh bug: `Wake Requests` lines ($4 == "Wake") closed every sleep interval (asleep 0.02 h,
  29 "full wakes" = 28 requests + 1). Fixed ($5 != "Requests"); mock-tested, old version reproduces it.
- PMP provider on T6020 is AppleASCWrapV4 (iop,ascwrap-v4); AppleA7IOPV4PMP matches only iop-pmp,t8015
  (13.5 prelink-info confirms). _runCPU = AppleA7IOPV4: CPU_CONTROL 0x44 bit 4. stopCPU polls
  AppleASCWrapV4::_isIdle = CPU_STATUS 0x48 & 3 every 1 ms. Index 2 = PMP firmware. harness/pmp-run withdrawn
  (never run).
- gP keys are function keys; user-space read returns 0. smc-keyread.ko (read only) on Linux: PSDR, PH0R, PH1R,
  PHDR read 0 W with gP06/gP16/gP17 high, so the agent's "rails off" inference is unsupported.
- s2idle-alloff.sh now also turns the HDMI rails off (smc-pwr-test.ko rebuilt for 7.1.12-2-11.35-sep-ARCH+).

## 2026-10-18 all-off night, Wi-Fi breakage, s2idle-wake
- All-off night (rfkill all, aop_als/aop_las unloaded, SD reader PCI-removed, HDMI rails off), 22:55 -> 08:42,
  9.78 h suspended: 47.48 -> 26.84 Wh, 2.108 W, higher than the 1.4 W baseline. AOP mbox still 69.8% of
  158,040 SoC wakes (3.6/s) with the two sensor drivers unloaded: they are not the AOP's traffic.
- Wi-Fi breakage: the restore's `echo 1 > /sys/bus/pci/rescan` (08:43:09) -> brcmf query timeouts 2 s later.
  Reproduced at 08:56 (dry run of s2idle-ab `sd`: rescan after resume; Wi-Fi fine before it) and at 13:12
  (remove 02:00.0 + rescan of 00:01.0 only, awake, no suspend). Removing 02:00.0 also leaves the 00:01.0 link
  up with ASPM disabled. With the chip dead every suspend fails (brcmf_pcie_pm_enter_D3 -5), so the owner's
  two lid closes (10:00-13:07, 13:18-14:33) never suspended: void. SD remove/rescan and rfkill are banned
  from the harness; s2idle-alloff.sh retired.
- s2idle-wake.ko: CLOCK_BOOTTIME hrtimer from PM_SUSPEND_PREPARE calls pm_system_wakeup(); fires on the
  SoC's own s2idle wakes. 45 s and 60 s tests ended on time. s2idle-ab.sh runs one self-waking suspend per
  setting on battery (coulomb counter BAAC, mA*s), toggling Omarchy stay-awake only around each suspend.

## 2026-10-18 14:47 awake A/B: SD link ASPM, HDMI rails (on the charger, 6 rounds x 30 s)
- s2idle-ab on battery stopped before its first suspend: the charger went in at 14:46 (runner refuses AC).
- Awake, Total System Power: SD reader link l1_aspm=0 (the state PCI remove left 00:01.0 in all night)
  +0.374 W (se 0.030, higher in 6 of 6). HDMI rails gP17+gP06 off -0.110 W (se 0.064, lower in 5 of 6).
  Default 8.67 W, busy 0.9%. So the all-off night's SD removal explains about half its +0.7 W.
- lspci: both PCIe links (Wi-Fi 00:00.0-01:00.0, SD 00:01.0-02:00.0) support ASPM L1.1 and L1.2 at both
  ends; all L1 substates are off, ClockPM off (root ports ClockPM-). Kernel ASPM policy [default].
  Results: awake-ab-20261018-1447.txt
- 15:00 SD link L1 substates, awake, guarded by net-guard.sh (reboot + resume if the network dies; it did not):
  6 rounds: L1.1 -0.096 W (se 0.046), L1.1+L1.2 -0.102 W. 12-round confirm of L1.1: +0.008 W (se 0.016,
  lower in 8 of 12): no measurable effect; the 6-round figure was noise. No quirk. No errors, Wi-Fi fine.
- 15:2x HDMI rails, 12 rounds: both off -0.130 W (se 0.011, 12 of 12), PHPC unchanged. Per-rail 12 rounds
  (hdmi -0.19, dp2hdmi -0.43, se 0.17/0.30, default busier): too noisy, not used.
- On T6020 dcp->external_native is false (T6030 only), so dcp_fixed_hdmi_reinit never runs: rails set high at
  probe and never touched. Patch drm: apple: dcp: lower the HDMI rails in system sleep (GH-1-DeepIdle
  5413b261bf65; Aurora-DeepIdle patches/hdmi-rails-off-in-sleep.patch). Compiles (worktree O= build dcp.o; and
  the running kernel's driver with the resume hunk adapted -> appledrm.ko in scratchpad). Not installed: a
  broken appledrm while the owner is away would leave no desktop, so no session.
- Boot -2 had 4,655 "PM: suspend exit" (failed suspends retried while the Wi-Fi chip was dead), boot -1 1,446.
- 16:1x SMC energy accumulator found (smc-keyread "all" + "watch"): zSPa (ui64) adds Total System Power in mW
  once per SMC sample, zSPc counts samples (~1.075 s each); zSPa/zSPc over 60 s = 8.413 W vs PSTR mean 8.409 W.
  (zSLa moves with zSPa; zSEw/zSEi ~2.37 W per sample, zSAa ~32 mW: unidentified.) The SMC keeps sampling in
  s2idle, so sleep can be measured on the charger: harness/smc-keyread/smc-acc.py snap/diff.
- On the charger, base state: 120 s s2idle 2.148 W (entry/exit included); 829 s s2idle (owner woke it before the
  900 s timer) 2.114 W. Battery-measured s2idle so far ~1.4 W, so PSTR on AC reads higher or this boot sleeps
  higher: needs one run on battery reading BAAC and zSPa together. Wi-Fi fine after both.
- 16:55 calibration (s2idle-calib.sh): charge limit 80 -> 65 makes the SMC force-discharge on the charger (CHLS
  0x100 | limit; status Discharging, -0.68 A awake). 900 s s2idle, base state: battery BAAC 1.981 W; zSPa 0.117 W
  in that mode, so zSPa is adapter-supplied power. On the charger with the battery held it covers the whole
  system: 2.114 W (829 s) vs 1.981 W from the battery, 7% apart. This boot's s2idle is ~2.0 W, not the 1.4 W of
  the unplugged nights (charger attached, or the first 15 min higher than a night's mean: not separated yet).
  Telemetry sleep.jsonl keeps the last 2,000 records; the failed-suspend storms pushed all older nights out.
- s2idle-ab.sh: measures by zSPa when the battery is held on the charger, by BAAC on battery.
- 17:12 s2idle A/B on the charger (zSPa), 15 min each: base 2.164, hdmi rails off 2.034 (-0.130 W, same as
  awake), aop drivers unloaded 2.164 (0), base 2.159. AOP wake rate 3.6-6/s across runs with no power change.
  => the HDMI patch's saving holds in s2idle; the AOP traffic is not worth chasing.
- 18:17 45 min base s2idle on the charger: woken early at 776 s, 2.178 W. Duration vs charger question still open.

## 2026-10-19 issue #5 (macOS S2R agent) checked; PMU RTC alarm mapped live; deepidle3
- Issue #5 (tools/macos-s2r-prompt.md on 15.7.1): 183.76 s S2R in a 3-min lid close; sleep/quiesce order
  matches 13.5. Mostly known already (PMP = RTKit AP IDLE 0x201 / ON 0x20, MBSE slpa/waka, WKTP=2,
  MPMGR_AON+0x4000). New: AIC quiesce (mask banks 0x6400+, die stride 0x4a00 = Linux AIC2 layout),
  restoreHW sets 0xc000 bit 31, PCIe manual-enable-s2r = driver drives L2 itself, CPU ACC 0xc5acce55.
- Corrected two claims by reading the PMU (apple-spmi-nvmem file, read only first):
  - the alarm is NOT a UNIX time: it is the PMU counter's whole seconds (CLKM >> 15). Value left by macOS
    3652420 -> 2026-10-18 22:30:58, during the agent's session. unix = counter s + (rtc_offset >> 15), exact.
  - 0x1411 is the rtc_offset scratchpad (Linux DT agrees), not the counter. The counter is 0x1406 (6 bytes,
    bytes 2-5 = seconds; low 2 bytes read 0a 00); reading 0x1406 latches it.
- Wrote (said first; macOS writes these ~27x/night): alarm +20 s at 0x140c, 0x14c2=0, 0x1401|=0x40 ->
  event 0x14c0 bit 0 at exactly the second; restored. No AIC line: SPMI controller masks all zero.
  SPMI pending (0x29e114060+) bit 2 = PMU irq 2 (ADT spmi-mpmu interrupts=[2], as t8140's DT). Unmasking it
  (0x29e114020 bit 2) raised AIC 724 only; notify (bit 256, mask 0x40 bit 0) also 724. Re-masked, acked.
  Tools: harness/mmio/{mmio-read, mmio-write (SPMI page only), pmu-rtc.py, dtb-chain.py}.
- Linux has spmi-apple IRQ support (47d246feceab) but T6020 DT gives no interrupts; no PMU RTC alarm
  driver anywhere (t8140 DT names apple,j700-pmu-rtc, no driver). Commit a868561d6298 (GH-1-DeepIdle):
  macsmc-rtc alarm via 4 NVMEM cells + SPMI irq 2 (one-shot, wakeup-source), spmi-apple
  IRQCHIP_SKIP_SET_WAKE (chained parent stays on in suspend: kernel/irq/pm.c:70), t602x DT.
- deepidle3 built (~/Work/deepidle-11.35, patch pmu-rtc-alarm.patch, LOCALVERSION=-deepidle3, no warnings).
  DTB: unpatched build == stock #31 byte for byte; masked diff = only the new props/nodes.
  boot.bin.rtcalarm-test 0fcb4c36d6d28447 (113 DTBs, only #31 differs). deepidle2 removed (no /boot room).
  Installed + armed one boot (harness/deepidle3/install.sh); smoke: awake alarm + 3x rtcwake freeze 30 s.

## 2026-10-19 deepidle3 smoke (07:23): alarm woke nothing in s2idle; cause found; deepidle3b
- Booted fine (ESP restored to stock, next_entry unset, Wi-Fi up). rtc0 macsmc-rtc with wakealarm, wakeup
  enabled, IRQ 124 "apple_spmi 2 Edge macsmc-rtc". Awake alarm fired (count 0 -> 1, wakealarm cleared).
- All three rtcwake -s 30 s2idle cycles slept until the owner touched the machine: 36504 s, 2344 s, 973 s;
  pm_wakeup_irq empty, alarm IRQ count stayed 1, PMU event bit 0 after.
- Cause: on fire the PMU clears ctrl 0x1401 bit 6 AND sets bit 1. While bit 1 is set, a later alarm clears
  bit 6 at its second but sets no event and no SPMI irq (checked with the handler unbound). The driver
  wrote bit 6 only (one-bit cell), so only the first alarm after boot worked. Morning pmu-rtc.py restored
  the whole byte (cleared bit 1) - why the manual tests worked. macOS writes the whole byte.
- With bit 1 cleared by hand: s2idle (alarm +30, s2idle-wake backup 90) woke at 30.14 s, pm_wakeup_irq 124.
  THE PMU ALARM WAKES s2idle.
- Fix 9cbf7cef4a7b: whole-byte rtc_alarm_ctrl cell, arm = (ctrl & ~0x42) | 0x40, disarm = ctrl & ~0x42.
  Rebuilt (Image unchanged), boot.bin.rtcalarm2-test 28fed82d8ec731d1 (only #31 differs, masked diff =
  intended nodes). Smoke now: 2 awake alarms back to back, 3 rtcwake cycles, backup waker 120 s.

## 2026-10-19 18:41 deepidle3b smoke: THE PMU ALARM WAKES s2idle, 3/3
- Booted deepidle3 + boot.bin 28fed82d; ESP back to stock 3630adc3, next_entry unset.
- Awake alarms 1 and 2 (back to back) both fired; ctrl back to 0x01 each time (bit 1 cleared).
- rtcwake -m freeze -s 30 x3: 30.61, 30.96, 30.97 s, pm_wakeup_irq 124 (macsmc-rtc) each; backup waker
  (s2idle-wake 120 s) never fired; IRQ 124 total 5. Wi-Fi up after (join_pref -52 as usual), ping ok.
- Unrelated, pre-existing (default kernel this morning too): aurora-fand.service restart loop,
  "/run/aurora-fand: No such file or directory" (NAMESPACE). Not touched; told the owner.
- Docs 913087106a99 (section "The PMU wake alarm"). Results: /var/lib/deepidle/results-deepidle3{,-run1}.

## 2026-10-21 No USB at all: CONFIG_USB4_APPLE_SOC missing; deepidle3 rebuilt with it
- Symptom: no USB bus (lsusb empty), every port. Not deep-idle work: same on the stock 11.35-sep-ARCH+ and
  11.32 kernels; last USB device seen 2026-09-26 (7.1.9-aurora-sep+, a DT without cio nodes).
- Cause: the T6020 DT links each cd321x connector (i2c 0-0038/3f/3b) to its USB4 host router
  (cio@701ac0000/b01ac0000/f01ac0000; 18 fw_devlink cycle lines now, 0 on 2026-09-26). The 11.35 config has
  `# CONFIG_USB4_APPLE_SOC is not set` (the tree's asahi.config fragment has =m), so cio never binds, the
  supplier link stays dormant, cd321x is deferred forever ("deferred probe pending: (reason unknown)"),
  dwc3-apple gets no role, xHCI never starts.
- Fix (config only): CONFIG_USB4_APPLE_SOC=m, one line of .config. Rebuilt in ~/Work/deepidle-11.35/build:
  only drivers/thunderbolt/apple.o plus relink; built-in code identical (Image 46375fe16628ab74 differs from
  8cb1e82915b08f93 only by the embedded config and timestamp). Module trees differ by thunderbolt_apple.ko.
- Installed in place under the same release (/boot has 24 MB free, no room for a second kernel):
  harness/deepidle3/usb4.sh; old Image + initramfs in /var/lib/deepidle/deepidle3-nousb4 (`usb4.sh rollback`),
  old modules in staging-deepidle3. Armed one boot as before (rtcalarm2 DTB, smoke test), earlier smoke
  results moved to results-deepidle3-before-usb4-20261021-1730.
- From here on deepidle3 = this build. Note for power numbers: every measurement before this had the USB4
  routers, cd321x and dwc3/xHCI unbound; idle and s2idle power may shift and need a fresh baseline.
- The owner's default kernel (linux-aurora 11.35 package) has the same gap; the real fix is that package's
  config. Not changed here.

## 2026-10-21 17:33 deepidle3 with USB4_APPLE_SOC: USB works, hotplug works
- Boot: thunderbolt-apple-acio bound all three cio, cd321x probed, xHCI on the two ports with devices
  (Cheapino2 keyboard on b02280000, Logi Bolt on 702280000). Nothing deferred.
- The third port (cd321x 0x3b, f02280000) had a Pixel plugged in but STATUS 0x00 (no plug) from boot, and
  the keyboard's USB link dropped at 17:36:35 (51 s after the last smoke s2idle) while its CC stayed
  attached (STATUS 0x...fd48). Both came back on a replug. harness/usb/plugwatch.sh (read only, 0.5 s
  sampling of the cd321x IRQ, STATUS 0x1a, partners, lsusb) logged the owner replugging all three:
  IRQ 0 -> 14, every attach and detach handled, the Pixel enumerated on a new xHCI (bus 5). The zero IRQ
  count before was just no plug events since boot. Open: a device present at boot or across s2idle can
  need a replug.
- Smoke rerun: awake alarms 2/2 fired; the three rtcwake cycles woke early (12.4, 20.1, 2.1 s, no
  pm_wakeup_irq). The keyboard and Bolt receiver have USB wakeup enabled: unattended alarm tests must
  turn wakeup off on USB devices first (power/wakeup), or the alarm is not what wakes them.

## 2026-10-22 Pi 5 controller connected
- The controller is a Raspberry Pi 5 (Debian 13, hostname core-node, on Wi-Fi). Its password did not
  match the owner's login file; the Mac's own key was already authorized on it, so the password was set
  from that file (sudo chpasswd over stdin) at the owner's word. Credentials stay out of this repo.
- Pi to Mac: a dedicated key (~/.ssh/id_ed25519_mac on the Pi), added to the Mac's authorized_keys with
  from= limited to the Pi's Tailscale and current Wi-Fi addresses (backup authorized_keys.bak-before-pi).
  Pi ~/.ssh/config: `mac` = the Mac's Tailscale address (the same on the Pi's Wi-Fi or Ethernet),
  `mac-lan` = omarchy-mac.local. Both log in. On Ethernet over the LAN, from= needs that address added.
- mac-ready.sh from the Pi: 6 ok, 2 failed. Both failures are one cause: sudo on the Mac now asks for a
  password (99-omarchy-nopasswd-jjr no longer applies; it still worked on 2026-10-21). The harness needs
  root, so unattended runs from the Pi wait on the owner's choice. Not restored here.
- Aura proxy on the Pi: python3-construct installed (pyserial was there), Aura cloned from the Mac's
  read-only clone into ~/deepidle/aura (362ae4f0), udev/80-aura.rules in /etc/udev/rules.d, user in dialout.
  proxyclient imports; it stops only at /dev/aura missing (no cable, Mac not in proxy mode).

## 2026-10-22 Harness-only passwordless sudo, no expiry (ready, needs the owner once)
- Why sudo stopped: `omarchy-sudo-passwordless` (Omarchy 4.0.3rc4) writes 99-omarchy-nopasswd-jjr with
  NOPASSWD: ALL and a systemd timer that deletes it after N minutes (default 15); it also deletes the file
  whenever its timer is not running (after a reboot). Run 2026-10-21 19:30, expired 19:45.
- Owner chose: harness only, no time limit. harness/sudo/90-deepidle-harness, a separate file the
  Omarchy tool never touches. Regex args (sudo 1.9.17): bash on harness *.sh, python3 -I on harness *.py,
  systemd-run --unit=di-* of a harness script, reboot (now or delayed unit), dmesg (no -H), journalctl
  --no-pager. Path components must start with [A-Za-z0-9_-], so .. and dotfiles never match.
- Limit, stated to the owner: the harness tree and what it installs (kernels, modules, boot images,
  insmod .ko) are jjr-writable, so this stops accidents and generic sudo abuse, not code aimed at the
  harness. Ad-hoc root reads (debugfs, i2ctransfer) now go in harness scripts.
- install.sh validates with visudo, installs 0440 atomically, rechecks all of sudoers, then self-tests
  by running harmless commands as jjr with sudo -n -k (sudo -l cannot tell NOPASSWD from password
  rules, and -k ignores the password just typed). teardown.sh removes the rule. mac-ready.sh now checks
  the rule by running sudo/selftest.sh.
- Owner, once:  sudo bash ~/Work/deepidle-harness/sudo/install.sh

## 2026-10-22 night: PMP wake from IDLE and the SMC sleep handshake, built as modules (untested)
- Both are module-only changes against deepidle3: the kernel image stays 46375fe1, so each is
  tested on the running kernel with insmod, no reboot, no /boot change. Neither has run: the
  harness sudo rule is not installed yet.
- PMP (pmp.ko a8ae3a2d, patches/deepidle3-pmp-wake-runcpu.patch). Found: deepidle3 blacklists
  pmp (/etc/modprobe.d/deepidle-no-pmp.conf), so its s2idle hook (s2idle_idle=Y) never ran. New
  idle hook: RTKit IDLE as before, then poll ASC CPU_STATUS (0x48) & 3 every 1 ms (up to 100)
  and clear RUN in CPU_CONTROL (0x44), as macOS stopCPU does. Wake hook: set RUN, 10 ms, then
  RtKit::boot(), which (its boot and IOP-ack completions still complete from IDLE) sends AP ON and
  waits for that ack only; on failure fall back to the INIT wake of deepidle2. No INIT after IDLE,
  as in macOS. Test: harness/pmp-wake/run.sh [CYCLES] insmods the staged module (blacklist kept
  for the next boot), rtkit.c dynamic debug on for every power-state transition, USB wakeup off,
  backup waker 120 s, 3 x 30 s PMU-alarm s2idle; pass = "CPU stopped" + "AP ON acked" each cycle
  and the next cycle IDLE acked (deepidle2 timed out there). Ends with s2idle_idle=0.
- SMC (macsmc-reboot.ko a0cf24df, patches/deepidle3-smc-s2idle-handshake.patch, also kernel
  worktree 3ff145247e7d). s2idle_steps bit mask, default 0, s2idle only: 1 WKTP = 2 in suspend /
  0 in resume; 2 MBSE = slpw in prepare; 4 MBSE = slpa in suspend_late, and in resume_early read
  MBSE + MBSW (logged) then MBSE = waka. The SMC atomic write cannot be used in noirq (its mode is
  one way, for power off), so slpa goes in suspend_late, before the PMP hook (macOS: PMP first).
  Test: harness/smc-sleep/run.sh STEPS [CYCLES] [owner-present] swaps the module at run time and
  puts the stock one back; bit 4 refuses to run without owner-present (the SMC may cut power with
  the SoC still up). Order: 1, then 3, then 7 with the owner there.
- Build note: building a single module target (make ... drivers/x/y.ko) rewrites Module.symvers with
  that module only, and the next single-target build then fails modpost; `make modules` fixes it
  and only relinks what changed.

## 2026-10-22 Screens stay off across reboots; agent stays on the Mac
- Owner: keep Claude on the Mac (no Claude on the Pi), and until told otherwise turn the agent
  headless mode (jjr.headless / omarchy-headless) back on after every reboot.
- harness/headless/headless-boot.sh as ~/.local/bin/deepidle-headless-boot, from Hyprland autostart,
  while ~/.local/state/deepidle/headless-on-boot exists. A reboot keeps headless's `active` flag
  but kills its keeper and inhibitor, so `omarchy-headless on` alone would only say "already on":
  the hook clears that stale state first. Tested on the live state (no change) and in a sandbox
  (stale state cleared, `on` called; nothing when the enable file is gone). teardown.sh removes it.
- Still lit after a reboot: m1n1, GRUB and the kernel console until Hyprland starts (about a minute),
  and the plugin plays its "enter" sound. Headless also selects power-saver: power numbers taken
  under it need saying so.
- AIC save/restore written and compile-tested (W=1 clean): kernel worktree 1ac4376377c6,
  patches/aic-syscore-save-restore.patch. syscore ops: save AIC2_CONFIG + every IRQ_CFG, mask all;
  on resume rewrite them and unmask from the IRQ core's own mask state. Inert today: s2idle never
  calls syscore ops. Kept out of the deepidle3 build source.
- PSCI-via-EFI reading: Linux calls m1n1's resident handler through a function pointer in an EFI
  config table (LINUX_EFI_ARM_PSCI_HANDLER_TABLE), same EL, no SMC/HVC. Neither kernel tree has the
  kernel side of Sven Peter's RFC, and the m1n1 side ("psci=direct") only works when m1n1 loads
  the kernel itself, with no U-Boot; this boot chain uses U-Boot + GRUB.

## 2026-10-22 late: the PMP test needs its own boot image (built), and a one-boot arm
- Found before any run: the PMP node is `status = "disabled"` in the DT deepidle3 boots with
  (rtcalarm2 boot.bin), so insmod pmp.ko alone would find no device. run.sh now refuses unless the
  node is okay. The PMP needs m1n1-pmpfix.bin (5d4c3553: copies the PMP tunables, sets okay) and the
  `pmp` alias.
- boot.bin.pmpwake-test 2c710fe4e8d91600 = m1n1-pmpfix.bin + the rtcalarm2 image's 113 DTBs with #31
  = the deepidle3 build's t6020-j414s.dtb plus only `aliases { pmp = &pmp; }` + the same U-Boot tail.
  Checked: the kernel's cpp+dtc recipe reproduces the build DTB byte for byte; decompiled diff of the
  new one = that one line; split back: m1n1 = pmpfix, #31 = new, the other 112 DTBs and the tail =
  rtcalarm2 (and = pmpfix-test). Recipe: harness/pmp-wake/t6020-j414s-rtc-pmp.dts,
  harness/tools/bootbin-split.py.
- harness/pmp-wake/arm.sh (root): checks ESP stock, installs two one-boot units (di-pmpwake-early runs
  deepidle3-early.sh: stock boot.bin back, next_entry unset; di-pmpwake-run: +120 s, boot-run.sh checks
  the booted image and runs run.sh 3), arms the flag, writes the test image, next_entry=deepidle3.
  `arm.sh remove` undoes it; teardown.sh removes the units. harness/reboot.sh then reboots with the
  session resume armed and the headless hook checked.
- Morning order once the sudo rule is in: (1) sudo bash sudo/install.sh (owner); (2) smc-sleep/run.sh 1,
  then 3, on the running kernel; (3) pmp-wake/arm.sh + reboot.sh, unattended; (4) smc-sleep 7 with the
  owner present.

## 2026-10-22 22:54-23:07: SMC sleep handshake in s2idle, steps 1, 3, 7 (deepidle3, macsmc-reboot.ko a0cf24df)
- Step 1 (WKTP = 2 on suspend, 0 on resume), owner-run, 3 cycles: 3/3. Every write returned 0, every
  wake on IRQ 124 (PMU alarm), battery read and Wi-Fi up after. smc-sleep-1-20261022-2254.txt.
- Step 3 (+ MBSE = slpw in prepare), 3 cycles: every write 0, wake IRQ 124 each time; scored 2/3 only
  because wlan0 was DORMANT at the cycle-3 check. Not the SMC: every s2idle resume on this kernel
  (step 1 too, and the Oct 21 smoke) logs CTRL-EVENT-DISCONNECTED reason=3 locally_generated=1 and
  reconnects; in cycle 3 the AP refused the first association (status 16), so it took 10 s, not 5.
  The NVMe log shows the normal s2idle path either way: ANS "NVMe shutdown start ... saveCtx" on
  suspend, RTKit re-init, "power up done PMU=Ocarina", "enabled 1p0v" on resume.
  smc-sleep-3-20261022-2300.txt.
- Step 7 (+ MBSE = slpa in suspend_late, MBSE/MBSW read and MBSE = waka in resume_early), owner
  present, 1 cycle, started 23:04:32: THE DISK WENT AWAY AFTER RESUME. The Mac resumed (Wi-Fi
  reconnecting at [106134], console visible), but from [106135] btrfs logged write and read errors on
  /dev/mapper/root (wr 1093, rd up to 1791 by [106160]), aborted the transaction and went read-only;
  journald could not rotate. Owner photo 23:06:52. The
  journal of that boot ends at 23:04:52 (the suspend itself): the resume, the MBSW wake source, the
  waka result and the NVMe errors were never written. run.log stops after "new macsmc-reboot loaded".
- The boot after (23:07:39, stock 7.1.12-2-11.35-sep-ARCH+) kept 1222 journal lines, all within its
  first second, up to the first journal flush; btrfs transid went 56525 -> 56526 only, and the next
  boot (Oct 23 07:39) had to replay the tree log and reported "PMU logged 1 boot error(s)" (first time
  on any boot kept). Reading: that boot lost its disk too, soon after start, and only the full power
  off cleared it, i.e. the SMC kept its slpa state across a warm reboot. Not proven (no log survived);
  the owner can say whether it booted to a desktop and how it was turned off.
- Damage: none found. Oct 23: btrfs device stats all 0; read-only scrub of all 107.39 GiB, no errors;
  ESP fsck -n: only the dirty bit and the usual boot-sector/backup byte; ESP boot.bin stock 3630adc3.
  tools/fs-check.sh (read-only) does these checks.
- Conclusion: slpa is not a notification. The SMC acts on it: after slpa it takes the storage down
  (NAND rails or the ANS link), as macOS expects with the SoC about to lose power. In s2idle the SoC
  stays up and the s2idle resume path (ANS re-init) cannot bring it back, and waka (if it was even
  sent) does not undo it. So slpa belongs only on a real S2R path, after every device is down, and its
  undo is the SMC's own wake sequence, not waka from a running kernel. Steps 1 and 3 did no harm (their power
  effect is not measured yet). No more slpa runs without the Pi watcher and the owner at the power
  button; recovery needs a full power off, not a reboot.
- New: remote/pi-watch.sh runs on the Pi and streams the Mac's `dmesg -w` (no root needed,
  dmesg_restrict 0) plus a ping log to ~/deepidle/watch/, reconnecting across suspend and reboots
  without duplicate lines (tested). Every risky run from now on starts it first.
- Pi access from the Mac: the ssh agent offered a "GitHub" key that waits for a confirmation and hung
  ssh; new aliases core-node-wifi / core-node-ts use the Mac's own key with IdentitiesOnly and no agent.

## 2026-10-23 07:53-08:10: PMP wake test (_runCPU wake), unattended boot: 0/3, and why
- Armed (pmp-wake/arm.sh), Pi watcher started (pi-watch.sh, tag pmpwake), rebooted via reboot.sh with
  the headless hook: screens stayed off (headless-boot.log 07:54:52), the session resumed. Boot:
  deepidle3 + boot.bin.pmpwake-test; early unit put stock boot.bin 3630adc3 back, next_entry unset.
  Disarmed after (arm.sh remove: units gone, ESP stock). The Pi caught both boots and every line.
- run.sh 3 (results-pmpwake-20261023-0756, pmp-wake-20261023-0756.txt; kernel timestamps from the Pi's
  copy, pi-watch-20261023-pmpwake.kmsg): cycle 1: AP and IOP IDLE acked (0x20 -> 0x201), "CPU stopped
  (0 ms to idle)" (CPU_STATUS & 3 already set), "PMP idle in 501 us"; on wake RUN set, 10 ms, then
  AP ON: no ack for 1 s (157.964 -> 158.984, ETIME from the AP-ack wait); INIT fallback: no IOP ack for
  1 s, "wake failed (-62)". Cycles 2, 3: "idle failed (-62)". Every wake on IRQ 124; the system itself
  was fine, the backup waker never fired. Result 0/3: the PMP never ran again after the stop.
- Read after (mmio/pmp-asc.sh, read only): CPU_CONTROL 0x10 (RUN set), CPU_STATUS 0x8 (& 3 = 0);
  A2I_CONTROL 0x00401501: inbox not empty, 4 messages queued (AP ON, INIT, the two IDLE requests) and
  the IOP inbox interrupt enabled (bit 0, macOS _getKICInboxEnabled); I2A_CONTROL 0x00021101: outbox
  enabled, empty. So the firmware is not reading its inbox at all: the CPU did not resume running it.
- macOS, read again (13.5 a7iop.s, RTBuddy disassembled now): RTBuddy states 0..3 request IOP 0x201,
  0x220, 0x202, 0x0 (table at 0xfffffe0007886c18); wake = startCPUWithOptions(fw, prev == 3) and INIT
  (wakeQuiesced) only from state 3. AppleA7IOP::stopCPU = _enableOutbox(0) (I2A_CONTROL bit 0),
  enableMailboxInterrupts(0), poll _isIdle, _runCPU(0), _unmapFirmware, _setMapperActive(0) (DART),
  _disablePower. startCPUWithOptions = _enablePowerLate, _setMapperActive(1), _mapFirmware (pre-loaded
  fw: _dartMapiBootFirmware), mailbox interrupt setup (no-ops on V4), _enableOutbox(1),
  _syncIOPTimebase only with `force-timebase-sync`, _runCPU(1). _runCPU writes only CPU_CONTROL bit 4
  for the PMP (the second CSR is used only with `auto-boot`, absent). _disablePower gates the node's
  power-gates unless `ignore-gating` (absent): ADT pmp power-gates [73, 74] = PMGR devices PMP (ps 0x2c8
  = Linux ps_pmp) and PMS_SRAM (0x2d0 = ps_pms_sram), both not critical. `no-shutdown` on the RTBuddy
  nub is read only by systemWillShutdown: not sleep.
- So on macOS the wake from IDLE is a power cycle of the PMP: its context is saved by the IDLE
  transition, power is removed, power comes back, DART is restored, RUN. Linux kept ps_pmp on (DT
  apple,always-on) and only toggled RUN; that leaves the IOP unable to run. Both Linux tries so far
  (deepidle2: IDLE + INIT; now: IDLE + stop + RUN) end the same way.
- PMGR now (mmio/pmp-ps.sh, read only): ps_pmp 0x1f0f03ff (target/actual 0xf, PS_MIN 0xf, auto
  enable, was-clk/pwr-gated set), ps_pms_sram 0x1f0003ff (PS_MIN 0). PS_MIN 0xf on ps_pmp means the
  domain cannot go below on until that field is lowered; pmp_dart lives in ps_pmp, so its registers
  would need the DART save/restore Linux has for system sleep.
- Next for the PMP (design, not run): after IDLE + stop, unmap and stop the DART (apple-dart suspend),
  gate ps_pmp (+ ps_pms_sram?) the way genpd would, ungate, restore the DART, RUN, wait for the IOP's
  own state report. Open questions first: does PMS_SRAM hold the pre-loaded firmware (1 MiB at
  0x28e700000) and keep it while gated, and what sets ps_pmp's PS_MIN (iBoot?). Not to be tried
  without the owner present: the PMP is the SoC's power manager.
- The Pi's Wi-Fi link stalls on bulk transfers (scp hung, plain cat cut at 327/1588 lines); gzip over
  the Tailscale alias got the full 4019 lines.

## 2026-10-23 afternoon to night: PMP restart tries, S2R plan, the hypervisor guest
- S2R plan written (docs/s2r-plan.md). Owner: no extra hardware (no PD board, no smart plug), so
  Phase 0 is dropped; recovery comes from the watchdog, Aura's early proxy wait, asahi-bless --next
  and a proxy reboot from the Pi. The PMP power-cycle test may run unattended.
- PMP, on a PMP already stopped by the morning's RUN-only test (mmio/pmp-cycle.c, address-limited
  writer; results in /var/lib/deepidle/pmp-cycle-20261023-*):
  - sram-cycle (15:14:01): RUN cleared, ps_pms_sram (0x2d0) gated (actual 0 in 1 us) and ungated
    (actual f in 3 us), RUN set: CPU_STATUS stayed 0x8 up to 2 s, A2I still 4 queued. Gating the
    SRAM domain alone does not restart the PMP.
  - reset-cycle (15:15:53): DEV_DISABLE + RESET (bit 31) on ps_pmp (0x2c8): the whole SoC died at
    once, no log line; the Mac came back on its own into the stock kernel at about 15:16:39. Never
    to be run again. ps_pmp is pinned on by iBoot (PS_MIN 0xf), so macOS probably never really
    power-cycles it either; what is left of macOS's restart is the DART off/on and the outbox
    steps around RUN (untried).
  - mmio/pmp-asc.sh mailbox fields fixed: FULL bit 16, EMPTY bit 17, count from bit 20 (as
    apple-mailbox.c); the script had used 17 and 18.
- macOS data for the hypervisor run: tools/macos-hv-prep.sh (curl | bash; prompts for the
  controller's login, nothing hardcoded) installed the hvsleep launch daemon (acts only with
  hvsleep=1) and sent sw_vers, diskutil, nvram, pmset, ioreg and the kernelcache to the Pi. Found:
  Macintosh HD was 15.7.1 (24G231), FileVault on, SIP off; the Linux stub carries 13.5 firmware.
- The Pi moved from the lossy 2.4 GHz network to the main 5 GHz one (NetworkManager profile,
  priority 10, the old one kept as fallback): 20 MB in 3.7 s, no stalls. Mac ssh alias updated,
  host key checked against the old entry.
- Option B (Aura as custom kernel of Macintosh HD) stopped at its own version check: Macintosh HD
  had auto-updated to 15.7.4 on the restart. Nothing was installed. Asahi's m1n1-hypervisor guide
  pins only 13.5 (M1/M2) and 14.8.3 (M1-M3) as guests; newer XNU needs SPTM, which Aura does not
  load (m1n1 PR #698, unmerged). Owner chose option A: a separate macOS 14.8.3 volume.
- Built for option A, nothing run on the Mac yet:
  - tools/macos-hv-testvol.sh: in the everyday macOS, checks Apple's catalog for 14.8.3, downloads
    it, adds an empty APFS volume macOSTest (container has 91 GB free; typed yes), opens the
    installer; `setup` mode in the new system turns off automatic updates and runs macos-hv-prep.sh.
  - hv-testvol-recovery.sh (harness hv/make-recovery.sh, served by the Pi on the LAN only, embeds
    aura.bin c7509ccf): only macOSTest at 14.8.3, refuses the Macintosh HD volume group, checks
    bputil reports a Paired recoveryOS, then bputil -nkcas, csrutil disable, kmutil configure-boot.
  - tools/im4p-extract.py: IMG4/IM4P to Mach-O with the lzfse tool; on the 15.7.1 kernelcache:
    krnl, 30.2 MB LZFSE, 114.9 MB fileset Mach-O, xnu-11417.140.69.708.3 RELEASE_ARM64_T6020.
  - harness hv/bless.sh (asahi-bless through the harness sudo rule): candidates Macintosh HD and
    omarchy (default). Each run boots macOSTest once with --next.
  - Pi deepidle/hv-run.sh: waits for /dev/m1n1, run_guest.py with trace_pmp and trace_smc, boot
    args debug=0x14e serial=3 apcie=0xfffffffe -enable-kprintf-spam wdt=-1 clpc=0 hvsleep=1, stdin
    /dev/null, 1 h limit, then tools/reboot.py so the Mac returns to Linux.
- Linux on the Mac sees no USB buses on the running kernel (dwc3/xhci load, /sys/bus/usb/devices
  empty); the hypervisor runs use the Mac's USB only from Aura, so this does not block them.

## 2026-10-23 23:53 to 10-24 08:13: overnight s2idle on the default kernel (7.1.12-2-11.35-sep)
- harness overnight/run.sh: drain probe armed as root, allow-idle, systemctl suspend, woken by the
  owner (lid) at 08:12:57; stay-awake back on after. Pi watcher (tag overnight): down 23:53:06, up
  08:13:11, nothing logged in between. Resume clean: the usual brcmf p2p/join_pref -52 lines and the
  known aurora-fand restart loop, nothing else. Results: overnight/results-20261023-235100.
- 8.33 h suspended, one suspend, 0.7 min awake. Battery 52.01 -> 47.24 Wh (90% -> 80%), but this
  is NOT a drain figure: the charger was connected and the battery was above the 80% end threshold,
  so the SMC ran the Mac from the battery only until it reached 80%, then held it there ("Not
  charging", AC input 5.99 W after). 4.77 Wh / 8.33 h = 0.57 W is only a lower bound; at the
  earlier 1.4 W it would have reached 80% after about 3.4 h. A real overnight figure needs the
  charger unplugged (or the battery at or below the threshold with charging inhibited).
- Wakes as before: 100,939 whole-SoC wakes (3.4/s); first interrupt AOP mailbox 2a6408000 72.4%,
  function-call IPI 27.5% (the 200 ms aop_als interval, worklog 2026-10-1x: 3.2/s, 61%/38%).
  Domains left on that may power off: afr, apcie_gp, apcie_gpshr_sys, disp0/dispext0/dispext1
  cpu0/fe/sys, sio.

## 2026-10-24 morning: S2R Phase 1 built (PSCI CPU_ON/CPU_OFF through EFI), not booted
- RFC fetched from lore (20260708-efi-psci-v1-0-9efb3abf0e4c@kernel.org): 6 patches apply clean
  on GH-1-DeepIdle 1ac4376 (local branch psci-efi-test). Review state: Ard took 3 and 4; Mark
  Rutland objects to calling it PSCI; the interface may change.
- Kernel: + t6020-j414s-psci.dts (opt-in, out of the Makefile). Built out of tree with the
  deepidle3 config (USB4=m, LOCALVERSION -psci-efi); the tree's built-in DRM_ASAHI needs
  APPLE_PMP=y to link (apple_pmp_set_device_power), a tree/config mismatch unrelated to the RFC.
  DTB checked: 12 x enable-method psci, no spin-table, psci { method = "efi" }.
- Aura (branch psci-efi): psci.c + smp_psci_* (CPU_ON dispatch/restart, CPU_OFF = PMGR stop +
  L1 set/way clean + cpu_sleep(true), AFFINITY_INFO from the CPU's own OFF mark, never a power
  status read), kboot dt_set_psci() -> /chosen aura,psci-*. Call graph from the handler checked:
  no printf, no FP.
- U-Boot asahi-v2026.07-2 (the installed uboot-asahi 2026.07.asahi2) + efi_platform_register()
  hook: runtime code + MMIO (ISA nGnRnE bits) + the config table. Built.
- arm64 stub skips SetVirtualAddressMap with 48-bit VAs, so the runtime map is already 1:1 (no
  efi=novamap needed on this config).
- Design, risks and the first boot test: docs/psci-efi.md. The boot test needs the owner's go.

## 2026-10-24: GH-8 part A from Linux (macOS guest)
- Step 1: Apple's catalog (swscan, macOS 14 and 15 catalogs) no longer lists 14.8.3 (nor 14.8.4 to 14.8.5): Sonoma is
  14.8.7 (23J520), 14.8.8 (23J620), 14.8.9 (23J631). The 14.8.3 pkg is gone from the feed. ipsw.me ends at 14.6.1,
  mesu has only the latest (27.0.1) IPSW, AppleDB knows 14.8.x only as InstallAssistant, OTA and KDK.
  Owner chose 14.8.9 as the guest. Changed variable: it was never run under the hypervisor.
- Step 2: tools/macos-hv-testvol.sh now pins the catalog pkg (URL, size 13654790295, SHA-1 10632733...c0), tries
  softwareupdate first, else curl -C - plus size and SHA-1 check, then installer -pkg. Version 14.8.9 also in
  harness/hv/make-recovery.sh and hv-run.sh. Not run: it needs macOS. The SHA-1 is the catalog's value, not yet checked
  against a downloaded copy.
- Step 3: not done. No 14.8.x IPSW URL is reachable, so no remote zip read; the pkg (xar, SharedSupport.dmg inside, not checked)
  would need a dmg parser and a large sequential read, not attempted. AppleDB lists a 14.8.9 KDK; not fetched (a KDK holds plain kernels, not the installed kernelcache).
  The `setup` step in the new system sends the installed kernelcache, as planned.
- Step 4: the Pi has Aura (deepidle/aura, python deps ok), hv/aura-hvsleep.macho and the recovery server running.
  The served hv-testvol-recovery.sh said 14.8.3 and would have refused 14.8.9: patched to 14.8.9 in place (text only,
  embedded Aura unchanged, sh -n ok), old copy kept on the Pi. /dev/m1n1 absent, as expected with the Mac in Linux.
- Step 5: docs/hv-guest-checklist.md. Part B not started (needs the owner's go for every boot step).

## 2026-10-25: macOSTest set up; guest kernelcache ready
- Owner ran the recovery script (after three fixes: no base64 in recoveryOS, bputil/csrutil/kmutil must read
  /dev/tty not the curl|sh pipe, tool report instead of a hard stop). bputil -nkcas: Permissive, 3rd-party kexts on,
  SSV/CTRR/boot-args filtering off; csrutil disable and kmutil configure-boot (Aura c7509ccf) ran in the second pass.
  recoveryOS lacks shasum and openssl (md5, cksum exist).
- The `setup` upload holds macOSTest's kernelcache: 14.8.9 23J631, xnu-10063.141.1.713.39~1/RELEASE_ARM64_T6020, IMG4/LZFSE
  28 MB -> fileset Mach-O 105414656 bytes (sha256 c1b073f8...). On the Pi as hv/kernelcache-14.8.9-23J631.macho; Aura's
  MachO loader parses it (entry 0xfffffe0008594548). SIP was on and FileVault off at that time.
- Pi watcher started (tag hvguest). Next: bless macOSTest once, run hv-run.sh (needs the owner's USB cable and root for asahi-bless).

## 2026-10-25 11:00-11:30: first two guest runs under the hypervisor (macOSTest 14.8.9)
- Run 1 (Mach-O Aura chained): the Pi chainloaded aura-hvsleep.macho, the guest booted far enough for the PMGR/PMP/SMC
  tracers to log (SMC KInfo reads, PMP DEV_STATUS_TGT writes, CPUSTART writes), then hv_start_secondary(1) failed. Cause in the
  second stage's own log: "SMP: RVBAR 0x1000300c000 differs from vector 0x1000301c000; refusing start". The volume's boot
  object is the RAW build (vectors at the image base); the Mach-O build has them 0x10000 higher and RVBAR is locked on T6020.
  Fix: chainload the raw build (hv-run.sh: *.bin -> chainload.py -r -E 2048).
- Run 2 (raw Aura chained): RVBAR now matches, but "SMP: RVBAR 0x1100036d0000 differs from vector 0x100036d0000" for CPUs
  1-3, 5-6, 9-10; only CPU 4 and CPU 8 (core 0 of clusters 1 and 2) started. RVBAR readback carries the CORE index in bits 44-45
  on T6020 (0x11.. = core 1, 0x21.. = core 2, 0x31.. = core 3); Aura masks GENMASK(47,12). Fix: GENMASK(43,12)
  (aura-hvsleep 90b2155e, patches/hvsleep-trace). The same bug would make Aura as stage 2 start one core per cluster, which
  matters for part B step 0 of GH-8 (stock Aura as stage 2 has never booted this Mac).
- Both runs left run_guest.py in its error shell on the Mac's rainbow logo; the Pi guard (mac-guard.sh) did not reboot the Mac
  because it skipped while run_guest.py was alive. Now it treats a run whose console file has not grown for 180 s as stalled
  and stops it, then reboots through the proxy after 300 s. The owner hard-rebooted by hand both times.
- Boot resume (harness/resume/deepidle-resume + ~/.local/state/deepidle/resume-always, boot-prompt.txt) resumes this session on
  every Linux boot; agy on the Pi (gemini-3.8-flash-high, --remote-control) is the rescue helper only.

## 2026-10-25 11:20-11:40: third guest run: all 10 CPUs in the guest; SMC tracer assert; agy readiness
- Run 3 (raw Aura chained, RVBAR fix 90b2155e): guest secondaries 1-6 and 8-10 started and entered the guest (9 + the boot CPU = the
  10 CPUs of the M2 Pro), no SMP refusal. The guest then ran with the PMGR/PMP/SMC
  tracers logging until 11:21, when SMCTracer.handle_msg hit an AssertionError in the ASC base-message field validator
  (trace/asc.py BASE_MESSAGE, a message type it does not know) and each one dropped the run into the interactive debug shell
  (stdin /dev/null: "Returning to tracer", ~150 MB of tracebacks). Not a guest or hardware fault.
  Fix: trace_smc.py catches the AssertionError and logs "[smc] unparsed msg dir r0 r1" (aura-hvsleep tree, patches/hvsleep-trace).
  Run ended with the Mac at the rainbow logo again; the owner hard-rebooted (11:35). The guard held (hold file) during the run.
- Owner rule (2026-10-25): start the agy helper in remote-control mode before every reboot; it keeps logs; read them after every test.
  Added harness/remote: agy-ready.sh (Pi: RC daemon up, logs to rescue/agy-ready.log), agy-report.sh (Pi: guard + agy events since a
  time), ready-for-reboot.sh (Mac: refuses unless agy RC, mac-guard, pi-watch and resume-always are all up; run before each reboot).
- BLOCKED: `agy remote-control start` on the Pi says "not signed in: run `agy`, sign in" (print mode works with the stored token, RC
  needs an interactive sign-in), and the Pi user has no linger (a user daemon would stop at logout; enabling it needs sudo on the Pi).
  No further test reboots until the owner signs in.

## 2026-10-25 11:53-12:10: run 4 reached the macOS login window; agy RC session; password to the Pi
- Run 4 (SMC tracer fix): the guest macOS 14.8.9 booted under the hypervisor to its login window. The owner rebooted from there after ~4 min
  (nothing seemed to happen; the hvsleep job sleeps the guest 5 min after boot, so it had not run yet) and had to type the account password.
  No agy RC session existed then (only the daemon, which is not a session), so the owner could not watch.
- Pi: agy-session.py keeps an interactive agy in RC mode (pty, log rescue/agy-session.log, restarts); ready-for-reboot.sh now requires it.
  Its banner says "not signed in" although the daemon is; unverified whether it can run tool calls. The guard reboots through the proxy itself first.
- The macOSTest login (1Password item "MacOS Test Login") is on the Pi in secret/macostest-login (mode 600) and in the Mac's
  ~/.local/state/deepidle. Owner: nothing on the macOSTest volume is sensitive and it will be deleted after testing; agy and Claude may modify it freely.
  op needs an approval prompt in the 1Password app (headless: invisible), so the owner approves it by hand.
- Autologin: the owner sets it once in the guest (System Settings), prompted by a phone notification (notify-when-guest.sh) that run 5 sends.

## 2026-10-25 12:12-15:14: run 5 (autologin prompt): the whole machine hung; owner power-cycled at ~15:14
- Run 5: the guest booted under the hypervisor (starting the guest 12:12:49), all tracers logging, then the console went silent at
  12:20:45 (7 min 56 s in) and the Aura USB proxy stopped answering (reboot.py timed out twice: the guard at 12:24, agy at ~12:29).
  The SoC itself is hung, not only the guest: no remote recovery exists (no serial, no power control from the Pi); the owner had to hold the
  power key. The Mac was down about 3 h (12:12 to 15:14) because nobody was at it.
- The phone notification asking for the autologin step never went out (script bug: it picked the previous run's directory before the new one
  existed, and hid curl's errors; fixed: waits for its own run dir, logs every step to guard.log). The Pi to phone path itself works (tested).
  So nobody logged in; the guest sat at the login window. The owner had asked to be called only once, so that cost the whole slot.
- What the tracers show before the silence: macOS only polling SMC (MSX0/MSX2/MSxb keys, 1152 each) and PMP registers; no PMGR/CPUSTART writes
  after boot, no SMC sleep keys (slpw/slpa/WKTP writes), no CYC_OVRD. So the hang came before any orderly sleep was begun: the hvsleep job
  (5 min after launchd) may have been about to fire, or the hang is a hypervisor/guest fault unrelated to sleep (e.g. a stuck tracer path or
  an unhandled guest exception). Not yet distinguished. console.txt has no timestamps; add them (hv-run.sh) so the time of the last event is known.
- agy: the helper ran (diagnosis report rescue/20261025-122810.md, correct: needs the power key). It cannot do more; remote control needs the
  proxy, and a hung SoC has none. The honest limit of unattended testing here is a hard hang needing the power key.
- Owner request 15:14: no reboots for now (using the Mac). Next when allowed: timestamp the console, run once with the owner present at the
  Mac for the autologin step, then unattended.

## 2026-10-25: GitHub Project
- Private user Project "S2R on M2 Pro (J414s)": https://github.com/users/JJRPF/projects/2 (number 2, id PVT_kwHOByT81M4Boss1), linked to the repo.
  Status field PVTSSF_lAHOByT81M4Boss1zhnLjfo: Todo 9c0cb1c9, In Progress c2f6f865, Blocked 5bf15dda, Done 9654d217.
  Holds issue #8, PR #7 and 13 draft items (done fixes, the run 5 hang, autologin, Phase 3 trace, Phase 1 boot test, wake path, GH-8 PR).
  Kept up to date after every test (boot prompt step 5).

## 2026-10-25 15:20-15:40: Phase 1 test image assembled offline (not installed, nothing armed)
- aura-psci (branch psci-efi) now carries the RVBAR core-index fix (cherry-picked 90b2155e as a local commit): without it stock Aura as
  stage 2 would start only core 0 of each cluster on T6020 (worklog 11:20). Rebuilt (build/aura.bin).
- harness/tools/bootbin-build.py (new) assembles the test boot.bin from the stock one: new stage-2 image + DTB #31 replaced + new gzipped U-Boot.
  Result ~/Work/psci-test/boot.bin.psci-test (8934040 B): image == aura-psci build; 113 DTBs, only #31 differs from the installed boot.bin
  (stock #31 is the apple,j414s DTB; new #31 == t6020-j414s-psci.dtb); the tail gunzips to the patched U-Boot (654512 B, stock 660216 B).
  Verified by splitting it back. The kernel and the GRUB entry are not built or installed yet.
- Step 0 of GH-8 B (stock Aura as stage 2, same boot.bin otherwise) can be assembled the same way from ~/Work/aurora-src/aura/build/aura.bin
  plus the stock DTB set, but that tree lacks the RVBAR fix: rebuild it with 90b2155e first.

## 2026-10-25: Aurora-DeepIdle switched to direct push
- Owner decision: one effort, not separate tasks, so no PR per step. `grove add-repo Aurora-DeepIdle --direct-push` (local config.json);
  the GH-8 work was rebased onto main (PR #7 merged) and is published with `git push origin HEAD:main`. Kernel, boot image and recovery
  scripts that are installed on the Mac's boot path still wait for the owner's go. The branch GH-8-S2R-NextSteps is kept: the issue comment's curl
  URL points at it.

## 2026-10-25 afternoon: offline work while the Mac was in use (no reboots)
- Direct push on; GH-8 work published to main. Run 5 decoded: the PMP device power target shows media blocks off at 90 % of the log and the display
  front end (DISP0_FE) off at 98.7 %, seconds before the console went silent: most likely the guest's sleep starting (docs/hv-boot-trace-reference.md).
  hv-run.sh has HVSLEEP=0 for the control run. Phase 1 test boot.bin assembled and verified offline. README/status updated;
  tools/tests/test_bootbin_build.py added (passes).

## 2026-10-25 17:03-17:20: run 6, control (HVSLEEP=0): no hang in 15 min; guest restart works
- Pi: hv-run HVSLEEP=0 RUNTIME=1800 (tag sixth-nosleep), started 17:03:48, 906 s of PMP writes, 104 578 lines, now stamped. No hang; the owner
  restarted the guest at 17:18:54 (the PMP targets went to 0x0, the Mac booted Linux at 17:19:35). Display domain off for ~1 min mid-run, no effect.
- The autologin notification again never went out: `cd ~/deepidle && cmd &` in the ssh one-liner ran in a subshell, so the second line looked for
  ./notify-when-guest.sh in the wrong directory (the script itself works). New launcher harness/remote/start-run.sh uses absolute paths.
- The guard asked agy for a diagnosis at 17:19:18 although the Mac was already about to come back (down 929 s at that moment: the guest run itself
  took 15 min and the guard only skips while run_guest is alive; it ended at 17:18:54). No harm; its threshold should be measured from the run's end.
- Whether autologin got set: not confirmed (the owner restarted the guest; check at the next guest boot).
- Open: how to make a sleep-job run end without the power key (Pi-side VBUS wake, or an armed SoC watchdog). See docs/hv-run5-analysis.md.

## 2026-10-25 — VBUS-cycle recovery (idea 1), prepared
- `uhubctl` 2.6.0 is on the Pi (Pi 5, per-port power switching advertised on all four hubs). Nothing is on USB while the Mac runs Linux, so the Mac's port is learned at run start (`vbus.sh learn`, called by `hv-run.sh` once Aura is present).
- `mac-guard.sh`: after VBUS_AFTER (420 s) with the Mac unreachable and no Aura on USB it runs `vbus.sh cycle` (8 s off, then on) before the agy diagnosis. Also fixed: the outage clock now starts when a guest run ends.
- Untested whether a hung M2 wakes on a cable attach. Run 7 tests it. Idea 2 (armed watchdog) follows if not.

## 2026-10-25 — Run 7 (hands-free, sleep job on): the sleep sequence reached, ended by an HV panic, no power key
- 18:27:56 guest started (Pi dir `hv/20261025-182728-seventh`). The sleep job fired ~3 min after boot; at 18:31:12 the console shows the real sleep sequence: PMP `DEV_STATUS_TGT_WR` steps down 0x8300 -> 0x300 -> 0x200 -> 0x0 (PCPM0, then PCPM1), the secondary CPUs get CPUSTART writes, a PMGR "Dangerous write" (2902801c0), then CPUs 1/2/3 write ACC_OVRD_EL1 / CYC_OVRD (0x3000001, WFI-ret and FIQ-mode bits masked by the HV).
- Then `HV panic: Failed to rendezvous, missing CPUs: 0x4 (current: 5)`. Breadcrumbs of CPU 5 end `X A - P`: an unhandled implementation-defined system register access (ESR_EC_IMPDEF) went to the proxy, whose rendezvous waits for CPU 2, which is already stopped (the guest cut PCPM power and CPU 2 never answers the IPI). This is an HV artifact: bare metal has no rendezvous.
- The panic path rebooted the Mac by itself: Linux was back at 18:31:50 (unreachable 96 s from the guard's view). So a sleep-job run does not need the power key when it ends in an HV panic (run 5's silent hang was a different ending). The VBUS cycle was not needed; Aura on USB was on hub 1 port 1 (learned by `vbus.sh learn`).
- Not yet known: which register CPU 5 touched. Patch `hv: print the exception syndrome at proxy entry` (esr, elr, afsr1 printed before the rendezvous) built into aura-hvsleep (c5e7df2d...); on the Pi as hv/aura-hvsleep.bin (the run 7 build kept as aura-hvsleep.run7.bin). Run 8 with it will name the register. Needs the owner's go.
- 2026-10-25 18:5x run 8 started (eighth): same as run 7 with the syndrome-print Aura.

## 2026-10-25 — Run 8 (syndrome print): the cause of the HV panic is the guest's WFI_MODE=3
- Run 8 (Pi `hv/20261025-185849-eighth`, 18:59:13 – panic 19:04:43): same ending as run 7, Mac rebooted itself, Linux 19:05:23. `Failed to rendezvous, missing CPUs: 0x2 (current: 8)`.
- The proxy-entry lines show the unhandled-by-C IMPDEF accesses are ordinary sysreg trace events (python handles them; e.g. S3_5_C15_C6_0 read/write at the guest's sleep code, pc ...a31b88/bb4). Not the cause.
- What precedes the panic in both runs: CPUs 1/2/3 each write `CYC_OVRD <- 0x3000001`. Bits 25:24 are WFI_MODE=3 (deep sleep), and the HV only masked DISABLE_WFI_RET and FIQ_MODE, so WFI_MODE=3 reached the hardware. The next guest WFI powers that core down; it cannot answer the rendezvous IPI inside the 1,000,000-spin timeout (run 7 CPU 2, run 8 CPU 1). A core that really deep-sleeps under the HV could not resume anyway (no HV resume path).
- Fix (patch `hv: also mask CYC_OVRD WFI_MODE ...`, aura-hvsleep 1248fddf...): WFI_MODE joins the masked bits, so guest cores stay in a light WFI. Proxy-entry print dropped (it doubled the console size). On the Pi as hv/aura-hvsleep.bin; run 8's build kept as aura-hvsleep.run8.bin.
- Expectation for run 9: the guest's sleep path continues past the CPU-off step to the final system-sleep trigger (PMP/SMC writes), which is what we want to see. That last step may really sleep the SoC (run 5's silent hang); the guard's VBUS cycle is then the first recovery.

## 2026-10-25 — Run 9: WFI_MODE masked, still a rendezvous panic; the PMP power-off of the CPU domains is the real killer
- Run 9 (Pi `hv/20261025-190650-ninth`, guest 19:07:11, panic 19:10:28): the CYC_OVRD mask works (`masked 0x3000001`, the deep-sleep bits no longer reach the hardware), yet `Failed to rendezvous, missing CPUs: 0x100 (current: 5)`: CPU 8 (second P cluster) never answers. The mac rebooted itself again (Linux 19:11:09).
- Before it, in both runs: `DEV_STATUS_TGT_WR` 0x8300 -> 0x300 -> 0x200 -> 0x0, i.e. the guest powers off ECPM/PCPM0/PCPM1 (the CPU complexes) through the PMP, then writes PMGR 2902801c0 ("Dangerous write"), then the cores go through the WFI dance. A powered-off cluster cannot rendezvous and the HV state in it is gone. So under the HV a faithful sleep is impossible past this step.
- Change for run 10 (hardware register write, said first): `hv/trace_pmp.py` with `HV_PMP_KEEP_CPUS=1` emulates the PMP registers in the HV and, on a guest write to DEV_STATUS_TGT_WR, keeps any CPU-domain bit (ECPM/PCPM0/PCPM1) that is currently on. The write that would power the CPUs off is the only thing dropped; everything else passes and is logged as before. This only keeps the machine more powered, never less. Patch in patches/hvsleep-trace/.
- Hope: the guest goes on to its last step (AP sleep request through PMP/SMC) with the HV alive, and we see it.

## 2026-10-25 — Run 10 lost to a tracer bug of mine; fix and guard hardening
- Run 10 (Pi `hv/20261025-191335-tenth`): `PMP: keeping CPU domains on (mask 0x380)`, then every PMP access raised `AttributeError: 'PMPRegs' object has no attribute 'addrof'` in my new hook (RegMap from m1n1.utils has no addrof; I had checked the wrong class). The debug shell looped on each access, the console stayed busy so the idle check never fired until 19:38, the proxy could not reboot the wedged Mac ("needs the power key"), and it sat until the owner pressed the power key at ~21:04 (~1 h 25 min lost).
- Fix: TGT_RD address computed from pmp_base + ptd offset; the decision is a pure function (tested); the hooks catch every exception and pass the access through, so a bug there cannot reach the debug shell. Guard: stops a run whose last 3000 console lines hold >= 20 "Entering debug shell".
- VBUS cycle also failed at 21:03:57: `sudo: a password is required` on the Pi (plain `uhubctl` lists hubs without root, a cycle needs root). Needs the owner: a NOPASSWD rule for /usr/sbin/uhubctl on the Pi. Not done yet.
- Lesson: run the new tracer code against stubs before a boot, not after (done now for the decision function).

## 2026-10-25 — Runs 11: the macOS sleep-entry sequence, complete; HV cannot go past it
- Run 11 (HV_PMP_KEEP_CPUS=1, fixed hook): the PMP hook works (`guest wrote TGT 0x200, CPU domains kept on -> 0x300`), the run reaches the same end: `Failed to rendezvous, missing CPUs: 0x106 (current: 10)` at 21:11:19, Mac rebooted by the HV panic, Linux 21:12:00 (guard saw 64+ s down). No power key.
- Full sleep entry written up in docs/hv-boot-trace-reference.md: `MBSE=slpw`, PMP TGT handshake, `MBSE=slpa`, `SetAPPower 0x201` (SMC + PMP), `SetIOPPower`, CPU stop writes, PCPM clears, CYC_OVRD deep sleep. `SetAPPower` is what takes the cores down, so no HV tweak keeps them alive; the HV phase of the sleep trace is done.
- Not obtainable under the HV: the wake side (what restarts the AP, the RVBAR it uses, which events wake it).
- Next needs the owner (rules): reproduce `slpw`/`slpa` + `SetAPPower` from Linux on the Phase 1/2 test image, which the project rule forbids ("No slpa") until lifted.
- 2026-10-25 21:31:57 Phase 1 step 0 armed (Aura stage 2, boot.bin 19d5f8f6...), rebooting; owner present.

## 2026-10-25 21:32 — Phase 1 step 0 PASSED: Aura as the stage 2 boots stock Linux
- Built `boot.bin.aura-stage2` (19d5f8f627f966a1): the stock boot.bin with only the stage-2 image replaced by the aura-psci build (RVBAR fix in); verified image == build, all 113 DTBs and the U-Boot payload byte-identical to stock. `harness/psci-efi/install.sh step0` armed it (stock kernel, default GRUB entry), owner present and approving (go given in session), rebooted 21:32.
- Result (`/var/lib/deepidle/results-psci-efi-step0-20261025-2132`): booted image sha 19d5f8f6; early unit put stock back (ESP 3630adc3 again); Linux 7.1.12-2-11.35-sep-ARCH+, "smp: Brought up 1 node, 10 CPUs", online 0-9, EFI v2.11 by U-Boot. No problem seen. Aura as a resident stage 2 is fine for this Mac.
- Next: stage the psci-efi-test kernel (modules building, release 7.1.12-psci-efi+), then step 1 (needs the owner's go again).
- 2026-10-25 21:45:59 Phase 1 step 1 armed (psci-efi kernel + boot.bin.psci-test 78b481c6, next_entry psci-efi-test-kernel); owner asleep, standing go; rebooting.

## 2026-10-25 21:46 — Phase 1 step 1: the psci-efi kernel boot died early, no log; bisecting
- Armed step 1 (psci-efi kernel 7.1.12-psci-efi+, modules staged stripped (96 MB, 1872 modules), boot.bin.psci-test 78b481c6, next_entry psci-efi-test-kernel), rebooted 21:46:02.
- Result: no journal for the psci-efi boot at all (journal list: boot -1 ended 21:46:02, next boot starts 21:48:20 on the DEFAULT stock kernel); the ESP still held the psci boot.bin (booted sha 78b481c6) and the early unit then restored stock. GRUB had consumed next_entry. So the psci-efi kernel (or its initramfs) died before the root filesystem was mounted and panic=10 (or a reset) rebooted into the default entry.
- Side result: the stock kernel on the PSCI DTB says `psci: invalid "method" property: efi` and brings up 1 CPU, exactly as the doc predicted for a kernel without the RFC patches; Linux stays usable.
- No early console to read (screens off, no UART). Bisect: step1a = the psci-efi kernel on the STOCK boot.bin (no PSCI node). Boots -> the fault is in the PSCI path; does not boot -> kernel/initramfs build (the initramfs has the same 207 modules as stock, no firmware blobs).

## 2026-10-25 21:52 — Step 1a PASSED; step 1m armed
- Step 1a (psci-efi kernel on the stock boot.bin, spin-table): booted, `7.1.12-psci-efi+`, 10 CPUs, headless hook fine. So the kernel and the initramfs build are good.
- Together with the step-1 fallback boot (stock kernel on the PSCI boot.bin: boots, `psci: invalid "method" property: efi`, 1 CPU), Aura, the patched U-Boot and the PSCI DTB are benign by themselves. The early death needs the new kernel AND the PSCI table: its probe (PSCI_VERSION/FEATURES through the EFI handler) or the first CPU_ON.
- Step 1m: same PSCI image, GRUB entry `psci-efi-test-kernel-mc1` (`maxcpus=1`): the kernel probes the handler only; run.sh then onlines cpu1..9 one at a time from the running system and logs before/after, so a CPU_ON fault is visible (and the Pi watcher streams dmesg). A boot that dies with maxcpus=1 means the probe itself.

## 2026-10-25 21:55 — Step 1m: probe works, the first CPU_ON faults (captured by the Pi watcher)
- The kernel boots with maxcpus=1 on the PSCI image: `psci: PSCIv1.0 detected in firmware.`, `SMC Calling Convention v1.0` (the cached version/features from the table), "Remapping and enabling EFI services." printed, no virtual-mapping error. So the table is found and read.
- run.sh onlined cpu1 at 21:55:12 and the kernel oopsed (Pi watcher kmsg kept it): `Unable to handle kernel paging request at virtual address 00000100039d6ca0`, ESR 0x86000006 = IABT (current EL), level 2 translation fault, `pgd=0`; `pc : 0x100039d6ca0`, call trace `arm64_efi_psci_call+0x44 -> __invoke_psci_fn_efi+0xa0 -> psci_0_2_cpu_on+0x34 -> cpu_psci_cpu_boot -> __cpu_up -> ... online_store`. x0 = 0xc4000003 (CPU_ON), x1 = 1 (cpu1), x4 = x pc = the handler pointer. The mm active during the call has no mapping of the handler's page at all.
- So the failure is not in Aura's handler: the kernel's EFI runtime map has no entry covering the Aura image (or it lacks EFI_MEMORY_RUNTIME / virt_addr). U-Boot adds the image from /chosen `aura,psci-runtime-code` as EFI_RUNTIME_SERVICES_CODE; either that range does not contain 0x100039d6ca0, or the kernel did not map it.
- Next: same step with `efi=debug` (the kernel prints the whole EFI memory map) and the raw `aura,*` /chosen properties saved before onlining.

## 2026-10-25 22:01 — Step 1m with efi=debug: the cause found (U-Boot overwrites the runtime-code range)
- Saved by run.sh before onlining (`results-psci-efi-step1m-20261025-2200`): `/chosen` is right: aura,psci-runtime-code = base 0x100039c4000 size 0x350000 (contains the handler 0x100039d6ca0 and the table 0x10003aeb638), aura,psci-runtime-mmio = 0x28e0a8000 size 0x4000.
- The kernel's EFI map (efi=debug): `0x0100039c4000-0x010003d13fff [Reserved | ... |WB]` (no RUN bit) while the MMIO range is `[MMIO |attr=0xc000000000000000]` (RUNTIME + ISA-valid, Device-nGnRnE). So the MMIO part of U-Boot's efi_platform_register() worked and the code range was demoted to Reserved afterwards, so the kernel mapped nothing for the handler: the level 2 translation fault.
- Cause in U-Boot: efi_carve_out_dt_rsv() (efi_dt_fixup.c) re-registers every DT reserved range (memreserve and /reserved-memory) as EFI_RESERVED_MEMORY_TYPE over whatever type it had, and Aura's own image is in the DT's reserved ranges. It runs after efi_platform_register().
- Fix (patches/psci-efi/u-boot/0001-efi_loader-let-a-platform-re-apply-...): weak hook `efi_platform_after_dt_rsv()` called at the end of efi_carve_out_dt_rsv(); the Apple board re-adds the image range as EFI_RUNTIME_SERVICES_CODE there. Rebuilt U-Boot (c0f9f281...), new test image `boot.bin.psci-test2` 005e72c523020fea (only the U-Boot tail differs from 78b481c6). The kernel maps runtime code RWX unless an EFI memory attributes table says otherwise, which the handler's data writes need; the next run shows whether that holds.

## 2026-10-25 22:06 — Step 1m with the U-Boot fix: CPU_ON works for all nine secondaries; the machine dies right after
- The kernel's map now has `0x010003630000-0x01000397ffff [Runtime Code|RUN|...|WB]` (Aura's image) and the MMIO range; probe `PSCIv1.0`.
- Pi watcher kmsg of the boot (`results-psci-efi-step1m-20261025-2205`, run.log only kept cpu1-3 because the machine died before later lines were synced): `CPU1: Booted secondary processor 0x1` ... `CPU4: Booted secondary processor 0x10100` (first core of the second cluster, EM perf domain created) ... `CPU9: Booted secondary processor 0x10202` at 85.65 s. **CPU_ON through the EFI handler works for all 9 secondaries, both clusters.** Phase 1's CPU_ON gate is met.
- The stream ends right after CPU9, no oops, no panic text: a hard hang/reset within ms; the Mac was back about 100 s later (the systemd watchdog resets a hung SoC, since Aura disables its own). The next action of run.sh after the online loop is the hotplug loop: `echo 0 > cpu1/online` = CPU_OFF through Aura's handler. Most likely culprit: CPU_OFF (PMGR stop + L1 flush + cpu_sleep(true)).
- Next: run.sh writes every action to /dev/kmsg before doing it (the Pi stream then names the last one) and runs 3 cycles per CPU first.

## 2026-10-25 22:11 — Step 1m: all ten CPUs online by CPU_ON; CPU_OFF takes the whole SoC down
- Run with /dev/kmsg markers (Pi stream): `onlining cpu1..9` each `-> 1`, `online: 0-9`, then `psci-efi-test: cpu1 cycle 1: offline ...` and the stream ends: no oops, no panic text. Hard reset by the watchdog about 100 s later.
- Reading Aura's CPU_OFF: it called `cpu_sleep(true)`, whose deep path writes `ACC_OVRD` (PWR_DN_SRM(3), POWER_DOWN_CPM(3), DIS_L2_FLUSH_ACC_SLEEP, DEEP_SLEEP). ACC_OVRD is per cluster (all cores of a cluster read the same value in the HV trace), and m1n1 uses that path only to stop the last secondaries at handoff. With cpu0 and the others still running Linux in the cluster it requests SRAM/CPM power-down for the whole cluster. macOS's per-core idle writes the per-core CYC_OVRD only.
- Fix (patches/psci-efi/aura/0001-psci-CPU_OFF-uses-cpu_sleep-false...): CPU_OFF uses `cpu_sleep(false)` (CYC_OVRD IRQ/FIQ modes, then WFI_MODE(3)+DISABLE_WFI_RET, deep WFI), after the PMGR stop request and the L1 flush as before. New image `boot.bin.psci-test3` (the same DTB and fixed U-Boot, new Aura).

## 2026-10-25 22:16 — CPU_OFF works (no more SoC death); re-onlining the core fails
- With `cpu_sleep(false)`: all 9 CPU_ON, then `echo 0 > cpu1/online`: `psci: CPU1 killed (polled 0 ms)`, the machine stays up, online `0,2-9`. Phase 1's CPU_OFF gate (the core powers down, others unaffected) is met. Read-back through /dev/mem (read only): cpu1 status register `0x210150100` low byte 0x00 (stopped; running cores read 0x0f), RVBAR `0x210150000` still the Aura vectors.
- `echo 1 > cpu1/online`: `psci: failed to boot CPU1 (-22)` after ~105 ms = Aura's restart waited its 100 ms for the park-loop flag. Cause found by reading the code: `smp_start_cpu()` sets `_reset_stack` (and `_reset_stack_el1`) to the core's own stack before every start because the reset handler takes its stack from that global; `smp_psci_restart()` only set `target_cpu`, so the restarted core ran on the leftover dummy stack. Fix: same setup in the restart (RVBAR deliberately not written: not in the handler's mapped MMIO ranges, and it is retained), dummy stack put back afterwards. `boot.bin.psci-test4`.

## 2026-10-25 night: PSCI restart attempt 3 (test image 5)
CPU_ON of a CPU_OFF'd core still failed (core stays stopped after PMGR start strobes). Image 5 (85b54e03f7a91214): restart clears the stop strobe (+0x0), then start strobes, then `smp_send_ipi` + `sev`, in case the deep-WFI core needs an event. Result: pending (step1m).

Result image 5 (step1m, 22:25): CPU_ON of cpu1 after CPU_OFF still fails (cycle 1 online failed). Cause found while reading the restart: it memset the spin_table entry, which zeroed the stored mpidr, so the wake IPI went to cpu0, not the target. Image 6 (4c5c4b22cf9f7428) keeps the mpidr. Result: pending.

Result image 6 (22:28): still `online failed` (-22). Userspace replay shows the core is not stuck on timing: PMGR strobes toggle status bit 21 for one sample, low byte stays 0; RVBAR is correct (Aura vectors, lock clear). Aura memory is readable through /dev/mem (base 0x10002a88000 + link offset): after the failed restart spin_table[1].flag is 0, target_cpu=1, psci_cpu_state[1]=OFF(2). So the core either never leaves reset or dies early in the reset path. Image 7 (fdd5572f5d2830cb) adds `reset_dbg[]` breadcrumbs (0xa1 asm entry, 0xa2 stack chosen, 0xa3 _cpu_reset_c, 0xa4 after init_cpu, 0xa5 smp_secondary_entry), cleared at each restart; read at base+0x2fa000 after the test. Result: pending.

Result image 7 (22:31): reset_dbg all zero after the failed online, so the restarted core never reaches the first reset instruction: the PMGR start strobes do not restart a core stopped by the PMGR stop request (userspace sequences with +0x4/+0x8 variants also fail; +0x4 ignores writes). New approach, image 8 (ff8535d16d9d0491): CPU_OFF does not use the PMGR stop at all; it cleans the cache and enters deep WFI (CYC_OVRD WFI_MODE 3 + DISABLE_WFI_RET, no FIQ/IRQ_MODE 2), the state smp_secondary_entry already handles as an RVBAR re-entry. CPU_ON of an OFF core dispatches the target and repeats the IPI until the core's flag moves. Result: pending.

Result image 8 (22:35): deep-WFI CPU_OFF puts the core in the stopped state (status low byte 0) but the repeated IPIs for 100 ms did not bring it back (online failed). Image 9 (e8c7aa8c88ffe732): wake also writes the PMGR start strobes after 10 ms, and clears reset_dbg so the breadcrumbs (base+0x2fa000: a1..a5) show whether the core reaches reset. Result: pending.

Result image 9 (22:37): reset_dbg all zero again: neither IPIs nor PMGR start strobes bring a deep-WFI (DISABLE_WFI_RET) core out. Image 10 (ff0035da55660a55): experiment, CPU_OFF arms the core's own virtual timer (50 ms) before the deep WFI; the reset path (RVBAR re-entry) disables it and the core parks in smp_secondary_entry, where IPI wake is the proven path. Tests whether any wake event reaches a core in this state. Result: pending.

Result image 10 (22:40): the timer test showed the answer: afterwards cpu1's status read 0x...02 (not 0x00) and no reset breadcrumbs: a deep-WFI core is woken by events but resumes after the WFI, it does not restart at RVBAR. So images 8/9 may well have woken the core on the IPI; the loop just went back to sleep. Image 11 (b1a6da1cdf2e5989): CPU_OFF parks the core in Aura, which Linux (EL2, VHE) called into: clean caches, switch to the core's Aura stack, deep WFI loop on the spin-table target. CPU_ON then dispatches as for a parked core; the parked loop turns MMU/caches off, resets HCR_EL2, and branches to the kernel entry with x0 = context. Result: pending.

Result image 11 (22:43): big step. CPU_OFF now parks the core and the SoC survives, but 100 us after "CPU1 killed" the parked core started the kernel by itself ("Detected PIPT I-cache on CPU9", NULL IABT, SoC hung, ~100 s watchdog reset, stock kernel boot at 22:45). Cause: spin_table[1].target still held the entry from the core's first CPU_ON (the kernel never returns, so the park loop never cleared it), so the park loop saw a target at once. Image 12 (dab9dfa935925380) clears the target in CPU_OFF before parking. Result: pending.

Result image 12 (22:48): after "CPU1 killed" the SoC hung silently (no panic-reboot in 35 s, watchdog reset later, stock kernel 22:50). Suspect: something in the Aura park code (stack switch to the Aura secondary stack, or the C park loop) faults; a fault on the Aura stack is read by the kernel's vmap-stack check as an overflow and dies silently. Bisecting. Image 13 (aa6d2a3da52c3647): stack switch + bare `wfi` loop only (online is expected to fail; the question is whether the SoC survives). Result: pending.

Result image 13 (22:53): bare `wfi` loop on the Aura stack survives (offline ok, online times out, SoC up). So the stack switch is fine; the hang is in the C loop: the civac/target read, `cpu_features`, or the IPI_SR ack. Image 14 (a9a568b8c284c7b8): loop with civac + target read, IPI_SR ack removed (a pending IPI then just makes the wfi return at once). Result: pending.

## 2026-10-27
Result image 14 (2026-10-25 22:56): the SoC hung after "CPU1 killed" again and stayed hung until a manual reset (next boot 2026-10-26 20:16; the guard's VBUS cycle does not help with a SoC hang, and the watchdog did not fire). So the hang is in the part bisect 1 left out: the civac + `me->target` read. Image 15 (a5e3ced5b3007515): plain load of `me->target` (the mapping is inner-shareable WB, no civac needed on the reading side), no civac in the park loop. Result: pending. (Boot at 2026-10-27 04:05 ran the step on the stock kernel: "table not found", harmless.)

Result image 15 (2026-10-27 17:34): the SoC died during the initial `onlining cpu6` (before any hotplug cycle), reset by the watchdog ~100 s later. That path is unchanged from images that passed, so either a flake or an interaction I do not yet see; repeating the same image once to tell. (The Pi's kmsg stream missed this boot: Wi-Fi was not up in time.)

## 2026-10-31: stop on owner's instruction
Owner (2026-10-27/28): no more CPU hotplug tests (they damage the filesystem) and no reboots until told. Stopped. State left: nothing armed (no psci-efi-armed, no GRUB next_entry, stock boot.bin 3630adc3b3be173c on the ESP); `psci-efi-run.service` disabled so no hotplug can run on a boot (psci-efi-early.service still restores the stock boot.bin; `install.sh remove` undoes everything later).

Where Phase 1 stands (all with the PSCI-via-EFI test kernel and Aura images in ~/Work/psci-test/, patches in patches/psci-efi/):
- Works: PSCI probe, CPU_ON for all 9 secondaries in both clusters (initial start), kernel boots at nproc 10.
- CPU_OFF: the PMGR stop request powers the core down but no later start strobe, IPI or timer brings it back (RVBAR re-entry never happens, reset breadcrumbs stay 0). A deep-WFI core (CYC_OVRD WFI_MODE 3 + DISABLE_WFI_RET) resumes after the WFI on a wake event, it does not restart at RVBAR.
- Current design (images 11-15): CPU_OFF parks the core in Aura (clean L1, switch to the core's Aura stack, deep WFI loop on spin_table[].target); CPU_ON hands the entry over, the loop turns MMU/caches off, resets HCR_EL2 and branches to the kernel entry. Bisect: stack switch + bare WFI loop survives (image 13); adding the civac/target read hung the SoC (images 12, 14); plain-load variant (image 15) died earlier at the initial `onlining cpu6` once, unexplained (possibly a flake, possibly a hardware effect of the earlier hangs).
- Open: why the loop hangs the SoC (suspects: the loop's load of spin_table after the cache clean+invalidate while the L2/cluster state is changing, an exception on the Aura stack that the kernel reads as a stack overflow, or the interaction of deep WFI with the pending-IPI wake). Next step when testing is allowed again: single-purpose images with one change each, preferably tested on a disposable boot with the FS mounted read-only.

## 2026-10-31: Phase 2a, SYSTEM_SUSPEND stub (image 16), maxcpus=1

Owner: hotplug tests stay banned, reboots allowed. So Phase 2 goes ahead on the boot CPU alone (`maxcpus=1`; no core is ever offlined).

* Aura: `SYSTEM_SUSPEND` (psci.c) waits 3 s on the counter, then `psci_enter(entry, context)` (MMU/caches off at EL2, jump to the kernel's `cpu_resume`). No power state changes. Advertised in PSCI_FEATURES. New `install.sh suspend` step; `run.sh` remounts filesystems read-only, writes `deep` to mem_sleep, `echo mem > /sys/power/state`, remounts rw.
* Result, first run: the kernel suspended all devices (DCP, NVMe shutdown with saveCtx, Wi-Fi), Aura returned through `cpu_resume`, devices resumed, `PM: suspend exit`, rc=0, back in 5 s. **First time the full Linux suspend/resume path ran with a firmware that hands back.** AIC save/restore ran without errors.
* Found: `BUG: scheduling while atomic ... Preemption disabled at efi_virtmap_load` in noirq resume. SYSTEM_SUSPEND never returns through `arm64_efi_psci_call()`, so `efi_virtmap_unload()` never ran (preempt count +1 per suspend). Kernel patch (`patches/psci-efi/linux/0001-*`): after a successful `cpu_suspend()` on the EFI conduit, unwind it (`arm64_efi_psci_resumed()`).
* Also seen after resume, not yet analysed (Phase 4): Bluetooth hci0 opcodes time out (-110) after resume, `brcmf_c_set_joinpref_default` error -52 once. aurora-fand / apple_sep failures were already there before the suspend.
* Next: rerun with the fixed kernel (same image 16).

### 2026-10-31: Phase 2a rerun with the unwind patch
Same Aura image 16, kernel with the EFI unwind patch. `echo mem` returned rc=0 after ~8 s, no `scheduling while atomic`, no BUG/WARN in the suspend window. Phase 2a works once on the boot CPU alone (maxcpus=1). Not yet done: 20 cycles, real wake sources (PMU alarm/lid/power key instead of Aura's fixed 3 s wait), the Bluetooth timeouts after resume, and any multi-CPU suspend (needs hotplug, banned).

### 2026-10-31: Phase 2a, 20 cycles
`install.sh suspend` now runs 20 `echo mem` cycles (image 16, kernel with the unwind patch, maxcpus=1, filesystems read-only). **20 of 20 returned rc=0**, about 8 s each (3 s Aura wait plus device suspend/resume, NVMe `saveCtx` shutdown ~0.5 s), no BUG/WARN/`scheduling while atomic`, system alive afterwards. Phase 2 gate met for the boot CPU alone, with Aura's fixed 3 s wait as the wake. Open before Phase 2 is closed: real wake sources (PMU alarm via AIC, lid, power key; Aura currently ignores them), the Bluetooth hci0 -110 timeouts after resume, multi-CPU suspend (the kernel offlines secondaries first: needs the banned hotplug path to be fixed, Phase 1).

## 2026-10-31: hotplug without risk to the filesystem (owner: find another way)
Hotplug tests are allowed again only in a boot that cannot hurt the root filesystem. `install.sh ram` boots the PSCI test kernel (image 15) into a RAM-only initramfs (`harness/psci-efi/ram/`): a static PID 1 that never opens the LUKS root or mounts btrfs, brings cpu1..9 online and cycles each 3 times (CPU_OFF/CPU_ON), logging to the kernel log and, after each line, to `psci-ram.log` on the ESP (vfat, mounted sync). First thing it does is put the stock boot.bin back from a copy in the initramfs. Result is read from `/boot/psci-ram.log` on the next normal boot. Risk left: the ESP only (recreatable).
Run 1 of `ram`: the initramfs init ran, put the stock boot.bin back and rebooted, but /proc and /sys were not mounted (the cpio had no mount-point directories), so no CPU files were seen. Fixed (init creates them); rerun.
Run 2 of `ram`: stock boot.bin was restored (so the init got that far) but no `psci-ram.log` survived; the machine went back to the normal boot within ~15 s of the restore. Either it died before the log file was created (after the restore, around the first `sync()`) or the file creation was lost. The init now creates and fsyncs the log (and the directory) before the restore. Rerun.
Run 3 of `ram`: no log again, and boot.bin/grubenv were rewritten in the same second by `psci-efi-early.service` of the following normal boot, i.e. the init never restored it: the RAM boot dies or hangs before the ESP is mounted, and a watchdog/panic reset brings the normal boot back. Run 1 got further only because /proc, /sys were not mounted. No console is visible, so the next run is a boot check only (`RAM_CYCLES=-1`: mounts, ESP, log line, restore, reboot; no CPU work) to see whether the init itself works.
Run 4 of `ram` (boot check, no CPU work): the init works (ESP mounted, log, stock boot.bin restored, clean reboot). So runs 2 and 3 lost their logs at the CPU_ON hang, not before. The init now keeps a preallocated 256 KB log file on the ESP and rewrites it with data-only synchronous writes after every line, together with the tail of the kernel log, so a hang leaves the last lines. Rerun with 3 cycles.
Run 5 of `ram` (3 cycles, durable log): the log file was created and preallocated only 4 KB of 256 KB, no text, stock boot.bin not restored by the init (early.sh did it). So the RAM boot dies within seconds, before the init finishes preallocating, in the 3-cycles configuration (runs 2, 3, 5) but passed in the -1 configuration (run 4), though nothing CPU-related runs that early. Either the death is flaky or depends on the cmdline. Rerun the boot check (-1) with the new init to tell the two apart.
Run 6 of `ram` (boot check, -1, durable log): works; the 256 KB log file holds our lines and the kernel log tail. Next, the same image with 3 cycles to see whether the early death in runs 2/3/5 repeats.
Run 7 of `ram` (3 cycles): dies again within seconds, log 4 KB, nothing but newlines. The -1 run finishes in a few seconds. Hypothesis: the RAM boot dies a fixed few seconds after the kernel starts whatever the init does (the -1 run simply reboots first). Init lines now carry the monotonic time, and a `-1` run with `psci_ram_wait=60` idles 60 s logging each second: if it dies, it is not the CPU work.
Run 8 of `ram` (-1, idle 60 s): the RAM boot is stable, 60 s idle, clean reboot, so there is no fixed-time death. The earlier 3-cycle deaths come from something that depends on the 3-cycle run itself. Rerun with 3 cycles and timestamps.
Run 9 of `ram` (3 cycles): again only 4 KB of the log. Reading the -1 runs again: they unmount the ESP cleanly, and that is what makes the log appear. vfat does not make O_DSYNC writes durable across a hard reset (neither the FAT nor the data), so every earlier "died early" reading of runs 2, 3, 5, 7, 9 was a lost log, not an early death. The CPU work may have run much further. The init now preallocates the log, finds its physical location with FIEMAP, unmounts the ESP cleanly and writes the log straight to the partition blocks with O_SYNC.
Run 10 of `ram` (3 cycles, raw log): still a 4 KB file whose directory size was never updated, so the init stops inside the preallocation loop, before any CPU work, whenever the cmdline says 3 cycles, and never when it says -1 (two runs each way with the same image, kernel and init apart from log changes). No explanation yet. Next: 0 cycles (CPU_ON of each core once, no offline).
Run 11 of `ram` (0 cycles = CPU_ON of cpu1..9 once, no offline): **all nine secondaries came online via the EFI PSCI CPU_ON in 0.25 s, clean boot, clean reboot, filesystem untouched** (log: `psci-ram-cycles0.log`). So the 3-cycle runs did not die early: they ran on and hung in the first CPU_OFF/CPU_ON cycle, and their logs were lost because the log was still in the vfat cache (the dir entry showed 4096 bytes). FIEMAP does not exist on vfat, so the raw log fell back; the init now uses FIBMAP. Rerun with 3 cycles: the log should survive the hang this time.
Run 12 of `ram` (3 cycles, FIBMAP): still a 4 KB file, nothing durable. vfat keeps the file and its metadata in cache whatever the mount flags, so any hang loses it. The log now goes to a free run of 64 ESP clusters (top of the FAT, found by install.sh, passed as `psci_ram_raw=<byte offset>`) with raw O_SYNC writes to the partition; read it back with `dd` on the next boot. The ESP is 85% full, so the run is chosen from the highest free clusters, away from where the 6.5 MB boot.bin copy lands.
Run 13 of `ram` (3 cycles, raw log): the raw region read back all zeros. The offset install.sh chose lay past the end of the partition: the FAT has more entries than the filesystem has clusters, and the unused tail looked free. Fixed (clusters limited to the real count). The init did run and restore the stock boot.bin this time. Rerun.
Run 14 of `ram` (3 cycles): the raw log works and shows the init dying between "raw log" and the ESP mount (the first `mount` of the vfat ESP, with the raw log fd open on the same partition). So the earlier "early deaths" (runs 2-13 with 3 cycles) may be this mount, not hotplug. The init no longer mounts the ESP at all (the next normal boot's early service restores the stock boot.bin); all output goes to the raw region. Rerun with 3 cycles.
Run 15 of `ram` (3 cycles, no ESP mount, raw log): the raw log again ends right after "raw log at partition offset" (2 lines), i.e. the init is gone after the second flush, now without any mount. Either the 256 KB O_SYNC raw write kills it, or cycles=3 does. Next: the same raw-log init with `-1` and a 5 s idle: if it also dies, the raw write is the culprit.
Run 16 of `ram` (-1, idle 5, raw log): complete log, clean. So the raw 256 KB O_SYNC writes are fine, and the same init with `psci_ram_cycles=3` is gone after the second log line (runs 14, 15), before it has read the cycle count. Odd: nothing in the init depends on the count before the loop. Next: 1 cycle.

## 2026-11-02: where the testing stands
* Done this week: SYSTEM_SUSPEND stub (Phase 2a) with the kernel EFI unwind patch, 20/20 cycles on the boot CPU alone; CPU_ON of all nine secondaries from a RAM-only boot (`ram`, 0 cycles).
* Finding: logs written to the NVMe do not survive a hard reset, because the ANS firmware caches writes until a clean shutdown (`saveCtx`). Every "died early" reading of the RAM-only runs with cycles >= 1 (runs 2 to 17) was lost data, not an early death; the runs with a clean exit (cycles 0 or -1) kept their logs. The same mechanism explains the owner's filesystem damage after a hotplug hang: the watchdog reset drops the cache. A disk log cannot show where the hotplug hang is; an off-box channel (the Pi's kmsg stream over Wi-Fi, with the root filesystem read-only and synced) can.
* Not yet known: where CPU_OFF/CPU_ON hangs. Next test (read-only root, Pi kmsg stream): one image, one change: park with a plain WFI instead of the deep WFI mode.
* Estimate: about 30% of S2R. Remaining big items: hotplug, real wake sources, SoC sleep steps from the macOS trace, DCP resume.

## 2026-11-02: paused for a separate project (owner)
All work is on main (nothing ahead of origin/main, tree clean), so there is no PR to open from GH-8-S2R-NextSteps; issue #8 stays open and the worktree stays for the S2R work. Nothing is armed (no psci-efi-armed file, no next_entry, stock boot.bin 3630adc3b3be173c on the ESP); psci-efi-run.service disabled. Next when resuming: the proxy-based park/wake test of CPU_OFF/CPU_ON (no OS, no disk), Phase 2b wake sources, then the guarded read-only hotplug test if the owner agrees.

## 2026-11-03: resumed (handoff from GH-10), kernel updated to 7.2.11
* Why we booted: the owner's/GH-10's kernel update and reboots (uptime 1h43 at start; running 7.2.11-14-1-ARCH). Headless was ACTIVE. The Pi watcher was not running; started it (tag s2r-resume). Nothing armed.
* Test kernel rebased onto `origin/integration/aurora` (7.2.11); the two RTC wake patches were dropped (upstream has the PMU alarm). Built clean (`7.2.11-psci-efi+`), staged in `~/Work/staging-psci-efi` (modules, Image); `install.sh` REL updated. Not installed to /boot, no reboot.
* Default `/boot/m1n1/boot.bin` is now the GH-10 PMP+EM image; our test images are still built from `/var/lib/deepidle/boot.bin.stock` (plain) and restored by the early service as before. Keep a copy of the default before any boot.bin swap and restore that one.
* Approval: the guarded hotplug test needs the owner's yes. Asked by push (agentmail has no API key on this Mac). Meanwhile: wake sources (Phase 2b).

## 2026-11-03 (09:10): second resume, Phase 2b test armed
* Why we booted: another reboot of the 7.2.11 update (uptime 1 min, running 7.2.11-14-1-ARCH). Pi watcher was already running.
* Finding: `/boot` (ESP, fstab `nofail`, 5 s device timeout) failed to mount at early boot ("Dependency failed for /boot"), so `psci-efi-early.service` (RequiresMountsFor=/boot) did not run and test image 17 stayed as the live `boot.bin` (the normal kernel still booted). Mounted by hand and restored the PMP+EM default (sha 76f85089...). If this recurs, the restore has to be done by hand; consider a longer device timeout for /boot.
* Fixed `install.sh`: the "next_entry already set" check matched an empty `next_entry=` line and refused to arm. `run.sh` now defaults to 3 cycles with a 10 s RTC alarm.
* Armed `install.sh suspend` (image 17 = wake poll on ISR_EL1, 7.2.11-psci-efi+ with maxcpus=1, filesystems ro): each cycle sets an RTC alarm 10 s ahead and `echo mem`; expect elapsed ~10 s (alarm wakes Aura's poll) instead of the 30 s timeout. No hotplug involved. Rebooting now.

## 2026-11-03 (09:35): Phase 2b result 1, and a correction
* Run of image 17 (3 cycles, `echo mem` + `rtcwake -s 10`): all three returned rc=0, but after 30.8 / 35.0 / 30.8 s, i.e. Aura's 30 s timeout, not at the alarm. Cause: `/sys/class/rtc/rtc0/wakealarm` did not exist, so no alarm was ever armed.
* Correction of the 2026-11-03 morning note: upstream's PMU alarm (`rtc: macsmc: Add the PMU alarm`) is for T6030: it expects one control byte holding monitor/event/enable bits. T602x has them in three separate PMU registers (enable 0x1401 bit 6, event 0x14c0, mask 0x14c2), so the upstream driver found no `rtc_ctrl` cell and left the alarm off. My two skipped patches are still needed for J414s. Reverted the two upstream commits in `psci-efi-test-72` and re-applied mine (patches in `patches/psci-efi/linux/`). The DTB in image 17 already had the alarm cells (rebuilt image = same sha 42f22aae).
* Rebuilt 7.2.11-psci-efi+ (clean), restaged, reinstalled to /boot and /usr/lib/modules, re-armed `install.sh suspend`. Rebooting.
* Also seen: Wi-Fi firmware crash (brcmf_fw_crashed) around resume in these runs; to look at after the wake path works.

## 2026-11-03 (09:30): Phase 2b run 2: still no alarm, stale DTB (image 18)
* Run with the rebuilt kernel (alarm driver back): same 31 s timeouts, no `wakealarm`; the live DT's `rtc` node had only `rtc_offset`. Cause: `t6020-j414s-psci.dtb` is not in the kernel Makefile, so `make dtbs` never rebuilt it (stale from 00:24, older than the alarm cells), and image 17/rebuild embedded that stale file (hence the identical sha). Rebuilt it by hand (cpp + dtc, recipe in the kernel's own dtb rule) into image 18 (4efd4813...). Armed `suspend` again; rebooting.

## 2026-11-03 (09:45): Phase 2b run 3 (image 18): alarm armed and fires, Aura's poll does not see it
* wakealarm now exists (stale DTB fixed). Three cycles: alarm armed 10 s ahead (`alarm: <epoch>`), but each `echo mem` still took 31.3 s (Aura's 30 s timeout). The macsmc-rtc IRQ count was 3 after the three cycles (and +1 for a plain alarm on the running system), so the PMU alarm does fire and the kernel services it after resume; only Aura's ISR_EL1 poll never saw it.
* Suspicion: Linux runs at EL2 with E2H/TGE (VHE); with HCR_EL2.IMO/FMO effectively 1, ISR_EL1 reports the virtual pending state, not the physical one. Image 19 (8ef550e2...) records HCR_EL2, DAIF, exit reason, last ISR value and elapsed ticks in `psci_dbg[]` (ELF 0x1472c8), `run.sh` reads it back after each cycle through the new `mmio-read` helper (`/dev/mem` via dd/pread gives EFAULT; the mmap helper works). Armed `suspend`; rebooting.

## 2026-11-04 15:35: Phase 2b run 4 (image 19): debug words were zero (cache)
* Run (09:34, image 19): same 30.8 s timeouts; the `psci_dbg` words read back all zero. Aura writes them with its caches on and Linux reads through an uncached mapping, so the writes sat in Aura's cache. (The Mac then idled in the test boot until the owner/system rebooted it on 2026-11-04 15:29; `/boot` mounted fine this time but `boot.bin` was left as image 19, which I restored to the PMP+EM default.) Image 20 (b5cce3f0...): `dc cvac` on the words before the resume. Armed `suspend`; rebooting.

## 2026-11-04 15:45: Phase 2b run 5 (image 20): debug words still zero at base + 0x1472c8
* Run 15:31 (image 20, `dc cvac` on the words): 3 x ~30.8 s again; `psci_dbg` at base + 0x1472c8 still all zero. Checked the mapping: base + 0x0/0x10800/0x90000 equal the aura.bin bytes, so the runtime-code region is the image, but the `.data` GOT slot for `psci_dbg` (0x138b88, R_AARCH64_RELATIVE) reads 0 there too, so that copy looks unrelocated: Aura's live (relocated) copy may be elsewhere. A scan of the reserved DRAM ranges for Aura's first code words finds exactly one copy (the runtime-code one). Next: `scan-magic` (new, harness/mmio) searches reserved ranges for the 0xA0AA0001 magic after each suspend so run.sh finds the live words wherever they are. Armed `suspend` (image 20); rebooting.

## 2026-11-04 15:45: Phase 2b run 6 (image 20 + scan): found why the poll is blind
* `scan-magic` found Aura's live debug words (a different copy than the runtime-code region, so base + link offset was wrong): `HCR_EL2 = 0x488000038`, DAIF `0x3c0`, exit reason 2 (timeout), last ISR_EL1 0, 30 s of ticks (0x2aea5400 at 24 MHz). HCR_EL2 has E2H, TGE and **IMO, FMO, AMO set** (Linux at EL2, VHE), so ISR_EL1 reports the *virtual* pending state, not the physical one. That is why the alarm (which does fire, and which the kernel handles after resume) never ended the wait.
* Image 21 (bb145793...): the poll clears HCR_EL2.IMO/FMO/AMO first (psci_enter overwrites HCR_EL2 at resume anyway). Armed `suspend`; rebooting. Expect `elapsed` ~10 s and exit reason 1.

## 2026-11-04 15:50: Phase 2b run 7 (image 21): clearing IMO/FMO did not help; image 22 polls the AIC
* Image 21 (poll with HCR_EL2.IMO/FMO/AMO cleared): still 3 x ~31.8 s timeouts, ISR_EL1 still 0 (E2H+TGE probably keep the virtual view). Image 22 (see below) drops that and polls the AIC event register instead: a pending hardware interrupt (type 1) ends the wait; the event read acknowledges it, so Aura writes MASK_CLR for that IRQ to let the still-asserted line reach the kernel after resume. `psci_dbg[4]` = the event word, `[6]` = ISR_EL1. Expect `elapsed` ~10 s and event type 1 num 724 (the SPMI controller line; the kernel maps the RTC as SPMI IRQ 2 under it). Armed `suspend`; rebooting.

## 2026-11-04 16:40: Phase 2b run 8 (image 22): hang at `PM: suspend entry`; image 23
* Image 22 (AIC event poll): the machine hung right after `PM: suspend entry (deep)` (Pi kmsg ends there; it came back only at 16:30 after a manual/forced reset, nothing on disk). Cause, found by reading the code: with fast IPIs Aura does not put the AIC in the MMIO ranges it hands the kernel for the EFI runtime map (only PMGR), so the first AIC read in the handler faulted at EL2. Also the AIC2 event register is not at AIC_EVENT: it is the DT's second reg (core + 0xc000).
* Image 23: the AIC (core + event page, 0xd000 bytes) is now always in the runtime map, and the poll reads core + 0xc000 (`aic_poll_event`, AIC2 only). Armed `suspend`; rebooting. If this hangs too, the next step is to poll something already mapped.

## 2026-11-04 16:50: Phase 2b run 9 (image 23): no hang, but the AIC event page stays empty; image 24
* Image 23: the three `echo mem` cycles ran (no hang: the AIC mapping fixed the image-22 fault) but again ended at the 30 s timeout with `psci_dbg[4]` (event) = 0 and ISR 0: the AIC's AP event register never showed the alarm while Aura waited, although the kernel handles the alarm IRQ right after resume.
* Image 24 (adds to the debug words): `max_irq` and the first non-zero AIC2 HW_STATE words (index, value) at the end of the wait, non-destructive: tells whether any interrupt line is asserted at the AIC at all while the kernel is suspended (and which). Armed `suspend`; rebooting.

## 2026-11-04 16:55: Phase 2b run 10 (image 24): the AIC sees many lines asserted; image 25 looks at IRQ 724 only
* Image 24 (3 cycles, same 31 s timeouts): debug words show `max_irq` 0x1000 and non-zero HW_STATE words 9, 0xb, 0xe, 0xf, 0x11, 0x12, 0x13 (many unrelated lines asserted) before the list filled up (7 slots); word 22 (IRQ 724 = nub-spmi0, 22*32+20) was beyond it, so no conclusion yet.
* Image 25: records exactly IRQ 724's HW_STATE word (at ~0.5 s, before the alarm, and at the end), the mask word and the IRQ_CFG word. Armed `suspend`; rebooting.

## 2026-11-04 17:05: Phase 2b run 11 (image 25): why the AIC poll sees nothing; image 26 polls HW_STATE
* Image 25 words: IRQ 724's HW_STATE word was 0x8 before the alarm and 0x100008 at the end (bit 20 = IRQ 724 asserted: the alarm line does rise during Aura's wait), but its mask word reads 0xffffffff (all lines masked). Reason: the 7.2.11 AIC driver's syscore suspend (`aic_syscore_suspend`: save IRQ_CFG, `aic_mask_all`) runs for PSCI SYSTEM_SUSPEND, as it should for real S2R (macOS masks everything too), so the AP event register never reports it. On the running system word 22 = 0xffefc07f (bit 20 clear = unmasked), so the mask readback semantics are 1 = masked.
* Consequence for the design: in the real S2R the wake cannot come from an unmasked AIC line. The firmware side has to detect the wake from the PMU/SPMI/SMC side (alarm line in HW_STATE here, power key/lid via the SMC). The stub uses HW_STATE of IRQ 724 because it is non-destructive.
* Image 26 (HW_STATE bit 20 of word 22 newly set ends the wait). Armed `suspend`; rebooting. Expect elapsed ~10-11 s and exit reason 1.

## 2026-11-04 17:15: Phase 2b result: Aura wakes on the RTC alarm (image 26)
* Image 26, 3 cycles (`rtcwake -s 10` then `echo mem`): elapsed 11.18 / 10.81 / 11.14 s, exit reason 1 (wake line), `psci_dbg[4]` = 0x100008 (HW_STATE word 22 with bit 20, IRQ 724). The first real wake source for SYSTEM_SUSPEND works; resume is clean in dmesg (NVMe `saveCtx` shutdown ~0.4 s, PS pstates, tasks restarted; one `bluetooth hci0: parent should not be sleeping` warning in cycle 2).
* What it took: (1) T602x RTC alarm patches re-applied on 7.2.11 (upstream's alarm is T6030-only), (2) the PSCI DTB is not in the Makefile and had been stale, (3) Aura's EFI MMIO map lacked the AIC (image 22 hung at `PM: suspend entry`), (4) ISR_EL1 is blind at EL2 with IMO/FMO set, (5) the AIC is fully masked by the 7.2.11 syscore suspend, so Aura watches HW_STATE. Mind for the real S2R: the AIC will be powered down; the wake then has to come from the PMU/SMC side.
* Project board: Phase 2b item updated (In Progress), the finding added (Done). Estimate: about 33%.
* Next: power key/lid as wake sources (SMC mailbox lines), and what Aura must do instead of a busy wait: park the boot CPU in the deep WFI (the same state cpuidle uses) and wake on the alarm line, the first real power-saving step.

## 2026-11-04 17:30: image 27: hardware-watchdog safety net around SYSTEM_SUSPEND
* Why: a hang inside the handler (image 22) kept the Mac away for 42 min until someone reset it; further experiments (deep WFI instead of the busy wait) can hang too and an unattended recovery is the point. The NVMe has already done its clean shutdown (`saveCtx`) by then, so a hardware reset at that point does not lose data.
* Aura now arms the reset watchdog (WD1, the one `wdt_reboot` uses) for 120 s at SYSTEM_SUSPEND entry and disarms it right before resuming; the WDT registers are in the EFI runtime map (`wdt_psci_base()` is looked up when the ranges are built). Image 27 (the same alarm wake as image 26): expect 3 x ~11 s and no reset. Then a deliberate-hang image to prove the reset really happens. Armed `suspend`; rebooting.

## 2026-11-04 17:15: image 27 result, and the deliberate-hang test of the watchdog
* Image 27 (watchdog armed 120 s at entry, disarmed on exit): 3 cycles, elapsed 10.85 / 10.83 / 11.06 s, exit reason 1, no reset: the arm/disarm path is harmless.
* Found again: after that run `/boot/m1n1/boot.bin` was still the test image (the early restore did not run, `/boot` mounts late/fails sometimes); restored by hand.
* Now image 27-hang (3a4f7aa5...): identical, but after the wake it loops forever instead of disarming. Expected: the watchdog resets the machine ~120 s after entry, the Mac comes back by itself (normal kernel; the test image is restored by the early service or by me). If it does not come back, the watchdog does not work as a safety net on this SoC and the owner has to power-cycle. Armed `suspend`; rebooting.

## 2026-11-04 17:20: Wi-Fi guard; the 27-hang test did not run

- The `psci-test27-hang` boot did not complete the test: the psci-efi kernel booted at 17:08, but its run service was killed by a reboot (SIGTERM at 17:09:11, about a minute in, so a reboot from outside, not the watchdog) before any `run.log` was written. The next boots came up on the normal kernels, and `psci-efi-early.service` restored the default `boot.bin` (sha 76f850895fed53d1, checked). A suspend step then ran on the stock kernel with the hang image and correctly refused ("no deep sleep offered"). So the watchdog-reset proof is still open; it will be repeated.
- New request from the owner: reboot if Wi-Fi does not connect after boot. Added `harness/wifi-guard/` (`wifi-guard.sh`, systemd unit, `install.sh`), installed as `wifi-guard.service` (enabled, runs every boot). It waits until 120 s of uptime for a connected `wifi` device in NetworkManager, then reboots; it gives up after 3 failed boots in a row (counter in `/var/lib/deepidle/wifi-guard.count`, reset by any good boot), so a dead radio cannot cause a reboot loop; it logs to `/var/lib/deepidle/wifi-guard.log` including the Wi-Fi kernel lines. `touch /var/lib/deepidle/wifi-guard.off` disables it for deliberate Wi-Fi-off tests. First boot with it: connected at 243 s uptime check (log shows it passed).

## 2026-11-04 17:25: watchdog proof passed (image 27-hang)

- Second try of `psci-test27-hang`: the psci-efi kernel logged `suspend 1: echo mem ...` at 17:17:48. The Mac then stayed dead (no kernel logs) and the next boot began about 25 s after the 120 s mark (17:20), on the normal kernel: the hardware watchdog armed by Aura's SYSTEM_SUSPEND reset the machine when the handler hung, with no hand reset. This is the unattended recovery net for the S2R work.
- `psci-efi-early.service` restored the default `boot.bin` (sha 76f850895fed53d1; `/boot` mounted this time) and cleared `next_entry`. The Wi-Fi guard saw Wi-Fi connected at 45 s uptime on both later boots.
- `install.sh` BIN2 is back to image 27 (the good one, sha 2c1e32f120e35841). Next: replace the busy wait in Aura with a WFI wake under the same watchdog.

## 2026-11-04 17:45: image 28, WFI wake works (3/3)

- Image 28 (`psci-test28`, sha c3716af0e9cb815b): after the 500 ms ignore window, SYSTEM_SUSPEND masks DAIF, unmasks AIC IRQ 724 (the PMU alarm line), runs `wfi`, and on wake checks that HW_STATE for 724 newly asserted, re-masks 724 and returns to Linux. The 120 s watchdog stays armed throughout.
- Result: 3 of 3 cycles woke at the alarm, `rc=0`, elapsed 11.48 s / 10.77 s / 10.93 s (alarm 10 s + suspend work). Debug words: wake flag 1, exactly one `wfi` return per cycle (no spurious wakes), woke through WFI (flag 1), IRQ 724 masked again afterwards. So the AIC delivers the line to the boot CPU even with DAIF masked, and the busy wait is gone: the core now sleeps in WFI for the whole suspend.
- Still not a deep sleep (WFI only, no SoC power-down). Next: lid/power-key wake lines (SMC mailbox), then the deeper steps.

## 2026-11-04 17:50: image 29, WFI wake on two lines (alarm still 3/3)

- Image 29 (`psci-test29`, sha 858beeaece821076): SYSTEM_SUSPEND now waits in WFI with two AIC lines unmasked: 724 (PMU alarm) and 865 (SMC mailbox `recv-not-empty`, where the SMC reports key/lid events). A line already asserted before the wait is left masked (it would end every WFI at once). The debug word for the wake records which line woke it.
- Result with the RTC alarm only: 3 of 3 woke on line 724 (0x2d4), `rc=0`, 11.1 / 11.0 / 11.1 s, one WFI return each; line 865 stayed quiet, so it causes no false wakes.
- Open: whether a power-key or lid event really raises 865 during suspend. That needs a person to press the key during a long-alarm suspend (the owner; I cannot do it unattended). Wi-Fi and Bluetooth after resume are still the other open items.
- Project board: item added for the WFI wake (Done).
- Resume quality in image 29's three cycles: no `hci0` errors or timeouts and no Wi-Fi firmware crash after resume; the only Wi-Fi line is `brcmf_netdev_start_xmit: xmit rejected` while the stack is being suspended, which is harmless. The earlier Bluetooth/Wi-Fi problems were not reproduced, so they are parked rather than fixed.

## 2026-11-04 17:55: key wake works (owner at the Mac, image 29)

- With the owner present, a suspend with a 100 s RTC alarm backup was run by hand on the running test boot (`echo mem`, 20 s after the alarm was armed). The owner pressed the power key; the Mac resumed after 28 s, not 100 s, and the wake line recorded by Aura was 865 (0x361), the SMC mailbox `recv-not-empty` line, not the alarm line 724. `rc=0`, the system stayed up.
- So a power-key event wakes the WFI through the SMC mailbox line. Lid wake goes through the same SMC notifications and is expected to work the same way; it is not tested separately yet.

## 2026-11-04 18:15: image 30, suspend with the PMP on (3/3)

- Update from GH-10: its upstream PRs are posted (aurora-silicon/m1n1#63, linux#932 energy model, linux#933 DRAFT enable PMP on J414s); #933 says S2R with the PMP is not qualified. Per GH-10, #933 is updated only with the owner's OK, so nothing was posted from here.
- Image 30 (m1n1 image 87c6ecf96828bd9f): Aura with the PMP DT-headroom port and a PSCI DTB that includes the PMP. Test boot on the psci-efi kernel with the PMP running, 3 cycles with a 10 s alarm: all 3 returned `rc=0`. Cycle 1 woke after 3.5 s on line 865 (an SMC mailbox event, no key pressed; unexplained, probably an SMC notification at suspend), cycles 2 and 3 woke on the alarm line 724 at 11.5 s and 11.7 s. So the PMP being on does not break the suspend/WFI wake path.
- To report to the owner for #933: with the PMP on, the PSCI SYSTEM_SUSPEND stub plus WFI wake (alarm and SMC key line) works 3/3; real power-down is not attempted yet, so S2R with the PMP is still only qualified for this stub level.

## 2026-11-04 18:30: the real path (`systemctl suspend -i`) with the system-sleep hooks, image 30

- The owner asked me to check the sleep hook after their own sleep work. The only sleep hooks on the machine are `/etc/systemd/system-sleep/10-radio-power.sh` (Wi-Fi off and Bluetooth blocked before sleep, back on after) and `20-sep-bio.sh` (stops fprintd before sleep); neither was changed recently, and no other recent sleep, logind or Omarchy hook change was found. (If a different hook was meant, tell me which.) My earlier runs wrote `mem` to `/sys/power/state` directly and skipped them, so `run.sh` now has a flag file `/var/lib/deepidle/suspend-via-systemd` that makes each cycle use `systemctl suspend -i` instead.
- Image 30 on the psci-efi kernel with the PMP, 3 cycles, 10 s alarm, through systemd: all `rc=0`; the journal shows the hooks and `Performing sleep operation 'suspend'` / `System returned from sleep operation`. Cycle 1 woke early at 3.2 s (the same early SMC-line wake seen before in cycle 1); cycles 2 and 3 woke on the alarm line at 11.6 s and 11.7 s. After resume the radios were back (`nmcli radio` Wi-Fi and WWAN enabled, `rfkill`: bluetooth and wlan unblocked) and Wi-Fi was connected.
- Finding: after each resume brcmfmac logs `brcmf_p2p_set_firmware: failed to update device address ret -52` and `add iface p2p-dev-wlan0 ... failed: err=-52` (the P2P device is not created after the radio is turned on again). Wi-Fi itself works. Probably the same quirk as toggling the radio by hand, not specific to the PSCI suspend; not chased. No hci0 errors this time.
- The flag file is removed again; normal runs use `echo mem`.

## 2026-11-04 18:50: image 31 (deep WFI), and why the SMC line wakes early

- Image 31 (sha 2be4308831440462, PMP DTB): the WFI in SYSTEM_SUSPEND is now Aura's `deep_wfi()` (CYC_OVRD WFI_MODE 3, the core powers down with state retention; AIDR says retention is supported, CYC_OVRD was 0x2000000 before). 3 of 3 cycles came back `rc=0`, so deep WFI of the boot CPU works inside the EFI call. But all 3 woke early on line 865 (SMC mailbox), at 2.7 / 4.6 / 4.5 s, before the 10 s alarm.
- Cause, from the kernel log: about 1 s after every `PM: suspend entry` the SMC sends RTKit syslog messages (`aceElec.cpp:1162: Elec: Elec Cause 0x0`, then 0x8000 after resume). Those arrive on the same mailbox line as key events. macOS avoids this: its sleep path sends RTKit `SetAPPower` 0x201 (AP idle) to the SMC (hv-boot-trace-reference step 5).
- Next test (test kernel only, options on by default there): macsmc sends `SetAPPower` 0x201 in `suspend_late` and 0x20 in `resume_early` (no `slpa`), through a new exported `apple_rtkit_set_ap_power()`. Since the AP-idle message might make the SMC power the cores down, apple_wdt keeps WD1 armed at 120 s across suspend instead of stopping it, so a hang anywhere after device suspend resets the Mac (NVMe has already flushed by then).
- `/boot` fix: on the test kernel the NVMe appears after fstab's 5 s `x-systemd.device-timeout`, so `/boot` is not mounted and `psci-efi-early.service` (which needed it) never ran, leaving the test image on the ESP. The service now only needs `/var/lib/deepidle`, and `early.sh` waits up to 90 s for the ESP and mounts it. The ESP was restored to the default (76f850895fed53d1) by hand this time.
- The kernel build on the 1-CPU test boot was too slow; rebooted to the normal kernel to build.

## 2026-11-04 18:55: SetAPPower IDLE to the SMC across suspend (test kernel, image 31)

- Test kernel with the two test options (patch `patches/psci-efi/linux/0001-TEST-macsmc-SetAPPower-IDLE-...`): macsmc `suspend_late` sends RTKit `SetAPPower` 0x201, `resume_early` sends 0x20; apple_wdt keeps WD1 armed at 120 s across suspend.
- Result, 3 cycles with a 10 s alarm: all `rc=0`. Every SetAPPower was acked (`IDLE: 0`, `ON: 0`). The SMC did not power the cores down: without `slpa`, AP idle is only a state notice. Cycles 1 and 3 woke on the alarm line (12.0 s, 12.1 s); cycle 2 woke on the SMC line at 4.1 s. The `Elec Cause` syslog messages still come (some arrive just before the IDLE message, the rest are delivered at resume), so AP idle reduces but does not stop the SMC chatter.
- Side effect: with the AP marked idle, `apple_rtkit_is_running()` is false, so SMC key reads issued between suspend_late and resume_early fail (`Endpoint 0x20 is not running`, 281 lines in 3 cycles). Harmless here, but the real path must stop SMC users before AP idle.
- `/boot` fix confirmed: `psci-efi-early.sh: mounted /boot after 1s`, the ESP was back to the default (76f850895fed53d1) without a hand restore.
- For Phase 5: `SetAPPower` IDLE alone is safe; the trace's order (`slpa`, then SetAPPower 0x201 to the SMC and the PMP) means the core power-down is triggered by `slpa` or by the PMP message, not by the SMC's AP state.

## 2026-11-04 19:05: image 32 first try was not image 32

- The arm step for image 32 printed "Reboot when ready", but the test boot ran the default image (`booted m1n1 image 76f850895fed53d1`): the ESP copy had failed silently (most likely `/boot` was still read-only from the previous suspend run's remount). The default image offers PSCI too, and its SYSTEM_SUSPEND hung after `echo mem` (18:57:39). About two minutes later the Mac reset by itself and came back on the normal kernel: the test kernel's apple_wdt (armed at 120 s across suspend) did its job, since the default Aura arms no watchdog.
- Fixes: `install.sh` now checks the ESP sha after the copy and refuses to arm on a mismatch; `run.sh` refuses to suspend when the booted image is the default one. Re-armed image 32 (5e3c98aeae91a352, checked on the ESP).

## 2026-11-04 19:12: image 32 hung after power-down; image 33 (silent RVBAR path, staged watchdog)

- Image 32 really booted this time (5e3c98aeae91a352 on the ESP and in `run.log`). `echo mem` at 19:04:07, then nothing; the Mac reset by itself about 2.3 min later (next boot about 19:06:30, Wi-Fi at 24 s) and came back on the normal kernel with the default image restored. So the boot core powered down and either never woke, or woke and died on the way back.
- Suspect: the RVBAR path prints. `_cpu_reset_c()` calls `uart_puts()`/`printf()`, and `init_cpu()` prints the CPU part; with Linux in charge the UART block may be powered down, and `uart_putbyte()` spins on `UTRSTAT` TX-empty forever (or the access faults). The same prints sit on the secondaries' runtime CPU_ON path, which may also be what hung the old hotplug tests.
- Image 33 (eae3eb713ce16d3b): a `psci_runtime` flag, set on the kernel's first PSCI call (cleaned to PoC), makes `_cpu_reset_c()`, `init_cpu()` and the secondary park entry silent from then on. And the watchdog is staged so the time to the reset says how far it got: 120 s from SYSTEM_SUSPEND entry if the core never reaches C after RVBAR, 30 s from `psci_suspend_rvbar()` (so about 40 s after entry with the 10 s alarm), 45 s from just before `psci_enter()` (about 55 s) unless the kernel resumes and reprograms its own watchdog.

## 2026-11-04 19:20: image 33 also reset at 120 s; the cause is in start.S

- Image 33: `echo mem` at 19:11:03, next boot at 19:13:27 (`uptime -s`), so the reset came about 120 s after entry (firmware to kernel takes about 25 s): stage 0, the core never reached `psci_suspend_rvbar()`.
- Cause found in `start.S`: the RVBAR entry `cpu_reset` calls `debug_putc('O')` and `debug_putc('K')` before any C, and on T6020 `EARLY_UART_BASE` (0x39b200000) is defined, so `debug_putc` spins on the UART's `UTRSTAT` TX-empty bit. With Linux running and the UART powered down, that wait never ends. The C-level silencing in image 33 came too late. The secondaries' runtime CPU_ON path runs the same code, which fits the old CPU_OFF/CPU_ON hotplug hangs (CPU_ON at boot worked, when the UART was still up).
- Image 34: `debug_putc` returns at once when `psci_runtime` is set. Same staged watchdog as image 33.

## 2026-11-04 19:25: correction (image 34 = image 33), and image 35 (clean the image to PoC)

- Correction: image 34 came out byte-identical to image 33 (both eae3eb713ce16d3b). This Aura build sets no `TARGET`, so `EARLY_UART_BASE` is not defined and `debug_putc` was already empty: the UART was not the problem. Image 34's run (`echo mem` 19:17:08, next boot 19:19:32) is a repeat of 33: reset at about 120 s, stage 0 again.
- New suspect: after a power-down without retention, the RVBAR path runs with the MMU and caches off and reads DRAM directly. Aura's globals written with caches on (`boot_cpu_mpidr` for `is_boot_cpu()`, the watchdog base, the reset stacks, cpu state) may still be dirty in the L2, so the core reads stale values: with a stale `boot_cpu_mpidr` it takes the secondary branch and parks forever, which would match "never reaches stage 1".
- Image 35 (f6fd7043bb98615b): just before the power-down WFI, `dc civac` over the whole resident image (`_base` to `_end`, which is exactly the EFI runtime region Aura hands the kernel) plus the AIC struct.

## 2026-11-04 19:30: image 35 also at 120 s; image 36 timestamps the reset vector

- Image 35 (whole image cleaned to PoC): `echo mem` 19:23:26, next boot 19:25:51, so again a reset about 120 s after entry: stage 0. The cache clean did not change it.
- Image 36: the first instructions of `cpu_reset` (the RVBAR entry, MMU off) check `psci_resume.magic` and, if set, re-arm WD1 (hard-coded 0x29e2c4000 for this diagnostic) at 15 s. The C stages move to 50 s (`psci_suspend_rvbar()`) and 75 s (before `psci_enter()`). With the 10 s alarm, the reset comes about 25 s after entry if only the asm runs, about 60 s if C is reached, about 85 s if the kernel entry is reached, and 120 s if the core never comes back through RVBAR at all.

## 2026-11-04 19:38: image 36: the powered-down boot core never comes back; image 37 for the Phase 2 gate

- Image 36: `echo mem` 19:29:26, next boot 19:31:51: reset about 120 s after entry again, so not even the first instructions at RVBAR ran (they would have re-armed the watchdog to 15 s). Across images 32 to 36, a boot core powered down without retention (CYC_OVRD WFI_MODE 3 + DISABLE_WFI_RET) is not restarted by the AIC wake line. Aura's secondaries only ever come back from that state through an explicit PMGR CPU-start written by another core, so the boot core would need a helper core (or the SoC-level wake of real S2R). Parked: deep WFI with retention already powers the core down, and the real S2R path powers the whole AP off and wakes through a different route.
- Image 37 (094a529eceab50f9): deep WFI with retention again (as image 31), the RVBAR resume code kept as a backstop, the runtime-silent prints and image-wide PoC clean kept. With the SetAPPower kernel. Run: 20 cycles (new `/var/lib/deepidle/suspend-cycles`), 10 s alarm; `run.sh` now logs a summary line (cycles back with rc=0, device error lines after the first suspend, with the known SMC/P2P noise filtered). This is the Phase 2 gate (20 of 20, no device errors) on the boot CPU alone.

## 2026-11-04 19:45: image 37 hung on cycle 1; image 38 restores CYC_OVRD

- Image 37 20-cycle run: `echo mem` 19:35:59, no cycle came back, next boot 19:38:24: a reset about 120 s after entry (WD1, from Aura's SYSTEM_SUSPEND arm or the test kernel's apple_wdt). The ESP was back to the default by itself.
- Cause, from the diff against image 31 (which worked 3/3 with the same deep WFI): image 31 used `deep_wfi()`, which restores CYC_OVRD after the WFI. Image 37's inline WFI left WFI_MODE 3 set on return, so the kernel resumed with every idle WFI on the boot core turned into a deep WFI. That is the most likely hang.
- Image 38 (667e1478dc27a9f8): `psci_sleep_core()` saves CYC_OVRD, sets WFI_MODE 3 (retention on) for the WFI, and restores it afterwards. Otherwise the same as 37. Re-armed the 20-cycle gate (maxcpus=1, 10 s alarm, SetAPPower kernel).
- The owner approved the all-CPU suspend test (CPU offlining inside suspend). It comes after this gate.

## 2026-11-04 19:50: image 38 also hung on cycle 1; rerun image 31 as the baseline

- Image 38 (CYC_OVRD restored): `echo mem` 19:43:40, next boot 19:46:04: a reset about 120 s after entry again, on cycle 1. So the CYC_OVRD left set was not the cause.
- The Pi's kmsg stream ends at `Filesystems sync` in every hung run (Wi-Fi is down from device suspend on; in good runs the rest is delivered after resume), so it does not show where it hangs.
- Image 31's source was not saved (the WIP diff starts at image 32), but its binary is. Rerunning image 31 for the 20 cycles on the same kernel: if it passes, the hang is in Aura's changes since 31 (resident-image PoC clean, `psci_resume`/`psci_runtime` globals, the RVBAR stamp in `start.S`); if it fails, something outside Aura changed.

## 2026-11-04 19:55: Phase 2 gate passed on the boot CPU (image 31, 20 of 20); image 39

- Image 31 (2be4308831440462: deep WFI with retention through `deep_wfi()`, PMP DTB), test kernel with SetAPPower IDLE and apple_wdt armed across suspend, maxcpus=1, 10 s alarm: **20 of 20 cycles back with `rc=0`**, every one after 10.9 to 11.9 s (all woke on the alarm; no early SMC-line wake this time). The summary's "21 device errors" were false hits: 20 are `printk: Suspending console(s) (use no_console_suspend to debug)` (`BUG` matched `debug` case-insensitively), and one is the NVMe RTKit syslog line `Util_Reset_FailGeom Info`. With the filter fixed (`warning:` and `\bbug:`, and that NVMe info line dropped) the count is 0. **So the Phase 2 gate (20/20, no device errors, boot CPU only) passes.**
- So the hang in images 37 and 38 comes from Aura's changes after 31. The prime suspect is the clean-and-invalidate of the whole resident image (`_base` to `_end`) added in image 35: it is the only one that runs on every retention suspend (the RVBAR stamp and `psci_suspend_rvbar()` only run after a reset; `psci_runtime` only silences prints).
- Image 39 (0b01a740069f7fbb): image 38 without the whole-image clean (only `psci_resume` is cleaned). Same 20-cycle run. If it passes, image 39 becomes the base for the all-CPU test (approved by the owner today).

## 2026-11-04 20:05: image 39 also hung on cycle 1; image 40 stages the watchdog through SYSTEM_SUSPEND

- Image 39 (no whole-image clean): `echo mem` 19:57:57, next boot 20:00:21: the same reset about 120 s after entry on cycle 1. So the cache clean was not the cause either. What is left between 31 and 39: the inline WFI instead of `deep_wfi()` (the same CYC_OVRD value, though), the `psci_runtime` flag set on the first PSCI call, the `psci_resume` state global, and the start.S/print changes that only run after a reset.
- Image 40 (ae88fc60c8cc1e43): image 39 with the watchdog re-armed at each step, so the time from `echo mem` to the reset (minus about 25 s of firmware) says where it stops: 120 s, before or at SYSTEM_SUSPEND entry; 105 s, after the 500 ms wait; 95 s, in the WFI loop (no wake seen); 80 s, after the wake; 65 s, after the return to the kernel (the kernel's apple_wdt resume takes the watchdog back from there). With the 10 s alarm these are about 120, 105, 95, 90 and 75 s after `echo mem`.

## 2026-11-04 20:12: image 40: the boot core waits in the WFI loop and never sees the wake; image 41

- Image 40: `echo mem` 20:04:08, next boot 20:06:08: 120 s in all, so about 96 s to the reset after taking the ~24 s of firmware off. That is stage C: the core entered the WFI loop (watchdog re-armed to 95 s there) and never got to stage D (a wake line seen). So in images 37 to 40 the 10 s alarm never ends the wait, whereas image 31 saw it in all 20 cycles.
- Found while comparing: `psci_runtime` (0x147340) shared its 64-byte cache line with `psci_dbg`, and `psci_runtime_quiet()` does `dc ivac` on that line, which can throw away dirty data of its neighbours. It only runs on the reset paths, so it does not explain this hang, but it is wrong: `psci_runtime` now has a line of its own.
- Image 41 (5018f64068ce1f52): `psci_sleep_core()` calls `deep_wfi()` itself, exactly as image 31 did, plus the `psci_runtime` line fix; staged watchdog kept. Same 20-cycle run.

## 2026-11-04 20:16: image 41 passes 20 of 20; image 42 checks whether image 31's deep WFI was really deep

- Image 41 (5018f64068ce1f52: `deep_wfi()` as in image 31, `psci_runtime` on its own line, staged watchdog): **20 of 20 back with `rc=0`, 10.9 to 11.9 s each (all on the alarm), 0 device errors** with the fixed filter. The Phase 2 gate passes again, now on the current code base (source kept as `patches/psci-efi/aura/wip-system-suspend-image41.diff`).
- So the hang in 37 to 40 was the inline WFI. Its CYC_OVRD value was the same as `deep_wfi()`'s, but it had `dsb sy; isb` between the CYC_OVRD write and the `wfi`; `deep_wfi()` writes CYC_OVRD and goes straight to the `wfi` (a call and seven `stp`s later, no `isb`). A system register write is only guaranteed to take effect after a context synchronization, so a likely reading is that `deep_wfi()`'s WFI_MODE 3 does not reach the `wfi` in time and that WFI is a plain one (core clock-gated, wakes on the AIC line), while the synchronized one really enters the deep state with retention and is not woken by the AIC line with DAIF masked. This matters for the wording of earlier entries ("deep WFI works", image 31): that is not proven.
- Image 42 (b9a1adf0a10b0cac): `deep_wfi()`'s own sequence with one `isb` after the CYC_OVRD write. A hang at about 96 s (stage C) confirms the reading; 3 cycles only.

## 2026-11-04 20:22: image 42 passes too (the deep-WFI reading was wrong); first all-CPU suspend armed

- Image 42 (b9a1adf0a10b0cac: `deep_wfi()`'s sequence with an `isb` after the CYC_OVRD write): **3 of 3 back with `rc=0`** on the alarm (10.9 to 11.4 s), 0 device errors. So a WFI_MODE 3 that has surely taken effect still wakes on the AIC line, and the reading in the 20:16 entry was wrong. What still separates the hanging images 37 to 40 from 31/41/42: they had `dsb sy` right before the `wfi`, and the `wfi` was inline in `psci_system_suspend()` instead of inside `_deep_wfi_helper` (which pushes x18 to x30 first). Left open; the working sequence is kept.
- Next, approved by the owner today: **suspend with all 10 CPUs online** (no maxcpus=1). The kernel takes the nine secondaries offline through PSCI CPU_OFF before SYSTEM_SUSPEND and brings them back with CPU_ON after; since images 33+ Aura's RVBAR/CPU_ON path prints nothing at runtime. Safety: filesystems read-only for the run, NVMe is flushed in device suspend (before the CPUs go offline) and resumes only after they are back, the 120 s watchdog covers the whole suspend (Aura 65 s stage after the wake until the kernel's apple_wdt resume takes it back).
- New step `install.sh suspendall` (the same run on the `psci-efi-test-kernel` entry, all CPUs); `run.sh` logs the online CPU list after each cycle. Armed with image 42, 5 cycles, 10 s alarm.

## 2026-11-04 20:25: first all-CPU boot did not suspend: the early service ran three times

- The `suspendall` boot came up on the test kernel with all 10 CPUs (`online: 0-9`), but `run.sh` logged `booted the default image ... not suspending`. The journal shows `psci-efi-early.service` started and finished three times within 0.4 s (13.23 s, 13.39 s, 13.56 s): it was a oneshot without `RemainAfterExit`, so later units pulling it in ran it again, and the second and third runs read the image the first had already restored and wrote that sha into `/run/psci-efi-booted-sha`. So the test image most likely did boot; the check was fooled. On the 1-CPU boots it happened to run once.
- Fix: `RemainAfterExit=yes` on the unit, and `early.sh` exits at once if `/run/psci-efi-booted-sha` already exists. Re-armed `suspendall` (image 42, 5 cycles).

## 2026-11-04 20:35: all-CPU suspend, run 1 (image 42): hang before SYSTEM_SUSPEND; image 43 parks with retention

- With the early-service fix the `suspendall` boot really ran image 42 (`booted m1n1 image b9a1adf0a10b0cac`, `online: 0-9`). `echo mem` 20:24:40, next boot 20:27:05: about 121 s to the reset after the firmware's ~24 s, so it came from a 120 s arm (the kernel's apple_wdt at device suspend, or Aura's at SYSTEM_SUSPEND entry) and Aura never got to its 105 s stage after the 500 ms wait. So it died while the kernel was taking the nine secondaries offline, or right at SYSTEM_SUSPEND entry. NVMe had been shut down (`saveCtx`) before that point; nothing was lost (run.log is complete up to `echo mem`).
- Reading Aura's CPU_OFF park (`psci_park_c`): it set `CYC_OVRD_WFI_MODE(3) | CYC_OVRD_DISABLE_WFI_RET`, a power-down **without** retention. Today's images 32 to 36 showed such a core is not woken back into the loop, and on 2026-10-25 (image 11) a parked core restarted through RVBAR into the kernel by itself and took the SoC down. That fits the old hotplug deaths too.
- Image 43 (1fb3139b0056d98c): the park loop uses deep WFI **with** retention (`DISABLE_WFI_RET` cleared, an `isb`, then `_deep_wfi_helper`, the sequence that works for the boot CPU in image 42). Watchdog stamps, so the time to a reset says where it died (reset time after `echo mem`, firmware ~24 s included): CPU_OFF entered on core n (1 to 9): 20+2n s, so about 46 to 62 s; core n reported off by AFFINITY_INFO: 41+2n, about 67 to 83 s; SYSTEM_SUSPEND entry 115 (about 139 s), then its stages 105/95/80/65 as before (about 130/120/115/100 s); CPU_ON of core n after the wake: 140+2n (about 177 to 193 s); only the kernel's 120 s arm: about 144 s.
- Armed `suspendall` with image 43, 5 cycles.
- Correction (20:32): that arm went out with image 42 again: my line-number `sed` for BIN2 hit the BIN0 line, since the new `suspendall` comment had moved BIN2 down two lines. The boot came up on image 42; I stopped `psci-efi-run.service` before it suspended (empty results dir `...-suspendall-20261104-2030`), restored the BIN0 line, set BIN2 to image 43 and re-armed (`armed suspendall: boot.bin 1fb3139b0056d98c`). From now on BIN2 is set by matching `^BIN2=`, not by line number.

## 2026-11-04 20:42: all-CPU run 2 (image 43): dies at the first CPU_OFF; image 44 stamps inside it

- Image 43 really booted (`booted m1n1 image 1fb3139b0056d98c`, `online: 0-9`). `echo mem` 20:33:21, next boot 20:34:06: only 45 s, so about 21 s after the last stamp. That is the "CPU_OFF entered on core 1" stamp (22 s): the first secondary entered CPU_OFF, and neither its "reported off" stamp (AFFINITY_INFO, 43 s) nor the next core's CPU_OFF (24 s) came. So the very first CPU_OFF inside suspend takes the machine down, or stops the boot CPU before it asks AFFINITY_INFO. Parking with retention did not change that.
- (The 2026-10-25 runtime hotplug runs got past this point: `echo 0 > cpu1/online` gave `psci: CPU1 killed`; what differs inside suspend is not known yet.)
- Image 44 (009682316dd50c5d): one-shot stamps along core 1's CPU_OFF path. Reset time after `echo mem` (firmware included): CPU_OFF entered about 44 s; `OFF` state written 48; L1 cleaned 52; parked on the Aura stack 56; first return from the park WFI 60; the boot CPU asked AFFINITY_INFO and core 1 still read ON 64; core 1 reported off 68; a later core reported off 72; then SYSTEM_SUSPEND 139 and its stages as before.

## 2026-11-04 20:48: all-CPU run 3 (image 44): reset 45 s after `echo mem` again; image 45 spaces the stamps

- Image 44 booted (009682316dd50c5d, `online: 0-9`). `echo mem` 20:37:50, next boot 20:38:35: 45 s, which fits "core 1 entered CPU_OFF" (20 s stamp, about 44 s) and not "OFF state written" (about 48 s). Image 43 also gave 45 s with its CPU_OFF stamp at 22 s, so with stamps only 2 to 4 s apart the firmware-time spread (~1 s) makes the reading weak.
- Checked: the kernel maps Aura's whole image as one EFI Runtime Code region (0x100030b4000, 0x350000 bytes, WB, from the `efi=debug` memory map), so CPU_OFF's stores to `.data` (spin_table, psci_cpu_state) are mapped the same as the BSS words SYSTEM_SUSPEND already writes.
- Asked the owner (agent-notify) for one runtime hotplug test (filesystems read-only, `echo 0 > cpu1/online` once, Wi-Fi up so the Pi captures the kernel's messages); the hotplug ban stands until they answer.
- Image 45 (69fcd874787297a5): the same stamps 10 s apart: CPU_OFF entered 30 (about 54 s after `echo mem`), spin_table target cleared 40 (64), OFF written 50 (74), L1 cleaned 60 (84), parked 70 (94), first park WFI return 80 (104), boot CPU asked and core 1 still ON 90 (114), core 1 reported off 100 (124), a later core off 110 (134), SYSTEM_SUSPEND entry 115 (139).

## 2026-11-04 20:55: all-CPU run 4 (image 45): 45 s again, so the reset is not a stamp; image 46 + panic=0

- Image 45 booted (69fcd874787297a5). `echo mem` 20:42:22, next boot 20:43:07: 45 s once more, although its first stamp had moved from 20 to 30 s (which would give about 54 s). So the 45 s reset in runs 2 to 4 does not come from Aura's stamps at all. It fits a kernel panic: the test entry has `panic=10`, so a panic about 1 s into the suspend, 10 s of panic delay and the restart path give a reset about 20 s in (run 1 on image 42, without the park change, hung instead and waited for the 120 s watchdog).
- Strong candidate: Aura's CPU_OFF returns `PSCI_RET_DENIED` (when `smp_psci_index()` does not find the caller, or takes it for the boot CPU) *before* any of the core-1 stamps, and arm64's `cpu_die()` then hits `BUG()`.
- Image 46 (db1fb321a20f0bdc): the first CPU_OFF call stamps 30 s on entry, before the checks, and 50 s (index not found) or 70 s (taken for the boot CPU) when it is denied; the core-1 stamps from image 45 are kept. And `install.sh suspendall` now sets `panic=0` on the all-CPU GRUB entry only, so a panic hangs and the last stamp (or the kernel's 120 s apple_wdt) decides the reset. Expected after `echo mem`: about 54 s (entered, then died in a later step with no stamp), 74 s (index not found), 94 s (taken for the boot CPU), 64 s or later for the core-1 steps as listed for image 45.

## 2026-11-04 21:00: all-CPU run 5 (image 46, panic=0): CPU_OFF and the suspend work; it dies at CPU_ON on resume

- Image 46 with `panic=0`: `echo mem` 20:46:48, next boot 20:49:47: 179 s, so about 155 s after the last stamp minus firmware. That matches none of the CPU_OFF stamps (30 to 110 s) or SYSTEM_SUSPEND's, only the CPU_ON stamp (140+2n s, set about 11 s in, after the wake): CPU_ON of core 2 (or of core 1 a little later). So **all nine CPU_OFFs, the SYSTEM_SUSPEND wait and the alarm wake work with all CPUs**, and the failure is in bringing the secondaries back. The 45 s resets of runs 2 to 4 were `panic=10` reboots from a panic at that point (11 s + 10 s panic delay + firmware). The Pi has nothing after `echo mem` (Wi-Fi is still down at CPU_ON time).
- Found while reading the park exit: the park loop sets CYC_OVRD WFI_MODE 3 and jumped into the kernel without restoring it, so a re-onlined core ran Linux with every WFI forced deep, which a boot-time CPU_ON (Aura's own park, `deep_wfi()` restores it) never does.
- Image 47 (3d58cb83f8403b71): the park saves CYC_OVRD before setting WFI_MODE 3 and restores it (plus `isb`) before `psci_enter`. CPU_ON stamps are now 100+5n s for core n (reset about 140, 145, ... 180 s after `echo mem` for cores 1 to 9). Same 5 cycles, `panic=0`.

## 2026-11-04 21:05: **all-CPU suspend works: 5 of 5 (image 47)**; kernel fix for the preempt count; 20-cycle gate armed

- Image 47 (park restores CYC_OVRD before entering the kernel), `suspendall`, 10 s alarm: **5 of 5 cycles back with `rc=0` and `online 0-9`**, 12.9 to 13.0 s each (about 2 s more than the 1-CPU runs: offlining and re-onlining nine CPUs). Every cycle: nine `psci: CPUn killed (polled 0 ms)` and nine `CPUn: Booted secondary processor` (45 of each). So the fix for the all-CPU failure was CYC_OVRD: re-onlined cores inherited WFI_MODE 3 from the park and the kernel died on them.
- The summary counted 95 device errors, of two kinds:
  - 45 × `BUG: scheduling while atomic: swapper/N/0/0x00000002`, once per secondary per cycle. A successful CPU_OFF never returns through `arm64_efi_psci_call()`, so the `preempt_disable()` in `efi_virtmap_load()` is never undone and the idle task of the re-onlined CPU starts with one extra preempt count (the same class as the SYSTEM_SUSPEND unwind fixed earlier for the boot CPU). Kernel fix (`patches/psci-efi/linux/0001-arm64-efi-drop-the-virtmap-preempt-count-across-a-PS.patch`): for CPU_OFF, `preempt_enable_no_resched()` before the handler (IRQs are masked on the dying CPU) and `preempt_disable()` again only if it returns. Built (27 s on the 10-CPU test boot) and installed as `/boot/vmlinuz-psci-efi-test` (the previous one kept as `/var/lib/deepidle/vmlinuz-psci-efi-test.pre-cpuoff`).
  - 50 × `IRQ132/134/145/146: set affinity failed(-38)` while CPUs go offline: these are PCIe MSI vectors (root-port PME/AER, brcmfmac, bcm4377), and the Apple PCIe MSI controller has no per-IRQ affinity, so `-ENOSYS` is expected on any CPU offline. Added to the summary's known-noise filter.
- Armed the gate: `suspendall`, image 47, fixed kernel, **20 cycles**, `panic=0`.

## 2026-11-04 21:10: **all-CPU suspend gate passed: 20 of 20 (image 47 + CPU_OFF preempt fix)**

- `suspendall`, image 47 (3d58cb83f8403b71), test kernel with the CPU_OFF preempt-count fix, PMP on, 10 s alarm, `panic=0`: **20 of 20 cycles back with `rc=0`, `online 0-9` after every one**, 12.9 to 13.2 s each. Nine CPUs offlined (CPU_OFF into Aura's retention park) and brought back (CPU_ON) per cycle, 180 of each.
- Device errors after the first suspend: **0**. No `scheduling while atomic` any more (the kernel fix works); the only other lines are the known PCIe MSI `set affinity failed(-38)` (the summary still counted them as 200 because the new filter entry had unescaped parentheses in `grep -E`; fixed).
- With this, Phase 2 is complete on the full system: PSCI SYSTEM_SUSPEND through EFI, boot CPU in deep WFI with retention, wake on the PMU alarm (and the SMC key line, tested earlier), and all secondaries through CPU_OFF/CPU_ON. What it is not yet: S2R proper. The SoC and DRAM stay up; the power saving is only the CPUs in deep WFI and the devices' own suspend.
- What made it work, in order: retention instead of non-retention deep WFI for every parked core (images 41/42/43), CYC_OVRD restored before a core goes back to the kernel (image 47), `panic=0` plus watchdog stamps to find where it died, and the kernel's preempt count across a non-returning CPU_OFF.

## 2026-11-04 21:15: status.md updated; the real path on all CPUs armed

- `docs/status.md` brought up to date (Phase 2 done on the full system, about 45%). Owner told (agent-notify) that the hotplug approval is no longer needed, and given the #933 draft (`docs/gh933-s2r-draft.md`, not posted).
- Next run: the user's path, `systemctl suspend -i` with the system-sleep hooks (flag `suspend-via-systemd`), all 10 CPUs, image 47, 20 cycles.

## 2026-11-04 21:20: the real path on all CPUs: 20 of 20

- `systemctl suspend -i` (system-sleep hooks: radios off/on, fprintd), all 10 CPUs, image 47, fixed test kernel, 10 s alarm: **20 of 20 suspends, `online 0-9` after each, 0 device errors**; 20 `PM: suspend entry (deep)` in the log; Wi-Fi reconnected after the run, rfkill unblocked. About 13.5 to 14 s per cycle.
- Harness quirk: in cycle 1 `systemctl suspend -i` returned at once (0.67 s, the job was queued) and the suspend ran just after the "back" line; cycles 2 to 20 waited normally. Harmless for the result; noted.
- A drain measurement is not possible right now: the Mac is on AC and the battery reads "Not charging" at 99%, so `charge_now` does not move. It needs the charger unplugged (owner), and it is only worth doing once SoC sleep steps exist; for now the SoC stays up as in s2idle.
- The `suspend-via-systemd` flag is removed again.

## 2026-11-04 21:25: image 48, the clean build of image 47

- Image 48 (afaef3840b21e459): image 47 without the diagnostic watchdog stamps (CPU_OFF, park, AFFINITY_INFO, CPU_ON and SYSTEM_SUSPEND stages B to E). SYSTEM_SUSPEND keeps one safety arm, 120 s from entry, disarmed again on the wake (as in image 31); the RVBAR backstop path keeps its own. With the stamps, image 47 re-armed the dog to 95 s for the wait, which would have reset any suspend longer than that. Still test-only: both this 120 s arm and the test kernel's apple_wdt `suspend_timeout=120` cap a suspend at two minutes; real use needs both off.
- Run: `suspendall`, 20 cycles, `echo mem`, 10 s alarm.

## 2026-11-04 21:30: image 48 (clean) passes 20 of 20 on all CPUs

- Image 48 (afaef3840b21e459), `suspendall`, `echo mem`, 20 cycles: **20 of 20 back, `online 0-9` after each, 0 device errors**. Image 48 is the Phase 2 reference image from here on (source: `patches/psci-efi/aura/wip-system-suspend.diff` at this commit).

## 2026-11-04 21:40: Phase 2 closed; the first real SoC sleep (slpa) is prepared and waits for the owner

- Phase 3's trace (2026-10-25, `docs/hv-boot-trace-reference.md`) already gives macOS's sleep entry: `MBSE=slpw`, the PMP display-domain handshake, `MBSE=slpa`, `SetAPPower 0x201` to the SMC and PMP, `SetIOPPower`, CPU stops, PCPM clears, deep WFI. The next step is to send those keys inside a real suspend, which the standing rule ("no slpa") and the plan (owner at the power key for the first cycle) hold back. Asked the owner (agent-notify): lift "no slpa" for one guarded boot, be at the Mac, ideally unplug the charger for a drain reading.
- Prepared, switched off: test kernel `macsmc-reboot.deep_steps` (patch `0001-TEST-macsmc-reboot-deep_steps-...`), the existing s2idle handshake (1 WKTP, 2 slpw, 4 slpa + waka on wake) for suspend to RAM; default 0, so nothing changes until a boot's command line sets it. The module is installed for 7.2.11-psci-efi+ (old one kept as `/var/lib/deepidle/macsmc-reboot.ko.pre-deepsteps`). Order fits macOS: macsmc-reboot is a child of macsmc, so its suspend_late (slpa) runs before macsmc's SetAPPower IDLE.
- Plan for that boot: image 48, `suspendall`, `macsmc_reboot.deep_steps=6` (slpw + slpa), 1 cycle, alarm wake, owner at the power key. Unknowns it answers: does the SMC take the SoC down at all without the PMP's PCPM clears; if it does, does the boot CPU come back through RVBAR (Aura's RVBAR resume path is still in image 48), and is DRAM kept.
- Test kernel base checked: the 7.2.11 line of Aurora (contains tag aurora-2026.10.17.20), the same line as the installed default `linux-aurora 7.2.11.aurora14-1`. Aurora's `integration/aurora` has since moved to 7.3.0; not followed, since the handoff names 7.2.11.aurora14 as current.
- Nothing armed now: no `psci-efi-armed`, no GRUB `next_entry`, the default boot.bin (76f850895fed53d1) on the ESP.

## 2026-11-04 21:30: slpa safeguard lifted by the owner; first real-sleep test armed (owner at the Mac)

- Owner: "Safeguard for slpa lifted permanently, I am at the Mac." (memory updated.)
- Armed: image 48, `suspendall` (all CPUs), `macsmc_reboot.deep_steps=6` (MBSE=slpw in prepare, MBSE=slpa in suspend_late, wake: read MBSE/MBSW, MBSE=waka) on the test GRUB entry via the new flag file `/var/lib/deepidle/deep-steps`, 1 cycle, 10 s alarm, `panic=0`. `run.sh` now logs battery status/charge and the macsmc sleep/SetAPPower lines around each cycle.
- Owner told: if no notification from me and no reboot by 21:37, long-press the power key ~10 s, then press it again to boot.

## 2026-11-04 22:00: first `slpa` in a real suspend: no SoC sleep, NVMe dead, reset by hand

- Run: image 48 (afaef3840b21e459), `suspendall`, `macsmc_reboot.deep_steps=6`, 1 cycle, 10 s alarm, `panic=0`. `run.log` ends at `suspend 1: echo mem ...` (21:32:22, battery "Not charging", 5107000, on AC). Linux booted again at 21:47:10, about 15 min later.
- The owner's photo of the screen: the kernel was running at uptime 796 to 873 s (about 21:44 to 21:46) and printing `BTRFS error (device dm-0 state EA): run_delalloc_nocow failed ... -5`, `bdev /dev/mapper/root errs: wr 26, rd 96..101`, and journald `Read-only file system`. So the cycle came back into Linux (the console was on), but NVMe was gone, as it was after `slpa` in s2idle. `run.log`, the "back" line and the wake's `MBSE`/`MBSW`/`waka` lines could not be written. The owner reset the Mac by hand.
- No watchdog fired, because the kernel was alive: Aura disarms its 120 s arm on the wake and apple_wdt resumes normally. Unattended `slpa` runs need a dead-man switch tied to the disk.
- Damage check on the next boot: `btrfs device stats /` all 0 (the failed writes never reached the disk, and the error state stopped further commits), and a read-only scrub of all 124 GiB found no errors.
- Reading: with all CPUs in Aura and the boot core in deep WFI, `slpw` + `slpa` alone do not make the SMC take the SoC down. In macOS's trace, `slpa` is followed by `SetAPPower 0x201` to the SMC **and** the PMP, `SetIOPPower`, the CPU stops and the PCPM0/PCPM1 clears before the cores' deep WFI. Not known yet: whether the SMC waits for the PMP's report, or for a PMGR step.
- Owner: "For the night, let's hold off on those. We can resume those when I am ready to manually reboot again." `/var/lib/deepidle/deep-steps` removed; memory updated. Default image 76f850895fed53d1 on the ESP.
- Status page: `docs/s2r-status.json` brought up to date (images 37 to 48 and this run, Phase 1 at 85%, Phase 2 done, Phase 5 active at 10%); overall 45% in both it and `status.md`. Added `tools/s2r-status-fmt.py`, which rewrites the JSON in its house style (one object per line).

## 2026-11-04 22:10: a dead-man switch for `slpa` runs; read-only mode; PMU cells logged

- Why nothing reset the Mac in the `slpa` run: systemd feeds the hardware watchdog (`RuntimeWatchdogUSec=1min`), and the kernel stayed alive with the disk gone. The Pi watcher could not help either: the Pi (`pi-hole` on Tailscale) is offline.
- New `harness/psci-efi/deadman.sh`, started by `run.sh` before each `echo mem` and run from `/run` with its own copy of `dd`. When `run.sh` marks the wake, it reads one 4 KiB block of `/dev/nvme0n1` with `iflag=direct` (three tries, 10 s each). If no read succeeds, or there is no wake marker after the alarm time plus 300 s, it:
  - collects the SMC sleep, PM, NVMe and first btrfs lines from `/dev/kmsg`;
  - pushes them to the owner's ntfy topic over plain HTTP, using bash's `/dev/tcp` and the address resolved before the suspend;
  - prints them on the console;
  - resets the Mac with sysrq `s`, `u`, `b`. If the restart handler hangs, systemd stops feeding the watchdog and it resets the Mac about a minute later.
  Dry runs on this boot: disk OK; a forced failure (push answered `200 OK`); and a missing marker. Caveat from October: a warm reset may not bring NVMe back after `slpa`, so the push is the part that surely helps.
- For `slpa` runs (`deep_steps` bit 4) or with the flag `/var/lib/deepidle/force-ro`, `run.sh` forces every filesystem read-only (sysrq `u`) before the cycles and logs to `/run` meanwhile. The normal remount fails while the desktop holds files open, which is why btrfs was still writable when the disk vanished.
- `run.sh` logs the PMU's `spmi_nvmem` cells on each armed boot (boot stage, error counts, shutdown flag, `fault-shadow`), to learn how each boot ended. On the boot after the hand reset: `boot-stage=30`, error counts 0, `shutdown-flag=00`, `fault-shadow=1012000000…`.
- Armed: image 48, `suspendall`, 3 cycles, 10 s alarm, `force-ro`, no `slpa`. It tests the dead-man switch's OK path and the read-only round trip in a real suspend.

## 2026-11-04 22:15: the watcher did catch the `slpa` cycle: the SMC cuts the storage controller’s power; dead-man switch 3 of 3

- Correction to the 22:10 entry: the watcher is not on the old `pi` alias. It runs on `core-node-ts` and has streamed the Mac’s kmsg since 2026-11-03 (`pi-watch.sh status`: running, Mac up). Its log has the whole `slpa` cycle of 21:32:
  - Entry: `MBSE = slpw (0)`; NVMe `shutdown start ... saveCtx 1 took 412 ms`; `MBSE = slpa (0)`; `SetAPPower IDLE: 0`; nine `psci: CPUn killed`. Then SYSTEM_SUSPEND, a wake, and `Enabling non-boot CPUs`, all nine back.
  - Wake: `SetAPPower ON: 0`; `sleep: wake MBSE 00010730 (0), MBSW 0000000000000000 (8); MBSE = waka (0)`. So `waka` is acked, and `MBSW` cannot be read (SMC error 8).
  - Then `nvme-apple: RTKit: IOP power acknowledgment failed: -62`, `ANS did not boot`, `nvme0: Reset failure status: -62`, and btrfs errors from 72.8 s. The transaction aborted and root went read-only at once (`forced readonly`), so nothing reached the disk after that.
- So **after `slpa` the SMC takes the storage controller’s power away, and `waka` from a running kernel does not give it back**. The ANS never acks its power-on. The rest of the system (CPUs, Wi-Fi, display) comes back normally. This also explains October’s s2idle run.
- In macOS the next step after `slpa` is the SoC power-down, and the wake comes from the SMC’s own sequence. Next `slpa` experiment: send the PMP its `SetAPPower 0x201` and `SetIOPPower 0x201` after `slpa`, as the trace does (under the hypervisor, step 5 is what took the cores down). If the SoC really powers down, the wake path is the open question (Phase 3 unknown).
- Test run (image 48, `suspendall`, 3 cycles, `force-ro`, no `slpa`): **3 of 3 back, `online 0-9`, dead-man switch `disk ok after resume (try 1)` every cycle**, 15.8 s each. `sysrq: Emergency Remount R/O ... complete`, and rw again afterwards.
  - The harness’s read-only count read per-mount flags (always `rw` after sysrq `u`). It now reads superblock options.
  - The PMU cells come from `spmi_nvmem0` on the test kernel (`spmi_nvmem2` on the default). `run.sh` now globs for it.
  - The 3 “device errors” were the dead-man’s own `timeout` lines and Wi-Fi `join_pref -52`, now filtered.
  - `fault-shadow` reads `1012…` after the hand reset and after a normal reboot alike, so it does not tell them apart.

## 2026-11-04 22:20: image 49 (watchdog heartbeat for long sleeps); test kernel with `macsmc.pmp_sleep` (off)

- Every suspend so far was capped at about two minutes, and not only by choice. WD1 counts a 32-bit value at 24 MHz, so it cannot be armed for more than about 178 s. Image 49 (391648c0e69c7d80) adds a heartbeat to `psci_system_suspend()`:
  - It arms the EL2 physical timer (CNTHP; Linux runs on the EL2 virtual timer) for 60 s.
  - A wake that is not a wake line, once the time has passed, re-arms the dog (120 s) and the timer, counts in `psci_dbg[16]`, and sleeps again.
  - The timer’s CTL and CVAL are restored before the return to the kernel.
  If Aura stops running, nothing re-arms the dog and the Mac resets as before. Source: `patches/psci-efi/aura/wip-system-suspend.diff` (image 48’s is in git at the image 48 commit).
- Test kernel rebuilt and installed (old Image, `macsmc.ko` and initramfs kept as `/var/lib/deepidle/*.pre-pmpsleep`), patch `patches/psci-efi/linux/0001-TEST-macsmc-pmp_sleep-...`. New option `macsmc.pmp_sleep` (default off): in suspend to RAM, right after the SMC’s `SetAPPower IDLE`, send the PMP `SetAPPower 0x201` and `SetIOPPower 0x201` (RTKit IDLE), and wake it after `SetAPPower ON`. That is macOS’s step 5 after `slpa`. It is staged for the next `slpa` run, which waits for the owner.
- `run.sh` takes the alarm from `/var/lib/deepidle/suspend-alarm`. Armed: image 49, `suspendall`, 2 cycles, **300 s alarm**. Without a working heartbeat the dog resets the Mac about 120 s in; with it, both cycles come back after about 300 s with `psci_dbg[16]` at 4 or 5.

## 2026-11-04 22:30: image 49’s heartbeat works (2 of 2 at 305 s); first drain A/B on battery armed

- Image 49, `suspendall`, 300 s alarm: **2 of 2 back after 305.3 s and 306.0 s, `online 0-9`, 0 device errors, dead-man switch OK both times**. `psci_dbg[16]` (heartbeats) is 4 in each cycle and `psci_dbg[12]` (WFI returns) is 5: one 60 s timer wake per minute, then the alarm. Before image 49 the dog would have reset the Mac at 120 s. **Suspends are no longer capped at two minutes.**
- On battery without unplugging: `charge_control_end_threshold` 20 (start 15) alone leaves the Mac on AC (“Not charging”). `charge_behaviour` = `auto-discharge` (the SMC’s CHLS force-discharge bit, down to the limit) does it: status “Discharging”, 1.92 W awake (headless, screen off). **To restore: `auto`, end 80, start 75.**
- `run.sh` can run several modes in one boot (`/var/lib/deepidle/sleep-modes`) and logs `energy_now` around each cycle with the average watts. For s2idle the test kernel’s apple_wdt suspend arm is set to 0 (nothing pets the dog in s2idle) and back to 120 afterwards.
- Armed: image 49, all CPUs, test kernel (`pmp_sleep` off), modes `deep` then `s2idle`, 2 cycles of 30 min each. Same kernel, same boot, so the A/B shows what Phase 2’s suspend (every CPU in Aura’s deep WFI, `SetAPPower IDLE` to the SMC) saves over s2idle before any SoC sleep.

## 2026-11-05 06:30: drain A/B on battery: suspend to RAM 1.37 W, s2idle 1.39 to 1.41 W

- Image 49, all CPUs, test kernel (`pmp_sleep` off), `charge_behaviour` = `auto-discharge` (status “Discharging” with the charger in). Four cycles of 30 min, **4 of 4 back, `online 0-9`, 0 device errors, the dead-man switch `disk ok after resume (try 1)` every time**. Heartbeats kept the dog fed through every 30 min `deep` cycle.
- From `energy_now` before and after each cycle:

  | Cycle | Energy (µWh) | Average |
  |---|---|---|
  | `deep` 1 | 58436400 → 58037400 | 0.796 W |
  | `deep` 2 | 58037400 → 57353400 | 1.365 W |
  | `s2idle` 1 | 57330600 → 56635200 | 1.390 W |
  | `s2idle` 2 | 56601000 → 55894200 | 1.413 W |

- The first `deep` cycle does not count. It started at 58436400 of 58493400 µWh (a full battery, discharge switched on a minute earlier), and `charge_now` fell only 35 mAh against 60 to 62 mAh in the other three. The gauge seems to hold near full.
- So **suspend to RAM with every CPU in Aura’s deep WFI saves about 0.03 to 0.05 W over s2idle**, within the noise. That fits the plan: in s2idle the CPUs already sit in their deepest idle state, and the SoC, DRAM and devices stay up in both. The 1.1 W gap to macOS’s 0.24 W is the SoC sleep (Phase 5), which needs `slpa` and the steps after it.
- Log: `data/drain-ab/2026-11-04-image49-deep-vs-s2idle.log`.

## 2026-11-05 06:40: what `slpa` takes from the storage controller: a register snapshot for the next run; issue #9 answered

- `ps_ans2` holds the ANS, its mailbox and its SART (`34bc50000`). genpd’s idle stats show it switched off 4 times this boot, once per suspend, and NVMe came back every time: the driver resets the ANS, sets RUN and boots RTKit again. So the PMGR gate alone keeps what the ANS needs (the SART entries, the firmware in DRAM). `slpa` must take away more, perhaps the rail.
- The dead-man switch now takes a read-only snapshot after every wake, from a static `mmio-read` in `/run`. It reads `ps_ans2` (PMGR `0x28e0801a8`), and then, only if the domain reports on, the ANS `CPU_CONTROL`/`STATUS`, the mailbox `A2I`/`I2A_CONTROL`, and the SART’s 16 config and 16 address words. On a normal wake it goes to the log. On a failure it is pushed after the kernel lines, before the reset. Baseline now: `ps_ans2 1f0000ff`; ANS cpu `00000010 00000028`; mailbox `00020001 00020001`; 8 SART entries (config `ff ff ea ff ff ea ff ff`). Both paths were tested dry.
- If the snapshot after `slpa` shows the SART cleared while `ps_ans2` is on, the fix to try is a SART save at suspend and a restore before NVMe’s reset (the Linux SART driver has no suspend or resume today). If `ps_ans2` itself reads off, the next step is the PMGR side.
- `install.sh` takes a flag file `/var/lib/deepidle/pmp-sleep` that adds `macsmc.pmp_sleep=1` to the test entry. `run.sh` treats that like `slpa` (root read-only before the suspend). Note for that run: the PMP wake from IDLE failed 0 of 3 on 10-23, so expect the PMP to stay down after the wake unless the SoC really powered down. Nothing is armed.
- Issue #9 (CoreyH, M1 Pro J314s, same Maverick PMU): answered with the owner’s OK. Yes to porting the RTC alarm upstream, the license terms from the README (GPL-2.0 patches, `GPL-2.0+ OR MIT` DTS), the two alarm patches (the fired-bit fix included), the drain A/B, the `slpa` warning and a link to this page.
- Battery back to `auto`, 80/75.

## 2026-11-05 06:50: SART save and restore in the test kernel; short test boot armed (no `slpa`)

- Test kernel patch `patches/psci-efi/linux/0001-TEST-soc-apple-sart-save-the-entries-at-suspend-rest.patch`: the SART driver saves all 16 entries in `suspend_noirq` (before genpd can gate `ps_ans2`). In `resume_noirq` (after genpd powers it back, before NVMe’s reset in the resume phase) it compares them, logs the first changed entry, restores any that changed, and logs `entries kept across suspend` otherwise. A normal wake should log “kept” and write nothing. After `slpa`, the same line answers the SART question, and the restore tests the fix in the same run.
- New Image installed as `/boot/vmlinuz-psci-efi-test` (a6c7ebd748545320, old one in `/var/lib/deepidle/vmlinuz-psci-efi-test.pre-sart`), staging updated. Modules unchanged.
- The dead-man snapshot also reads the SART’s 16 size words (v3 layout: config `0x00`, address `0x40`, size `0x80`).
- Armed: image 49, `suspendall`, no `slpa` flags, modes `deep` and `s2idle`, 2 cycles each, 120 s alarm. Expect 4 of 4 back, `entries kept across suspend` 4 times, and identical snapshots.

## 2026-11-05 06:50: SART save and restore: a no-op on normal wakes (4 of 4)

- The test boot came up as planned (06:38, `reboot.sh`, headless ACTIVE, watcher running; the default boot.bin was back early in the boot). Image 49, `suspendall`, no `slpa`, 120 s alarm.
- **4 of 4 back** (`deep` 122.3 and 122.4 s, `s2idle` 121.0 and 120.4 s), `online 0-9`, 0 device errors, the dead-man switch `disk ok` every time.
- `apple-sart 34bc50000.sart: entries kept across suspend` 4 times, no `changed` line, so nothing was written. The restore costs nothing on a normal wake.
- The dead-man snapshots match every cycle (`ps_ans2 1f0000ff`; ANS cpu `00000010 00000028`; SART entries 0 to 5 the same), except **SART entries 6 and 7, whose addresses change every cycle** (`10180dbc`/`1016ced0`, then `100a55b0`/`1000ed44`, …). Those are the NVMe driver’s own RTKit buffers, freed and requested again by its reset after each resume. That happens after `resume_noirq`, so the SART patch does not see them as lost. Entries 0 to 5 (iBoot’s firmware windows) are the ones that matter after `slpa`.
- The energy figures read 0 W: the Mac was on AC at the 80% limit (“Not charging”), so this run says nothing about power.
- Ready for the next owner-attended `slpa` run. It now logs whether the SART was cleared (and restores it), and the dead-man snapshot shows the ANS and PMGR state if the disk still fails.

## 2026-11-05 07:10: macOS writes the ANS SART back on every ANS start (13.5, static)

- ADT (13.5, J414s): `ans` has `ignore-gating` and `power-gates = None`, so macOS never gates the ANS power itself. Its `iop-ans-nub` has `shutdown-sleep` (a full RTKit shutdown for sleep, as Linux does), `quiesced`, `cold-boot-after-hibernate` and `power-managed = 1`. `iommu-parent` is 207, `sart-ans` (`sart,coastguard`, `sart-version = 3`, `0x14BC50000`).
- `AppleA7IOP::_setMapperActive(b)` calls the mapper’s `callPlatformFunction("setActive", …, b)`, and `startCPUWithOptions` calls it with 1 (10-23 notes). For the ANS that mapper is `IOSARTMapper`. Its `_setActive(true)` (`fffffe000994652c`, disassembled now into `dis/AppleSART.s`, not committed):
  - first time: copies the 16 `CONFIG` words (`+0x00`) and the 16 `PADDR` words (`+0x40`) from the hardware into the object (`+0x140`, `+0x100`) and sets a flag;
  - every later time: writes both arrays back to the hardware;
  - `_setActive(false)` only records the state and writes nothing.
- So **macOS rewrites the SART every time it starts the ANS**. That is the step Linux was missing after `slpa`, and the test kernel’s SART patch does the same (it also restores the size words at `+0x80`, which macOS leaves alone). It also explains why the PMGR gate alone never hurt: the gate keeps the SART, and deeper sleep evidently does not.
- The SART windows the ANS uses (from the snapshot, `paddr << 12`): entries 0 and 1 at `0x2a2414000` and `0x2a2434000`, inside the SMC’s ASC block (ADT `smc` at `0xA2400000`, size `0x6C000`); entry 2 at `0x29e2cc000`, one of the `apcie` node’s registers (ADT `0x9E2CC000`, size `0x2100`); entries 3 to 7 in DRAM.
- iBoot (`iBoot.j414s.RELEASE.bin` from the IPSW) is encrypted (entropy 8.0 bits a byte), so what iBoot does on an S2R wake cannot be read from it.
- Next `slpa` run (owner-attended), expected outcomes: `apple-sart: N entries changed across suspend, restored`, then the ANS boots. If it still does not, the dead-man snapshot shows the ANS CPU and mailbox state for the next step.

## 2026-11-05 07:25: armed: one 2 h suspend to RAM on battery (the long-sleep check)

- Nothing else is left to do without the owner (the next `slpa` run needs them; notified). Per the owner’s standing instruction for that case, a sleep check on battery with the charge limit at 20%: image 49, test kernel (SART restore), all CPUs, `deep`, **one cycle with a 7200 s alarm**. It is the first sleep longer than 30 min under Aura. Expect about 120 heartbeats (`psci_dbg[16]`), a wake on the PMU alarm at about 7200 s, and about 2.8 Wh used at 1.4 W.
- `run.sh` takes `/var/lib/deepidle/discharge`: it sets `charge_behaviour` = `auto-discharge` before the cycles (it resets to `auto` at every boot) and puts back `auto` and the thresholds named in the file (`80 75`) afterwards. Limit now 20/15.

## 2026-11-05 06:56: owner-attended `slpa` run with the SART restore, armed

- The 2 h battery run was cancelled before it suspended (its service was stopped in its start delay; nothing ran), and the thresholds are back at 80/75. The owner is present and ready to reset by hand.
- Armed: image 49, `suspendall`, `macsmc_reboot.deep_steps=6` (`slpw` and `slpa`), **no** `pmp_sleep`, 1 `deep` cycle, 60 s alarm. Test kernel with the SART save and restore; dead-man switch with the register snapshot; root read-only before the suspend; the watcher on `core-node-ts` streams kmsg. Instructions went to the owner by ntfy.
- The question: after `slpa`, does `apple-sart` report entries changed, and does the ANS boot once they are restored?

## 2026-11-05 07:12: owner-attended `slpa` run (image 49, 60 s alarm): no resume; the Mac cold-booted about 100 s after entry

- Image 49, `suspendall`, `deep_steps=6`, test kernel with the SART restore, `panic=0`, 1 `deep` cycle. `echo mem` at 07:01:04 (kernel 64.56 s). The PMU alarm was set for 07:02:04 (60 s). Root was read-only first (`filesystems ro: 1 of 4`, then the suspend).
- Nothing more from that boot: no `PM: suspend exit`, no dead-man line, no `apple-sart` line. The next kernel started at **07:03:08** (`uptime -s`; the default kernel, which saw the default image and did not suspend). Disk and btrfs clean (`device stats` all 0, no errors in `dmesg`); test disarmed, `next_entry` unset, boot.bin back at 76f850895fed53d1.
- The timing, against earlier resets from the watcher log and the journal, measured from `echo mem` to the next kernel start:
  - WD1 120 s (image 37, 19:35:59 to 19:38:24): **145 s**, so the firmware chain after a dog reset takes about 22 s;
  - kernel panic with `panic=10` (images 43 to 45): **45 s**;
  - this run: **124 s**, so the reset came at about 07:02:46, **about 100 s after entry and about 42 s after the alarm**. That is about 20 s before any of the 120 s dogs (the test kernel’s `apple_wdt suspend_timeout`, Aura’s `SYSTEM_SUSPEND` arm or its 60 s heartbeat re-arm) could have fired. `panic=0` rules out a panic restart.
- `macsmc-reboot: PMU logged 1 boot error(s)` on the new boot. In the watcher log, that line follows every dog or panic reset (16:30 to 20:50 on 11-04) and **no clean reboot, and not the owner’s long-press after the first `slpa` run (21:47)**. So this was most likely not a hand reset (the owner was also told to wait 10 min first); still to confirm with the owner.
- Two readings fit:
  - **H1, the SoC went down:** `slpa` took the SoC into S2R this time, so Aura, its heartbeat and WD1 (all in the AP’s power domain) stopped. The 60 s alarm woke the PMU, and with no resume path armed (unknown 1, the reconfig engine and boot RVBAR), iBoot started cold, which would make a PMU wake to Linux take about 64 s. In the first `slpa` run, the 10 s alarm came before the SMC had finished, so Aura woke in WFI with the SoC still up but the ANS already cut.
  - **H2, an SMC sleep timeout:** the SMC waits a fixed time (about 100 s) for the AP to go down after `slpa` and resets the system when it does not.
- Next owner-attended run to tell them apart: the same setup with a **30 s alarm**. H1 predicts a kernel start about 64 s after the alarm (about 96 s after entry), or a resume like the first run if the SMC is not done by then, which would also test the SART restore. H2 predicts 124 s again.

## 2026-11-05 07:18: image 50, reset times that name the RVBAR stage; regression run armed

- Image 49’s RVBAR path arms WD1 for 50 s on entry (stage 1, looking for the wake line) and 75 s when it resumes the kernel (stage 2). The 07:01 reset (about 100 s after entry) would fit stage 1 only if the boot CPU had come back through RVBAR about 50 s after entry, which matches no known wake. The chain from a reset to the next kernel is 144 to 145 s minus 120 on four WD1 resets of 11-04 (19:23, 19:29, 19:35, 19:57: from `echo mem` to the next kernel start, taken from each boot’s RTC line minus its uptime), so about 24 s.
- Image 50 (537df561fbdf13e3): image 49 with `RVBAR_WDT_S` 10 s and `RESUME_WDT_S` 150 s, which are unlike the 120 s dogs and the reset seen at about 100 s. With a 30 s alarm at the next owner-attended `slpa` run, the next kernel would start, counted from `echo mem`, at about:
  - 64 s: the boot CPU came back through RVBAR on the alarm but found no wake line (the AIC lost its state);
  - 84 s: an RVBAR entry about 50 s after entry, whatever the cause;
  - 94 s: a cold boot from the alarm, if that takes about 64 s as the 07:01 run would suggest;
  - 124 s: the SMC resets the system about 100 s after `slpa`;
  - about 205 s: RVBAR on the alarm, the wake line found, then the kernel’s resume hangs;
  - or it resumes, as the first run did after 10 s.
- A DRAM breadcrumb that survives the reset was considered and dropped for now: Aura’s runtime region moves on every boot (iBoot’s slide, 50 different bases in the result folders), and the PMU’s scratch cells are read by iBoot (a wrong panic count can mean recovery mode), so neither is safe without the owner.
- Armed the regression run for image 50 (normal path, no `slpa`): `suspendall`, 2 `deep` cycles with a 120 s alarm (each crosses one heartbeat), root read-only first, test kernel with the SART restore.

## 2026-11-05 07:27: image 50 regression run: 2 of 2

- Image 50 (537df561fbdf13e3), `suspendall`, 2 `deep` cycles, 120 s alarm, root read-only first, test kernel with the SART restore, no `slpa`: **2 of 2 back** (122.0 and 122.4 s), `online 0-9`, 0 device errors, dead-man switch `disk ok` both times, `apple-sart: entries kept across suspend`, register snapshot as before (`ps_ans2 1f0002ff`, ANS cpu `00000010 00000028`). Aura’s debug words match image 49’s 06:41 run word for word, so the normal path is unchanged (as expected: only the RVBAR stages moved).
- Disarmed: `force-ro` removed, boot.bin back at 76f850895fed53d1, `next_entry` unset. Image 50 is ready for the next owner-attended `slpa` run (30 s alarm).

## 2026-11-05 07:34: macOS’s watchdog kext at sleep: PMU boot stage 0x50, and a 10 s SMC deadline at quiesce (13.5, static)

- The SMC firmware cannot be read: it is not in the IPSW as a file of its own (`Firmware/rt13m0` is the USB-C retimer; `EFI/SMCPayloads` are Intel Macs’), so on Apple silicon it comes inside iBoot, which is encrypted. Whether the SMC has a sleep timeout (H2) cannot be settled statically.
- `AppleARMWatchdogTimer::callPlatformFunction` (disassembled now, `dis/AppleARMWatchdogTimer.s`, not committed) handles the platform actions:
  - **`IOPlatformSleepAction`**: reads the PMU variable `IOPMUBootStage`, stashes it, and writes **0x50**;
  - **`IOPlatformWakeAction`**: writes the stashed value back;
  - **`IOPlatformQuiesceAction`** (not hibernating): `enableReconfigWatchdogMonitoring()`, which writes **(continuous time + 10 s), in seconds**, to the wdt node’s third MMIO range (`0x9E2A002C`, Linux `0x29e2a002c`, 4 bytes, an “AP watchdog deadline” that the SMC enforces: strings `_useSMCEnforcedWatchdog`, “Need to add 'reg' entry in device tree for the AP watchdog deadline”, “Reconfig watchdog cannot be supported without SMC AP watchdog support”; ADT `reconfig-wdog-support`), then writes 0 to the WDT at `+0xc` (WD0’s control word);
  - halt and restart: `IOPMUBootStage` 0 (as Linux’s macsmc-reboot does on a clean shutdown).
- So macOS tells the PMU that the AP is asleep (0x50) before it sleeps, and gives the SMC a 10 s deadline at the last step. Linux leaves 0x30 (“OS running”, written by macsmc-reboot at probe) through every suspend. A wake or reset from S2R with 0x30 looks to iBoot like a crash, which fits the `PMU logged 1 boot error` after the 07:01 run (and after every dog reset). It does not by itself explain the reset at about 100 s.
- Test kernel option, staged and off: `macsmc_reboot.deep_steps` bit 8 writes `boot_stage` 0x50 in `suspend_late` (just before `slpa`) and puts the old value back in `resume_early` (patch `0001-TEST-macsmc-reboot-deep_steps-bit-8-...`, module installed, old one at `/var/lib/deepidle/macsmc-reboot.ko.pre-bootstage`). Not tried unattended: if a reset came with 0x50 in the PMU, what iBoot does then is unknown, so it waits for the owner like `slpa`. Proposed order with the owner present: image 50, `deep_steps=6`, 30 s alarm first (H1 against H2); then the same with `deep_steps=14` (adds the boot stage).
- The deadline register was not read: no Linux node maps that block, and an unclocked read would end in an SError.

## 2026-11-05 07:40: macOS’s sleep-action map; the PMGR’s AP wake-source mask, read on Linux

- Every kext that handles a platform action (GOT references to `gIOPlatform{Sleep,Quiesce,Active,Wake,Panic}ActionKey` in the 13.5 kernelcache), for the S2R list: ARMWatchdogTimer, AVD, DockChannel, EmbeddedPCIE, EmbeddedTempSensor, GPIOIC, IIS, InterruptControllerV2 (Quiesce, Active), MCA2, PMGR, PMP, I2C, NCO, DWI, SEPKeyStore, SEPManager (Quiesce), SMC, SPMI, SPMIPMU, SmartIO2, Stockholm, the DARTs (Sleep), T6000PCIeC, T6020 (MCC and IO), the CLPCs, SOCTuner, TCA7408 GPIO, ThunderboltNHI, IODARTFamily.
- **PMU (AppleDialogSPMIPMU)**: Sleep locks its SPMI bus (`_lockBus(true)`); Quiesce programs the RTC wake alarm once more (`scheduleRTCWakeAlarm`, log “pmu go hib”). Its alarm registers are the ones our rtc-macsmc patch uses (`info-rtc_alarm_offset` 0x140c, `_ctrl` 0x1401 bit 6, `_event` 0x14c0, `rtc_irq_mask_offset` 0x14c2), so the alarm set-up is not where Linux differs.
- PMU fault log (`info-fault_log` 0x1000, 10 bytes; bit names in the ADT: 4 `wdog`, 9 `btn_rst`, 10 `btn_shutdown`, 12 `force_off`, …): reads 0 on Linux, so iBoot copies and clears it; the shadow (0x867b) is `10 12 00…` after clean reboots and dog resets alike, so it cannot say what reset the 07:01 run.
- **Memory cache controller** (AppleT6020MemCacheController): handles Quiesce, Active and Wake; the kext has `_mccFlush` (“Flushing Mem Cache …”), a flush of the system-level cache, not looked at further yet.
- **The AP wake-source mask (PMGR)**: `AppleT6020PMGR::setAPWakeupSources(UInt32[9])` writes `valid & ~enabled` (so **1 = disabled**) to nine words of PMGR range 42 at +0x0c (ADT `0x204EA8000`, Linux `0x404ea8000`, the “AOP global” block), once per die. `getAPWakeupSources` reads nine status words at +0x30. `ApplePMGR::initAON` (boot) and `ApplePMGR::restoreHW` (each wake) call it; the enabled set is built in `initDriver` from the ADT’s `ap-wake-sources` (bit numbers: AOP.GPIO.IRQ4 12, IRQ6 14, AOP.OutboxNotEmpty 26, AOP.CPUWakeupAP 27, NUB.WakeupAP 40, NUB.GPIO.IRQ2 43, NUB.APWatchdog 49, NUB.APWakeupTime 50, NUB.SPMI0Sw0/1/3IRQ 51/52/54, SMC.CPUWakeupAP 85, SMC.OutboxNotEmpty 90, ATC0–3 CIO/USB 126–133, MTP dock channel 223). The valid mask is all ones up to bit 262.
- Read on Linux (read only, after a `sync`; the block answered): mask `0000ca00 27d00000 00000202 16f83e04 0 0 0 0 0`, status all 0 (these wakes were from WFI, not from S2R). So iBoot leaves almost every source enabled, but **disables 14 (AOP.GPIO.IRQ6), 52 and 54 (NUB.SPMI0Sw1IRQ, SPMI0Sw3IRQ)**, which macOS enables; macOS disables everything except its 22 sources. Which SPMI line carries the PMU alarm is not known yet. If it is Sw1 or Sw3, the alarm cannot wake a SoC that is really in S2R, which fits the 07:01 run (no wake at 60 s).
- The dead-man switch’s register snapshot now also reads the mask and the status words, so the next wake from a real S2R says which source woke it (installed; dry run OK).

## 2026-11-05 07:42: test option for the wake mask; unattended code-path check armed

- The PMU alarm is AIC 724, the second of `nub-spmi0`’s interrupts (`[256, 724, 260, …]`), so most likely `NUB.SPMI0Sw1IRQ`: **wake bit 52, which iBoot leaves disabled**. If so, the alarm cannot wake the SoC from a real S2R (an inference from the order, not proven).
- Test kernel option `macsmc_reboot.deep_steps` bit 16 (patch `0002-TEST-macsmc-reboot-deep_steps-bit-16-...`): in `suspend_late` it clears, in the PMGR mask, the bits of the 22 sources macOS enables (keeping all others), and on wake it logs the 9 status words’ first 4 and writes the old mask back. Default off.
- Bit 16 is only a PMGR register write that matters once the SoC is really in S2R, with no PMU write and no `slpa`, so its code path is checked unattended: image 50, `suspendall`, 2 `deep` cycles, 120 s alarm, root read-only, `deep_steps=16`. Expected: 2 of 2 back, the mask line before each suspend (`0000ca00 27d00000 …` -> `00008a00 27800000 …`), status 0 and the mask restored on each wake.

## 2026-11-05 07:49: the wake-mask step broke the normal suspend: no wake, a 120 s dog reset

- Image 50, `suspendall`, root read-only, `deep_steps=16` (no `slpa`): `echo mem` at 07:44:48 (kernel 71.47 s) and nothing after it; the next kernel started at **07:47:13, 145 s after entry, the signature of a 120 s dog** (four 11-04 WD1 resets: 144 to 145 s). PMU boot error logged, disk and btrfs clean. The image 50 baseline without the step passed 2 of 2 at 07:21.
- The step’s own `sleep: wake mask …` line is printed in `suspend_late`, after the console has gone and Wi-Fi is down, so it never reached the Pi. Two places it can have gone wrong, the dog cannot tell which (the kernel’s `apple_wdt` arm and Aura’s `SYSTEM_SUSPEND` arm are both 120 s and about a second apart):
  - the write itself (an MMIO write to PMGR range 42 that hangs or upsets the AOP side) in `suspend_late`, before Aura;
  - or the changed mask: with NUB.SPMI0Sw1IRQ (the PMU’s line, which carries the alarm and every other PMU interrupt) and AOP.GPIO.IRQ6 made AP wake sources while the SoC is up, the PMGR may start an AP wake sequence on an event that Aura’s deep WFI (and its 60 s heartbeat) then never survives.
- After the reset the mask reads `0000ca00 27d00000 00000202 10f83e04 0…` (bits 121 and 122 now clear), so iBoot writes it on every boot and not quite the same each time.
- Next (unattended, root read-only, Pi streaming): write the same value from user space while the system is awake and the network up, read it back, wait, restore, and only then suspend normally. A hang at the write points to the write; a clean pass points to the suspend interaction.

## 2026-11-05 07:53: correction: the wake mask is PMGR reg 7 (`0x29e004000`), not `0x404ea8000`; Linux finds it at 0

- **The 07:40 and 07:42 readings were of the wrong block.** `writeAOPGlobalReg` passes ApplePMGR’s own `RegMap` enum 42, and `AppleT6020PMGR`’s init binds RegMap 42 to **ADT pmgr reg index 7** (`initRegMap(42, 7, 0, 0)`), `0x9E004000` (0x1000 long), Linux **`0x29e004000`**, mask at +0x0c, status at +0x30. The block at `0x404ea8000` (ADT reg 42, also in `event-log-handler`) is live state: sampled every 2 s, its words 2 and 3 change on every read (`00f80e54`, `02f80e54`, `06f80e54`, `10f83e04`, …). Writing it in `suspend_late` is the likeliest reason the 07:44 suspend never came back.
- The real mask reads **all 0** on Linux (three reads; status 0 too): with 1 = disabled, every AP wake source is enabled (or the block was never written; iBoot does not set it, unlike macOS’s `initAON`). So the claim that iBoot disables the PMU alarm’s line (bit 52) is withdrawn; the alarm’s line is not masked, and the 07:01 run is not explained by the mask.
- Fixed: the dead-man snapshot reads `0x29e00400c`/`0x29e004030`; `harness/mmio/wakemask.c` (show, `macos`, `write`) is limited to that page; the test kernel’s `deep_steps` bit 16 now writes macOS’s value (`valid & ~enabled`: everything but the 22 ADT sources disabled) at `0x29e00400c` and restores the old words on wake (patch `0003-…-fix-the-mask-is…`).
- Armed (unattended, root read-only, Pi streaming): image 50, `suspendall`, `poke-wakemask` (macOS’s value written while awake, read back after 10 s, old value restored, all logged to kmsg before any cycle), then 2 `deep` cycles of 120 s with `deep_steps=16`. A hang at the poke points to the write; a hang in the cycles to macOS’s mask during a suspend with the SoC up.

## 2026-11-05 08:00: the real wake mask is writable, and macOS’s value stops Aura’s wake even with the SoC up

- Image 50, root read-only. The poke while awake (kmsg on the Pi): old mask all 0; **macOS’s value written and read back** (`f3ffafff ffa1f6ff fbdfffff 3fffffff ffffffc0 ffffffff 7fffffff ffffffff 0000007f`), the same 10 s later, then 0 written back and read back. Nothing else happened, so the register at `0x29e00400c` is the mask and writing it is harmless while awake.
- Then the cycle with `deep_steps=16` (macOS’s value across the suspend): `echo mem` 07:56:10, next kernel 07:58:35, **145 s: a 120 s dog**. The alarm was due at 120 s and Aura’s 60 s heartbeat would have pushed the dog to about 181 s, so **neither the heartbeat (EL2 timer) nor the PMU alarm woke the boot CPU from Aura’s deep WFI** with only macOS’s 22 sources enabled.
- So the PMGR’s AP wake mask also gates the AP’s wake from deep WFI with the SoC up, and Linux’s all-zero mask (every source enabled) is what lets the alarm and the heartbeat through. The mask is not the reason the 07:01 `slpa` run failed. In macOS’s mask the alarm’s path into the PMGR evidently is not one of the enabled bits (or needs the SPMI controller set up as macOS does).
- Next, unattended and on the normal path: read the wake status words after each wake with the mask left at 0 (the dead-man snapshot now reads the right block). If they latch on a deep-WFI wake, they name the bit the PMU alarm (and the heartbeat) use, which an S2R mask must keep enabled.

## 2026-11-05 08:01: armed: which wake-status bits a deep-WFI wake sets (mask 0)

- Image 50, `suspendall`, normal path (no `deep_steps`), root read-only, 2 `deep` cycles with a 90 s alarm (each crosses one 60 s heartbeat before the alarm). The dead-man snapshot after each wake reads the mask (expect 0) and the 9 status words at `0x29e004030`.

## 2026-11-05 08:07: wake status after deep-WFI wakes: all 0

- Image 50, normal path, mask left at 0, 2 `deep` cycles with a 90 s alarm (each crossing one heartbeat): **2 of 2 back** (92.0 and 92.4 s), 0 device errors. The dead-man snapshot after each wake: mask 0, **status 0** in all nine words. So the status words do not latch on a wake from Aura’s deep WFI with the SoC up; they are for a wake from real S2R (or need setting up first). They stay in the snapshot for the next `slpa` run, where they would name the wake source if the SoC went down.
- Disarmed: `force-ro` removed, boot.bin 76f850895fed53d1, `next_entry` unset.

## 2026-11-05 08:09: what an S2R resume must restore: the AIC is covered, the system cache needs no flush (13.5, static)

- **AIC** (`AppleInterruptControllerV2::callPlatformFunction`): Quiesce reads each die’s mask words (the mask-set bank read at +0x200) into a copy and masks everything (0xffffffff to `0x6400 + die × 0x4a00`), saves the shared-timestamp table (`0x1800 + 0x10 × i`, `#shared-timestamps` entries) and `AIC2_CONFIG` (0x14). Active writes `AIC2_CONFIG` back, re-applies `_configureExternalInterruptMap` (ADT `aic-ext-intr-cfg`: 3-byte entries, IRQ number and a 4-bit config OR’d into that IRQ’s `IRQ_CFG` at `0x2000 + die × 0x4a00 + 4 × irq`), the masks (set and clear banks) and the timestamp table. The test kernel’s AIC syscore save and restore (commit `1585343af9f8`) already covers `AIC2_CONFIG`, every `IRQ_CFG` (which includes the external map) and the masks; the timestamp table is for interrupt timestamps, which Linux does not use. Nothing to add there.
- **System-level cache**: on H14, `ml_arm_sleep()` (xnu-8796.141.3 `osfmk/arm64/cpu.c`) does not clean the memory cache before S2R: `platform_cache_shutdown()` is only on the `WITH_CLASSIC_S2R` (iBoot sleep token) path, which H14 does not use, so the SLC is left to the hardware (the MCC and the reconfig engine). `AppleT6020MemCacheFlushFunction` (`_mccFlush`) is a published platform function used elsewhere, and the MCC’s own Quiesce and Wake handlers save and restore its performance counters (tables of 0xa0-byte entries). So Linux does not need its own SLC flush before `slpa`.
- What a working S2R resume still needs on the Linux side, from today’s reading: the RVBAR resume into the kernel (Aura has the path; it never ran on real S2R), the SART restore (in the test kernel), the AIC restore (in the test kernel), the ANS boot after the wake, and the PMU boot stage (staged, off).

## 2026-11-05 08:09: armed: the 2 h suspend to RAM on battery (long-sleep check)

- Image 50, test kernel (SART and AIC restore), normal path (no `slpa`, mask 0), all CPUs, `deep`, **one cycle with a 7200 s alarm**, root read-only, on battery via the SMC’s forced discharge (`discharge` flag; limit 20/15 for the run, 80/75 put back afterwards). Battery 85%. Expect about 120 heartbeats, a wake on the alarm after about 7200 s, and about 2.8 Wh used at 1.4 W. It is the first sleep longer than 30 min under Aura.

## 2026-11-05 10:01: the first long suspend under Aura: 1 h 46 min on battery, 1.44 W, clean

- Image 50, test kernel, normal path, all CPUs, `deep`, one cycle with a 7200 s alarm, root read-only, on battery (forced discharge from 85%): **back after 6390.6 s** (08:12:27 to 09:59:00), `online 0-9`, 0 device errors, dead-man switch `disk ok`, `apple-sart: entries kept across suspend`.
- Energy 49.727 to 47.162 Wh: **2.565 Wh, 1.444 W average** (85% to 84%), the same as the 30 min runs (1.365 W; s2idle 1.39 to 1.41 W): parking every CPU in Aura saves nothing measurable while the SoC stays up.
- Aura’s debug words: **106 heartbeats** (word 15 = 0x6a; 6390 s / 60 = 106.5) and 107 WFI returns, so the 60 s heartbeat held the dog off for the whole sleep with no slip.
- The wake came **13.5 min before the alarm, on line 0x361 = AIC 865, the SMC mailbox** (the alarm is 724): an SMC event, most likely from the battery or the forced discharge (the 10-23 overnight s2idle saw the same kind of mailbox wakes). The wake path took it as a normal wake line and resumed.
- Afterwards `charge_behaviour` is back to `auto` and the thresholds to 80/75; flags removed, boot.bin 76f850895fed53d1, `next_entry` unset.
- Also fixed today’s worklog headings from 07:12 on: several carried estimated times instead of the clock; they now show each entry’s commit time.

## 2026-11-05 10:02: `MBSE` on wake is macOS’s SMC wake reason; the plan for the owner-attended runs

- `AppleSMC::callPlatformFunction(IOPlatformWakeAction)` reads `MBSE` and claims it as the system wake event `SMC.MBSE.%02x` (`IOPMrootDomain::claimSystemWakeEvent`), then reads 8 bytes of `MBSW` and sends `waka`. So the `MBSE 00010730` after the first `slpa` run (11-04 21:32) was the SMC’s wake reason; its codes are in the SMC firmware (inside the encrypted iBoot), so it cannot be decoded here.
- The owner-attended runs, in order, each one boot with the owner at the power key (long press only after 10 min with no push and no chat message):

| Run | Flags (`/var/lib/deepidle/…`) | Question | Reading of the next kernel start, from `echo mem` |
|---|---|---|---|
| A | `deep-steps` 6, `suspend-cycles` 1, `suspend-alarm` 30, image 50 | Does the SoC go down after `slpa`? | resume: SoC still up (then SART restore results); about 64 s: RVBAR on the alarm (SoC went down, wake path reached Aura); about 94 s: cold boot from the alarm; 124 s: SMC timeout |
| B | as A, plus `deep-steps` 14 (PMU boot stage 0x50) | Does iBoot treat the wake as a sleep wake once the PMU says the AP is asleep? | as A; a change from A’s reading is the answer |
| C | as A or B, plus `pmp-sleep` | macOS’s PMP steps after `slpa` | as A |

- Arming each: write the flag files, `findmnt /boot`, `sudo bash harness/psci-efi/install.sh suspendall`, send the owner the ntfy instructions, then `reboot.sh` with a prompt naming the run. The dead-man snapshot (wake mask and status, ANS, SART) and the watcher on `core-node-ts` record what happens.

## 2026-11-05 10:03: image 51: the RVBAR path resumes the kernel even without a wake line; regression armed

- After a real S2R the AIC has lost its state, so image 50’s RVBAR path would never find a wake line and its 10 s stage would reset the Mac: a signature but a dead end. Image 51 (eb1904c3373bd624) hands over to the kernel’s resume on any RVBAR entry with the resume magic set (`psci_dbg[13]` = 3 when no wake line was found, 2 with one), under the 150 s stage-2 dog. If DRAM did not survive, the magic check fails first and nothing is resumed.
- Expected at the first real S2R wake: Linux resumes on the boot CPU (its AIC and SART restores run), the nine secondaries time out on `CPU_ON` (their park loops are gone; a cold restart of secondaries from Aura at runtime is the next piece), and the kernel log reaches the Pi. A hang in the kernel’s resume shows as a reset 150 s after the RVBAR entry plus about 24 s of firmware.
- The normal path is unchanged; regression run armed: `suspendall`, 2 `deep` cycles of 120 s, root read-only. The owner-attended table (10:02 entry) now uses image 51; run A’s 64 s reading becomes “Linux resumes” or about 204 s (stage 2).

## 2026-11-05 10:10: image 51 regression run: 2 of 2

- Image 51 (eb1904c3373bd624), `suspendall`, 2 `deep` cycles of 120 s, root read-only, normal path: **2 of 2 back** (121.7 and 122.4 s), `online 0-9`, 0 device errors, dead-man `disk ok`, SART kept, Aura’s debug words the same as image 50’s. Image 51 is the image for the owner-attended runs. Disarmed.

## 2026-11-05 10:11: design note: restarting the secondaries after a real S2R (not built yet)

- After S2R the nine secondaries are powered off with their park loops gone, so Aura’s `CPU_ON` (which only hands an entry to a parked core through the spin table) cannot bring them back; Linux would time out on each (about 5 s apiece) and run on the boot CPU. Linux `linux-aurora 7.2.11.aurora14-1` is still the newest package, so the test kernel’s base is current.
- What a runtime cold start needs, from `smp_start_cpu()` (boot time, `src/smp.c`):
  - each core’s implementation registers (`cpu_info[i].impl_reg`, from the ADT `cpu-impl-reg`): RVBAR is written there (`write64(impl_reg, _vectors_start)`; T6020 has `apple_sysregs_unlocked`). They are **not** in `aura,psci-runtime-mmio` today (only the CPU-start block, the WDT and the AIC are), so Linux does not map them for the EFI call;
  - the PMGR CPU-start block (already mapped): the system start bit at +0x4 and the per-cluster start word at +0x8;
  - a reset stack per core and the spin-table flag handshake, without `printf`/`udelay` from boot (the UART is not mapped at runtime) and without `mmu_add_mapping`;
  - the secondary’s RVBAR entry (`_cpu_reset_c`, quiet when `psci_runtime`) then reaches `smp_secondary_entry()` and parks, after which the normal `CPU_ON` dispatch works.
- Plan: on an RVBAR resume of the boot CPU with no wake line (`psci_dbg[13]` 3), mark every secondary as lost; `CPU_ON` for a lost core runs the cold start above, then dispatches. It can only be exercised after a real S2R wake, so it waits until run A shows the boot CPU coming back through RVBAR.

## 2026-11-05 10:12: the PMP after `slpa`: run C will likely leave it down; long `s2idle` A/B armed

- From the 10-22 notes: on macOS the PMP’s wake from IDLE is a power cycle (`stopCPU`, DART unmapped, `ps_pmp` and `ps_pms_sram` gated, then ungated, DART back, `_runCPU(1)`). Linux cannot gate `ps_pmp` (always-on in the DT, and the owner’s rule: no `ps_pmp` reset), so owner-attended run C (`pmp_sleep`) will most likely leave the PMP silent until the next boot, unless a real S2R power-cycles it anyway (then the PMP driver must boot it again, as the NVMe driver does the ANS).
- Armed the long A/B partner for the 10:01 `deep` run: same test kernel and image 51, **`s2idle`, one cycle with a 6300 s alarm**, on battery (forced discharge, limit 20/15, 80/75 put back after), root read-only.

## 2026-11-05 12:01: long A/B on battery: `deep` 1.444 W, `s2idle` 1.478 W

- Image 51 test kernel, normal path, `s2idle`, one cycle with a 6300 s alarm, on battery (forced discharge from 82%), root read-only: **back on the alarm after 6300.4 s** (10:15:10 to 12:00:13), `online 0-9`, 0 device errors, dead-man `disk ok`, SART kept, wake mask and status 0.
- 47.743 to 45.155 Wh: **2.588 Wh, 1.478 W**. Against the 10:01 `deep` run (1.444 W over 6391 s), suspend to RAM with every CPU parked in Aura saves **about 0.03 W (2%)**, the same as the 30 min A/B (1.365 against 1.39 to 1.41 W). The rest, about 1.4 W, is the SoC and its devices staying up; only the SoC power-down (`slpa` and what follows) can take it away. macOS: 0.24 W.
- Logs in `data/drain-ab/2026-11-05-image50-51-long-deep-vs-s2idle.log`. Afterwards `charge_behaviour` `auto`, thresholds 80/75; flags removed, `sleep-modes` back to `deep`, boot.bin 76f850895fed53d1, `next_entry` unset.

## 2026-11-05 12:04: lead: the PMGR’s own state counters (`SLP_S2R`) could say whether the SoC slept

- The ADT pmgr `events` name per-state PMGR performance counters: `SLP_DDR` (block 0, index 42/43), `AWAKE` (44/45), **`SLP_S2R` (46/47)**, `DEEP_WAIT` (48/49), `SYS_AWAKE` (50/51), `SYS_S2R_AOP` (52/53), `SYS_SLP_DDR` (54/55), and `DDR_WK_TIME`/`S2R_WK_TIME` (block 1, 40 and 38). The ADT `perf-regs` list places block 0 at pmgr reg 1 + 0x48000 (Linux **`0x29e2c8000`**, 0x3D counters) and block 1 at pmgr reg 0 + 0x60000.
- Read on Linux (read only, after a `sync`; nothing maps it): only +0x4/+0x8 move, a 64-bit count at 24 MHz (about 6645 s); every per-event word up to +0x500 is 0, so the event counters are off under Linux. macOS turns them on in `ApplePMGR::initAON` (`_enableAONPerfCounters` → `_enableSOCPerfCounter`): a read-modify-write of a per-counter config word, at `base + 16 × idx + 0x100` or, in layout version 2, `base + 28 × idx + 0x2c` (low bits: 4 = enable, 1 = an inverted flag), then a busy-bit poll for some groups.
- Not written: which layout this PMGR uses is not pinned down (a global in the driver), and a PMGR write on a guess is how the 07:44 suspend was lost. With the layout confirmed, enabling `SLP_S2R` and `SYS_S2R_AOP` before an `slpa` run would show directly whether the SoC entered S2R and for how long, without reading reset times. Proposed for a session with the owner present.

## 2026-11-05 12:07: the counter layout pinned down; baseline run armed (counters on, SoC up)

- `ApplePMGR::start` reads `perf-counter-version` from the ADT and, when it is absent (as on the J414s), uses **1** (`csinc w8, w8, wzr, ne`), so the counters use the 16-byte layout: config at `0x29e2c8000 + 0x100 + 16 × idx`, the 64-bit count at +0x108/+0x10c. `SLP_S2R` is index 46: config `0x29e2c83e0`, count `0x29e2c83e8`.
- `harness/mmio/pmgrcnt.c` (show, `enable`), limited to indices 42 to 55 of that perf-only block; `enable` writes `(old & ~7) | 4 | 1` as `_enableSOCPerfCounter(…, true, false)` does. `run.sh` takes `/var/lib/deepidle/pmgr-counters`: enable before the cycles (after the read-only remount), log the counters 2 s later and after each cycle.
- Armed the baseline: image 51, normal path, root read-only, counters on, **one `deep` and one `s2idle` cycle of 120 s**. Expected: `AWAKE`/`SYS_AWAKE` counting, `SLP_S2R` and `SYS_S2R_AOP` staying at 0 (the SoC stays up). If a counter moves with the SoC up, that is worth knowing before the `slpa` runs read them.

## 2026-11-05 12:15: counter baseline: the counters did not start, and the `deep` cycle lost the secondaries during an AOP failure

- Image 51, counters “enabled” at kernel 64.4 s: the 14 config words read back **1** after writing `(old & ~7) | 4 | 1` (bit 0 stayed set, bit 2 did not), and every count stayed 0 through both cycles. So the per-counter write alone does not start them; macOS also calls `_enableSOCPerfCounters(group, …)` for the whole group, which was not done.
- The `deep` cycle came back after **94.4 s** (alarm at 120 s) with **only CPU 0 online**: all nine `CPUn: failed to come online`, two `macsmc: Failed to send command` right after the CPU_OFFs, 31 device errors; the `s2idle` cycle then ran on one CPU. Dead-man `disk ok` both times; no reset.
- Confounder: in this boot **the AOP’s probe failed on its own** from 19 s (endpoints 0x20 to 0x2c `did not acknowledge its shutdown`, 5 s each, then `Failed to stop AOP ETIMEDOUT` at 118 s, `probe … failed with error -110`), so its teardown was still running across the `deep` suspend, long before and after the counter write. None of the previous six boots shows it.
- So the cause is open: the AOP failure, or the counter config write. One repeat decides it: the same run with the counters, on a boot where the AOP comes up normally.

## 2026-11-05 12:24: counter repeat: 2 of 2 with the AOP healthy, so the 12:15 loss came from the AOP failure

- Same run on a fresh boot where the AOP came up normally (`AOP IS READY`, no shutdown timeouts): counters “enabled” as before, then 2 `deep` cycles of 120 s: **2 of 2 back** (122.1 and 122.3 s), **`online 0-9`**, 0 device errors. So the per-counter config write is harmless and the 12:15 loss of the secondaries (and the SMC command failures) came with the AOP’s failed probe; the AOP failure itself is a one-off so far (1 of the last 8 boots).
- The counters still did not count. `ApplePMGR::_enableSOCPerfCounters(group, true)` sets bit 0 of the group’s control word (block 0 `+0`, which reads `0x00030000`, bit 0 clear) after the per-counter configs; `pmgrcnt enable` now does that last step too. One more short run with it.

## 2026-11-05 12:31: the PMGR’s state counters work: with the SoC up, only `AWAKE` counts

- Image 51, AOP healthy, `pmgrcnt enable` with the group bit (control `0x30000` → bit 0 set), then one `deep` and one `s2idle` cycle of 120 s: **2 of 2 back, `online 0-9`, 0 device errors**.
- The counters run at 24 MHz and count time in each state: 2 s after enabling, `AWAKE` and `SYS_AWAKE` (and their second counters) read 48.2 M ticks; after the `deep` cycle 3.040 G (+124.6 s), after the `s2idle` cycle 6.049 G (+125.4 s). **`SLP_DDR`, `SLP_S2R`, `DEEP_WAIT`, `SYS_S2R_AOP` and `SYS_SLP_DDR` stayed at 0 throughout**: the PMGR’s own record that the SoC never left AWAKE during Aura’s suspend or s2idle, the first direct measurement of that (it fits the drain: 1.44 W against 1.48 W).
- So in an `slpa` run that comes back (a resume, or Linux through image 51’s RVBAR path), `SLP_S2R` and `SYS_S2R_AOP` above 0 would prove the SoC went down, and their ticks say for how long. A cold boot resets the PMGR, so they cannot tell anything after a reset.
- Added to the owner-attended plan (10:02 table): **every run also sets `/var/lib/deepidle/pmgr-counters`**. The counters stay off by default.

## 2026-11-05 12:32: `attended.sh`: one command per owner-attended run

- `harness/psci-efi/attended.sh A|B|C [--dry]` arms a run from the 10:02 plan with today’s changes (image 51, `pmgr-counters`, 1 `deep` cycle, 30 s alarm, root read-only): A `deep_steps` 6; B 14 (adds the PMU boot stage 0x50); C 14 plus `pmp-sleep`. It checks `/boot` and the default boot.bin, writes the flags, runs `install.sh suspendall`, sends the owner the ntfy instructions (when to hold power), writes the boot prompt for the result (what each reading means) and reboots. Run only after the owner says they are at the Mac. Dry runs of A and C pass.

## 2026-11-05 12:43: awake idle never leaves the PMGR's AWAKE state either

- Image 51 test kernel, the counters left on after the run, 10 min headless awake idle (12:32:23 to 12:42:23, this session the only load): `AWAKE` and `SYS_AWAKE` +14.398 G ticks = **599.9 s of 600**, `SLP_DDR`, `DEEP_WAIT`, `SLP_S2R`, `SYS_S2R_AOP` and `SYS_SLP_DDR` **0**. So with Linux, the SoC sits in AWAKE all the time, awake or suspended; the SoC-level idle and sleep states the PMGR knows (DDR sleep, deep wait, S2R) are reached by none of today's paths. This is the gap behind both the awake idle power (GH-10) and the 1.44 W suspend.

## 2026-11-05 12:44: RVBAR handover reviewed; a 90 min `deep` run on battery with the counters armed

- Review of image 51's new path for a freshly reset boot CPU: `_cpu_reset_c` → `psci_suspend_resuming()` → `psci_suspend_rvbar()` with the MMU off and printing quiet; `psci_enter` clears SCTLR_EL2 M/C/I, sets HCR_EL2 to its reset value (RW) and branches with x0 = context, and Linux's `cpu_resume` begins with `init_kernel_el`, which rebuilds EL2 itself. Nothing in it depends on state a reset would have lost.
- Leads noted from the PMGR kext: APSC voltage-rail controls with sleep variants (`apsc-sleep-soc`, `apsc-sleep-dcs`, `apsc-snooze` = 1 in the ADT, a `snooze-counter`), likely part of how macOS reaches `DEEP_WAIT`/`SLP_DDR`; not followed today.
- Armed the last unattended run of the day: image 51, normal path, **one `deep` cycle of 5400 s on battery** (forced discharge, 80/75 put back after), root read-only, PMGR counters on. A third drain figure, and the counters over a long sleep (expect `AWAKE` all of it).

## 2026-11-05 14:18: 90 min `deep` on battery with the counters: 1.489 W, AWAKE the whole time

- Image 51, normal path, AOP healthy, PMGR counters on, one `deep` cycle with a 5400 s alarm on battery (forced discharge from 81%): **back on the alarm after 5402.0 s** (12:47:23 to 14:17:28), `online 0-9`, 0 device errors, dead-man `disk ok`.
- 47.378 to 45.144 Wh: **2.234 Wh, 1.489 W**. With the 10:01 `deep` run (1.444 W) and the 12:01 `s2idle` run (1.478 W), the three long runs spread 1.44 to 1.49 W: the difference between suspend to RAM with parked CPUs and s2idle is inside the run-to-run spread. Parking the CPUs buys nothing measurable while the SoC stays up.
- Counters over the cycle: `AWAKE` and `SYS_AWAKE` +130.35 G ticks (5431 s at 24 MHz, the suspend plus the half minute around it); `SLP_DDR`, `SLP_S2R`, `DEEP_WAIT`, `SYS_S2R_AOP`, `SYS_SLP_DDR` 0. The PMGR stayed AWAKE for the whole 90 min.
- Afterwards `charge_behaviour` `auto`, 80/75; flags removed, boot.bin 76f850895fed53d1, `next_entry` unset, nothing armed. The log is appended to `data/drain-ab/2026-11-05-image50-51-long-deep-vs-s2idle.log`. End of today’s unattended runs; the owner-attended runs A to C are next (`attended.sh`).

## 2026-11-05 15:00: day summary sent; the Mac is on the default kernel

- The owner was sent the day's summary by ntfy (the open question about the 07:01 run, the withdrawn wake-line claim, the PMGR state counters, the long-sleep drain, image 51, the run C caveat, and that runs A to C are one command each with `attended.sh`). Nothing posted to #933.
- The Mac is on the default kernel (7.2.11-14-1-ARCH), boot.bin 76f850895fed53d1, `next_entry` unset, no test flags, battery `auto` 80/75, headless on, the Pi watcher running. No test boots armed; the next `slpa` runs wait for the owner to say they are ready.

## 2026-11-05 15:18: owner-attended run A (image 51, `slpa`, 30 s alarm): no resume; the reset follows the alarm, not `slpa`

- Owner present and hands off. Image 51, `suspendall`, `deep_steps=6` (`slpw` and `slpa`), 1 `deep` cycle, 30 s alarm, PMGR counters on, root read-only (`superblock ro 1 of 4`), dead-man switch armed (330 s). The owner says they may have woken the Mac by hand during the 07:01 run.
- Counters before the suspend: enabled, and 2 s later only `AWAKE`/`SYS_AWAKE` count (48.2 M ticks = 2.0 s at 24 MHz), as in the 12:31 baseline.
- `echo mem` at 15:14:14.15; the watcher's last line from that boot is `PM: suspend entry (deep)`. No resume, no dead-man line, no RVBAR handover: image 51 would have resumed Linux, or reset about 204 s after entry.
- Next kernel start **15:15:47** (the default kernel; RTC line 20:16:01 UTC at 14.0 s uptime), so **93 s after `echo mem`, 63 s after the alarm**. The default kernel saw the default image and did not suspend. `PMU logged 1 boot error(s) and 0 panic(s)`, as after every dog or panic reset. Disk clean (`device stats` all 0, no btrfs or NVMe errors), boot.bin 76f850895fed53d1, `next_entry` unset; flags removed.
- With the 07:01 run: 60 s alarm, reset 124 s after entry; 30 s alarm, 93 s. **Both times the next kernel starts 63 to 64 s after the alarm.** That rules out H2 (a fixed SMC timeout about 100 s after `slpa`), and with it the morning's possible hand wake as the cause. The alarm is what starts the reset.
- In the first `slpa` run (11-04 21:32, 10 s alarm) the alarm still woke Aura's deep WFI. With 30 s and 60 s it no longer reaches Aura at all (no RVBAR entry either), so by 30 s after `slpa` the AP was most likely powered down: the SoC goes down, and the wake comes back through a path that does not resume. Not proven: the counters are lost on a reset.
- Still open: what the 63 s is. A watchdog reset takes about 24 s to the next kernel, so either a cold boot from a sleep wake is that slow, or something waits about 40 s after the wake for the AP and then resets the system. Run B (boot stage 0x50, as macOS sets it at sleep) asks whether iBoot then treats the wake as a sleep wake.

## 2026-11-05 15:57: correction: runs A and B, and the 07:01 run, all resumed; the disk was dead and the dead-man switch reset the Mac

- The 07:12 and 15:18 entries are wrong. The dead-man switch pushes its evidence to ntfy, and I did not read those pushes. The topic has one for each run: **07:02:36** (the 07:01 run), **15:15:17** (run A) and **15:22:47** (run B), each "the disk does not answer after the resume. Resetting the Mac".
- All three logged the same kernel lines: `MBSE = slpw`, NVMe `saveCtx 1 took ~400 ms`, `MBSE = slpa`, `SetAPPower IDLE`, nine `CPU killed`, then on the alarm `SetAPPower ON`, `wake MBSE 00010730, MBSW (8); MBSE = waka`, `PM: suspend exit`, `IOP power acknowledgment failed: -62`, `ANS did not boot`, `Reset failure status: -62`. That is the 11-04 21:32 result again. Run B also logged `boot_stage 0x30 -> 0x50` and `back to 0x30`, and changed nothing.
- So the SoC did not go down in any of them: Aura woke from deep WFI on the alarm, as in every normal cycle. The watcher's stream ends 3 to 4 s after each alarm, when Wi-Fi drops at the resume, which is why its log stops at `PM: suspend entry`. The 63 s from the alarm to the next kernel is the dead-man switch: the resume, three disk probes of 10 s, the push, `sysrq b`, and the firmware chain. H1 and H2 were both wrong. The PMU boot error comes from that reset.
- The SART restore's log line and the PMGR counters after the cycle were lost: `run.sh` stalls on the dead disk before logging them, and the dead-man evidence filter dropped `apple-sart` lines. The register snapshot shows SART entries 4, 6 and 7 empty against a healthy boot (`10006400`, `10015f9c`, `1000c734`), but the driver itself frees those (`apple_rtkit_reinit`, `shmem_destroy`) before the failed boot, so that says nothing about the restore. ANS CPU status 0x08 against 0x28 healthy, `ps_ans2` on.
- Fixed in the harness: the dead-man snapshot now also pushes the PMGR counters and Aura's `psci_dbg` words (static `pmgrcnt` and the debug address copied to `/run` before the suspend), and the evidence filter keeps `sart`, `pmp` and `SetIOPPower` lines. Checked on this boot: the snapshot reads the counters.
- Lesson kept for every `slpa` run: read the ntfy dead-man pushes first.

## 2026-11-05 16:03: owner-attended run C (`slpa` plus macOS's PMP steps): the PMP crashed; resumed, ANS dead; the SART kept; the SoC stayed AWAKE

- Image 51, `deep_steps=14`, `pmp_sleep=1`, 1 `deep` cycle, 30 s alarm, counters on, root read-only. `echo mem` 16:00:39, alarm 16:01:09, the watcher's stream ended at 16:01:13 (the resume), dead-man push 16:01:42, next kernel 16:02:12 (93 s after entry).
- The dead-man push (with the 15:57 additions):
  - `PMP SetAPPower/SetIOPPower IDLE: -62`: the **PMP firmware crashed** on the IDLE request after `slpa` (RTKit crashlog, its last messages `00b0000000000201`). So the PMP side of macOS's sequence needs more than the two messages.
  - The CPUs went off, the alarm woke them, `SetAPPower ON`, `waka`, `PM: suspend exit`, then `IOP power acknowledgment failed: -62`, `ANS did not boot`, as in every `slpa` run.
  - **`apple-sart: entries kept across suspend`**: the SART had not changed, so it is not why the ANS fails after `slpa`.
  - **PMGR counters after the cycle: `AWAKE` 1,562,564,648 ticks = 65.1 s at 24 MHz** (from the enable through the suspend to the snapshot), `SLP_S2R`, `DEEP_WAIT`, `SYS_S2R_AOP`, `SLP_DDR` all 0. **The SoC never left AWAKE**, even after `slpa` and the PMP steps. That is the first direct proof, and it fits the four earlier runs.
  - Aura's `psci_dbg` words read all 0 from the new snapshot: the address or the static reader is wrong. To check on the next test boot (`run.sh` read them fine through the disk-resident `mmio-read`).
  - `ps_ans2` read `1f0000ff` (run B `1f0002ff`), ANS CPU status 0x08 (healthy 0x28), mailbox `0002ff01 00109a01`.
- Disk clean (`device stats` 0, no btrfs or NVMe errors), PMU boot error from the reset, boot.bin 76f850895fed53d1, `next_entry` unset, flags removed.
- Where this leaves Phase 5: `slpa` makes the SMC take the storage controller down, but by itself does not start the SoC's sleep. The PMGR's own sleep entry (the S2R timer and the PMGR quiesce, read statically from macOS 13.5) has to come from the AP side, and with the SoC up the ANS does not come back. Next, static: what macOS does to start the ANS after a sleep wake (`AppleANS3`/`IOSARTMapper` and the PMGR), and the PMP's IDLE preconditions. No more `slpa` runs without the owner.

## 2026-11-05 16:05: harness: Aura's debug words found by their magic; the fixed offset had gone stale

- `run.sh`'s `aura dbg (words …)` line reads `psci_dbg` at a fixed ELF offset (`0x1472c8`) and has printed zeros on every run today, while its `aura dbg scan` line (`scan-magic 0xA0AA0001`) found the block each time. So the offset is stale for images 50 and 51, and the zeros in run C's dead-man push meant nothing.
- The dead-man snapshot now finds the block the same way: `install.sh` builds a static `scan-magic`, `run.sh` copies it to `/run/psci-deadman`, and `regs()` adds its first line. Checked on the default image: no block found, the snapshot is otherwise unchanged.

## 2026-11-05 16:32: the linked docs brought up to date

- On the owner's request, the docs linked at the bottom of https://jjrpf.com/S2R are current again. Most were last written on 10-24.
- `status.md` was rewritten as of this evening. The short version now carries Phase 2 done, the SoC staying `AWAKE` through `slpa`, the 45% estimate and the next steps. It also has the timeline through 11-05, a current S2R piece table and a "built and booted" table.
- `s2r-plan.md` gains a "where each phase stands" section and dated status lines per phase, and "what comes next" replaces the 10-23 "what can start now".
- `psci-efi.md` now describes the booted design: the retention park, SYSTEM_SUSPEND with the wake lines, the watchdog heartbeat and the RVBAR resume, the kernel unwinds and the U-Boot runtime-range fix. It also has a results table.
- `deep-idle-research.md` gains an update bullet at the top and a section, "S2R work, 2026-10-25 to 11-05". Its unknowns are updated.
- `hv-boot-trace-reference.md` gains a section on what Linux found when it replayed macOS's sleep entry.
- `data/README.md` now covers the 90 min run with the PMGR counters.
- `s2r-status.json`: the stale pieces (SMC, PMP, PMGR), the `slpa` finding ("survived a warm reboot" no longer holds: the dead-man reboot brings the disk back) and the macOS-sleep rows are updated.

## 2026-11-05 16:39: image 52, the PMGR's S2R timer and macOS's all-core deep sleep, behind a control word; regression armed

- What macOS does last, from the 13.5 kernelcache and xnu-8796.141.3.
  - `AppleT6020PMGR::startS2RTimer` is one write: `writeMasterMiniPMGRReg(0x4000, 1)`, i.e. 1 to MPMGR_AON + 0x4000 (`0x29e5c4000`).
  - It is the last of `quiesceHW`. Before it come the SoC-East clock gates at 0x1c0/0x1e0, the ClkGen PLL-off writes at 0x38158 to 0x3816c, and the GPU PMGR quiesce. The AIC quiesce (97000) and the PMU's (98000) follow it, then `ml_arm_sleep`.
- `ml_arm_sleep` (xnu `cpu.c`): the secondaries stall in WFE on `arm64_stall_sleep` until CPU0 clears it. Then every core runs `arm64_prepare_for_sleep(true)`, CPU0 last: ACC_OVRD deep sleep, `CYC_OVRD` ok-to-power-down with no WFI retention, then WFI.
- The comment there says the deep-sleep register is global: once it is set, a core that idles in an ordinary WFI hangs ("can hang the sleep process or cause memory corruption on wake"). That is the 2026-10-25 22:11 SoC death: one core's `cpu_sleep(true)` under cores still running Linux.
- The comment also says the wake skips iBoot on these SoCs: "The reconfig engine script brings the CPU out of reset at the kernel's reset vector", which for us is Aura's RVBAR path (image 51).
- Image 52 (`3617bb517d0e6813`, Aura diff in `patches/psci-efi/aura/wip-system-suspend.diff`) adds a control word:
  - `psci_ctl`: its magic is written at boot and is built at run time, so no copy of the image carries it.
  - Linux sets it before each suspend with `harness/mmio/aura-ctl.c`. The tool refuses unless exactly one block is found, and writes only the word after the magic.
  - `run.sh` sets it from `/var/lib/deepidle/aura-ctl`.
  - Bit 1: the S2R timer write, just before the boot core sleeps. MPMGR_AON's page is added to the runtime MMIO map.
  - Bit 2: macOS's order. The parked secondaries are released into `cpu_sleep(true)` after a set/way clean, then 2 ms later the boot core cleans all levels and does the same. Such cores come back only through RVBAR.
  - 0 is image 51's suspend. `psci_dbg[17]` holds the word Aura read, `[18]` 1 if the timer was written.
- `attended.sh` gains three runs, each with `slpa`: D (timer, aura-ctl 1), E (timer plus all cores, 3) and F (cores without timer, 2, the control). If the cores power down and the SoC never restarts them, WD1 resets the Mac about 144 s after `echo mem`, as in images 32 to 36.
- Regression armed, unattended and without `slpa`: image 52, aura-ctl 0x80 (a marker with no effect), 2 `deep` cycles of 60 s, counters on, root read-only. On the default boot `aura-ctl` finds no block and refuses (checked).

## 2026-11-05 16:44: image 52 regression: 2 of 2, Aura reads the control word

- `results-psci-efi-suspendall-20261105-1641`: no `slpa`, aura-ctl 0x80. `aura-ctl` found exactly one block (`0x10002bf3380`) before each `echo mem`.
- Both cycles came back, rc 0, after 62.5 and 61.4 s on the alarm line (`psci_dbg[4]` 0x2d4 = 724), all 10 CPUs online, 0 device errors. `psci_dbg[17]` = `5300000080` (the word Aura read), `[18]` 0 (no timer write). PMGR counters: `AWAKE` only.
- So the normal path is image 51's, and the control word reaches Aura. Flags cleared; boot.bin is the default again and next_entry is unset. Next: owner-attended run D (`slpa` plus the PMGR S2R timer).

## 2026-11-05 16:52: run D (`slpa` plus the PMGR S2R timer): reset without a resume record, earlier than the dead-man would; D2 armed

- Owner-attended run D: image 52, `deep_steps=6`, aura-ctl 1, 30 s alarm. `aura-ctl` set 0x1 at `0x10002b77380`. `echo mem` at 16:47:32.2; the alarm was due at 16:48:03.
- The next kernel started at 16:48:58: its RTC line at 21:49:12 UTC, uptime 14.0 s. That is 86 s after `echo mem`, against about 93 s in runs A to C.
- **No dead-man push** (ntfy has only the run's start push). The watcher's stream stopped after `PM: suspend entry`, as in every run (it ends about 34 s after the Mac goes quiet, even in the regression's 60 s cycles, so its end says nothing about the alarm).
- The test boot's journal ends at `echo mem`. The PMGR counters and `psci_dbg` are lost: their RAM is System RAM in the default boot. The PMU boot lines are the same as after every reset today.
- Reading:
  - The dead-man resets only after a push succeeds, or after 6 failed tries 10 s apart. A reset by it without a push would come later than A to C's, not 7 s earlier. So this was not the dead-man, and the timer write changed the outcome.
  - Assuming the usual 24 s from reset to kernel, the reset came at about `echo mem` + 62 s: about 59 s after the timer write, 32 s after the alarm.
  - Two readings fit:
    1. The SoC entered S2R, and the alarm woke it into a cold boot: no warm path, or Aura's RVBAR path failed inside its 10 s stage, with a firmware chain longer than a dog reset's.
    2. The S2R timer resets the SoC about 60 s after it starts if the AP never powers down. In run D only the S2R timer ran, and the cores stayed in retention.
- **Run D2 tells them apart:** the same steps with a 90 s alarm. A next kernel at about 86 s again means reading 2 (the timer, not the alarm). At about 146 s (the alarm plus 56 s) it means reading 1 (the SoC slept). A dead-man push means Linux resumed with the SoC up.

## 2026-11-05 16:57: run D2: the S2R timer resets the Mac by itself, about 60 s after it is written; run E armed

- Run D2 used run D's steps (image 52, `deep_steps=6`, aura-ctl 1) with a 90 s alarm. `echo mem` at 16:54:44.3, the alarm due at 16:56:14.
- The next kernel started at 16:56:09.1 (RTC 21:56:23 UTC at uptime 13.9 s): 84.8 s after `echo mem` and 5 s *before* the alarm. Run D's gap was 86 s with a 30 s alarm. There was no dead-man push.
- So the reset does not follow the alarm (reading 1 of the run D entry is out). The S2R timer resets the SoC about 60 s after it is written (about 61 s after `echo mem`, minus the 24 s firmware chain), whatever the alarm does.
- That fits a sleep-entry timeout: macOS powers every core down right after `startS2RTimer` (`ml_arm_sleep`). Our cores stayed in retention WFI, so the S2R entry never completed. Whether the SoC went partly down before the reset is not known: the counters do not survive it.
- It is also the first PMGR write from Linux/Aura that the SoC visibly acts on. Disk and filesystem clean; no PMU boot error logged.
- Next, run E: the timer plus macOS's all-core deep sleep (aura-ctl 3).
  - Reset at about 85 s again: the timer needs more than the cores off, i.e. quiesceHW's clock and PLL steps.
  - A resume, or a reset timed by the alarm: the SoC got further.
  - About 144 s: the cores powered down but the timer did not reset, and WD1 did, at 120 s.

## 2026-11-05 17:02: run E (timer plus macOS's all-core deep sleep): the same reset at about 86 s; run F (the control) armed

- Owner-attended run E: image 52, `deep_steps=6`, aura-ctl 3 (set at `0x10003bff380`), 30 s alarm. `echo mem` at 16:59:39.3. The next kernel started at 17:01:05.0 (RTC 22:01:19 UTC at uptime 14.0 s), 85.7 s later. No dead-man push.
- Same as D (86 s) and D2 (84.8 s). The reset was not timed by the alarm, and it was not WD1 (that would be about 144 s). With every core sent into macOS's deep sleep after the timer, the S2R timer still resets the Mac about 60 s after it starts.
- Unless the cores did not really power down: F tells.
- Reading: the cores alone are not what the S2R entry is waiting for. Left from macOS's sequence before the timer:
  - `quiesceHW`'s SoC-East clock gates, the ClkGen PLL-off writes and the GPU PMGR quiesce;
  - the PMP's IDLE `SetAPPower`/`SetIOPPower` (which crashed the PMP after `slpa` in run C);
  - the AIC and PMU SPMI quiesce (97000, 98000) after it;
  - the SMC's AP watchdog deadline (`0x29e2a002c`) at quiesce.
- Run F (aura-ctl 2, the cores without the timer) is the control.
  - About 144 s (WD1): the cores really do power down, and nothing restarts them without S2R.
  - A resume on the alarm: bit 2 does not really power them down, and E did not test what it meant to.

## 2026-11-05 17:08: run F (the cores without the timer): WD1 at 120 s, so the cores really power down. What D to F settle

- Owner-attended run F: image 52, `deep_steps=6`, aura-ctl 2 (set at `0x100024df380`), 30 s alarm. `echo mem` at 17:04:23.9. The next kernel started at 17:06:49.0 (RTC 22:07:03 UTC at uptime 14.0 s): 145.1 s later, which is WD1's 120 s plus the chain. No dead-man push.
- So with aura-ctl 2 every core really powers down (macOS's `cpu_sleep(true)`), the alarm cannot restart them, and only Aura's watchdog brings the Mac back, as with images 32 to 36. Run E therefore tested what it meant to.
- What D to F settle:

  | Run | Steps (all with `slpa`) | `echo mem` to next kernel | What reset the Mac |
  |---|---|---|---|
  | D | S2R timer, 30 s alarm | 86 s | the S2R timer |
  | D2 | S2R timer, 90 s alarm | 84.8 s (before the alarm) | the S2R timer |
  | E | S2R timer plus every core into deep sleep | 85.7 s | the S2R timer |
  | F | every core into deep sleep, no timer | 145.1 s | WD1 (120 s) |

  - Writing 1 to MPMGR_AON + 0x4000 starts a timer that resets the SoC about 60 s later unless the S2R entry completes. It is the first PMGR write from our side that the SoC acts on.
  - With `slpa` done and every core powered down macOS's way, the entry still does not complete. What macOS does before the timer and we do not:
    - `quiesceHW`'s SoC-East clock gates (0x1c0, 0x1e0), the ClkGen PLL-off writes (0x38158 to 0x3816c, bit 31 on and a wait on bit 30) and the GPU PMGR quiesce;
    - the PMP's IDLE;
    - the AIC and PMU SPMI quiesce actions;
    - the SMC's AP watchdog deadline.
  - Any of them may be what the reconfig engine waits on.
- No damage: every run reset cleanly, the filesystems are clean, and no PMU boot error was logged. Flags cleared; default boot.bin and no next_entry.
- Next (static, then owner-attended): decode `AppleT6020PMGR::quiesceHW`'s indirect calls (vtable +0xbd0, +0xdc0, +0x9b0, +0x958) into register writes. Then an image 53 step that does them in macOS's order before the timer. Also find what macOS's AIC and PMU quiesce actions write.

## 2026-11-05 17:24: image 53: the rest of `AppleT6020PMGR::quiesceHW` decoded and built (attended runs G, H); regression armed

- `AppleT6020PMGR::quiesceHW` (13.5) is decoded from the raw disassembly, since Ghidra mangles the indirect calls. The vtable slots were resolved with `vt-AppleT6020PMGR.txt`, and the register maps with `initRegMaps` (map → ADT `reg` index; ADT `0x8…`/`0x9…` is Linux `0x28…`/`0x29…`, and `0x204e…` is `0x404e…`). For each die, in order:
  1. `ApplePMGR::quiesceHW` (the super call): `_enableSOCPerfCounters(i, false)` over its table (the SoC perf counters off) and a log line.
  2. If MINI (`0x29e280000`) + 0x4d010 bits 18-19 are not both set: `writeReg32`(map 6 = reg 44, `pmgr_gfx` `0x404e80000`, + 0x100 = **`ps_afr`**, 0), then wait for the actual state (bits 7:4) to read 0 (timeout 0x2ee00). Read on Linux: MINI 0x4d010 = 0, so macOS takes this branch here. `ps_afr` reads `0x1404024f` (AUTO_ENABLE, PS_AUTO 4, PS_MIN 4, target f, actual 4).
  3. (T6022 only: two more writes on map 3.)
  4. Unless hibernating: `enableCluster(c, false, c > 3, die)` for clusters 1..N: a cluster PS register's target is set to 0, with a wait on bit 4 for c > 3. The register (`this`+9788/9792) is not resolved yet, so it is **not in image 53**.
  5. SOC-East (map 2 = `pmgr_east` `0x290280000`) + 0x1c0 = **`ps_sio`** and + 0x1e0 = **`ps_sio_cpu`**: AUTO_ENABLE (bit 28) cleared, then wait for actual == target. Linux reads `0x1f0000ff` and `0x1400024f`. These are the "afr and sio stay on in s2idle" domains from October.
  6. ClkGen-SOC (map 0x3f = reg 4, `0x28e000000`) + 0x38160, 0x38168, 0x38164, 0x38158, 0x3816c: `(v & 0x70ffffff) | 0x80000000`, then wait for bit 30 to clear.
  7. Unless hibernating: `setPLLOffMode`(map 0x37 = reg 46, `0x28e224000`, 0, 3): bits 5:3 = mode 3, then set bit 1, clear bit 0, wait for bit 31 to clear.
  8. `startS2RTimer`.
- The PMU's quiesce (`AppleDialogSPMIPMU::callPlatformFunction`) locks the SPMI bus; it sends no sleep command.
- Image 53 (`e93c3a7644406710`): two more control bits, run before the timer in that order. Polls are bounded at 10 ms each; old values are saved and written back on any resume, the RVBAR path included. `psci_dbg[19..22]` hold before/after for AFR, SIO, SIO_CPU and PLL-off; `[23]` the poll timeouts. The new MMIO pages are in the runtime map.
  - Bit 4 is steps 2 and 5.
  - Bit 8 is steps 6 and 7.
- `attended.sh` gains G (aura-ctl 7: E plus the domains) and H (15: plus the clocks and PLL-off). Both wait for the owner.
- Regression armed, unattended and without `slpa`: image 53, aura-ctl 0x80, 2 `deep` cycles of 60 s, root read-only. It checks the extra runtime ranges and the normal path; none of the new steps run.

## 2026-11-05 17:31: image 53 regression: 2 of 2

- Results dir `results-psci-efi-suspendall-20261105-1726`: aura-ctl 0x80 at `0x10003a77380`.
- Both cycles came back, rc 0, after 62.7 and 62.8 s on the alarm line (724), with all 10 CPUs online and 0 device errors.
- `psci_dbg[17]` read `5300000080`; `[18..23]` were 0 (no new step ran).
- The extra runtime MMIO ranges are harmless. Flags cleared; default boot.bin, no next_entry. G and H are ready for the owner.

## 2026-11-05 17:36: lead: the ANS wrapper's IO RVBAR, iBoot's boot address for the ANS CPU; save/restore in the test kernel; regression armed

- The cluster register for `quiesceHW` step 4 is still open: `enableCluster` writes regmap [`this`+9788] at offset [+9792] + 4 × physical cluster. It is filled through a pointer in `ApplePMGR::initDriver` after the ADT's `clusters` property (`[4, 4, 4]`) is read, not by a direct store. Parked.
- `AppleA7IOP::startCPUWithOptions` and `AppleASCWrapV4` (13.5) have `_setIORVBAR(addr)`: a 64-bit write of `addr | lock` to offset 0 of the ASC's device memory index 1. `_isIORVBARLocked` reads bit 0 back.
  - For the ANS, ADT `/arm-io/ans` reg 1 is `0x347050000`. Linux does not map it.
  - Read now (the ANS is up): `0x0000010000004001`, i.e. boot address `0x10000004000` in DRAM, locked.
  - The PMP's (`/arm-io/pmp` reg 1, `0x28e850000`) reads `0x000000028e700001`: boot address `0x28e700000`, the PMP firmware region, locked.
- Lead: iBoot sets these once. If the SMC's `slpa` power cut resets the ANS wrapper, the IO RVBAR comes back 0. RUN then starts the ANS CPU with no boot address, which fits status 0x08 and `ANS did not boot` after every `slpa` (the SART was ruled out in run C). The PMP's wake failures in October may share the cause.
- Test kernel patch `0001-TEST-nvme-apple-save-the-ANS-wrapper-s-IO-RVBAR-at-s.patch`:
  - `nvme_apple.iorvbar_phys` (0 = off) maps the register at probe and logs it. Suspend saves it.
  - The reset path writes it back just before RUN (both RUN sites), only when it changed, and logs `TEST iorvbar: kept …` or `was …, restored …`.
- Image installed (`9ca4c03061249ba0`, the old one in `/var/lib/deepidle/vmlinuz-psci-efi-test.pre-iorvbar`). `install.sh suspendall` now passes `nvme_apple.iorvbar_phys=0x347050000`.
- The dead-man snapshot also reads the IO RVBAR, so the next `slpa` run shows whether `slpa` clears it.
- Regression armed (unattended, no `slpa`, image 53, aura-ctl 0x80, 2 `deep` cycles of 60 s). Expect the probe line, then `kept 0x10000004001` on each resume and 0 errors.

## 2026-11-05 17:41: IO RVBAR test kernel regression: 2 of 2, the register survives a normal suspend

- At probe: `TEST iorvbar: 0x347050000 reads 0x10000004001`. After each resume: `kept 0x10000004001`.
- Both cycles came back, rc 0, after 62.9 and 62.4 s, with all 10 CPUs online and 0 device errors.
- genpd gates `ps_ans2` during a normal suspend (11-05 06:40), so a PMGR power gate does not clear the IO RVBAR. Whether the SMC's `slpa` cut does is what the next attended `slpa` run shows: the dead-man snapshot now reads it, and the restore is in place.
- Flags cleared; default boot.bin, no next_entry.

## 2026-11-05 17:51: the PMP crash in run C was a double SetAPPower (test kernel bug), fixed; regression armed

- Run C's dead-man push (16:01) has the PMP's crashlog mailbox tail: `#029`, `#030`, `#031` are all `00b0000000000201` (management endpoint, type 0xb = SetAPPower, state 0x201), after a long quiet gap.
- The test kernel's `apple_pmp_sleep_power` sent `set_ap_power(0x201)` and then `RtKit::idle`, and `apple_rtkit_idle` sends SetAPPower 0x201 itself before SetIOPPower 0x201. So the PMP got the same AP state twice: request, ack, request again.
- The PMP firmware (`t6020pmp` from 13.5, `__TEXT` at 0x1000000) handles management type 0xb at 0x1044f28. It maps the state to an internal value (0x201 → 8; 0x20 → 0x21; 0x10 → 0x20) and **panics with `Invalid AP power: %d` when the new value equals the current one** (0x1044f48: `cmp`, `b.eq` to the panic at 0x1044fac).
- That matches the 10-23 PMP test, where `idle()` alone was acked (`0x20 -> 0x201`). So run C's crash says nothing about the PMP's sleep preconditions; it was my bug.
- Fix (kernel patch `0001-TEST-pmp-send-the-PMP-s-sleep-IDLE-once-…`): `idle()` only, which is macOS's order (SetAPPower 0x201, then SetIOPPower 0x201). Image `254c93bd5410a827` installed; the old one in `/var/lib/deepidle/vmlinuz-psci-efi-test.pre-pmpidle`; staging updated. `macsmc.pmp_sleep` stays off by default, so only attended run C uses it.
- On the AP side, macOS's `ApplePMP::_powerStateHandlerGated` only checks that no PMP command is pending (`_eHubCommandPending == NULL`, `_pmCommandPending[i] == NULL`) before sleep; it sends nothing itself.
- One more difference, not acted on: the PMP's power-request word (`0x28e3c2000`, ack at `+0x80`) reads `0xf000` on Linux now: ISP_SYS, DISP0, DISPEXT0 and DISPEXT1 (report entries 0xc to 0xf; the display ones are always-on in the DT). In the macOS trace it is `0x300` (only the CPU complexes PCPM0 and PCPM1) when `slpa` is sent. If the PMP or the PMGR waits for those domains, clearing them before `slpa` is the next PMP-side step.
- `attended.sh`: the boot prompt now has readings for A (the IO RVBAR restore) and C (the PMP IDLE once).
- Regression armed (unattended, no `slpa`, no `pmp_sleep`, image 53, aura-ctl 0x80, 2 `deep` cycles of 60 s): it only checks that the new Image boots and suspends.

## 2026-11-05 17:58: PMP-IDLE-once test kernel regression: 2 of 2

- Image `254c93bd5410a827` (build #9), no `slpa`, no `pmp_sleep`, image 53, aura-ctl 0x80, 2 `deep` cycles of 60 s.
- Both back, rc 0, after 62.3 and 62.8 s; `online 0-9`; 0 device errors. The dead-man switch saw the disk each time.
- `TEST iorvbar: kept 0x10000004001` on both resumes. The PMP answered throughout (no crash line). PMGR counters: `AWAKE` only, `SLP_S2R` 0. Aura read the word (`psci_dbg[17]` 0x5300000080), and `[19..23]` are 0.
- Flags cleared; default boot.bin `76f850895fed53d1`, `next_entry` unset.
- Static, the PMP's requests: `pmp-report` already has a sleep release (`apple,release-for-sleep` per report entry). It withdraws an acknowledged request in `suspend_noirq` and asserts it again in `resume_noirq`, up to 3 writes. No J414s entry sets it. Setting it on disp0, dispext0 and dispext1 (and isp-sys, which is not always-on) would give the `0x300`-like state macOS has at `slpa`.
  - Risk: if the PMP powers the display complexes down and DCP cannot restart afterwards, the display stays dark until reboot. That is acceptable headless, and it is the same problem a real S2R has anyway.
  - It is a DT-only test change. For an attended run, not unattended: it changes what the PMP powers in a normal suspend.
- Board: the PMP item notes run C's real cause.

## 2026-11-05 18:06: owner-attended run A again (`slpa`, IO RVBAR restore): the IO RVBAR is kept, the lead is wrong; the ANS does start

- Owner-attended (5 min window), image 53, `deep_steps=6`, aura-ctl 0, 1 `deep` cycle, 30 s alarm, counters on, root read-only. Test kernel `254c93bd5410a827`. The run started at 18:01:37 (ntfy). Dead-man push at 18:04:50. The Mac reset itself and came back on the default kernel at 18:05. The owner did not reset it by hand.
- From the dead-man push (run.log never reached the dead disk):
  - Resumed on the alarm.
  - `TEST iorvbar: kept 0x10000004001`: **`slpa` does not clear the ANS wrapper's IO RVBAR**. The dead-man snapshot reads `IORVBAR 00004001 00000100`, the same value.
  - Then `RTKit: Initializing (protocol version 12)`, `IOP power acknowledgment failed: -62`, `ANS did not boot`. ANS CPU status `0x10`/`0x08`, as in every `slpa` run.
  - `apple-sart: entries kept`. PMGR counters `AWAKE` only (`SLP_S2R` 0). `psci_dbg[17]` 0x5300000000 (aura-ctl 0).
- Reading, and a correction to the 17:36 lead: `RTKit: Initializing (protocol version 12)` means the ANS firmware runs and answered the management HELLO. That was already in runs A to C, so the IO RVBAR lead could have been ruled out from the logs. The ANS boots; what it does not do is ack the IOP power-on.
  - Most likely it is stuck behind the storage power the SMC cut at `slpa` (NAND and its rails). The SMC only brings that back in its own S2R wake, and `waka` from a running AP does not (finding of 11-04).
  - So the ANS failure follows from the SoC never going down, and the ANS is not a separate bug to fix first. What counts next is the SoC sleep itself: runs C, G and H.
- After the run: test flags removed; default boot.bin `76f850895fed53d1`, `next_entry` unset. btrfs error counters all 0, no errors in the kernel log, so no scrub. Headless on.
- The IO RVBAR restore stays in the test kernel: it is a logged no-op, and it keeps logging the value.

## 2026-11-05 18:11: test: release the PMP's display requests for sleep, as macOS has them at slpa; regression armed

- Owner, 18:1x: "run any unattended tests, then update all docs and status pages/files. then, do a sleep to test what we have now vs baseline."
- Unattended means no `slpa` and none of image 53's SoC steps: PLL-off or the AFR off on an awake SoC can hang it. Runs C, G and H stay attended.
- The PMP's request word reads `0xf000` on Linux (ISP_SYS, DISP0, DISPEXT0, DISPEXT1); macOS has `0x300` at `slpa`. `pmp-report` already withdraws `apple,release-for-sleep` entries in `suspend_noirq` and asserts them again in `resume_noirq`. Its comment puts the J514S external-display case at about 0.25 W in s2idle.
- Test kernel patch `0001-TEST-pmp-report-test_release_aon-…`: `pmp_report.test_release_aon` (default off, writable at run time) sends the always-on entries (disp0, dispext0, dispext1) down that path. Each withdraw and assert logs the PMP's ack word. Image `6ad0396dbb7259df`; the old one is in `/var/lib/deepidle/vmlinuz-psci-efi-test.pre-pmprelease`.
- `run.sh`: `/var/lib/deepidle/pmp-release-modes "<modes>"` sets the parameter per sleep mode (1 in the listed modes, 0 in the others). It logs the request and ack words before the cycles and after each resume. So one boot can measure `deep` with the release against plain `s2idle`.
- Risk: if a display complex does not come back, the screen stays dark until reboot. That is acceptable headless. The driver retries the assert 3 times and logs a failure.
- Regression armed (unattended): image 53, aura-ctl 0x80, 2 `deep` cycles of 60 s, release on. Expect `withdrawn … ack` without the display bits, `asserted` on resume, `0xf000` back after each resume, and 0 device errors.
- If it passes, next: the sleep A/B on battery, `deep` plus the release against `s2idle` (the baseline), 1 h each in one boot.

## 2026-11-05 18:18: PMP request release regression: 2 of 2; the PMP drops the display requests and takes them back

- Image `6ad0396dbb7259df` (build #10), image 53, aura-ctl 0x80, `pmp_report.test_release_aon` = Y in `deep`, 2 `deep` cycles of 60 s, root read-only.
- Before the cycles: requests `0xf000`, ack `0xf000`.
- In each suspend (`suspend_noirq`), requests 14, 15 and 13 (dispext0, dispext1, disp0) were withdrawn, each acked: the ack word went `0xf000` → `0xb000` → `0x3000` → `0x1000`. Only ISP_SYS (bit 12) stays.
- On resume (`resume_noirq`) all three were asserted again, each acked. A transient `0x2f000` shows AVD_SYS (bit 17) coming up with them.
- After each resume: requests and ack `0xf000`.
- Both cycles back, rc 0, 62.5 and 62.8 s; `online 0-9`; 0 device errors. The only DCP lines are the usual `dcp_dptx_disconnect` and `dcp_hotplug() connected:0` for the unused external port. The internal panel still reads `connected`.
- So the PMP is now in macOS's state at `slpa` for the displays. ISP_SYS is the one difference left: its DART keeps the domain on (`PM domain pmp-isp-sys will not be powered off`).
- Flags cleared; default boot.bin `76f850895fed53d1`, `next_entry` unset. Next, per the owner's order: all docs, then the sleep A/B with the release in `deep`.

## 2026-11-05 18:23: sleep A/B armed: what we have now (`deep` with the PMP release) against the baseline (`s2idle`)

- Owner's order, step 3: "do a sleep to test what we have now vs baseline."
- One boot, the test kernel (`6ad0396dbb7259df`), image 53 with no aura-ctl (image 51's suspend).
  - Cycle 1: `deep` = PSCI `SYSTEM_SUSPEND` through Aura, every CPU parked, the PMP's display requests released (`pmp-release-modes` `deep`).
  - Cycle 2: `s2idle` = the baseline.
- 3600 s alarm each, on battery: forced discharge from 89%, limits 20/15 for the run, 80/75 put back after (`discharge` holds `80 75`). PMGR counters on, root read-only.
- Earlier references (11-05 12:01): `deep` 1.444 W over 6391 s, `s2idle` 1.478 W over 6300 s. macOS: 0.24 W. The difference this run can show beyond that is the release (estimated 0.25 W for the J514S external display case; not measured here).
- The docs commit (c9b8a78) was rejected twice by GitHub (`remote: fatal error in commit_refs`, both refs), with githubstatus all operational and admin permission. It was retried after this entry.

## 2026-11-05 20:28: sleep A/B: what we have now 1.458 W, s2idle (baseline) 1.504 W, macOS 0.24 W

- Run 18:25 to 20:27, one boot, test kernel `6ad0396dbb7259df`, image 53 with no aura-ctl, on battery (forced discharge from 89%), root read-only, PMGR counters on.

  | Arm | Elapsed | Energy (µWh) | Average |
  |---|---|---|---|
  | `deep`: Aura `SYSTEM_SUSPEND`, every CPU parked, the PMP's display requests released | 3602.8 s | 52029600 → 50570400 | **1.458 W** |
  | `s2idle` (baseline) | 3600.4 s | 50547600 → 49042800 | **1.504 W** |

- Both back on the alarm, rc 0, `online 0-9`, 0 device errors.
- The release ran only in `deep`: 3 withdrawn, 3 asserted, requests `0xf000` after each resume.
- PMGR counters: `AWAKE` only in both cycles, `SLP_S2R` 0. The SoC never slept.
- Reading:
  - Suspend to RAM is 0.046 W (3%) below s2idle in the same boot. The morning's long pair gave 0.034 W (1.444 against 1.478 W).
  - Both arms are about 0.015 to 0.025 W higher than in the morning, so the absolute level moves run to run.
  - Releasing the display requests made no measurable difference: 1.458 W with it, 1.444 W without it in the morning, inside the 1.44 to 1.49 W spread of the long runs. With nothing plugged in, the display domains it lets go draw little.
- So what we have now is the same as before: about 1.46 W, against s2idle's 1.50 W and macOS's 0.24 W. The 1.2 W gap is the SoC staying awake, and only the attended S2R runs (C, G, H) can move it.
- Afterwards: `charge_behaviour` auto, limits 80/75 (`discharge off` in the log), flags removed, `sleep-modes` back to `deep`. Default boot.bin `76f850895fed53d1`, `next_entry` unset.
- Log: `data/drain-ab/2026-11-05-image53-deep-release-vs-s2idle.log`.

## 2026-11-05 21:21: owner at the Mac for attended runs: C, then G, then H

- Owner: "ready for attended tests. send notifications before starting each."
- `attended.sh` sends the owner a push before each reboot: what to expect, and when to hold power.
- New options:
  - `REL=1` (default): the PMP's display requests are released for sleep in each run, so the PMP is in macOS's state at `slpa` (harmless in normal suspends, 2 of 2).
  - `NEXT="G H"`: each run's boot prompt arms the next run once the result is recorded and the Mac is clean. It stops the chain on a btrfs error, a hand reset or a missing default boot.bin.
- C: `slpa` and the PMU boot stage (`deep_steps` 14), plus the PMP's IDLE (now sent once).
- G: `slpa` + aura-ctl 7: the S2R timer, every core in deep sleep, and `quiesceHW`'s power domains.
- H: G + the clock-generator and PLL-off writes (aura-ctl 15).

## 2026-11-05 21:26: owner-attended run C again: the PMP accepts its IDLE now; the SoC still stays AWAKE

- Image 53, `deep_steps=14`, `pmp_sleep=1`, aura-ctl 0, the PMP display release on, 1 `deep` cycle, 30 s alarm, counters on, root read-only. Test kernel `6ad0396dbb7259df`. Started 21:21:18 (push). Dead-man push and reset at 21:24:38; the owner confirmed it ("Dead man switch was activated @ 9:24"), no hand reset. Back on the default kernel at 21:25.
- `PMP SetAPPower/SetIOPPower IDLE: 0`: **the PMP accepted macOS's step 5, no crash**. So the double SetAPPower was the whole cause of the 16:01 crash.
- The display release ran after that, in `suspend_noirq`, and found the PMP already idle: `withdrawn for sleep: -114` (`-EALREADY`: the status is not READY), `ack 0x0`. Once IDLE, the PMP has dropped every ack. So with `pmp_sleep` the release has to come before `slpa`, as in macOS (step 3 before step 4), not in `suspend_noirq`.
- Wake: `SetAPPower ON: 0` to the SMC; the PMP did not ack the IOP power-on (`PMP wake: -62`), as expected without a power cycle (10-23).
- ANS: `RTKit: Initializing`, then `IOP power acknowledgment failed: -62`, `ANS did not boot`. The dead-man snapshot has ANS CPU status `0x28` this time, not `0x08` (0x28 is its healthy value); `ps_ans2` `1f0002ff`. IO RVBAR kept, SART kept.
- PMGR counters `AWAKE` only, `SLP_S2R` 0; `psci_dbg[17]` 0x5300000000.
- btrfs error counters 0, no errors in the log. Flags removed; default boot.bin, `next_entry` unset; headless on.
- Chain: G next (`NEXT="H" attended.sh G`).

## 2026-11-05 21:31: owner-attended run G (image 53, aura-ctl 7): the same S2R-timer reset, 85.3 s after `echo mem`

- `slpa` (`deep_steps` 6) and the PMP display release. aura-ctl 7: the S2R timer, every core in deep sleep, and `quiesceHW`'s power domains (`ps_afr` off, the SmartIO auto power-on off) before the timer. `run.sh` logged `aura ctl … 0x7`.
- Started 21:26:37 (push). `echo mem` 21:28:43.3. No dead-man push, so no resume. Next kernel 21:30:08.6 (the RTC line at 21:30:22.5 minus its 13.9 s): **85.3 s**, the S2R timer's own reset as in D, D2 and E (84.8 to 86 s). It was not a hand reset.
- So the GPU fabric domain and the SmartIO auto power-on are not what the S2R entry waits for. Aura's before/after register words (`psci_dbg[19..21]`) are lost with the reset.
- btrfs counters 0; flags removed; default boot.bin, `next_entry` unset. Chain: H next (adds the clock-generator and PLL-off writes).

## 2026-11-05 21:36: owner-attended run H (aura-ctl 15): the same S2R-timer reset, about 84.7 s; what G and H settle; run I added

- `slpa` (`deep_steps` 6), the PMP display release. aura-ctl 15 (Aura logged `0xf`): the S2R timer, every core in deep sleep, `quiesceHW`'s power domains, and its clock-generator and PLL-off writes, in macOS's order.
- Started 21:31:38 (push). `echo mem` 21:33:44.3. No dead-man push. Next kernel about 21:35:09 (the RTC line at 21:35:23, 1 s resolution, minus its 14.0 s): **about 84.7 s**, the S2R timer's reset again. No hand reset. btrfs counters 0.
- G and H together: all of `AppleT6020PMGR::quiesceHW` except the cluster power-off, run before the timer with `slpa` and every core powered down, still does not let the S2R entry complete. The Mac resets about 60 s after the timer write in every case (D, D2, E, G, H).
- What macOS does that none of these runs did together:
  1. **The PMP's IDLE and the PMGR steps in the same sleep.** Run C had the PMP's IDLE (accepted) but no timer. G and H had the timer but no PMP IDLE. The PMP is the SoC's power manager, and the S2R sequence may run through it.
  2. `quiesceHW`'s cluster power-off (`enableCluster(c, false)`; its register is likely the CPU complexes' power states at `0x28e080060` to `0x70`).
  3. The PMU's SPMI quiesce.
- Next: **run I** = C + H (`deep_steps` 14, `pmp_sleep`, aura-ctl 15), added to `attended.sh`. The PMP display release cannot happen in `suspend_noirq` once the PMP is idle (run C: `-EALREADY`). In run I it is skipped harmlessly; moving it before `slpa` is a kernel change for later.
- Flags removed; default boot.bin, `next_entry` unset. The chain C, G, H is done.

## 2026-11-05 21:39: owner-attended run I (C + H) starting

- Owner: "Go, I am here for now, so just notify and run."
- `deep_steps` 14, `pmp_sleep`, aura-ctl 15, PMP release on (skipped once the PMP is idle), 1 `deep` cycle, 30 s alarm.

## 2026-11-05 21:44: owner-attended run I (C + H): the same S2R-timer reset, about 84.9 s

- `deep_steps` 14 (`slpw`, `slpa`, PMU boot stage 0x50), `pmp_sleep` (the PMP's IDLE after `slpa`), aura-ctl 15 (Aura logged `0xf`: the whole PMGR quiesce but the cluster power-off, every core in deep sleep, the S2R timer).
- Started 21:39:15 (push). `echo mem` 21:41:29.0. No dead-man push. Next kernel about 21:42:53.9 (the RTC line at 21:43:08, minus its 14.1 s): **about 84.9 s**, the S2R timer's reset once more. No hand reset. btrfs counters 0.
- Whether the PMP acked its IDLE in this run is not recorded: the root was read-only and the reset took the kernel log. Run C showed it acks in this exact sequence.
- So macOS's PMP IDLE plus the PMGR quiesce plus every core powered down still leave the S2R entry incomplete.
- What is left of macOS's sequence:
  1. `quiesceHW`'s cluster power-off.
  2. The PMU's SPMI quiesce.
  3. The **AOP**: the PMGR's own counters include `SYS_S2R_AOP`, an S2R state with the AOP, and Linux never tells the AOP the system is going to sleep. In macOS the AOP stays up through S2R (it runs the lid and keyboard wake sources). An AOP sleep handshake is a new lead, to read statically in macOS 13.5 (`AppleAOP`/`AOPRTBuddy` platform actions).
- Flags removed; default boot.bin, `next_entry` unset.

## 2026-11-05 21:58: static: macOS tells the AOP the AP is going to sleep (SetAPPower 0x201); test kernel sends it now; regression armed

- **What macOS sends the AOP.** The AOP's ADT nub (`iop-aop-nub`, `rtbuddy-v2`) has neither `power-managed` nor `user-power-managed`, only `sleep-on-hibernate`. For such an IOP, `RTBuddy::_setPowerStatePerformChangeGated` does not power it down at system sleep. It calls `RTBuddy::_signalApStateGated(state)` (13.5, `0xfffffe000ae95298`), which goes to the management endpoint's `_signalApPowerGated`: `SetAPPower` (type 0xb) with 0x201 for sleep, 0x20 for on, 0 for off. It then waits for the IOP to report that state (`_waitForRemoteStateGated`) and logs "No response to AP power notification" if it does not. The AOP keeps running.
- **Linux never sent it.** `aop.rs` has no suspend hooks. The SMC already gets the same message in our test kernel (`macsmc.ap_idle_in_suspend`, which stopped the SMC ending sleeps). The AOP's outbox (`AOP.OutboxNotEmpty`, bit 26) is an AP wake source in the PMGR mask, and every source is enabled on Linux. In s2idle the AOP mailbox raised 61 to 72% of all SoC wakes. So a busy AOP outbox is a candidate for what keeps the PMGR's S2R entry from completing in runs D to I.
- **Test kernel** (patch `0001-TEST-soc-apple-aop-SetAPPower-0x201-to-the-AOP-acros.patch`): a PM notifier in `aop.rs` sends 0x201 at `PM_SUSPEND_PREPARE` and 0x20 at `PM_POST_SUSPEND`, the latter only after an acked 0x201 (the PMP's firmware panics on a repeated AP state). It is sent outside the driver's `rtkit` lock: the RTKit receive work is ordered and takes that lock for AFK messages, so one queued ahead of the ack would deadlock. The Rust `RtKit` gained `as_raw()`. `apple_aop.sleep_ap_idle=0` turns it off (default on).
- Image `86fc1002a296c8a0`, the module tree re-staged and installed (old Image in `/var/lib/deepidle/vmlinuz-psci-efi-test.pre-aopidle`), initramfs rebuilt.
- `run.sh` now logs the AOP mailbox interrupts over each cycle and the `TEST SetAPPower` lines.
- **Regression armed** (no `slpa`, no `pmp_sleep`): `install.sh suspendall`, 2 `deep` and 2 `s2idle` cycles of 60 s, PMGR counters on. To check: the AOP acks 0x201 and 0x20, every cycle comes back, the AOP's interrupt count over the sleep drops, and the ALS still reads after resume.

## 2026-11-05 22:07: AOP SetAPPower regression: the AOP crashes after acking 0x201; CPUs 1 to 9 do not come back after the first deep resume; control run armed

- Image `86fc1002a296c8a0`, no `slpa`, no `pmp_sleep`, 2 `deep` and 2 `s2idle` cycles of 60 s, PMGR counters on. Log: `data/aop-sleep/2026-11-05-2159-ap-idle-on.log`.
- All 4 cycles came back, rc 0 (106.7, 60.4, 60.4, 60.5 s). The dead-man switch saw the disk every time; btrfs error counters 0.
- **The AOP acked 0x201 (`TEST SetAPPower 0x201 for system sleep: 0`), then crashed 140 ms later**, during device suspend: `RTKit: co-processor has crashed`, firmware `mac14jaop:AppleSPUFirmwareBuilder-427.100.4` (RTKit-2062.141.1.debug), exception from EL1t, PC `0x1002880`, ESR `0x96000061` (a write, alignment fault), FAR `0xffffffffe501e9d2`. The mailbox history ends with our 0x201 and its ack, once each, so this is not a repeated AP state (unlike the PMP crash in run C).
- After that the AOP is gone: the 0x20 on resume returns -22, every later 0x201 -22, and no AOP mailbox interrupts over cycles 2 to 4 (cycle 1 shows -286, the line's count reset with the crash). The ALS read 0 before and after (dark room); the lid angle stays at its cached 106.
- **After the first `deep` resume CPUs 1 to 9 failed to come online** (`CPU1: failed to come online`, `Error taking CPU1 up: -5`, 5 s each, hence the 106.7 s cycle). Every regression earlier today came back with `online 0-9`. Whether the AOP message, its crash, or something else in this boot caused it is not known yet.
- PMGR counters: `AWAKE` only; `SLP_S2R` and `SYS_S2R_AOP` 0, as expected without `slpa`.
- So macOS must do something before `SetAPPower 0x201` that Linux does not, or the firmware's sleep path touches state that Linux left differently (the bad FAR looks like a garbage 32-bit pointer, sign-extended).
- **Control run armed:** the same run with `apple_aop.sleep_ap_idle=0` (new `install.sh` flag `/var/lib/deepidle/aop-ap-idle-off`). If the CPUs come back, the AOP's 0x201 is what broke them.

## 2026-11-05 22:14: control run void (wrong parameter name); both results repeat; control armed again

- The control boot had `apple_aop.sleep_ap_idle=0`, but the module is `aop.ko` (`apple_aop` is only the driver name), so the parameter was ignored and the AOP got 0x201 again. Log: `data/aop-sleep/2026-11-05-2208-ap-idle-on-again.log`.
- That run reproduced both results: the AOP crashed 220 ms after acking 0x201, and CPUs 1 to 9 failed to come online after the first `deep` resume (106.6 s cycle). 4 of 4 cycles back, rc 0.
- `install.sh` now passes `aop.sleep_ap_idle=0`. Control armed again.

## 2026-11-05 22:21: control run (AOP message off): 4 of 4 back, CPUs 0-9, 0 device errors; the AOP's 0x201 breaks the CPU bring-up

- Same image and run with `aop.sleep_ap_idle=0`. Log: `data/aop-sleep/2026-11-05-2215-ap-idle-off.log`.
- 4 of 4 back, rc 0 (63.3, 63.0, 60.7, 60.9 s), `online 0-9` after every resume, 0 device errors, no AOP crash.
- AOP mailbox interrupts over each cycle: 16 and 14 in `deep` (Aura's deep WFI), 219 and 219 in `s2idle` (3.6 a second, as in the s2idle nights).
- **So the AOP's `SetAPPower 0x201`, or the crash that follows it, is what keeps CPUs 1 to 9 from coming back.** Two runs with it failed the same way, the run without it is clean. The AOP takes part in the AP's power at sleep, which fits the PMGR's `SYS_S2R_AOP` state. It is the first Linux-side change that has altered how the CPUs behave across a suspend.
- Next: the crash itself, statically (PC `0x1002880` in the AOP firmware from the 13.5 IPSW), and what macOS gives the AOP before the 0x201.

## 2026-11-05 22:24: why the AOP crashed: macOS stops each AOP endpoint's queue before the 0x201; test kernel does it now; regression armed

- **The crash site.** In `aopfw-mac14jaop` (13.5), PC `0x1002880` is in `memcpy` (`0x1002768`), called at `0x100f0d8` from the AOP's ring writer. That routine builds an entry header (magic `0x4f41`, "AO"), asserts on the ring indices, and copies (pointer, length) segments into the ring. Its destination was `0xffffffffe501e960`. So the AOP was writing a sensor report into an AP-side ring after it had been told the AP was asleep.
- **What macOS does first.** `AppleSPU` (one instance per AOP endpoint, a child of RTBuddy, so it powers down first) has `setPowerStateGated(0)` → `AppleSPU::_stopQueue`. That sends the endpoint `0xa4 << 48` (`0xc2` when hibernating) and sleeps on `_queueStopped`. `_asyncMessage`'s opcode table sets it on the AOP's `0x87` (and `0xc3`). Wake: `_startQueue` sends `0xa3` (START) and waits for `0x86` (START_ACK). Linux's `aop.rs` knew neither `0xa4` nor `0x87`.
- **Test module** (patch `0001-TEST-soc-apple-aop-stop-the-AFK-queues-…`): the PM notifier now stops every started endpoint's queue (`0xa4`, waits up to 1 s for `0x87`) and only then sends 0x201. On wake it sends 0x20, then restarts each queue (`0xa3`, waits for `0x86`). If any endpoint does not confirm the stop, it skips the 0x201. Waits are outside the `rtkit` lock.
- Only `aop.ko` changed (old one in `/var/lib/deepidle/aop.ko.pre-queues`).
- **Regression armed** with the message on (`aop-ap-idle-off` removed): 2 `deep` and 2 `s2idle` cycles of 60 s. To check: the queues stop and restart, no AOP crash, `online 0-9` after every resume, AOP interrupts in `s2idle`.

## 2026-11-05 22:35: queue handshake works (12 of 12 stop and start, no AOP crash, sensors live); CPUs 1 to 9 still do not come back; 0x20 moved to syscore resume; armed

- Run 22:25 (log `data/aop-sleep/2026-11-05-2225-queues-stopped.log`): every sleep logged `TEST queues stopped for system sleep: 12 of 12`, then `SetAPPower 0x201: 0`. Every wake logged `SetAPPower 0x20: 0`, then `queues started after system sleep: 12 of 12`. No AOP crash in four cycles. After resume the ALS read 139.6, 138.9, 137.9, 137.0 lux and the lid angle 13 (live values; the earlier runs had only cached ones).
- 4 of 4 back, rc 0, 0 dead-man resets. **But CPUs 1 to 9 again failed to come online after the first `deep` resume.** So it is the AOP's "AP asleep" state, not its crash, that keeps the parked cores from waking.
- PMGR counters: no `SLP_S2R`, `DEEP_WAIT` or `SYS_S2R_AOP` time. The SoC stayed awake; only the cores failed. The cluster power words `0x28e080060`/`68`/`70` read `0x1f0` with the cores stuck, as normally.
- **Why (hypothesis).** Aura parks an offlined core in deep WFI and `CPU_ON` wakes it with SEV and an IPI. The 0x20 went only at `PM_POST_SUSPEND`, long after `pm_sleep_enable_secondary_cpus()`. Told the AP is asleep, the AOP may own the cores' wake (the PMGR's `AOP.CPUWakeupAP` source) and swallow it. macOS does not hit this: its cores are powered off and restarted through the PMGR, not woken by IPI.
- **Test module** (patch `0001-TEST-soc-apple-aop-SetAPPower-0x20-from-syscore-resu…`): a syscore resume hook sends 0x20 atomically (interrupts off, boot CPU only) before the secondaries come back. The ack is handled once interrupts are on. `PM_POST_SUSPEND` then only restarts the queues. In `s2idle` no syscore runs, so there the 0x20 stays at `PM_POST_SUSPEND`.
- **Armed** with `force-ro` (every filesystem read-only for the cycles), since a hang in syscore resume would end in a watchdog reset: 2 `deep` and 2 `s2idle` cycles of 60 s.

## 2026-11-05 22:44: 0x20 from syscore resume does not help; the 0x201 moved after the parking; armed

- Run 22:36 (`data/aop-sleep/2026-11-05-2236-ap-on-syscore.log`, read-only): the queues stopped (12 of 12), 0x201 acked, and `SetAPPower 0x20 from syscore resume (before the secondary CPUs): 0`. CPUs 1 to 9 still failed to come online. 4 of 4 back, rc 0.
- So whatever the AOP does in its "AP asleep" state reaches the cores **while they are parked**, not only after. Aura's `CPU_ON` of a parked core is SEV plus an IPI, never the PMGR's `CPU_START` (`smp_psci_dispatch`). A core that the AOP-and-PMGR sleep state power-gated would not come back that way. macOS restarts its cores through the PMGR.
- **Next test (module only):** the 0x201 from `syscore_suspend` (interrupts off, after `pm_sleep_disable_secondary_cpus()`; the ack is handled after resume). The queues still stop at `PM_SUSPEND_PREPARE`, and the 0x20 still goes from syscore resume. In `s2idle` there is no syscore phase, so there the AOP is not told. If the cores now come back, the AOP acts on cores as they enter the park. If not, Aura's `CPU_ON` needs a PMGR start for a core that lost power, which is what real S2R will need anyway. Armed read-only.

## 2026-11-05 22:53: 0x201 only after the parking: CPUs still stuck; queues-only run armed to separate the two

- Run 22:45 (`data/aop-sleep/2026-11-05-2245-ap-idle-syscore.log`, read-only): the queues stopped at `PM_SUSPEND_PREPARE` (12 of 12). `SetAPPower 0x201 from syscore suspend (after the secondary CPUs): 0`, then `0x20 from syscore resume: 0` once the sleep ended. CPUs 1 to 9 still failed to come online. 4 of 4 back, rc 0.
- So when the 0x201 goes does not matter: cores already parked are lost too. But every failing run also stopped the queues, and the clean control (22:15) did neither. **Queues-only run armed:** `aop.sleep_ap_idle=2` (new mode: stop and start the queues, no SetAPPower; `install.sh` flag `/var/lib/deepidle/aop-sleep-mode`). If the CPUs come back, the AOP's AP-sleep state is the cause. If not, stopping the queues is.

## 2026-11-05 23:00: queues only, no SetAPPower: CPUs still stuck; a confound, the lid; AOP-off control armed with the lid as it is

- Run 22:54 (`data/aop-sleep/2026-11-05-2254-queues-only.log`, `aop.sleep_ap_idle=2`): the queues stopped and started (12 of 12), no SetAPPower at all. CPUs 1 to 9 still failed to come online after the first `deep` resume.
- **A confound:** the lid. The clean control (22:15) read a lid angle of 106. Every run from 22:25 on reads 13, so the lid was closed between those runs. The two lid-open failures (21:59, 22:08) both had the AOP crash. So the CPU failure may come from the closed lid (or what the SMC does with it) and not from the AOP handshake at all.
- **Control armed:** `aop.sleep_ap_idle=0` (no notifier, no syscore hooks), the lid left as it is. If the CPUs fail now, the lid is the variable and the AOP handshake is cleared. Then the next test is the full handshake again with the lid open, which needs the owner.

## 2026-11-05 23:09: AOP-off control with the lid closed is clean; the AOP queue stop loses the parked cores; queues-only again with Aura's per-CPU state logged

- Run 23:02 (`data/aop-sleep/2026-11-05-2302-ap-idle-off-lid-closed.log`, `aop.sleep_ap_idle=0`, lid angle 13): 4 of 4 back, `online 0-9` after every resume, 0 device errors. **The lid is not the cause.** Stopping the AOP's queues loses CPUs 1 to 9, with or without the SetAPPower (5 failing runs against 2 clean ones).
- Aura's parked cores do not take the S2R power-down here (`psci_s2r_go` is set only with aura-ctl bit 2). They sit in deep WFI with retention, and `CPU_ON` wakes them with SEV and an IPI. So with the AOP's queues stopped, a parked core either misses the wake or does not get to the kernel.
- To tell which, `run.sh` now logs Aura's shared SMP state after each resume: `psci_cpu_state` (0 parked, 1 on, 2 off) and each core's spin-table `flag` (entries taken) and `target`. It finds them from the `psci_dbg` magic (image base = `psci_dbg` − `0x1473e8`; `run.sh`'s old fixed `0x1472c8` read is stale for this build). Checked on this boot: CPU 1 is `mpidr 1`, `flag 5`. A core with `target` set and `flag` unchanged never woke from the park.
- **Armed:** queues only (`aop.sleep_ap_idle=2`), read-only.

## 2026-11-05 23:17: the stuck cores did leave Aura's park and jump to the kernel; they hang inside the kernel's secondary bring-up; cpuhp trace armed

- Run 23:10 (`data/aop-sleep/2026-11-05-2310-queues-only-cpustate.log`, queues only): the same failure, CPUs 1 to 9. After it, Aura's state for every secondary is `1` (ON, set by `CPU_ON`'s dispatch), its spin-table `target` is 0 and its `flag` went up (4 after one cycle). So each core woke from the park, took the entry and called `psci_enter`. The wake works; Aura is not where they stop.
- Linux's "failed in unknown state : 0x0" is the case where `secondary_data.status` is still `CPU_MMU_OFF` and `__early_cpu_boot_status` is 0. The core recorded no failure; it hung somewhere between the kernel entry and `complete(&cpu_running)`, possibly in a hotplug "starting" callback, which runs on the new core.
- The `flag` of 4 after one bring-up (the clean boot read 5 after four cycles, i.e. 1 + 1 per cycle) suggests a core entered the kernel more than once. Not explained yet.
- **Armed:** queues only again, now with the `cpuhp` tracepoints on (`/var/lib/deepidle/trace-cpuhp`; the trace is kept in `/run` during the read-only cycles and saved with the results). The last `cpuhp_enter` on `[001]` without its `cpuhp_exit` names the step that hangs.

## 2026-11-05 23:26: cpuhp trace: CPU 1 never reaches its first hotplug step; queues restarted from syscore resume; armed

- Run 23:18 (`data/aop-sleep/2026-11-05-2318-queues-only-cpuhp.log`, queues only, `cpuhp` tracing): CPU 1's last events on `[001]` are its own teardown at 67.10 s (`kvm_offline_cpu`). During the bring-up only CPU 0 logs for it: `bringup_cpu` (step 83) returns -5 at 72.53 s, 5 s later, and the rollback follows. CPU 1 never ran a single `cpuhp_enter`, so it hangs in the kernel's secondary entry before `notify_cpu_starting` (head.S, `__cpu_setup`, MMU on, or early `secondary_start_kernel`), after Aura's jump.
- **Next split (module only):** the syscore resume hook now restarts the stopped queues, firing `0xa3` to each one atomically before `pm_sleep_enable_secondary_cpus()`. The acks are handled later, and `PM_POST_SUSPEND` then skips its own restart. If the cores come back, the AOP's queue state during the bring-up is the link. Armed: queues only, trace on, read-only.

## 2026-11-05 23:33: the queues restarted before the CPU bring-up: 4 of 4, CPUs 0-9, no errors; the full handshake armed

- Run 23:27 (`data/aop-sleep/2026-11-05-2327-queues-restart-syscore.log`, queues only, read-only): the queues stopped at `PM_SUSPEND_PREPARE` (12 of 12). The syscore resume hook sent their `0xa3` before the secondaries (`12 sent, 0 failed`). **4 of 4 back, `online 0-9` after every resume**, 0 device errors (the 2 counted are the hook's own "0 failed" line).
- So **the AOP's queues must be running again before the secondary CPUs are brought back**. With them stopped, an incoming core hangs in the kernel's secondary entry. It is not yet known why: the AOP may hold a fabric or memory vote while its queues run. But it fits macOS: its `AppleSPU` restarts the queues in its own wake, and XNU's secondaries come up under conditions Linux does not reproduce here. The practical rule: stop the queues late, start them early.
- **Armed: the full handshake** (`aop.sleep_ap_idle=1`): stop at `PM_SUSPEND_PREPARE`, 0x201 from syscore suspend (after the parking), then from syscore resume 0x20 and the queues' START, both before the secondaries. 2 `deep` and 2 `s2idle` cycles, read-only.

## 2026-11-05 23:40: the full AOP handshake in `deep`: 4 of 4, CPUs 0-9, no crash; mode 3 (0x201 before `slpa`) armed

- Run 23:34 (`data/aop-sleep/2026-11-05-2334-full-handshake.log`, `aop.sleep_ap_idle=1`, read-only): in each `deep` cycle the queues stopped (12 of 12) and the 0x201 went from syscore suspend; then from syscore resume came the 0x20 and the queues' START (`12 sent, 0 failed`). **4 of 4 back, `online 0-9` every time, no AOP crash**, 0 device errors (the 2 counted are the hook's own line).
- **So the AOP sleep handshake that macOS does, and Linux never did, now runs across a suspend to RAM without breaking anything.**
- One difference from macOS is left. macOS sends `slpa` from a platform action after every driver, so after RTBuddy's 0x201 to the AOP. Our `slpa` goes in `suspend_late` and the 0x201 from syscore suspend, after it. New mode 3: the 0x201 right after the queues stop at `PM_SUSPEND_PREPARE`, acked. The 0x20 and the queue restart stay in syscore resume, so the cores come back. Armed in `deep` (no `slpa`), read-only. If clean, mode 3 is what the next attended `slpa` run uses.

## 2026-11-05 23:54: mode 3: the queue restart was refused, CPUs lost again (the rule holds); RTKit early send added; mode 3 armed again

- Run 23:41 (`data/aop-sleep/2026-11-05-2341-mode3-restart-refused.log`, `aop.sleep_ap_idle=3`): the queues stopped, then `SetAPPower 0x201: 0`, acked, before the SMC's `SetAPPower IDLE` (so before `slpa`'s place, as macOS). On resume: `0x20 from syscore resume: 0`, but `queues restarted from syscore resume: 0 sent, 12 failed`, and CPUs 1 to 9 hung again.
- **Why the restart failed:** `apple_rtkit_send_message` refuses app endpoints unless the AP state is ON. After an acked 0x201 it is 0x201, and the 0x20's ack cannot be handled with interrupts off. (In mode 1 the 0x201's ack was still pending, so the state still read ON.) So this run confirms the rule from the other side: queues stopped during the bring-up means the cores hang.
- **Test kernel:** `apple_rtkit_send_message_early()` in `rtkit.c`, an atomic send without the running check, used only by the AOP's syscore restart. Image `cb9c74b6affcecc9` (old one in `/var/lib/deepidle/vmlinuz-psci-efi-test.pre-rtkearly`); the module tree and the initramfs were reinstalled.
- Mode 3 armed again, `deep` and `s2idle`, read-only.

## 2026-11-06 00:02: mode 3 with the early send: 4 of 4, CPUs 0-9; the AOP handshake is done in macOS's order; run J added; status, status file

- Run 23:55 (`data/aop-sleep/2026-11-05-2355-mode3.log`, Image `cb9c74b6affcecc9`, `aop.sleep_ap_idle=3`, read-only). Each `deep` cycle:
  1. the queues stopped (12 of 12);
  2. `SetAPPower 0x201 for system sleep: 0`, acked at `PM_SUSPEND_PREPARE` (before `slpa`'s place in `suspend_late`);
  3. on resume, `0x20 from syscore resume`, then `queues restarted from syscore resume: 12 sent, 0 failed`.
- **4 of 4 back, `online 0-9` every time**, 0 device errors (the 2 counted are the hook's own line), no AOP crash.
- **The AOP's sleep handshake is now in the test kernel in macOS's order.** Summary of 2026-11-05 22:00 to 2026-11-06 00:00, 11 unattended runs, no hand resets, btrfs counters 0:
  - the 0x201 alone crashes the AOP;
  - macOS first stops each endpoint's queue (`0xa4`/`0x87`);
  - the queues must run again before the secondaries come back.
- `attended.sh` has **run J**: I (`deep_steps` 14, `pmp_sleep`, aura-ctl 15) plus `aop.sleep_ap_idle=3`. Runs A to I now pass `aop.sleep_ap_idle=0` (the test kernel's default is 1), and cleanup removes `aop-sleep-mode`.
- status.md and s2r-status.json updated (new AOP piece and finding; estimate stays 45%).
- Mac state: default boot.bin `76f850895fed53d1`, `next_entry` unset; `trace-cpuhp` removed.
- Next: ask the owner for an attended window for run J. Meanwhile, static: the cluster power-off and the PMU's SPMI quiesce.

## 2026-11-06 00:07: static: `quiesceHW`'s cluster power-off resolved (the PMGR's soc-clusters, not the CPU complexes); image 54 built; regression armed

- **The PMU item is closed:** `AppleDialogSPMIPMU`'s quiesce only locks the SPMI bus and sends no sleep command (17:24 entry), so there is nothing to port.
- **`enableCluster`** (`ApplePMGR`, 13.5 `0xfffffe00098957e4`):
  - It reads RegMap `[this+9788]` at `[this+9792]` + 4 × the cluster's id, writes `(v & ~0xf) | (enable ? 0xf : 0)`, and with the wait flag polls bit 4 to 0.
  - The clusters are the ADT pmgr's `soc-clusters` (`EACC`, `PACC0`, `PACC1`, `ANE0`, `AVEMSR`, `DISPLAY`; the first byte of each entry is the id: 0, 1, 2, 3, 6, 4).
  - The base is `cluster-ctl-offset` `0x88000` in pmgr reg 4: **Linux `0x28e088000`**. Read live: `0xf` at +0 (EACC, the boot cluster) and `0x2f` at +4, +8, +0xc, +0x10 and +0x18, 0 elsewhere. The occupied words are exactly those ids.
  - So `quiesceHW` step 4 (c = 1..5, wait for c > 3) sets the target of PACC0, PACC1, ANE0, AVEMSR and DISPLAY to 0, and waits on AVEMSR and DISPLAY.
  - Not ported: for AVEMSR macOS makes one more PMGR call first (vtable +0xa08 with the entry's byte 11, `0x0d`).
  - The earlier guess `0x28e080060` to `0x70` was wrong.
- **Image 54** (Aura `2d7db967f92f5f8a`, `boot.bin.psci-test54` `78a01628af5e79e9`, diff `patches/psci-efi/aura/wip-image54.diff`):
  - It is image 53 plus aura-ctl bit 16 (`PSCI_S2R_CLUSTERS`): the five words' targets go to 0 after the domain step and before the clocks. The old values are saved and written back on any resume, and before/after go to `psci_dbg[6..10]`.
  - The MMIO range is added (10 of 16).
  - The current tree first rebuilt image 53 byte for byte (`e93c3a7644406710`), so the base is known.
  - `install.sh` suspendall now uses image 54. `run.sh` takes the image base from the DT (`aura,psci-runtime-code` − `0x10000`), since `psci_dbg` moved to +`0x147400`.
- **Regression armed:** image 54, aura-ctl 0x80 (marker only), AOP mode 3, 2 `deep` and 2 `s2idle` cycles, read-only. After that, the cluster step alone (aura-ctl 16) without `slpa`, to see whether the PMGR acts on the writes.

## 2026-11-06 00:13: image 54 regression: 4 of 4, CPUs 0-9; the cluster step alone (aura-ctl 16, no `slpa`) armed

- Run 00:08 (`data/aop-sleep/2026-11-06-0008-image54-regression.log`): booted `78a01628af5e79e9`, aura-ctl 0x80 read back, AOP mode 3. 4 of 4 back, `online 0-9`, the per-CPU state read through the DT-based base. 0 device errors (the 2 counted are the AOP hook's own line).
- **Armed:** 1 `deep` cycle with aura-ctl 16 only: the five soc-clusters' targets go to 0 under Aura, no timer, no `slpa`, read-only. `run.sh` logs the live cluster words after the resume; `psci_dbg[6..10]` hold before/after and `[23]` the poll timeouts (bits 27 and 28).
  - Expected: the actual-state bits fall (the PMGR acts), and the undo brings them back on the resume.
  - Possible cost: the P-cores (PACC0/1) or the display do not come back until a reboot.

## 2026-11-06 00:17: cluster run void (`aura-ctl` refused 16); tool fixed; armed again

- Run 00:14: `aura-ctl: only bits 0 to 3 (and the test marker 0x80) are defined`, so Aura got no step. The cycle was a plain `deep` one: back, `online 0-9`, cluster words unchanged (`0xf 0x2f 0x2f 0x2f 0x2f 0 0x2f`). The one device error is the known SMC "Failed to send command".
- `harness/mmio/aura-ctl.c` now accepts bit 4 (16). Armed again, the same run.

## 2026-11-06 00:21: the cluster step alone: the PMGR acts on it (ANE, AVE off; P-cores and display pending), CPUs back; runs J and K set; status

- Run 00:18 (`data/aop-sleep/2026-11-06-0018-clusters-only.log`, image 54, aura-ctl 0x10, 1 `deep` cycle, read-only): Aura read `0x10` (`psci_dbg[17]` `0x5300000010`).
  - `psci_dbg[6..10]` (before → after):

    | Cluster | Before | After |
    |---|---|---|
    | PACC0 | `0x2f` | `0x10` |
    | PACC1 | `0x2f` | `0x10` |
    | ANE0 | `0x2f` | `0x00` |
    | AVEMSR | `0x2f` | `0x00` |
    | DISPLAY | `0x2f` | `0x10` |

  - `[23]` = `0x10000000`: DISPLAY's bit-4 poll timed out after 10 ms; AVEMSR's passed.
  - So bits 5:4 read as the actual state (2 as boot leaves it, 0 off, 1 in between). The idle ANE and AVE clusters power fully off. The P-core clusters (the cores parked in retention) and the display (DCP running) stop in state 1.
- Back after 63.2 s, **`online 0-9`**. After Aura's undo (targets back to `0xf`), PACC0, PACC1 and DISPLAY read `0x1f` (state 1), not `0x2f`, and stay so. ANE and AVE are back at `0x2f`. Nothing failed (1 device error, the known SMC "Failed to send command"), the CPUs work, and the display is headless. macOS's `restoreHW` re-enables the clusters on wake; that path is not ported, and a reboot clears it.
- **`attended.sh`:** J is now I plus the AOP handshake plus aura-ctl 16 (CTL 31): every macOS sleep step found so far, in one sleep. K is the same without the cluster step, the fallback if J fails in a new way.
- status.md and s2r-status.json updated. Flags back to the default unattended set (`deep s2idle`, 2 cycles, no aura-ctl); default boot.bin, `next_entry` unset.

## 2026-11-06 15:16 Owner at the Mac: run J armed; unattended slpa runs allowed from now on

The owner (15:15): "ready for attended runs. also, let's let some slightly riskier runs go unattended. These attended runs have not needed intervention recently." True: since 2026-11-05 every attended slpa run (A to I) recovered on its own, by the S2R timer's reset (~85 s), WD1 or the dead-man switch; none needed a hand reset.

New rule: slpa runs that repeat or vary a configuration that already ran without a hand reset may go unattended, one at a time, with force-ro, the dead-man switch, the `findmnt /boot` and default boot.bin checks, and an agent-notify before each. A brand-new kind of step still gets one attended run first while the owner is around. Any hand reset, btrfs error or missing default boot.bin stops the unattended runs and goes to the owner.

Run J (slpa + PMP IDLE + AOP handshake + the whole quiesceHW incl. the soc-cluster power-off, image 54) is armed now with the owner present. `attended.sh` takes `EXTRA=` text for the next session's prompt; it tells that session to arm K unattended if J does something new (anything but the ~85 s timer reset), else to go on with the next step from the status page.

## 2026-11-06 15:23 owner-attended run J: every macOS sleep step found so far in one sleep, the S2R timer's reset at 86 s; run L next (with macOS's wake mask)

- Image 54, test kernel #12, `deep_steps` 14 (`slpw`, `slpa`, PMU boot stage 0x50), `pmp_sleep`, aura-ctl 31 (Aura logged `0x1f`: the S2R timer, every core in deep sleep, quiesceHW's domains, ClkGen/PLL-off and the soc-cluster power-off), `aop.sleep_ap_idle=3`, the PMP's display requests released (`0xf000` acked), 1 `deep` cycle, 30 s alarm, root read-only, counters on.
- Test kernel up 15:17:39. `echo mem` at 66.65 s = 15:18:45.6. Before it: `TEST queues stopped for system sleep: 12 of 12`, `TEST SetAPPower 0x201 for system sleep: 0` (Pi kmsg; the stream ends there as usual, Wi-Fi goes down). No dead-man push. Next kernel 15:20:12: **about 86 s, the S2R timer's reset again**, as D to I. No hand reset. btrfs counters 0, no btrfs errors.
- So the AOP's handshake and the cluster power-off, added to `slpa`, the PMP's IDLE and the rest of the quiesce, still leave the S2R entry incomplete.
- One difference from macOS was in every timer run (D to J): Linux's PMGR AP wake mask stays all 0, every wake source enabled (worklog 2026-11-05 08:00). macOS enables 22. With the mask open, any pending interrupt source (the AOP's outbox raised most s2idle wakes; DCP, GPU and the rest are still up) may keep the PMGR from entering. The test kernel's `deep_steps` bit 16 writes macOS's mask in `suspend_late`, before `slpa`, and restores it on wake (checked 11-05: with the SoC up it also blocks Aura's heartbeat and the alarm, so the cycle ended in WD1 at 145 s).
- **Run L** = J + bit 16 (`deep_steps` 30), added to `attended.sh`. It is a new combination with a new possible end: the SoC really sleeping and the alarm unable to wake it through macOS's mask. So it runs owner-attended (the owner is at the Mac since 15:15). Readings: 85 s = the mask was not it; 145 s = WD1; a resume or dead-man push = read `sleep: wake status` and the counters; nothing = power key or hand reset, ask the owner.
- Flags removed; default boot.bin (`76f850895fed53d1`), `next_entry` unset; headless on, Pi watcher running.

## 2026-11-06 15:30 owner-attended run L (J + macOS's wake mask): no S2R-timer reset; WD1 at about 146 s; run M (L + the power key) next

- J's setup plus `deep_steps` bit 16 (30): macOS's PMGR AP wake mask written in `suspend_late` before `slpa`. Test kernel up 15:24:36, `echo mem` at 66.31 s = 15:25:42.3; the AOP queues stopped 12 of 12, 0x201 acked (Pi kmsg, which ends there). No dead-man push. Next kernel 15:28:08: **about 146 s = WD1** (the 120 s dog; Aura's heartbeat cannot wake the boot CPU through macOS's mask, worklog 2026-11-05 08:00). No hand reset (the owner waits 10 min). PMU: 1 boot error logged, as after J's reset; btrfs counters 0.
- **New: the S2R timer's reset at about 85 s (D to J, every run with the timer) did not happen.** With every wake source enabled the timer resets the SoC; with only macOS's 22 it does not. Either the entry now completed (the timer is cancelled once the SoC is in S2R), or the timer's reset itself goes through a wake source macOS's mask blocks. A reset gives no counters, so this run cannot tell which.
- The PMU alarm most likely is wake bit 52 (`NUB.SPMI0Sw1IRQ`), which macOS's mask leaves off (worklog 11-05 07:42), so nothing could have woken it.
- **Run M** (`attended.sh M`): L with the owner pressing the power key once about 3 min after the push, i.e. about 50 s after `echo mem`, before the 120 s dog. Key wake through the SMC worked with the SoC up (Phase 2). If it resumes, the PMGR counters say whether the SoC slept (`SLP_S2R`, `SYS_S2R_AOP`); the ANS will then be dead and the dead-man switch resets. An early press is harmless: logind's HandlePowerKey is `ignore`.
- Unattended follow-up, built next: L with bit 52 also enabled, so the alarm can wake it.
- The default boot after J ran `run.sh` once more (the armed flag outlived the reset) and stopped at "booted the default image, not the test image: not suspending", as designed. Flags removed; default boot.bin, `next_entry` unset; headless on.

## 2026-11-06 15:42 owner-attended run M (L + the power key): no wake, WD1 at 145 s; correction on bit 52; wake bisection built

- L's setup, the owner asked to press the power key once about 3 min after the push (15:31:26). Test kernel up 15:32:25, `echo mem` at 66.41 s = 15:33:31.4 (the AOP queues 12 of 12, 0x201 acked). Nothing after it on the Pi. No dead-man push. Next kernel 15:35:56: **about 145 s = WD1**. The owner's press time is asked for (not in the chat yet). btrfs counters 0.
- **Correction to the 'run L' entry:** bit 52 (`NUB.SPMI0Sw1IRQ`) is one of macOS's 22 sources, so macOS's mask leaves it **enabled** (it is iBoot that had it off). So in L and M the PMU's SPMI lines (51, 52, 54), the AP wake time (50), the SMC (85, 90) and the AOP (26, 27) were all enabled, and still neither the alarm, the power key nor Aura's heartbeat woke anything. The same as 11-05 08:00 with the SoC up (no `slpa`, no timer): **with macOS's mask, Aura's deep WFI cannot be woken at all.** Some source macOS disables is what wakes it (in macOS, presumably, that path is not needed: its idle wakes come another way, and in S2R the AP is off).
- So L and M cannot say whether the SoC slept; the next step is to find the source(s) Aura needs, then run L with them.
- **Built:** `macsmc_reboot.wake_extra` (9 words, 1 = also keep enabled, OR'ed into macOS's set when `deep_steps` bit 16 writes the mask; the wake mask line now prints all 9 words). Only the module changed (patch `0001-TEST-power-reset-macsmc-reboot-wake_extra-…`), installed, old one at `/var/lib/deepidle/macsmc-reboot.ko.pre-wakeextra`; not in the initramfs. `install.sh` passes `/var/lib/deepidle/wake-extra`.
- **Bisection** (`tools/wake-bisect.py`, state `data/wake-bisect/state.json`; 241 candidate bits, about 8 runs): `attended.sh W` = normal path (`deep_steps` 16, no `slpa`, no timer, aura-ctl 0), AOP mode 3, 30 s alarm, root read-only. A resume on the alarm keeps the tested half, a 145 s dog reset the other. Unattended, as the 11-05 07:49 and 08:00 mask runs were; each failure is the 120 s dog.
- First the check run: `wake_extra` = every valid bit, i.e. the same as Linux's open mask, expected to resume on the alarm (proves the parameter). Flags removed; default boot.bin, `next_entry` unset; headless on, the watcher running.

## 2026-11-06 15:50 wake bisection check run: no wake even with a mask of 0, so the mask step itself breaks the suspend; L and M reread; the step moved to the PM notifier

- Run W, check run: `deep_steps` 16, `wake_extra` every valid bit (the mask written = 0, Linux's own value), no `slpa`, no timer, aura-ctl 0, AOP mode 3. The kernel took the parameter (no "unknown parameter"). `echo mem` 15:44:34.2, nothing after it on the Pi, no dead-man push, next kernel 15:47:00: **about 146 s, WD1 again.**
- So the value is not what breaks it: writing (or reading) the mask from `suspend_late` breaks the suspend whatever it writes. That covers 11-05 07:49 (wrong address) and 08:00, and **L and M too: they most likely never got past `suspend_late`**, where `slpa` comes after the mask step, so neither `slpa` nor Aura's S2R timer happened. That explains the missing 85 s timer reset better than the SoC sleeping. The L finding ("macOS's mask stops the timer's reset") is withdrawn, and so is the 08:00 conclusion that macOS's mask blocks every wake: neither run tested the mask.
- Why the access fails there is open: `0x29e004000` is in the always-on block next to the SoC watchdog (`0x29e2c4000`) and SPMI, and it was read and written fine while awake (11-05 08:00 poke). After device suspend something it depends on may be off.
- **Change:** the module now writes the mask from a PM notifier at `PM_SUSPEND_PREPARE` (before tasks freeze, as the AOP's 0x201) and restores it at `PM_POST_SUSPEND`, logging all 9 words read, written and the status. Those lines reach the Pi before `PM: suspend entry`. Patch `0001-TEST-power-reset-macsmc-reboot-write-the-wake-mask-a…`, module reinstalled (the pre-`wake_extra` one stays at `macsmc-reboot.ko.pre-wakeextra`).
- Next: the check run again (unattended). A wake = the placement was the problem, then the bisection with macOS's real mask. No wake with the 'now' line on the Pi = the mask write itself is harmful in any place before suspend.
- Flags removed; default boot.bin, `next_entry` unset; headless on; btrfs counters 0.

## 2026-11-06 15:56 check run 2: the first read of the wake mask hangs the system right after the AOP's sleep message; mask step moved before it

- Check run again (mask step in the PM notifier, `wake_extra` all, AOP mode 3). Pi kmsg: `echo mem` 15:53:42.9, `PM: suspend entry`, the AOP's `queues stopped 12 of 12` and `SetAPPower 0x201: 0`, **and no wake mask line at all**. No dead-man push. Next kernel 15:55:00: **about 77 s**, not WD1's 145 s: the system stalled before Aura's suspend dog was armed, and the 60 s systemd hardware watchdog plus the boot time fits.
- So the macsmc-reboot notifier ran after the AOP's (both priority 0, the AOP registered first) and its first `readl` of `0x29e00400c` hung the bus. The block is the PMGR's "AOP global" block; it answered while awake with the AOP running (11-05 08:00 poke), and stops answering once the AOP is told the AP sleeps (and, in `suspend_late`, once Linux has suspended the AOP or earlier: the 11-05 runs had no AOP handshake but failed there too).
- That fits macOS: `setAPWakeupSources` runs from `initAON` (boot) and `restoreHW` (each wake), never at sleep entry. The mask is set while the AOP is up and simply stays.
- Change: the notifier has priority 100 (runs before the AOP's) and logs "sleep: wake mask: reading" before the first access. Patch `0001-TEST-power-reset-macsmc-reboot-wake-mask-notifier-be…`, module reinstalled.
- Check run 3 armed (unattended). Flags removed; default boot.bin, `next_entry` unset; headless on.

## 2026-11-06 16:02 check run 3: the mask read hangs before the AOP's message too; cause: a posted mapping (ioremap, not ioremap_np)

- Check run 3 (the mask notifier before the AOP's): `echo mem` 15:59:05.1, then nothing on the Pi (not even `PM: suspend entry`: in a bus stall the last lines never leave), next kernel 16:00:22, **about 77 s** again. So the AOP was not the trigger: the module's own access to `0x29e00400c` stalls the system wherever it runs.
- Cause, by comparison: the 11-05 08:00 poke from userspace read and wrote the same words fine. `harness/mmio/wakemask.c` maps `/dev/mem` with `O_SYNC` (Device-nGnRnE, non-posted). The module used `ioremap()` (Device-nGnRE, posted). The DT's `/soc` node has `nonposted-mmio`: Apple's SoC fabric needs non-posted accesses, and every DT driver gets them, but a raw `ioremap()` of a physical address does not. So **every module mask access since 11-05 07:49 stalled the bus**: 07:49, 08:00, L, M and the three check runs. None of them tested a wake mask.
- Fix: `ioremap_np()` for both accesses (patch `0001-TEST-power-reset-macsmc-reboot-map-the-wake-mask-non…`), module reinstalled. Check run 4 armed.
- Lesson for any new raw MMIO in a test patch: `ioremap_np()` on this SoC. The other raw maps in the test kernel (`nvme_apple.iorvbar_phys`) read fine at boot; to be checked if they ever write.
- Flags removed; default boot.bin, `next_entry` unset; headless on; btrfs counters 0.

## 2026-11-06 16:05 check run 4: the mask step works with ioremap_np (back on the alarm); next macOS's own mask alone

- Check run 4 (`ioremap_np`, notifier before the AOP's, `wake_extra` all, mask written 0): `sleep: wake mask: reading`, `read` all 0, `now` all 0, then the suspend; **back on the 30 s alarm, 33.1 s, `online 0-9`**, `sleep: wake status` all 9 words 0, mask restored. So the non-posted mapping was the whole problem.
- The one counted device error is `macsmc: RTKit: Endpoint 0x20 is not running, cannot send message` at the first SMC command after resume; it is in every resume since 2026-11-05 23:55 (1 to 4 times), not new. Noted for later.
- Before bisecting: no run has yet tested macOS's mask with a working module (the 11-05 08:00 "nothing wakes" was the posted-mapping stall). So next is `wake_extra` = 0, macOS's 22 sources only, normal path. A wake = no bisection needed, L (J + macOS's mask) next; no wake = bisect.

## 2026-11-06 16:09 macOS's own wake mask lets the alarm wake Aura's deep WFI (SoC up); no bisection needed; run L again, unattended

- Run W with `wake_extra` 0: `sleep: wake mask now f3ffafff ffa1f6ff fbdfffff 3fffffff ffffffc0 ffffffff 7fffffff ffffffff 0000007f` (macOS's value), suspend, **back on the 30 s alarm after 33.1 s, `online 0-9`**, status words all 0 (they do not latch for these wakes), mask restored. Counters `AWAKE` only (no `slpa`). The same SMC endpoint 0x20 line as every resume.
- So with the SoC up, the PMU alarm wakes the boot CPU through macOS's 22 sources. The bisection is not needed (`data/wake-bisect/state.json` stays at its start).
- **Run L again** (J + macOS's mask, `deep_steps` 30), now with a working mask step: unattended under the owner's 15:15 rule, since both parts recover on their own (J: the S2R timer's reset; the mask: tested on the normal path). New possible end: the SoC really sleeps; the alarm then has macOS's path. If it neither wakes nor resets, the Mac stays dark until the power key; the push before the run says so.
- Readings: about 85 s = the timer's reset again, the mask was not what held the entry; a resume or a dead-man push = read the PMGR counters (`SLP_S2R`, `SYS_S2R_AOP`), `psci_dbg[13]`, the wake status; about 145 s = WD1.

## 2026-11-06 16:14 run L again, with the mask really set: the S2R timer's reset at about 86 s; no more slpa runs until a new step

- Unattended. Pi kmsg: `sleep: wake mask now f3ffafff ffa1f6ff …` (macOS's value), then the AOP's `queues stopped 12 of 12` and `0x201: 0`, then nothing (as always after `slpa`). `echo mem` 16:11:51.6, next kernel 16:13:18: **about 86 s, the timer's reset, as J.** No dead-man push, no hand reset, btrfs counters 0.
- So with every macOS sleep step found so far **and** macOS's wake mask, the S2R entry still does not complete. A pending wake source was not what held it.
- Per the plan: no more `slpa` runs until there is a new step. Next is static: what the PMGR's S2R entry waits for in macOS 13.5 (`AppleT6020PMGR` / `ApplePMGR` S2R entry, the XNU last-core path in `ml_arm_sleep`), and which devices Linux leaves powered that macOS has off at that point (DCP, GPU, ISP, the PCIe links: Phase 4).
- Flags removed; default boot.bin, `next_entry` unset; headless on; watcher running.

## 2026-11-06 16:19 static: the cores match XNU; the next difference is the PMP's request word (ISP_SYS still held); test switch built

- **Cores:** XNU 8796.141.3 `arm64_prepare_for_sleep(true)` (`machine_routines_asm.s`) sets ACC_OVRD enDeepSleep with the deep-sleep values of disL2Flush4AccSlp, ok2PwrDnSRM, ok2TrDnLnk, ok2PwrDnCPM and disPioOnWfiCpu, then CYC_OVRD ok2pwrdn force-down and disWfiRetn, then WFI. Aura's `cpu_sleep(true)` sets the same fields (ACC_OVRD_PWR_DN_SRM(3), DIS_L2_FLUSH_ACC_SLEEP(2), TRAIN_DOWN_LINK(3), POWER_DOWN_CPM(3), DISABLE_PIO_ON_WFI_CPU, DEEP_SLEEP; CYC_OVRD WFI_MODE(3), DISABLE_WFI_RET). The IRQ/FIQ masking in XNU is only on the non-deep path. Nothing to add there.
- **AIC:** macOS masks every AIC line at Quiesce, after the S2R timer; Linux's syscore suspend does too, and Aura unmasks only the alarm (724) and SMC (865) lines for its wait. Not a likely blocker; noted.
- **The PMP's request word** (Phase 3 trace, worklog 2026-10-25 18:31 and run 9): macOS's `DEV_STATUS_TGT_WR` steps 0x8300 → 0x300 → 0x200 → 0x0 before the cores sleep: every device request released, then the CPU complexes (PCPM0, PCPM1) last, then a PMGR write at `0x2902801c0`. Linux's word reaches only `0x1000` with the display release: **ISP_SYS (entry 12) stays requested**, and Linux never requests or clears the CPU complexes at all.
- **Test switch:** `pmp_report.test_release_ids` (bit = entry id) withdraws further entries in `suspend_noirq` and asserts them in `resume_noirq`, logged as the display ones. Built in, so a new test Image (`ca3513d9be0d4935`, old one at `/var/lib/deepidle/vmlinuz-psci-efi-test.pre-isprel`); patch `0001-TEST-pmdomain-apple-pmp-report-test_release_ids-…`. `run.sh` sets it from `/var/lib/deepidle/pmp-release-ids`.
- Runs: **P** = normal path (no `slpa`), ISP_SYS released with the display ones: does the PMP ack, does the word reach 0, does it come back. Then **N** = L with it. Both unattended (P has no `slpa`; N is a variation of L, which recovers on its own).

## 2026-11-06 16:26 run P: ISP_SYS is released by genpd anyway, but only in noirq, after slpa and the PMP's IDLE; PMP requests now withdrawn before slpa (deep_steps bit 32)

- Run P (normal path, no `slpa`, `test_release_ids` 0x1000): back on the alarm, 33.3 s, `online 0-9`. In `suspend_noirq`: requests 14, 15, 13 withdrawn (`0xf000` → `0xb000` → `0x3000` → `0x1000`), then request 12 `-114` with the ack word already `0x0`: Linux's genpd had powered ISP's domain off by itself. After the wake all asserted again, `pmp requests after resume: 0xf000 ack 0xf000`. The only error is the old SMC endpoint 0x20 line.
- **What that means for J and L:** the word does reach 0 in a Linux suspend, but in the noirq phase, while `slpa` (macsmc-reboot) and the SMC's and PMP's IDLE (macsmc) go out in `suspend_late`. Run C (11-05 21:22) showed that the noirq release then finds the PMP idle and is refused (`-EALREADY`). So in C, I, J and L **the PMP went IDLE still holding the displays and ISP (`0xf000`)**, where macOS has released everything but the CPU complexes by `slpa`. That difference was never tested.
- **Change:** `deep_steps` bit 32: macsmc-reboot calls `apple_pmp_report_sleep_release(true)` (new, pmp-report) just before `slpa`, withdrawing every sleep-release entry (the displays with `test_release_aon`, ISP_SYS with `test_release_ids` 0x1000) while the PMP still acks; on resume, after the SMC driver has woken the PMP, `(false)` asserts them again. Entries released early are skipped by the noirq path. Test Image `14c5a983f4df3f02` and module installed; patch `0001-TEST-pmp-report-macsmc-reboot-deep_steps-bit-32-…`.
- Runs: **Q** = the normal-path check (`deep_steps` 32 alone); **N** = L + bit 32 (`deep_steps` 62). Both unattended.

## 2026-11-06 16:29 run Q: the PMP's requests withdrawn before slpa's place and back after the wake; run N armed

- Run Q (normal path, `deep_steps` 32, ISP_SYS and the display ones): in macsmc-reboot's `suspend_late`, requests 12, 13, 15, 14 withdrawn, each acked, the ack word `0xf000` → `0xe000` → `0xc000` → `0x4000` → **`0x0`**; `sleep: PMP requests released before slpa (0)`. On resume all four asserted again (`0x2f000`), `pmp requests after resume: 0xf000 ack 0xf000`. Back on the alarm after 33.1 s, `online 0-9`; only the old SMC endpoint 0x20 line.
- **Run N armed** (unattended, owner's 15:15 rule): L (`slpa`, PMU boot stage, macOS's wake mask, the AOP handshake, the PMP's IDLE, the whole quiesce, the clusters, every core down, the S2R timer) with the PMP's requests at 0 before `slpa` (`deep_steps` 62).

## 2026-11-06 16:36 run N: the S2R timer's reset at 86 s again; macOS's trace step 6 (CPU stop requests) missing in Aura; image 55

- Run N (unattended; L + the PMP's requests at 0 before `slpa`, `deep_steps` 62): Pi kmsg to `SetAPPower 0x201: 0` (mask set, AOP queues 12 of 12). `echo mem` 16:31:57.6, next kernel 16:33:24: **about 86 s, the timer's reset again.** No dead-man push, no hand reset, btrfs counters 0.
- So the PMP going IDLE with nothing requested is not what the entry waits for either.
- **Trace step 6** (`docs/hv-boot-trace-reference.md`): after `slpa` and `SetAPPower`, macOS writes `CPUSTART` (`0x28e0a8000`, one bit per secondary: 1 to 6, 8 to 10), clears PCPM1 and PCPM0 in the PMP's target word, writes PMGR `0x2902801c0`, then every core sleeps. `0x2902801c0` is `ps_sio`, already in image 53's quiesce. Linux never requests PCPM, so there is nothing to clear. But **Aura's S2R release (`smp_psci_release_parked`) only IPIs each parked core into `cpu_sleep(true)`; it never writes the PMGR stop request (`CPUSTART` + 0 = `cpu_start_base` + 0, the write `smp_stop_cpu()` makes before a stop).** The PMGR may wait for those requests before it treats the cores as down.
- **Image 55** (Aura `a6c53ba8caa72b6e`, `boot.bin.psci-test55` `e53a793bb3c942c7`, diff `patches/psci-efi/aura/wip-image55.diff`): aura-ctl bit 5 (32) writes each parked secondary's stop request before its IPI. Aura's step mask and `aura-ctl` (now up to 0x3f) let it through. `tools/swapimg.py` (puts a new Aura image in front of a boot.bin's DTB chain) is now in the repo. `install.sh` suspendall uses image 55.
- Runs: **G55** = image 55 regression on the normal path (aura-ctl 0x80), then **R** = N + aura-ctl 63. Both unattended.
- Flags removed; default boot.bin, `next_entry` unset; headless on.

## 2026-11-06 16:39 image 55 regression clean; run R armed

- G55: booted `e53a793bb3c942c7`, aura-ctl `0x80` (`psci_dbg[17]` `0x5300000080`), back on the alarm line (`psci_dbg[4]` 0x2d4 = 724) after 33.1 s, `online 0-9`; the old SMC endpoint 0x20 line only.
- **Run R armed** (unattended): N + aura-ctl 63, each parked secondary's PMGR stop request before it sleeps.

## 2026-11-06 16:44 run R: every step of macOS's sleep trace in one sleep, the S2R timer's reset at 86 s; slpa runs paused

- Run R (unattended; N + image 55's CPU stop requests, aura-ctl `0x3f`): Pi kmsg to the AOP's `0x201: 0` (mask set). `echo mem` 16:41:39.5, next kernel 16:43:05: **about 86 s, the timer's reset.** No dead-man push, no hand reset, btrfs counters 0.
- So with every step of macOS's sleep entry found so far, in macOS's order, the PMGR's S2R entry still does not complete: `slpw`, the PMP's requests at 0, `slpa`, the PMU boot stage, macOS's wake mask, the AOP's queues and 0x201, the SMC's and PMP's IDLE, the whole `quiesceHW` with the clusters, the S2R timer, each secondary's stop request, every core in deep sleep.
- What macOS has and Linux does not, as far as the trace shows: the devices themselves. In macOS every driver has powered its device down by then (DCP, GPU, ANE, AVE, ISP, the PCIe links and Wi-Fi, the DARTs), and their PMGR power domains are off. Linux suspends the drivers, but many `ps_*` domains stay on (always-on in the DT, or held). The PMGR's S2R entry may wait for them.
- Next, static (no more `slpa` runs until there is a new step): list the `ps_*` domains on at `suspend_late` in a Linux suspend (a normal-path run can log `pm_genpd_summary` and the PMGR power-state registers just before `echo mem` and from `suspend_late`), and compare with what macOS turns off (the PMGR kext's per-domain sleep handling).
- Flags removed; default boot.bin, `next_entry` unset; headless on; watcher running.

## 2026-11-06 16:46 power-domain dump built (deep_steps bit 64); run S armed

- Awake, `pm_genpd_summary` has 121 domains on (the PMP's display and ISP ones, gfx, afr, the ATC/USB and PCIe ones, the DCS and AMCC, ans2, dcp's disp0/dispext, ane, sio, SPMI, …).
- `deep_steps` bit 64: macsmc-reboot reads every enabled `apple,pmgr-pwrstate` register (the parent PMGR block mapped with `ioremap_np`; 195 nodes in 5 blocks) at `suspend_late`, just before where `slpa` goes, and again at `resume_early`, and logs each domain whose actual state is not 0 (`name=state`, 0xf on, 4 clock-gated) and the count. Module only; patch `0001-TEST-power-reset-macsmc-reboot-deep_steps-bit-64-log…`.
- **Run S** (unattended, normal path, no `slpa`): `deep_steps` 96 (the PMP release + the dump). It shows what Linux leaves powered at `slpa`'s place, to compare with macOS, whose drivers have every device off by then.

## 2026-11-06 16:53 run S: the register dump at suspend_late hung the suspend (WD1); replaced by genpd's own list at syscore suspend (run S2)

- Run S (normal path, no `slpa`, `deep_steps` 96 = the PMP release + the PMGR register dump): the Pi kmsg ends at the AOP's `0x201: 0` (no `sleep: ps` line came out before Wi-Fi went down). `echo mem` 16:48:19, next kernel 16:50:44: **about 145 s, WD1**. Run Q (the same without bit 64) came back, so **reading the pwrstate registers at `suspend_late` hung the suspend**, most likely on a block that is clock-gated by then. Not repeated (bit 64 stays in the module, not to be used).
- Also, on reflection: `suspend_late` was the wrong place to look. genpd powers domains off in the **noirq** phase, after `suspend_late`, so most domains would read on there by design. What matters for the S2R entry is what is still on when Aura takes over: after every noirq phase, at syscore suspend.
- **Change:** `pm_genpd.test_dump` (pm-domain core, built in): a syscore suspend hook that walks genpd's domain list (software state, no register access; single CPU, IRQs off, so no lock) and logs every domain still on, `*` for always-on. Test Image `c955df41e27aaf1f` (previous at `/var/lib/deepidle/vmlinuz-psci-efi-test.pre-genpddump`); patch `0001-TEST-pmdomain-core-pm_genpd.test_dump-…`. `run.sh` sets it from `/var/lib/deepidle/genpd-dump`.
- **Run S2** (unattended, normal path): the PMP release (`deep_steps` 32) + the genpd dump.
- Flags removed; default boot.bin, `next_entry` unset; headless on; btrfs counters 0.

## 2026-11-06 16:58 run S2: 99 of 200 PM domains still on at syscore suspend, 19 of them held by devices; run U (display stack and USB-C unbound) armed

- Run S2 (normal path, the PMP release, `pm_genpd.test_dump`): back on the alarm, 33.2 s, `online 0-9`. At syscore suspend (after every noirq phase, just before PSCI `SYSTEM_SUSPEND`) **99 of 200 domains are on** (`data/s2r-domains/2026-11-06-1655-syscore-suspend.txt`):
  - **80 always-on** in the DT: the memory controllers (`dcs_00` to `_15`, `amcc0` to `3`), the fabrics (`afnc*`, `afc`, `afi`, `nub_*`, `mtp_fabric`, `soc_dpe`), `aic`, `pmp`, `pms*`, `sep`, `aes`, the SPMI lines (`nub_spmi*`, `clvr_spmi*`), `gpx` (GPU), `dptx_phy_ps`, `apcie_phy_sw`, `apcie_gp_sys`, the debug ones, and the USB-C/Thunderbolt ports' `atc*_pcie`, `atc*_common`, `atc*_usb_aon`.
  - **19 held by a device that stays bound**: the three display coprocessors and their stacks (`disp0_*`, `dispext0_*`, `dispext1_*`, `pmp-disp0`, `pmp-dispext0/1`: the `apple-dcp` devices, their DARTs and mailboxes), the three USB-C ports' USB (`atc0/1/2_usb`: `dwc3-apple`, its PHY, mux and DARTs), `sio` (its DART), `afr` (GPU fabric; Aura's quiesce turns it off later), `apcie_gp` and `apcie_gpshr_sys` (the PCIe port with Wi-Fi).
- macOS has its devices off by sleep (DCP and GPU through the PMP target word, the PCIe links, USB). The display stack and the USB-C controllers are what Linux can take down without the PCIe rule (no PCI remove/rescan).
- **Run U** (unattended, normal path): S2 with `apple-drm` (`soc:display-subsystem`), the three `apple-dcp` and the three `dwc3-apple` unbound first (`run.sh` `unbind-before`, logged), to see that their domains go off and the suspend still comes back. With the display stack gone the desktop session goes too, so `run.sh` reboots 20 s after the run (results already on disk) and the next boot's session reads them. Then **V** = R + the same unbinds.

## 2026-11-06 17:08 run U: unbinding a USB-C port that never probed oopses dwc3-apple; no suspend; run U2 (probed ports only) armed

- Run U (normal path, S2 + the unbinds): `apple-drm`, the three `apple-dcp` and `dwc3-apple 702280000.usb` unbound with rc 0 at 17:00:51. The next, `b02280000.usb`, **oopsed in `dwc3_apple_remove`** (NULL pointer + `0x5b0` in `mutex_lock`). The shell running `run.sh` was killed (SIGSEGV), so no suspend and no self-reboot happened; the Mac stayed up and this session with it. No reset, btrfs counters 0, default boot.bin `76f850895fed53d1`, `next_entry` unset.
- Cause (driver, `drivers/usb/dwc3/dwc3-apple.c:680`): `dwc3_apple_remove()` gets its state from `platform_get_drvdata()`, but only `dwc3_core_probe()` sets drvdata, and that runs on a port's first cable event (`dev_set_drvdata(dev, dwc)` in `core.c`), and the core clears it again on removal. A port with no cable since boot (`DWC3_APPLE_PROBE_PENDING`, the state the remove comment itself handles) has NULL drvdata, so `to_dwc3_apple(NULL)` points at `0x5b0`, the mutex. Unbinding such a port, or unloading the module, oopses. `702280000` had its xHCI up and unbound fine; at the time of this entry only `f02280000` has an `xhci-hcd` child. Not reported upstream (owner's rule); a finding to give the owner.
- Also from the driver: a port whose core is up is made a syscore device on purpose (`dev_pm_syscore_device`, "Keep xHCI running in suspend-to-idle"), so its `atc*_usb` domain stays on in every Linux suspend while a cable is in. That is one of the 19 held domains of run S2.
- **Change:** `run.sh` skips a `dwc3-apple` port with no `xhci-hcd.*` child (`unbind ...: skipped, core not probed`).
- **Run U2** (unattended, normal path): U with the skip. The rest of the boot holds `b02280000`'s device lock (the killed unbind), so a `systemctl reboot` could hang in `device_shutdown`; this boot ends with sysrq sync, read-only remount and reboot after U2 is armed.

## 2026-11-06 17:14 run U2: unbinding the display stack frees only the PMP's display domains; genpd's DEFER_OFF keeps the rest on

- Run U2 (normal path, S2 + the unbinds, never-probed dwc3 ports skipped): `apple-drm`, the three `apple-dcp` and `dwc3-apple f02280000.usb` unbound with rc 0; `702280000` and `b02280000` skipped (no xHCI this boot; in U `702280000` had one). No oops. **Back on the alarm, 33.2 s, `online 0-9`**, PMP requests back to `0x1000`. The run rebooted itself at 17:12:30; no hand reset, btrfs counters 0, default boot.bin, `next_entry` unset.
- The 17 device errors after the suspend come from the unbinds, not the sleep: the three `tps6598x` controllers cannot set their Type-C mux (-19, the mux's consumers are gone) and one audio rate-symmetry error.
- At syscore suspend **96 of 200 domains on** (S2: 99; `data/s2r-domains/2026-11-06-1712-u2-syscore-suspend.txt`). Only `pmp-disp0`, `pmp-dispext0` and `pmp-dispext1` went off. `disp0_*`, `dispext0_*`, `dispext1_*`, `atc0/1/2_usb`, `sio`, `afr`, `apcie_gp*` are still on.
- Why (`drivers/pmdomain/apple/pmgr-pwrstate.c:398`, `drivers/pmdomain/core.c`): every PMGR domain that is on at boot gets `GENPD_FLAG_DEFER_OFF | GENPD_FLAG_ACTIVE_WAKEUP`.
  - DEFER_OFF: genpd never powers the domain off while any consumer in the DT has no bound driver (`fw_devlink_count_absent_consumers`). An unbound DCP is exactly such a consumer, so **unbinding keeps its domains on** rather than freeing them.
  - ACTIVE_WAKEUP: the domain also stays on while any of its devices is on a wakeup path (`device_awake_path`).
  - Otherwise genpd powers a domain off only once every attached device (the DCP's DARTs and mailbox, the USB port's DARTs, PHY, mux and dwc3) has gone through noirq suspend and every child domain is off; a syscore device (a dwc3 with its core up) is never counted.
- So unbinding is the wrong tool. **Next:** extend `pm_genpd.test_dump` to print, for each non-always-on domain still on, why it is held (devices suspended vs attached, absent consumers under DEFER_OFF, awake-path devices, children on), then a run S3 (S2 again, no unbinds, unattended) to read it. Run V (R + unbinds) dropped: it would sleep with the same domains on as R.

## 2026-11-06 17:16 the genpd dump says why each domain is held; run S3 armed

- `pm_genpd.test_dump` now also prints, after `N of M domains on`, one line per non-always-on domain still on at syscore suspend: `held NAME: susp S/D [defer] [awake]; dev X(syscore|wakepath|not-noirq) … child C … nodev FWNODE … unbound DEV`. Those are genpd's conditions for powering a domain off at sleep (`genpd_sync_power_off`, `genpd_finish_suspend`, `genpd_must_defer`). Software state only, no locks taken. Test Image `b83b00e1e29edf5f` (previous at `/var/lib/deepidle/vmlinuz-psci-efi-test.pre-genpdheld`); patch `0001-TEST-pmdomain-core-pm_genpd.test_dump-prints-why-eac.patch`. Clean build.
- **Run S3** (unattended, normal path, no unbinds): S2 on the new kernel.

## 2026-11-06 17:20 run S3: why each domain is held at sleep: the DCPs hold every display chain on purpose, the USB-C ports are syscore or on a wake path, sio and PCIe have always-on children

- Run S3 (normal path, `deep_steps` 32, the new dump, no unbinds): **back on the alarm, 32.6 s, `online 0-9`**, PMP requests back to `0xf000`, one device error (the old SMC endpoint line). Flags removed; default boot.bin, `next_entry` unset, btrfs counters 0; watcher running. Lines in `data/s2r-domains/2026-11-06-1718-s3-held-reasons.txt`.
- The 19 held domains (99 of 200 on, as S2), by reason:
  - **Display, 13 domains:**
    - `pmp-disp0`, `pmp-dispext0` and `pmp-dispext1` are each held by their DCP (`389c00000`, `289c00000`, `315c00000.dcp`) on a **wake path**;
    - every parent above them stays on because a child is on: `disp*_cpu0` (its DARTs and mailbox all suspended, 3/3), `disp*_fe`, `disp*_sys`, and `afr` (child `dispext0_sys`);
    - the DCP driver does this on purpose: `dcp_platform_suspend()` calls `device_set_wakeup_path(dev)`, "which forces its power domains to stay on. We need this as we do not support full shutdown properly yet." (`drivers/gpu/drm/apple/dcp.c`). The firmware stays up across sleep; for the panel the pipe even keeps scanning out with DPMS off.
  - **USB-C, 3 domains:**
    - `atc0_usb`: `702280000.usb` is syscore;
    - `atc2_usb`: `f02280000.usb` is syscore and has wakeup enabled (its xHCI is up);
    - `atc1_usb`: `b02280000.usb` has wakeup enabled (`power/wakeup`), with no core up;
    - in each, the DARTs, PHY and mux are suspended (4/5).
  - **Held by always-on children (DT), 3 domains:** `sio` (children `aes`, `dptx_phy_ps`), and `apcie_gp` / `apcie_gpshr_sys` above `apcie_gp_sys`.
  - No domain was held by DEFER_OFF in a normal suspend (no absent consumers); that only appears once something is unbound (U2).
- So on the Linux side the display chains are the DCP driver's deliberate choice (no full DCP shutdown and restart yet: Phase 4 work), the USB-C ones are dwc3-apple's (syscore while the core is up, to keep xHCI over sleep) plus a wakeup setting, and the rest come from DT always-on flags.
- Whether these domains are what the PMGR's S2R entry waits for is still untested. The direct test: Aura turns the 19 off (children first) just before the S2R timer, on the `slpa` path, where the run ends in the timer's reset anyway. That is a new kind of `slpa` step, so it gets one attended run first.

## 2026-11-06 17:23 image 56: Aura turns the domains Linux keeps on at sleep off before quiesceHW (aura-ctl 64); runs G56 and X

- From S3's list, the 12 PMGR power-state registers of the held, not-always-on domains (addresses from the live DT):
  - the display chains, children first: `dispext0_cpu0/_fe/_sys` (`0x28e0802d8`, `…2c0`, `…258`), `dispext1_*` (`0x28e0802b8`, `…2b0`, `…248`), `disp0_*` (`0x2902801d8`, `…1d0`, `…1b0`);
  - `atc0/1/2_usb` (`0x29e2800c8`, `…0d0`, `…0d8`).
  - Left out: `pmp-disp*` are PMP request domains, which `deep_steps` 32 already releases before `slpa`; `afr` is already in image 53's quiesce step (bit 2, after this one, as `dispext0_sys`'s parent); `sio` and the `apcie_gp` pair have always-on children.
- **Image 56** (Aura `d559aa68b0027293`, `boot.bin.psci-test56` `20f6d711f9f7add5`, diff `patches/psci-efi/aura/wip-image56.diff`): `PSCI_S2R_HELD` (bit 6, aura-ctl 64) writes each register with target 0 and AUTO_ENABLE, reset, disable and the flag bits cleared (as Linux's `apple_pmgr_ps_set`), then polls its actual state to 0 (10 ms each; timeouts in `psci_dbg[23]` bits 32-43). It runs before quiesceHW's domains. The old words go back on any resume, parents first.
- `psci_dbg` moved to `+0x147430` in image 56; `run.sh` reads it there when that image booted. `install.sh` suspendall now uses image 56 (55 with bit 6 off). `aura-ctl` takes up to `0x7f`.
- **Run G56** (unattended, normal path, aura-ctl `0x80` marker only): the image check, as G55. Then **run X** = R + bit 6 (aura-ctl 127): a new kind of `slpa` step, so **attended**, when the owner is at the Mac.

## 2026-11-06 17:26 run G56: image 56 is sound on the normal path; run.sh's fixed psci_dbg read was stale; X waits for the owner

- Run G56 (unattended, normal path, image 56 `20f6d711f9f7add5`, aura-ctl `0x80` marker): **back on the alarm, 33.0 s, `online 0-9`**, PMP requests back to `0xf000`, no new device errors (only the `set affinity failed(-38)` lines the filter skips). Aura read the marker: the scan line has `psci_dbg[17]` = `0x5300000080`.
- `run.sh`'s fixed-offset `aura dbg` read gave zeros. The DT's `aura,psci-runtime-code` is the image base + 0x10000, so the offset is the ELF symbol − 0x10000: **`0x137430`** for image 56 (checked live: magic `0xa0aa0001`, word 17 `0x5300000080`). The old `0x1472c8` had gone stale too (zeros with image 55); the `aura dbg scan` line is what carried the words in those runs. `run.sh` fixed for image 56.
- Flags removed; default boot.bin `76f850895fed53d1`, `next_entry` unset, btrfs counters 0.
- **Run X** (R + image 56's held domains off, aura-ctl 127) is a new kind of `slpa` step: one attended run first. No reply from the owner yet (push and mail sent); static work meanwhile: the DCP's full shutdown and restart (Phase 4), which a real S2R needs anyway.

## 2026-11-06 17:29 static: the DCP restart (Phase 4) depends on X; #933 draft updated; run Y armed (the domain-off writes alone, normal path)

- **DCP, static.** The external DCPs (`dispext0/1`) already have a cold start in the driver (`iomfb_v14_7.c`: set the ASC's `CPU_CONTROL` RUN bit, `apple_rtkit_wake`/`boot`, then DCPLink and the DPTX/DPAV endpoints), using the firmware iBoot left in memory. The internal panel's DCP is adopted live from iBoot (`adopt_live_session`). A sleep that powers them off therefore needs: an RTKit shutdown in suspend instead of `device_set_wakeup_path`, then on resume the cold start and the endpoint setup again (a re-probe of the session), and for the panel a modeset from scratch. That is a real driver change. It is worth it once X shows whether these domains are what the S2R entry waits for (they must be off in a real S2R anyway, but they may not be the blocker).
- **#933 draft** (`docs/gh933-s2r-draft.md`, not posted): added the PMP findings from 11-05/06 (IDLE handshake works; a double `SetAPPower` crashed it, our bug; requests must be released before IDLE; the S2R entry still does not complete, nothing points at the PMP).
- **Run Y** (unattended, normal path: no `slpa`, no S2R timer, no cores off): aura-ctl 64 only. Aura turns the 12 held domains off before its WFI wait and restores them on wake. It checks that the writes and polls themselves are safe (`psci_dbg[23]` bits 32-43 = 0) and do not stall the fabric, so a WD1 in X would not be ambiguous. The DCPs and USB-C controllers lose their state, so display/USB errors are expected after the wake.
  - New `reboot-after` flag: `run.sh` reboots 20 s after the run through sysrq (sync, read-only, reset), because a regular reboot could hang in `device_shutdown` on the dead devices.

## 2026-11-06 17:38 run Y: turning the 12 held domains off on the normal path ends in WD1; a harness bug rebooted the next boot; image 57 bisects by group

- Run Y (normal path, no `slpa`, no timer, no cores off; aura-ctl 64, all 12 held domains off before Aura's wait, restored on wake): Pi kmsg to the AOP's `0x201: 0` as always, then nothing. `echo mem` 17:31:30.6, next kernel 17:33:55: **about 145 s, WD1.** No dead-man push (Linux's userspace never came back); no hand reset; btrfs counters 0, no btrfs errors.
- G56 and S3 came back on the same path without bit 6, so the step is what hangs. Two candidates, which this run cannot tell apart:
  - Aura's writes or polls (or the restore) stall the fabric, e.g. the panel DCP's domain going off under a live scanout;
  - or Linux resumes and hangs in a device resume against a DCP or xHCI that lost its state, past the 120 s suspend dog.
  - For X this matters less: there the S2R timer is written after the domain step, so 86 s would mean the writes passed and 145 s that they stalled.
- **Harness bug, fixed:** the hung Y never reached the end of `run.sh`, so `psci-efi-armed` and the new `reboot-after` stayed. In the next boot (default kernel) `run.sh` refused to suspend ("booted the default image") but then honoured `reboot-after` and sysrq-rebooted at 17:35:03 (sync and read-only first). `reboot-after` now needs a `suspend deep 1: back` line in this run's log.
- **Image 57** (Aura `a33667a0d03dc344`, `boot.bin.psci-test57` `ae5f5e93323269a6`, diff `wip-image57.diff`; `psci_dbg` at `+0x137470`): `psci_ctl[2]` bits 0-11 pick which held domains bit 6 turns off (0 = all), kept in the cache-cleaned save block for the RVBAR-path undo. `aura-ctl <steps> <mask>`, `/var/lib/deepidle/aura-held-mask`; `install.sh` uses image 57.
- **Bisect, normal path, unattended** (variations of Y, which recovered on its own): **Y1** USB-C only (`0xe00`), **Y2** the external displays' chains (`0x03f`, nothing attached), **Y3** the panel DCP's chain (`0x1c0`). Y1 doubles as image 57's check. X then uses the groups that came back.

## 2026-11-06 17:45 run Y1 (USB-C domains only): WD1 too; run Y1T uses the S2R timer as a probe of how far Aura gets

- Run Y1 (image 57, normal path, aura-ctl `0x40` mask `0xe00` = `atc0/1/2_usb` only; `run.log` line `aura ctl … 0x40 mask 0xe00`): Pi kmsg to the AOP's `0x201: 0`, then nothing. `echo mem` 17:41:22.9, next kernel 17:43:47: **about 145 s, WD1** again; no dead-man push, no hand reset, btrfs counters 0. `reboot-after` correctly did not fire in the next boot (no `back` line). Flags removed; default boot.bin, `next_entry` unset.
- So the USB-C domains alone are enough to hang the normal path. That still does not say whether Aura stalls at the writes or Linux hangs resuming the power-cycled USB-C devices (the dwc3s are syscore and the xHCI ran through the suspend).
- **Run Y1T** (unattended, normal path): Y1 plus the PMGR S2R timer (aura-ctl 65), which Aura writes after the domain step. The timer resets the SoC about 60 s after it is written even with the SoC awake (D, D2: `AWAKE` counters, reset at 86 s). Next kernel at about 60 to 90 s = Aura got past the writes, so the hang is Linux's resume; about 145 s = Aura stalled at the writes or polls.

## 2026-11-06 17:51 run Y1T: WD1 again, with the timer after the USB-C domain step; control run T0 (timer alone, normal path)

- Run Y1T (image 57, normal path, aura-ctl `0x41` mask `0xe00`: the USB-C domains off, then the S2R timer): `echo mem` 17:48:04.8, next kernel 17:50:29: **about 145 s, WD1**; no dead-man push, no hand reset, btrfs counters 0. Flags removed; default boot.bin, `next_entry` unset. (The armed prompt said "mask 0"; the mask file was fixed by hand before the reboot and `run.log`'s `aura ctl … mask 0xe00` confirms it.)
- If Aura had got past the domain writes, the timer would have reset the SoC about 60 s after it (86 s in D and D2). It did not. So either Aura stalled at the USB-C writes or polls, or the timer does not count without `slpa` (D and D2 both had `slpa`).
- **Run T0** (unattended, normal path): the timer alone (aura-ctl 1). About 60 to 90 s = the timer works without `slpa`, so Aura stalls at the USB-C domain writes; a resume and no reset = the timer needs `slpa`, and Y1T says nothing.

## 2026-11-06 17:56 run T0: the S2R timer resets the SoC without slpa too (85 s); so Aura stalls in the USB-C domain-off step

- Run T0 (normal path, aura-ctl `0x1` mask 0: the timer alone, written just before Aura's wait): `echo mem` 17:54:03, next kernel 17:55:28: **about 85 s, the timer's reset**, as D and D2 with `slpa`. No dead-man push, no hand reset, btrfs counters 0. Flags removed; default boot.bin, `next_entry` unset.
- So the timer counts with the SoC awake and without `slpa`, and **Y1T's 145 s means Aura never reached the timer write: it stalled inside the USB-C domain-off step.** The writes and polls are bounded (10 ms each), so the likely stall is the fabric: `702280000` and `f02280000` are syscore with their xHCI running through the suspend (S3), and powering `atcN_usb` off under a live bus master can wedge the interconnect, after which no MMIO completes.
- For X this means the USB-C domains cannot simply be switched off from Aura; xHCI must be stopped first (on the Linux side, as macOS's driver has its controller off by then). The display groups get the same probe next: **Y2T** (external displays, mask `0x03f`) and **Y3T** (panel, `0x1c0`), each the timer after the domain step.

## 2026-11-06 18:04 run Y2T: the external displays' domains stall Aura too; Aura cannot force the held domains off, Linux must quiesce them; run S4 (USB-C wakeup off) armed

- Run Y2T (image 57, normal path, aura-ctl `0x41` mask `0x03f`: `dispext0/1`'s CPU, front-end and system domains off, then the S2R timer): `echo mem` 17:58:58.9, next kernel 18:01:23: **about 145 s, WD1**; no dead-man push, no hand reset, btrfs counters 0. Flags removed; default boot.bin `76f850895fed53d1`, `next_entry` unset.
- With T0's control (the timer resets at 85 s without `slpa`), Aura again never reached the timer write: it stalled inside the domain-off step, this time with nothing plugged into the external ports. So it is not only a live bus master: a domain whose devices Linux left running (the DCP coprocessors run their RTKit firmware, `device_set_wakeup_path` keeps them on by design) cannot be pulled from under them by a PMGR write. **Y3T (the panel) is skipped**: the panel's DCP is busier still, and the answer would be the same.
- **Conclusion: X as designed (Aura forcing the 12 held domains off) is not viable.** The held domains must be turned off by Linux, through genpd, after their devices are quiesced:
  - USB-C (`atc0/1/2_usb`, S3: held by syscore dwc3s and wake paths): first the wake paths. `b02280000` (no cable, no xHCI) is held only because its wakeup is enabled; `f02280000` has its xHCI up and is syscore, so it needs the driver to stop xHCI in suspend rather than keep it running;
  - the DCPs (13 display domains): an RTKit shutdown in suspend and the cold start on resume (Phase 4, entry 17:29).
  Then X comes back as "the S2R entry with these domains already off".
- **Run S4** (unattended, normal path, as S3: DS 32, the PMP release, the genpd held-reason dump; no `slpa`, no timer): `run.sh` disables `power/wakeup` on the three dwc3-apple devices and their `xhci-hcd.*` children first (`/var/lib/deepidle/wakeup-off`, once per boot). Expected: `atc1_usb` (and `atc0_usb` if `702280000` was only a wake path) drops out of the held list; `f02280000` stays held as syscore. Risk: none beyond S3's path, only the wake source changes, and the RTC alarm is not on USB.

## 2026-11-06 18:10 run S4: with USB-C wakeup off, the cable-less port's domain goes off through genpd; the other two are held by the driver's syscore choice

- Run S4 (test kernel `b83b00e1e29edf5f`, image 57 with no Aura steps, normal path, DS 32, the PMP release, the genpd held-reason dump; `run.log`: `wakeup off:` for `702280000`, `b02280000`, `f02280000` and `f02280000`'s `xhci-hcd.4.auto`): **back on the alarm, 32.8 s, `online 0-9`**, PMP requests back to `0xf000`. The one device error after the wake is the SMC's `Failed to send command`, the same single error as S3 and G56. No reset; btrfs counters 0. Flags removed; default boot.bin `76f850895fed53d1`, `next_entry` unset; headless on, watcher running.
- **genpd at syscore suspend: 98 of 200 domains on (S3: 99).** The only change is `atc1_usb`: `b02280000` (no cable, core never up) was held only by its wake path, and with wakeup off genpd now powers the domain off in noirq and back on at resume without trouble. Lines in `data/s2r-domains/2026-11-06-1808-s4-wakeup-off-held.txt`.
- Still held for USB-C, both `syscore` (and no longer `wakepath`, except `f02280000`'s, which the dump still reports from the xHCI child's wake path):
  - `atc0_usb`: `702280000` is in device mode (`gadget.0`, the charger's cable);
  - `atc2_usb`: `f02280000` is a host with xHCI up (the Logitech receiver).
  `dwc3-apple` marks a port syscore whenever its core is up, on purpose: if genpd power-gated the core under a live cable, xHCI would find a dead core on resume and could not restore the root hubs without a full teardown. A syscore device also gets no PM callbacks at all, so the fix cannot be a suspend callback.
- **Next (test kernel change):** on a deep (`mem`) suspend only, tear a live port down from a PM notifier at `PM_SUSPEND_PREPARE` (the same exit path as a cable unplug: xHCI or the gadget removed, core stopped, reset asserted, syscore cleared), and bring it up again at `PM_POST_SUSPEND` in the role the Type-C controller last asked for. USB devices then re-enumerate after the wake, as they do after a macOS S2R. s2idle keeps today's behaviour (xHCI running, for USB wake).

## 2026-11-06 18:15 test modules: dwc3-apple stops a live USB-C core for a deep suspend, the ATC PHY restores itself after its domain was off; run S5 armed

- **Why the PHY matters:** the ATC PHYs are in the same PMGR domains as their dwc3 cores (`703000000.phy` → `atc0_usb`, `b03000000.phy` → `atc1_usb`, `f03000000.phy` → `atc2_usb`), so a freed domain also resets the PHY. `phy-apple-atc` already has the code to bring a PHY back to its tracked Type-C mode after that (`atcphy_restore_after_pd_off`, driven by a genpd `GENPD_NOTIFY_OFF` notifier), but only for the T8122 table; T6020 binds the `apple,t8103-atcphy` fallback, where it is off. In S4, `b03000000.phy` therefore came back at its reset values; with no cable that went unnoticed, and the port's next cable may need a reboot (not testable unattended).
- **Test modules** (patch `0001-TEST-usb-dwc3-apple-stop-a-live-core-for-a-deep-susp.patch`, kernel commit `f60139c75aa5`; the Image is unchanged, `b83b00e1e29edf5f`):
  - `dwc3_apple.test_deep_teardown` (default off, writable at run time): a PM notifier stops a live core at `PM_SUSPEND_PREPARE` for a deep suspend (not when s2idle is the default), through the same exit as a cable removal (xHCI or gadget removed, core stopped, reset asserted, syscore cleared). Role switches while it is down are only recorded; at `PM_POST_SUSPEND` the core starts again in the last role. Logs `TEST: core stopped for deep suspend (role R): ret` and `TEST: core restarted …`.
  - `phy_apple_atc.test_restore_pd_off` (default **on**, read at probe): the PHY follows its power domain on every generation.
  - Installed stripped into `/lib/modules/7.2.11-psci-efi+`, `depmod`, test initramfs rebuilt (`phy-apple-atc` is in it). The old modules and initramfs are in `/var/lib/deepidle/mods-pre-usbteardown/`.
- **Run S5** (unattended, normal path, no `slpa`): S4 (USB-C wakeup off, genpd held dump) plus the flag `/var/lib/deepidle/usb-teardown`, which `run.sh` writes to the module parameter (`usb teardown:` line). Expected: back on the alarm; `atc0_usb` and `atc2_usb` leave the held list (only the display chains and the always-on children stay); after the wake the Logitech receiver re-enumerates on `f02280000` and `702280000` is in gadget mode again. Recovery if not: WD1, then the saved modules.

## 2026-11-06 18:18 run S5: with the deep-suspend teardown all three USB-C domains go off in sleep and USB comes back; only the display chains and two always-on groups are left

- Run S5 (test kernel `b83b00e1e29edf5f` with the new `dwc3-apple` and `phy-apple-atc` modules, image 57 with no Aura steps, normal path, DS 32, the PMP release, the genpd held dump; `run.log`: `wakeup off:` ×4, `usb teardown: Y; phy restore: Y`): **back on the alarm, 32.7 s, `online 0-9`**, PMP requests back to `0xf000`. The one device error after the wake is again the SMC's `Failed to send command`. No reset; btrfs counters 0, no btrfs errors. Flags removed; default boot.bin `76f850895fed53d1`, `next_entry` unset; headless on, watcher running.
- The teardown did what it should:
  - `702280000`: `TEST: core stopped for deep suspend (role 2): 0` (device mode), `… restarted … (role 2): 0`, `/sys/class/udc/702280000.usb` back;
  - `f02280000`: xHCI removed, `TEST: core stopped … (role 1): 0`, after the wake `… restarted … (role 1): 0`, both buses registered again and the Logitech receiver re-enumerated (`usb 1-1` at 70.6 s, `lsusb` shows it), its HID inputs back;
  - no PHY warnings (`Failed to restore mode`, `did not power down`, `Failed to park`): the PHYs came back with their domains.
- **genpd at syscore suspend: 96 of 200 domains on (S4 98, S3 99).** `atc0_usb` and `atc2_usb` are gone from the held list; no USB-C domain is left. What remains held (16 lines, `data/s2r-domains/2026-11-06-1817-s5-usb-teardown-held.txt`):
  - the three DCPs (`289c00000`, `315c00000`, `389c00000`), each a `wakepath` from `dcp_platform_suspend()`'s `device_set_wakeup_path()`, and with them their chains (`pmp-*`, `*_cpu0`, `*_fe`, `*_sys`, `afr`): 13 domains;
  - `sio` (children `aes`, `dptx_phy_ps`) and `apcie_gp` → `apcie_gpshr_sys` (child `apcie_gp_sys`, always-on): held by always-on children, as in S3.
- **Next: the displays (Phase 4).** The two external DCPs have no display attached, but Linux cold-starts their firmware at boot anyway (`289c00000`/`315c00000`: `RTKit: Initializing` at 0.84 s, AFK services `system`, `disp0-service`, `AppleDCPDPTXRemotePort` by 1.9 s); `dcp_external_sleep_vetoed()` lets them sleep while nothing is attached, and `dcp_platform_suspend()` then claims the wake path for them unconditionally. So freeing `dispext0/1`'s chains (8 domains) needs an RTKit shutdown in suspend and the existing cold start again on resume. They are the easier half (no scanout, a cold-start path exists); the panel's DCP (adopted live from iBoot) comes after. (An earlier version of this line said their firmware was not running; corrected from the boot log.)

## 2026-11-06 18:19 static: how the external DCPs start (Phase 4 notes, unfinished)

- On T6020 the external DCPs are not `external_native` (`dcp_t6030_ext_native()` only accepts `apple,t6030-dcpext`) and `adopt_live_session` is false (`apple_dcp_hw_t6020_dcpext`). At probe Linux sets `CPU_CONTROL` RUN (0x44 bit 4), `apple_rtkit_init`, then `apple_rtkit_wake` (`dcp.c` around line 3920), so their firmware runs from boot with no display attached.
- `dcp_external_stop_locked()` (line 1645) only stops a display session (pipe power-off, DPTX link release); it does not stop RTKit. A sleep that frees `dispext0/1` needs a new step: `apple_rtkit_shutdown` (or `idle`), clear RUN, then on resume the probe's start sequence again (RUN, `apple_rtkit_reinit`/`wake`, endpoints), only while nothing is attached and no session was started. Not written yet.

## 2026-11-06 21:17 test switch: the DCPs shut their firmware down for a deep suspend (never restarted); run S6 armed

- A full DCP restart after sleep does not exist in the driver (a crashed DCP needs a reboot; the external DCPs' start runs only at bind). Before writing one, S6 tests the premise cheaply: do the display domains go off through genpd once the firmware is stopped, and (later, with `slpa`) does the S2R entry then complete?
- **`appledrm.test_sleep_off`** (default off, run time; patch `0001-TEST-drm-apple-dcp-test_sleep_off-shuts-the-firmware.patch`, kernel commit `babd5eada9c5`): in `dcp_platform_suspend()`, for a deep suspend (`pm_suspend_target_state == PM_SUSPEND_MEM`), instead of `device_set_wakeup_path()`: `apple_rtkit_shutdown()` (AP quiesced, IOP to sleep), `CPU_CONTROL` cleared (as the ANS driver does), the DCP marked crashed and dead so resume and later commits skip it. Logs `TEST: firmware shut down for deep suspend, down until reboot`. `appledrm.ko` reinstalled and the initramfs rebuilt; the previous ones are in `/var/lib/deepidle/mods-pre-dcpoff/`.
- **Run S6** (unattended, normal path, no `slpa`): S5 plus the flag `/var/lib/deepidle/dcp-off` (`run.sh`: `dcp off:` line) and `reboot-after` (the displays are dead after the wake; sysrq reboot 20 s after a `back` line). Expected: the 13 display domains leave the held list, a resume on the alarm, then the reboot. A WD1 would mean genpd's power-off of a display domain stalls the SoC like Aura's write did (Y2T) even with the firmware stopped.

## 2026-11-06 21:23 run S6: with the DCP firmware shut down, all 13 display domains go off through genpd: 83 of 200 on, only always-on children hold the rest; run R6 armed (R with these domains off)

- The reboot into S6 came three hours after arming: the S5 boot ran until 21:18:04, and `reboot.sh` logged `armed resume, rebooting in 30 s` only at 21:17:33, although `attended.sh` had printed `reboot in 30 s` at about 18:25. Why the reboot was held back is not known (the arming session's time ran out at about then); the flags stayed in place and nothing else ran meanwhile. In the S6 boot the session saw the run still ahead and left the prompt for the next boot, as planned.
- Run S6 (test kernel `b83b00e1e29edf5f` + the test modules, image 57 with no Aura steps, normal path, DS 32, the PMP release, the genpd held dump; `run.log`: `wakeup off:` ×4, `dcp off: Y`, `usb teardown: Y; phy restore: Y`): `echo mem` 21:19:38, **back on the alarm, 32.8 s, `online 0-9`**, PMP requests back to `0xf000`; then `reboot-after` sysrq-rebooted about 20 s later, as planned (the journal ends at 21:20:20, before the sync and read-only remount). No hand reset; btrfs counters 0, no btrfs errors; no dead-man push (`dead-man switch: rc=0`). Flags removed; default boot.bin `76f850895fed53d1`, `next_entry` unset; headless on, watcher running.
- Previous boot's kernel log: `TEST: firmware shut down for deep suspend, down until reboot` for `289c00000`, `315c00000` and `389c00000` (70.13 s), the two USB-C teardowns and restarts as in S5, and **`genpd test syscore suspend: 83 of 200 domains on` (S5 96, S3 99)**. Held (non-always-on) are only:
  - `sio` (children `aes`, `dptx_phy_ps`, always-on);
  - `apcie_gp` → `apcie_gpshr_sys` (child `apcie_gp_sys`, always-on).
  So every domain a driver held is off; the other 80 on are the DT's always-on ones. Lines in `data/s2r-domains/2026-11-06-2119-s6-dcp-off-held.txt`.
- Errors after the wake (3): the SMC's `Failed to send command` (as always), `drm_mode_config_helper_resume … Failed to resume (-22)` (expected, the DCPs are dead), and, **new**, `apple-pmgr-pwrstate 404e80000…@108: PS gfx: Failed to reach power state 0xf (requested 0xf00000f, now: 0xf000b0f)`: the GPU's domain did not power on again at resume (BUSY set, actual 0). S5 did not have it, so it comes with the display domains being off; the GPU's power-up may depend on one of them (`afr`, or the display fabric) without the DT saying so. To look at before S2R can be used with a GPU (not a blocker for the entry test).
- **Run R6** (unattended, `slpa`; a variation of R, which recovered by itself through the S2R timer at 86 s): R's steps (DS 62, PMP sleep, aura-ctl 63, the AOP mode 3, the PMP release) plus S6's Linux-side domain-offs and the genpd dump, `reboot-after` for a run that comes back. It asks whether the PMGR's S2R entry completes once Linux has the devices' domains off: 86 s again = it does not, and the devices were not what it waited for; anything else is new. No new Aura step; the dead-man switch is on and a push goes out first.

## 2026-11-06 21:30 run R6: run R with every device-held domain off still ends in the S2R timer's reset at 86 s; the devices are not what the S2R entry waits for

- Run R6 (unattended `slpa`; run R's steps, DS 62, PMP sleep, aura-ctl `0x3f`, AOP mode 3, the PMP release, plus S6's USB-C wakeup off, dwc3 teardown and DCP firmware shutdown): booted at 21:25:39, `echo mem` 21:26:38.6; Pi kmsg: `wakeup off` ×4, `dcp off: Y`, `usb teardown: Y`, `aura ctl … 0x3f`, `PM: suspend entry (deep)`, the AOP's `SetAPPower 0x201: 0`, both USB-C cores stopped, then nothing (Wi-Fi down; the genpd dump at syscore suspend did not reach the Pi). Next kernel (default) at 21:28:04.6: **86.0 s, the S2R timer's reset, exactly as in R.** No dead-man push (none expected on a reset), no hand reset; btrfs counters 0, no btrfs errors. The default boot's `run.sh` refused as designed (`booted the default image`). Flags removed; default boot.bin `76f850895fed53d1`, `next_entry` unset; headless on, watcher running.
- S6 showed that this setup leaves 83 of 200 domains on at syscore suspend (every device-held domain off). R6 could not log that itself, but nothing in its setup differs before syscore suspend except `deep_steps` 62 and the PMP sleep, which act later.
- **So the devices' power domains are not what the PMGR's S2R entry waits for.** USB-C, displays, and with them everything Linux's drivers held, were off, and the entry still did not complete.
- What is left from the macOS trace (`docs/hv-boot-trace-reference.md`) that Linux does not do: in step 3 macOS starts from PMP target `0x700` (PCPM0, PCPM1, GFX) and ends the display handshake at `0x300`; in step 6, after `slpa` and `SetAPPower`, it **clears PCPM1 (`0x200`) and PCPM0 (`0x100`)**. Linux never requests PCPM (the word is `0xf000` awake, ISP and the displays), so the PMP never sees the CPU complexes go from requested to released. The 11-06 16:3x note dismissed this ("nothing to clear"), but if the PMP reports "AP complexes released" onward to the PMGR/SMC, that transition, not the bits' final value, may be what lets the S2R entry go on. Next: look at the PMP driver and the target word to assert PCPM0/1 while awake and drop them after `slpa`.

## 2026-11-06 21:33 test switch: the PMP's CPU-complex requests (PCPM0/1) asserted for a deep suspend and withdrawn after the PMP's IDLE; run S7 armed, R7 waits for the owner

- **Where macOS's step 6 fits in Linux:** `macsmc-reboot` (a child of the SMC device) sends `slpa` in its `suspend_late`; the SMC driver's own `suspend_late` runs after it and sends `SetAPPower` IDLE to the SMC and, with `macsmc.pmp_sleep`, `SetAPPower`/`SetIOPPower` IDLE to the PMP: the same order as macOS's steps 4 and 5. Step 6's PCPM clears go right after that.
- **`pmp_report.test_pcpm`** (built in, run time; bit = report entry id; patch `0001-TEST-pmdomain-apple-pmp-report-test_pcpm-asserts-the.patch`, kernel commit `d0694778a0e7`): a PM notifier asserts the entries at `PM_SUSPEND_PREPARE` for a deep suspend (acknowledged writes, as the display entries), and `apple_pmp_report_test_pcpm_release()`, called by `macsmc` right after the PMP's IDLE, withdraws them; `PM_POST_SUSPEND` withdraws whatever is left (the normal path has no PMP IDLE). Logs `pmp-report: TEST pcpm 0x300 asserted|withdrawn: ret, request …, ack …`.
- New test Image `33ba2c087f23548f` (previous at `/var/lib/deepidle/vmlinuz-psci-efi-test.pre-pcpm`), `macsmc.ko` and the initramfs reinstalled (previous in `/var/lib/deepidle/mods-pre-pcpm/`).
- **Run S7** (unattended, normal path, no `slpa`): S3 plus `/var/lib/deepidle/pcpm` = `0x300`. Checks that the PMP takes and acknowledges CPU-complex requests from the AP and that a suspend with them asserted comes back.
- **Run R7** (R6 + PCPM 0x300, withdrawn after the PMP's IDLE, i.e. after `slpa`) is a new kind of `slpa` step: one attended run first. Asked the owner.

## 2026-11-06 21:37 run S7: the PMP takes and acknowledges the CPU-complex requests from the AP; R7 ready, waiting for the owner; gfx hangs off afr

- Run S7 (test Image `33ba2c087f23548f`, image 57 with no Aura steps, normal path, DS 32, the PMP release, the genpd dump; `run.log` `pcpm: 768` = `0x300`): **back on the alarm, 32.8 s, `online 0-9`**. `pmp-report: TEST pcpm 0x300 asserted: 0, request 0xf300 ack 0xf300` at `PM_SUSPEND_PREPARE`, `withdrawn: 0, request 0xf000 ack 0xf000` at `PM_POST_SUSPEND`; genpd 99 of 200 on (as S3, none of S5/S6's switches). Only the SMC's usual `Failed to send command` after the wake. No reset; btrfs counters 0. Flags removed; default boot.bin `76f850895fed53d1`, `next_entry` unset; headless on, watcher running.
- So the PMP accepts PCPM0/1 requests from Linux and acknowledges both directions within the 50 ms poll. Nothing else changed on the way down or up.
- **Run R7** (R6 + PCPM asserted, withdrawn after the PMP's IDLE, i.e. after `slpa`) is ready but a new kind of `slpa` step: waiting for the owner (push and mail at 21:33; no reply yet).
- **The GPU's power-up failure after S6, static:** in the DT, `gfx` (`404e80000…@108`) has two parents, `gpx` (`@0`, always-on) and **`afr`** (`@100`); `afr`'s sub-domains are `gfx` and `dispext0_sys`. Before S6, `afr` always stayed on (held through `dispext0_sys`). In S6 the display chain went off, and with the GPU runtime-suspended `afr` went off for the first time; at resume genpd powered `afr` and then `gfx` on, and `gfx` stayed at BUSY with actual 0. So `afr` coming back from off is not enough for `gfx`: either `afr` needs something restored after a power-off (`quiesceHW` also touches AFR, `psci_dbg[19]`), or the GPU domain needs the PMP's GFX request (bit `0x400`, part of macOS's `0x700`). Next for this: keep `afr` on in sleep (a test flag, as the DT's always-on) and see whether S6's setup then resumes with a working GPU.

## 2026-11-06 21:39 test switch: named PMGR domains kept on through system sleep; run S8 armed (S6 with afr kept on)

- The saved dumps agree: `gfx` was off at syscore suspend in S3, S5 and S6 (the GPU idle), `afr` was on in S3 and S5 and off only in S6. So S6's resume was the first time `afr` came back from off before the GPU's `gfx` powered up.
- **`pmgr_pwrstate.test_sleep_keep`** (built in, run time; comma-separated domain names; patch `0001-TEST-pmdomain-apple-pmgr-pwrstate-test_sleep_keep-ke.patch`, kernel commit `94ef56466730`): while system sleep is in progress (`ps->system_sleep`, set in `suspend_late`), the PMGR driver refuses those domains' power-off with `-EBUSY`, which genpd counts as rejected and leaves on. Logs `TEST: NAME kept on through system sleep`. Test Image `1a1105ae670401b0` (previous at `/var/lib/deepidle/vmlinuz-psci-efi-test.pre-sleepkeep`).
- **Run S8** (unattended, normal path, no `slpa`): S6 plus `/var/lib/deepidle/sleep-keep` = `afr` (`run.sh`: `sleep keep:`). Expected: 84 of 200 on (S6's 83 plus `afr`), and after the wake no `PS gfx` error. If `gfx` still fails, `afr` is not the cause and the PMP's GFX request (`0x400`) is next.
- R7 still waits for the owner (no reply by mail or ntfy at 2026-11-06 21:39).
