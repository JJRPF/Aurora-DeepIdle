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
