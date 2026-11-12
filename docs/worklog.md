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

## 2026-11-06 21:44 run S8: with afr kept on through the sleep the GPU's domain powers up again; afr going off was the cause

- Run S8 (test Image `1a1105ae670401b0`, normal path, S6's switches plus `sleep keep: afr`): `echo mem` 21:41:52, **back on the alarm, 33.3 s, `online 0-9`**; then `reboot-after` (21:42:30 + 20 s), as planned. No hand reset; btrfs counters 0, no btrfs errors. Flags removed; default boot.bin `76f850895fed53d1`, `next_entry` unset; headless on, watcher running.
- Previous boot's kernel log: the two USB-C teardowns and restarts, the three DCP firmware shutdowns, `apple-pmgr-pwrstate 404e80000…@100: TEST: afr kept on through system sleep`, **`genpd test syscore suspend: 84 of 200 domains on`** (S6's 83 plus `afr`, listed as held with `susp 0/0`), and **no `PS gfx … Failed to reach power state`** after the wake. The two device errors are the SMC's usual `Failed to send command` and `drm_mode_config_helper_resume … Failed to resume (-22)` (the DCPs stay dead by design). Lines in `data/s2r-domains/2026-11-06-2141-s8-afr-kept-held.txt`.
- **So `afr` going off was what broke the GPU's power-up in S6.** `afr` comes back from a power-off without whatever `gfx` needs from it (state lost with the power, or an ordering the PMGR driver does not know). For the test runs, `afr` stays on (`sleep-keep`; R7 now includes it). For a real S2R, where everything loses power, the GPU's bring-up after the wake has to handle this; noted for later (macOS's PMP asks for GFX, `0x400`, during its display handshake, which may be the missing piece).
- R7 still waits for the owner (no reply by mail or ntfy at 2026-11-06 21:44). Meanwhile: the DCP restart after sleep (Phase 4).

## 2026-11-06 21:46 static: the DCP restart is a large change, deferred; the S2R timer hides whether the entry completes; run R7N (no timer, attended) defined

- **DCP restart after sleep, scoped:** a restart means, after `apple_rtkit_wake`, tearing down and re-creating every endpoint `dcp_start()` opens (system, DPAV, iBoot, DPTX, the IOMFB session, AV) and the AFK services the firmware announces, then a modeset; today a crashed DCP's buffers are kept until reboot on purpose (DMA safety). That is days of driver work and only pays off once the S2R entry completes, so it is deferred; test runs use `dcp-off` + `reboot-after`.
- **The timer as evidence:** every full-sequence run (I, J, L, N, R, R6) included the PMGR S2R timer (aura-ctl bit 0), which resets the SoC about 60 s after it is written whether the SoC is awake or not (T0, 85 s). So "86 s" says only that the timer fired; an S2R entry that completed but whose wake path iBoot never armed for our raw image (an open unknown) would also end in a reset. The PMU's `boot-error-stage` does not help: it is sticky and records the stage (`0x50` from `macsmc-reboot`'s sleep step) at the last reset of any kind (table over 11-06's boots: it turns 50 after each reset while the stage was 0x50 and back to 30 only after a reset without it).
- The timer is also the safety net: without it, a SoC that really went down with no armed wake path could stay off until the power key. So the no-timer variant needs the owner at the Mac, like run M.
- **Run R7N** (attended): R7 with aura-ctl 62, i.e. no timer, owner presses the power key 3 min after the push. WD1 (~145 s) = the SoC never slept; a resume with S2R counters, or a cold boot before the key = the entry completed. Both R7 and R7N wait for the owner (no reply at 2026-11-06 21:46).

## 2026-11-06 22:13 references: DJ and Naeem Malik reached real S2R under their hypervisors (Neo, M1); what applies to the M2 Pro

The owner pointed at two posts: DJ ("Goes to 0.109W on Neo") and Naeem Malik ("M1 Air under m1n1: all cores power down, memory stays intact, the RTC alarm fires, and the chip comes back"). Both run macOS as a guest under a hypervisor and let it do the sleep. Neither has done it from Linux yet. Their write-ups, both public and from 2026-11-06:

- **DJ** (Diljit Singh, GitHub `DjDeveloperr`), T8140 / J700: `aurora-silicon/aura` branch `feat/sptm-hv`. The "Suspend to RAM" section of `docs/sptm-nv2-virt.md` (commit `a2cfc9e9`) has "What it found for a Linux port"; the code is in `src/sptm_virt_s2r.c` (`ef337312`).
- **Naeem Malik** (GitHub `malik-na`), t8103 / J313: `malik-na/m1-power-lab` branch `omarchy-live-power`, `docs/evidence/2026-11-06-mac27-hv/README.md` (tries 23-43) and `tools/hv-trace-kit/`. Linux-side groundwork is on `malik-na/linux-aurora` branches `m1power/*`: spin-table CPU offline, the PMU RTC wake, the M1 PMP v1 driver, and `1618cc6d56af`, which fixes the `dwc3_apple_remove` NULL oops on a port that never saw a cable.

What they found that bears on our open questions (their SoCs, not checked on T6020):

- **The entry, macOS's order.**
  - T8140: the secondaries self-disable (a bit per core); **WD2 is armed for 5 s**; the CPU complexes are armed off; the power gates, CLLT and clock muxes are parked; the **commit** (the S2R-timer write); the PMU RTC alarm over SPMI; "go hib"; then each core's deep WFI (`S3_5_C15_C6_2` bits 63 and 0).
  - t8103 is the same shape: the commit is at `0x23d2c4000`, the clkgen muxes are parked before it, ACC_OVRD is set to deep sleep and CYC_OVRD to `0x3000001` on every core.
- **The 5 s reset means the entry did not complete.**
  - WD2 (the "reconfig watchdog") is loaded by the AON engine at the commit. The hardware stops it only once the entry completes.
  - Naeem's tries 26-31 reset at about 5 s because the last core hung before its WFI: it touched the dwc3 after the clock muxes were parked.
  - DJ: printing anything after the first core disables itself delayed the boot core past WD2.
  - **Our resets come about 60 s after the S2R timer, not 5 s**, so the T6020 either differs or never arms WD2 this way. Worth reading WD2's CTRL/alarm at the commit in a future Aura step.
- **The wake lands at the locked boot-CPU RVBAR.** On the M1 this works for a raw m1n1 boot object: Naeem's trampoline in the installed image ran after the RTC alarm, 'Z' in PMU scratch `0x9f0a`.
  - That answers our open "does iBoot arm the wake path for a raw image" question for t8103.
  - His proof that the SoC slept rather than reset: a breadcrumb in PMU scratch written from the RVBAR entry, and m1n1's base address unchanged. After a full reset, iBoot reloads m1n1 at a new base.
- **Our own wake sources can wake the SoC halfway** if left powered. The debug USB port (ATC0) has to be powered off at the commit; uart0 and the CDC link are SoC-domain devices. This matches our wakeup-off / usb-teardown runs.
- **AMCC errors (DJ):** with no platform error handler (Linux's position), a memory-controller error that is enabled and pending at the commit wakes the SoC within 20 ms.
  - Fix: before the commit, clear error-enable word 0 bit 25 (DSID_AGE_OUT) and word 1 bit 8 (UNEXP_RT_HIT_DIR) on every plane.
  - **Display power-off raises DSID_AGE_OUT**, and our dcp-off runs do exactly that. New candidate step for the R-series.
- **Power once asleep (Naeem):** a completed entry still drew about 2 W until the PMP saw the E-cluster idle (cluster idle reports in the `0x23b738004` word). With them it is at or below about 0.3-0.4 W.
  - Relevant to our PCPM requests: the PMP has to see the clusters idle, not just receive the AP's IDLE.
- **The wake path (DJ):** 83 writes on one core in about 18 ms. Both clusters and the power gates come on, 22 domains go to their targets with AUTO_ENABLE, and WD2 is stopped last. DCP, DCPEXT, ANS, SIO, PMP and GFX restart their firmware (RTKit HELLO).
  - So the DCP restart after sleep (deferred at 21:46) is required for a real S2R, and the ANS has to come back through a fresh firmware start.

No runs changed. R7 and R7N still wait for the owner; the AMCC clear and a WD2 read at the commit are candidates to add before them.

## 2026-11-06 22:27 image 58: DJ's and Naeem Malik's leads, mapped to T6020; the Y-run "stalls" were unmapped pages; chain G58, W1, R8 (owner attended)

The owner is at the Mac for attended runs and asked to test the leads from DJ's and Naeem Malik's work (22:13 entry).

- **Correction to the 22:13 entry: "go hib" is not a missing step.** In our 13.5 analysis (11-05) the PMU log line "pmu go hib" comes from `AppleDialogSPMIPMU`'s quiesce re-programming the RTC alarm; it sends no sleep command. DJ's J700 trace agrees: the four SPMI writes after the commit are the alarm (`0xf80c`, `0xf808`, `0xf80e`, `0xf800 <- 0x41`), then the log line.
- **AMCC errors on T6020, from the 13.5 kernelcache** (`AppleT6020PlatformErrorHandler::_amccEnableErrors`, `fffffe0009b1a93c`, and its decoder tables):
  - each plane's error enable word *i* is at plane + `0x21000` + 8*i*, its status at + 4 (`_amccDecodeInterrupts` reads `0x21004` + 8*i*); planes `0x40000` apart, 4 per instance (Aura's `mcc.c` T6000 layout); macOS also zeroes plane + `0x22000` + 8*i*;
  - word 0 bit 26 is DSID_AGE_OUT (T8140: bit 25) and word 1 bit 8 UNEXP_RT_HIT_DIR. DJ's offset (`0x25000`) would have hit the wrong register here.
- **The Y-run stalls were most likely a mapping bug, not the hardware.** Aura's handler runs under Linux's EFI runtime map, which holds only the MMIO ranges Aura lists (`smp_psci_mmio_ranges`). Image 56 added the 12 held domains' writes but not their pages: `0x28e080000` (dispext0/1 chains) and `0x29e280000` (atc0/1/2_usb) were never mapped; disp0's chain shares the mapped `ps_sio` page. Y1, Y1T (USB-C) and Y2T (external displays) are exactly the unmapped groups, and Y3 (the panel's, mapped) never ran.
  - So "Aura cannot force those domains off" (17:41 to 18:04) is unproven.
  - R6's conclusion stands: Linux turned those domains off itself in R6, and the timer still reset at 86 s.
- **Image 58** (Aura `464131290c7949c2`, `boot.bin.psci-test58` `29448f1a7cab4ddd`, diff `patches/psci-efi/aura/wip-image58.diff`; `psci_dbg` at `+0x137940`; `install.sh` uses it). New aura-ctl bits, each off by default:
  - `0x100` records in a second block, `psci_dbg2` (magic `0xA0AA0002`, `run.sh` logs `aura dbg2`). It holds WD0..2 (count, alarm, ctl; WD*n* at WDT + `0x10`*n*) and the S2R timer word at four points: entry, just before the timer, right after it, and 100 ms later. It also holds each AMCC instance's error status at entry and before the timer, and the plane 0 enables.
  - `0x200` clears DSID_AGE_OUT and UNEXP_RT_HIT_DIR in every plane's enables before the timer, and restores them on any resume.
  - `0x400` stops WD2 100 ms after the timer.
  - `0x800` masks every AIC line after the timer, as macOS's AIC quiesce does; it applies only with bit 2, and the masks are restored on resume.
  - The held pages and the AMCC planes' pages are now in the runtime map (up to 48 ranges; U-Boot passes any number); the WD range is `0x30`.
  - `scan-magic` takes a word count and `aura-ctl` accepts bits 0 to 11.
- **Why WD2 matters:** on t8103 (Naeem, try38) and T8140 (DJ) the commit loads WD2, the AON "reconfig watchdog", and only a completed entry stops it. On the M1, iBoot leaves WD2's alarm at 90 s. Our timer resets the SoC about 60 s after it is written, even awake (T0). If that reset is WD2, every 86 s run was the engine's own "entry incomplete", and the timer is the commit the entry needs, not a separate safety net. In that case **R7N (no timer) cannot work and is dropped**.
- **Chain, owner attended** (each arms the next after it is recorded):
  - **G58**: normal path, records only (`0x100`). Checks image 58 and reads the watchdogs and AMCC status at entry.
  - **W1**: T0 + records + WD2 stopped (`0x501`). A resume = the 60 s reset is WD2; 85 s = it is not.
  - **R8**: R7 (R6 + PCPM + afr kept) + the AMCC clear + the AIC mask-all + records (`0xb3f`, slpa).

## 2026-11-06 22:32 run G58: image 58 is sound; the AMCC errors DJ named are enabled and pending on all four instances; WD2 sits at 90 s

- Run G58 (image 58, `boot.bin.psci-test58` `29448f1a7cab4ddd`, normal path, DS 32, the PMP release, genpd dump, aura-ctl `0x100`): `echo mem` 22:30:31, **back on the alarm, 31.7 s, `online 0-9`**, PMP requests `0xf000`, filesystems rw. The one device error is the usual one; the rest of the new kernel lines are `set affinity failed(-38)`. No reset, btrfs counters 0. Flags removed; default boot.bin `76f850895fed53d1`, `next_entry` unset; headless on, watcher running.
- Image 58's extra MMIO ranges and reads are fine (the scan finds both blocks; `psci_dbg` at `+0x137940` as computed).
- **`aura dbg2`** (words after the magic):
  - `[1]` = `0x40400000100`: steps `0x100`, **4 AMCC instances of 4 planes**.
  - WD0 counts with alarm 0 and ctl 0.
  - WD1 = Aura's dog: alarm `0xaba95000` = 120 s, ctl 4.
  - **WD2: alarm `0x80befc00` = 90 s, ctl 0, counter running** (`0x7c8f58fe` ≈ 87 s at entry, `0x7d4663ce` just before the wait). That is iBoot's leftover, as on the M1 (Naeem try28: 90 s).
  - The S2R timer word reads 1 before any write in this boot, as on the M1 after a reboot, so its value means nothing.
  - **AMCC status at entry and before the wait: `0x00000100_04000000` on every instance**, so word 0 bit 26 **DSID_AGE_OUT** and word 1 bit 8 **UNEXP_RT_HIT_DIR** are pending.
  - **Plane 0 enables: `0xb7bffdfd` / `0x00003f00`, both bits enabled.** This is DJ's condition (with no platform error handler, an enabled pending AMCC error wakes the SoC within 20 ms of the commit), present here even without a display power-off.
- Not fitting yet: if the commit started WD2 from its 90 s alarm, the reset would come about 90 s after the timer, not 60. W1 checks directly: it stops WD2 100 ms after the timer and records it.
- Next, per the chain: **W1** (T0 + records + WD2 stop, `0x501`), then **R8**.

## 2026-11-06 22:38 run W1: stopping WD2 after the timer moved the reset from about 85 s to about 116 s, but the alarm still did not bring Linux back

- Run W1 (image 58, normal path, DS 32, the PMP release, genpd dump, aura-ctl `0x501`: the S2R timer, records, WD2 ctl = 0 100 ms after the timer): `echo mem` 22:34:44.6; the next kernel started at 22:36:41 (`uptime -s`, NTP-synced). **About 116 s.** No dead-man push (Linux never came back), no hand reset, btrfs counters 0. The Pi watcher saw the Mac go down at 22:34:49 and come back up at 22:37:14. Flags removed; default boot.bin `76f850895fed53d1`, `next_entry` unset; headless on.
- Compare:
  - T0 (the timer alone, same path): about 85 s, i.e. the reset about 60 s after the timer write.
  - WD1 (Aura's 120 s dog): about 145 s.
  - 116 s is neither. **Stopping WD2 changed the reset time**, so WD2 is involved in the 60 s reset. But something else still resets the SoC about 90 s after the timer write. The 30 s alarm did not resume Linux in either run.
- The records (`psci_dbg2`) are lost with the reset, so this run cannot say what WD2 held after the commit.
- Candidates for the second reset:
  - WD2 restarted by the S2R engine after our stop;
  - WD0;
  - a reset 60 s after the alarm's wake attempt (30 s + 60 s ≈ 90 s after the timer).
- **Next diagnostic (image 59, unattended, normal path):** Aura resumes the kernel right after the timer write and WD2 stop, without waiting for the alarm. Linux then logs the WDT block (WD0..2) and the timer word every second, synced to disk, until the reset. That shows directly which watchdog runs out.
- Per the chain, R8 now (the owner is at the Mac): every sleep step with slpa, plus the AMCC enables cleared and the AIC masked. Its reading stands: about 86 s = the entry still did not complete.

## 2026-11-06 22:43 run R8: R7 plus clearing the AMCC errors and masking the AIC: the timer reset at 86 s again

- Run R8 (owner attended; image 58, slpa, DS 62, PMP sleep, AOP mode 3, the PMP release, aura-ctl `0xb3f`; plus wakeup off, `sleep keep: afr`, PCPM `0x300`, dcp off, USB teardown):
  - Pi kmsg: every switch line, `aura ctl … 0xb3f`, `TEST pcpm 0x300 asserted: 0, request 0xf300 ack 0xf300`, the AOP's queues stopped (12 of 12) and its `0x201` acked, and both live USB-C cores stopped. The stream ends when the network goes down (22:41:17), as in every slpa run.
  - `echo mem` 22:41:15.6; the next kernel at 22:42:41: **about 86 s, the timer's reset**.
  - No dead-man push, no hand reset, btrfs counters 0. Flags removed; default boot.bin `76f850895fed53d1`, `next_entry` unset; headless on, watcher running.
- **So neither DJ lead completes the entry here.** The AMCC DSID_AGE_OUT/UNEXP_RT_HIT_DIR enables were cleared before the timer, and every AIC line was masked after it. Nor does R7's own lead (PCPM0/1 asserted and then released after the PMP's IDLE).
- Two caveats:
  - Only the enables were cleared. The two status bits stay pending, and macOS also zeroes the plane + `0x22000` words. Whether a pending status still counts as a wake source with its enable off is not known.
  - The records are lost with the reset.
- Next:
  - the image 59 watchdog log (W1's open question, unattended, normal path);
  - a static comparison of the cluster-level steps in Naeem's t8103 entry (CPM power gating `0x23b71c080/088 = 0x80000000`, cluster PS `0x23b718000/4 = 0`, cluster controls) and DJ's T8140 entry (pmgr-pwrgate `0x300724060/68`, CLLT `0x300768030/34/3c`) with what Aura does on T6020. Aura so far does only the soc-cluster targets (image 54) and each core's own deep sleep.

## 2026-11-06 22:50 static: macOS's PMGR quiesce has no write that this Mac is missing; the AON watchdogs do differ; image 59, runs W2 and R9

Checked against the M1 and Neo sleep entries, which write the CPU-complex power gates and CLLT before the commit. 13.5 kernelcache:

- **`ApplePMGR::quiesceHW`**, the base-class call that `AppleT6020PMGR::quiesceHW` makes first. Its whole content:
  - `quiesceACC(i)` for each CPU complex (vtable `0x930`). T6020's override calls the base, which does a perf request, turns the perf counters off and takes an energy snapshot; `_enableFeatureACC(77)` is skipped because `isFeatureACC(77)` is false on T6020. Then **`enableCPMPowerDomainGating(true)`**: bit 31 of PMGR map 0 (ADT reg 0, `0x28e080000`) + `0xc030/0xc034/0xc038` per die. This is the counterpart of the M1's `0x23b71c080/088 = 0x80000000` and the Neo's pwrgate writes.
  - `_enableFeature(77, false)`: a no-op, since `_enableFeature` ignores ids above 50.
  - `enableVoltageChanges(false)`: only a check that can panic.
  - **`quiescePerfState()`**: fabric perf state 5, then 3; DCS (DRAM) 7, then 5; each is the low nibble of MPMGR ClkGen-SOC (map `0x40` = ADT reg 40, `0x28e20c000`; DCS at + `0x400`) followed by a poll for bit 31 to clear.
- **Live values on this Mac** (read-only, `mmio-read`):
  - `0x28e08c030/34/38` = `0x80000000`: CPM gating is already on.
  - `0x28e20c000` = `0x333` and `0x28e20c400` = `0x555`: fabric 3 and DCS 5, exactly where macOS's quiesce ends.
  - **So the PMGR quiesce has no write that this Mac is missing.**
- **CLLT on T6020** (`setCLLTAgentConfig`: PMGR + `0x54040/0x54050`) is a boot-time tunable (`ApplePMGR::_applyParam`), not a sleep step.
- **The watchdogs (13.5 `AppleARMWatchdogTimer`):**
  - The ADT `wdt` node: reg 0 `0x29e2c4000` (WD0..2), reg 1 `0x29e2a8254`, reg 2 `0x29e2a002c`, reg 3 `0x29e2a0008`, reg 4 `0x29e2a0020`; `reconfig-wdog-support` is present.
  - Its sleep action (not hibernating) calls `enableReconfigWatchdogMonitoring()` (WDT interrupt off, WD0 ctl = 0) and `disableWatchdog()` (reg 3's low byte cleared; WD1 is not touched on this path).
  - Live: reg 1..4 all 0 and WD0 ctl 0, so that is already the state. **WD1, however, is armed:** Linux's `apple_wdt` has it at ctl 4 with a 60 s alarm, and Aura re-arms it at 120 s for every suspend.
  - Naeem's M1 trace: "AON AP watchdog disabled", and at the entry WD0/WD1/WD2 ctl were all 0. **Aura is the only side with an AON watchdog running into the commit.**
- **Image 59** (Aura `c00741f7d3f10754`, `boot.bin.psci-test59` `246054fceb614142`, diff `patches/psci-efi/aura/wip-image59.diff`; `psci_dbg` still at `+0x137940`):
  - aura-ctl `0x1000` disarms WD1 right before the timer. The timer's reset is still the safety net, and dbg2 `[45]` = `0x5100000001`.
  - aura-ctl `0x2000` resumes the kernel right after the timer, for the normal path only.
  - The `run.sh` flag `/var/lib/deepidle/wd-log` logs WD0..2 and the timer word every second after the resume to `wdlog.txt`, each line synced.
- **Runs:**
  - **W2** (unattended, normal path, `0x2101`): Linux logs the watchdogs from the timer write to the reset. That shows which one fires, which W1 could not.
  - **R9** (owner attended, slpa): R8 + `0x1000`. 86 s = WD1 was not it.

## 2026-11-06 22:58 run W2: invalid, aura-ctl refused 0x2101; fixed, W2 re-armed

- `run.log`: `aura-ctl: only bits 0 to 11 are defined`. The word stayed 0, so Aura ran image 51's plain suspend: `suspend deep 1: back, rc=0, elapsed 32.19`, dbg2 `[1]` = `0x40400000000`. No timer write, no reset.
- The wd-log loop still ran its 200 s (`wdlog.txt`, 200 lines): with no timer the baseline is steady. WD1 is armed by Linux (ctl 4, alarm `0x55d4a800` = 60 s, count kicked), WD2 alarm `0x80befc00` (90 s) ctl 0, WD0 ctl 0, timer word 1. That is the before picture for the real W2.
- Cause: `harness/mmio/aura-ctl.c` still capped the word at `0xfff` (image 58's bits). Now `0x3fff` (image 59's `0x1000` WD1 off and `0x2000` resume now). R9's `0x1b3f` would have hit the same refusal. `install.sh` rebuilds the tool before each armed run.
- No hand reset, btrfs counters 0, default `boot.bin` `76f850895fed53d1`, no next_entry. Re-armed: `NEXT="R9" bash harness/psci-efi/attended.sh W2`.

## 2026-11-06 23:05 run W2: after the S2R timer, Linux cannot be resumed; the reset at 86 s again

Boot after W2 (image 59, `246054fceb614142`, aura-ctl `0x2101`: records, the S2R timer, then straight back to the kernel). No dead-man push, no hand reset.

- **Timing** (Pi kmsg and ping): `echo mem` at 23:01:39 (`aura ctl ... 0x2101` read back); the last kernel line is the AOP's `SetAPPower 0x201`; ping down at 23:01:45; the Pi's stream ended at 23:02:13; the next kernel (the default, `7.2.11-14-1-ARCH`) started at 23:03:05. **86 s, the timer's usual reset** (G58's T0, R6, R8).
- **Linux never came back:** no resume line, no network, no `wdlog.txt` (the results dir stops at `filesystems ro`; the root was read-only for the run). Aura's dbg2 did not survive the reset: the default boot has no Aura, so there was nothing to read.
- **The resume-now path is the normal one:** `psci_resume_kernel(-1, 0)` is the call the normal wake makes (wake lines masked, WD1 disarmed, quiesce undone, `psci_enter` to the kernel's resume entry); image 59 only skips the wait. And W1 showed Aura's own code still runs at least 100 ms after the timer (its WD2 stop took effect). So the CPU and DRAM keep working, but **the kernel's resume does not get through once the timer is written**. Likely something it needs (interrupt delivery, the fabric or a device link) is already going down. The timer write is the point of no return, as in macOS, where it is the last write before the cores stop.
- **Consequence:** the reset source after the timer cannot be logged from Linux. A log kept by Aura in DRAM would not survive either: the next boot is the default without Aura, and the area is ordinary RAM there.
- **What W1 and the reset times still say:** without anything stopped, ~86 s after echo mem (about 60 s after the timer). WD2 stopped: ~116 s. That is not WD1's 120 s from the PSCI call, which comes out at about 144 s. So a source other than WD1 and WD2 remains.
- Clean afterwards: flags removed, `/boot` mounted, default `boot.bin` `76f850895fed53d1`, no next_entry, btrfs counters 0.
- **Next (chain):** R9, owner attended: R8 + `0x1000` (WD1 off before the timer). WD2 is not stopped in R9, so the timer's own reset still recovers the Mac if the entry does not complete.

## 2026-11-06 23:11 run R9 (owner attended): WD1 off before the timer: the 86 s reset again

Boot after R9 (image 59, `246054fceb614142`, aura-ctl `0x1b3f` = R8 + `0x1000`). No dead-man push. No hand reset: the reset came at 86 s, well inside the 10 minutes the owner was asked to wait.

- **Settings, from the Pi kmsg:** slpa (emergency ro remount), USB wakeups off, `sleep keep: afr`, `pcpm: 768` (`0x300`), `dcp off: Y`, `usb teardown: Y`, `pmp release for sleep: Y; requests 0xf000 ack 0xf000`, `aura ctl ... 0x1b3f`, then `echo mem` at 23:08:24 and the AOP's `SetAPPower 0x201`.
- **Timing:** ping down at 23:08:28; the next kernel (the default) started at 23:09:50: **86 s after echo mem**, the timer's reset as in R6, R8 and W2.
- **So Aura's armed WD1 did not keep the entry from completing.** Every AON watchdog except WD2 (which the commit loads) is now off at the commit, as in macOS and the M1 trace.
- **Tried so far against the 86 s reset, on top of every macOS step found:**
  - device domains off (R6);
  - PCPM0/1 (R7);
  - AMCC errors cleared and the AIC masked (R8);
  - WD1 off (R9).
  None changes it.
- Clean afterwards: flags removed, `/boot` mounted, default `boot.bin` `76f850895fed53d1`, no next_entry, btrfs counters 0. The chain ends here (`NEXT=""`).

## 2026-11-06 23:13 static: DJ's per-core deep-sleep register is T8140's; every DJ/Naeem lead now tried or ruled out on T6020

- DJ's entry ends with each core's deep WFI flagged in `S3_5_C15_C6_2` (bits 63 and 0; `src/sptm_virt_s2r.c` on `feat/sptm-hv`, `sptm_virt_s2r_wfi()`).
  - On this Mac, macOS's sleep code writes `S3_5_C15_C6_0` (ACC_OVRD) and CYC_OVRD `0x3000001` instead: our HV trace of the guest's sleep (worklog 2026-10-25 18:31, `docs/hv-boot-trace-reference.md` step 7), and XNU 8796's `arm64_prepare_for_sleep` (16:19 entry).
  - Aura's `cpu_sleep(true)` writes the same fields.
  - So `C6_2` is the T8140 form of the same step, not a missing T6020 write.
- DJ's order also puts the PMU RTC alarm (SPMI `0xf80c/0xf808/0xf80e`, `0xf800 <- 0x41`) after the commit. That is the alarm re-programmed at Quiesce ("go hib", 22:27 correction). Linux sets the same alarm before the suspend.
- **Where the leads stand on T6020:**
  - secondaries stopped (CPUSTART stop requests, image 55);
  - CPU complexes / CPM gating (already on, 22:50);
  - fabric and DCS states (already macOS's, 22:50);
  - AMCC errors (R8);
  - AIC masked (R8);
  - AON watchdogs off (R9);
  - the debug USB port off (usb-teardown);
  - per-core deep sleep (same as XNU).
  None completes the entry.
- **The gap is observability after the commit.**
  - W2 showed Linux cannot run after the timer.
  - Aura's DRAM records do not survive the reset into the default boot.
  - Naeem proved his M1 slept with a breadcrumb in PMU scratch (`0x9f0a`), which survives a reset.
  - **Next:** find PMU scratch registers on T6020 that are free and survive a watchdog reset (the ADT `pmu` node and 13.5's `AppleDialogSPMIPMU`), read-only first. Aura can then leave a few bytes after the timer: did each core reach its deep WFI, did the boot core come back through RVBAR before the reset. Linux reads them on the next boot.

## 2026-11-06 23:18 static and read-only: the PMU's scratch map; boot-error-stage 0x50 marks the resets that came after macOS's AP-sleep messages

- **Where Naeem's breadcrumb lives.** `0x9f0a` on the M1 is `info-leg_scrpad + 0xa` (`leg_scrpad` = `0x9f00` there, `tools/hv-trace-kit/pmu_postmortem.py` in malik-na/m1-power-lab). On this Mac the primary PMU (ADT `nub-spmi0/spmi-mpmu`, `pmu,maverick`, from the 13.5 `DeviceTree.j414sap`) has:
  - `info-leg_scrpad` `0x6000`;
  - `info-scrpad` `0x8000`+`0x1000`, with `info-scrpad_socd` `0x8b00`+`0x400` and `info-fault_shadow` `0x867b`+`0x10` inside it (3666 of its 4096 bytes are nonzero, so it is in use);
  - `info-fault_log` `0x1000`+`0xa`, whose bits are named in `info-fault_name-N` (4 `wdog,reset_in1`, 5 `dbg_rst,reset_in2`, 6 `sochot,reset_in3`, 7 `crash,crash_n`, 15 `crash_follower_n`, …).
- **The legacy scratch keys macOS uses** (`AppleDialogSPMIPMU::_readBootKey/_writeBootKey`, which access `leg_scrpad + key`; every call in the 13.5 kext):
  - 0 `BootDebug`;
  - 1 `BootStage`;
  - 2 the error and panic counts;
  - 3 `BootErrorStage`;
  - 8–11 `BootAppName` (so Naeem's `+0xa` is inside it here);
  - `0xf` the shutdown flag;
  - `0x18` `UPOState`;
  - `0x19`–`0x1a` `UPOCounter`;
  - `0x1f`.
  - **Not used by macOS:** 4–7, `0xc`–`0xe`, `0x10`–`0x17`, `0x1b`–`0x1e`. They read 0 now, except `0x6017` = `0x01` (iBoot's, presumably). iBoot is encrypted in the IPSW, so whether iBoot reads 4–7 cannot be checked statically.
- **Read now (read only, R9's post-reset boot):**
  - `leg_scrpad` `00 30 00 50 00…`;
  - the fault log is all 0. The 86 s reset is not a PMU fault, or iBoot clears the log.
  - `fault_shadow` `1012…` (the same after every kind of reset, 11-04).
- **A marker we already had:** `run.sh` logs `boot-error-stage` on every boot (122 readings). It changes only at unclean resets:
  - It becomes `0x50` (macOS's "AP asleep" stage) after the resets of I, J, L (16:14), N, R, R6, R8 and R9. All of these sent macOS's `slpa` and `SetAPPower 0x201` and were then reset by the S2R timer.
  - It becomes `0x30` after:
    - D (`slpa` and the timer, without the AP-sleep messages);
    - T0, W1 and W2 (no `slpa`);
    - M and S (hung before the messages);
    - C (Linux resumed).
  - Linux never writes `0x50` (`deep_steps` bit 8 was never used). So the SMC or PMU firmware sets boot stage `0x50` when it takes the AP-sleep messages, and the timer's reset then finds it there.
  - **Meaning:** the SMC side considers the AP asleep at the reset. The missing part is on the SoC side.
  - It is a free per-run check from now on: `0x50` means the SMC got as far as macOS's sleep.
- **Next: a breadcrumb in key 4 (`0x6004`).**
  - First, one attended check from Linux: write `0x6004` = `0xa5`, reboot normally, read it back (does it survive, does iBoot ignore it), then clear it.
  - Then image 60: Aura writes a stage code to `0x6004` over SPMI at each step of the sleep tail (before and after the timer, after WD2, after the AIC mask, before the last core's deep WFI, and on the RVBAR wake), and `run.sh` reads and clears it at boot.
  - That says how far the boot core got before the reset, and whether a wake came back through RVBAR.

## 2026-11-06 23:21 image 60: Aura leaves stage codes in the PMU's scratch key 4; built, not yet run
- **Scratch check from Linux (no reboot):** `0x6004` read 0, took `0xa5` and read it back through `spmi_nvmem2`, then went back to 0. It is plain writable scratch. Whether it survives a reset and whether iBoot reads it is still the attended part.
- **Image 60** (Aura `7958e947d95759d4`, `boot.bin.psci-test60` `4ba57db10e3fc58b`, diff `patches/psci-efi/aura/wip-image60.diff`; `psci_dbg` at `+0x137980`; `install.sh` uses it):
  - New aura-ctl bit `0x4000`, off by default: Aura writes a one-byte stage code to PMU `0x6004`.
  - The write is one SPMI "extended register write long" to slave `0xb` on `nub-spmi0` (`0x29e114000`). It uses the same command word as Linux's `spmi-apple`. This ADT has no `gen`, so the registers are at `0x0`, `0x4` and `0x8`, as in Linux.
  - `psci_ctl_init` finds the controller from the ADT and keeps it in a cache-cleaned block, so the RVBAR path, with the MMU off, can write too.
  - Each write has no printing and bounded waits, about 1 ms at most. If the TX FIFO is busy, the write is skipped.
  - **Codes:**
    - `11` entry (the steps read);
    - `12` before the timer step;
    - `13` timer written;
    - `14` 100 ms later, after WD2 is stopped;
    - `15` after the AIC mask;
    - `17` before the secondaries are released;
    - `18` before the cache flush and the boot core's deep WFI;
    - `1a` the heartbeat loop (the deep WFI returned);
    - `1e` a normal resume into the kernel;
    - `21` an RVBAR wake;
    - `22` the RVBAR resume into the kernel.
- `run.sh` logs `0x6000`–`0x601f` on every boot. Nothing clears `0x6004` yet. A run's code tells only if it changed from the one before.
- `aura-ctl` takes up to `0x7fff`.
- **Next (owner present, a new kind of step):**
  - First, write `0xa5` to `0x6004` and reboot normally, to see that it survives and iBoot ignores it.
  - Then run R10: R9 + `0x4000` (aura-ctl `0x5b3f`, R9's `0x1b3f` + the crumbs).
  - Its code at the next boot says where the boot core was when the timer reset came. `18` would mean it reached the deep WFI and stayed there, and `1a` that it woke from it.

## 2026-11-06 23:31 scratch check S1 (owner present): `0x6004` = `0xa5`, then a normal reboot
- Before: `0x6000`–`0x601f` = `00300050a5000000…0001000000000000` (`0xa5` just written; `0x6017` = `01` as before). Default `boot.bin` `76f850895fed53d1`, nothing armed, `/boot` rw.
- On the next boot: read `0x6004` (survived?), check that the boot was normal (iBoot ignored it), then clear it to 0.

## 2026-11-06 23:33 scratch check S1 result: `0x6004` survives a reboot and iBoot ignores it; run R10 armed (owner present)
- After the normal reboot (23:31): `0x6000`–`0x601f` = `00300050a5000000…0001000000000000`. **`0xa5` survived**, and nothing else changed. The boot was normal: default `boot.bin` `76f850895fed53d1`, fault log 0, `fault_shadow` `1012…` as always, no btrfs errors, clean shutdown in the previous boot's journal.
- `0x6004` cleared to 0 again, so R10's code is unambiguous (0 = Aura never wrote).
- Correction: R9's word was `0x1b3f` (no `0x40`, no `0x400`), so R10 is `0x5b3f`. The earlier Next said `0x5f7f`; fixed.
- **Run R10** (`attended.sh R10`): R9's settings + aura-ctl `0x4000`, image 60 `4ba57db10e3fc58b`. Expect the 86 s reset again; the point is the code in `0x6004` at the next boot. Headless on, Pi watcher running.

## 2026-11-06 23:41 run R10 (owner attended): image 60 faulted on its first breadcrumb, WD1 reset at 146 s; image 60b fixes the mapping
- **Dead-man pushes:** none. No hand reset. btrfs counters 0, default `boot.bin` `76f850895fed53d1`, `next_entry` unset, flags removed, headless on, watcher running.
- **Pi kmsg:** the usual sequence: slpa (ro remount), PMP release `0xf000` acked, `aura ctl ... 0x5b3f` (the word reached Aura), `echo mem` 23:35:38, the AOP's `SetAPPower 0x201`.
- **Timing:** the next kernel started at 23:38:04. That is **146 s after echo mem**: WD1's reset (about 144 s), not the timer's 86 s. So the timer was never written.
- **PMU:** `0x6004` = 0 (cleared before the run), so not even the entry code `11` landed. `boot-error-stage` `0x50` (unchanged from R9; the AP-sleep messages were sent). Fault log 0.
- **Cause:** the same bug as image 56's Y runs (worklog 22:27). Aura's handler runs under Linux's EFI runtime map, which holds only `smp_psci_mmio_ranges`. Image 60 never listed the SPMI controller's page `0x29e114000`, so the first `read32` in `qs_crumb(0x11)` faulted at the top of the sleep tail, and WD1 (still armed then; it is turned off only just before the timer) reset the SoC.
- **Image 60b** (Aura `501d9ddc5471ad2f`, `boot.bin.psci-test60b` `438533ef2e0b277b`, diff `wip-image60b.diff`; `psci_dbg` still at `+0x137980`; `install.sh` uses it):
  - `psci_crumb_base()` exported; `smp_psci_mmio_ranges` adds `0x29e114000` + `0x10`.
  - The range list goes from 48 to 64 entries (`dt_set_psci`), so that a full list cannot drop it silently. U-Boot reads any count.
- **Next:** R10 again on 60b (same `attended.sh R10`, owner still present). It is a self-recovering variation either way: if the crumb write itself hangs, WD1 resets at about 146 s again.

## 2026-11-07 06:26 run R10 on image 60b (owner attended): the breadcrumb works; the boot core's last code is `18`, the reset is the timer's at 86 s
- **Dead-man pushes:** none (only the two "starting" pushes and my result push). No hand reset.
- **Timing:** `echo mem` 23:43:34 (Pi kmsg, `aura ctl ... 0x5b3f`, `SetAPPower 0x201`), the next kernel at 23:45:00: **86 s**, the S2R timer's reset as in R6, R8, R9.
- The test boot listed 29 runtime MMIO ranges, `0x29e114000` among them.
- **PMU after the reset:** `0x6000`–`0x601f` = `00 30 00 50 18 00…` (`0x6017` = 1 as always). **`0x6004` = `0x18`.** `boot-error-stage` `0x50` again, fault log 0, `fault_shadow` `1012…`.
- **Meaning:** Aura wrote `11` through `18` in order and nothing after. So the boot core:
  - read the steps, wrote the timer, stopped WD2 100 ms later and masked the AIC;
  - released the nine secondaries into their deep sleep and waited 2 ms;
  - reached the point before its cache flush and its own deep WFI.
  It never reached the heartbeat loop (`1a`, the deep WFI returned) and never came back through RVBAR (`21`). Either it hung in the set/way flush, or it slept and nothing ever woke it while the SoC stayed up until the timer reset.
- Clean afterwards: flags removed, `/boot` mounted, default `boot.bin` `76f850895fed53d1`, no `next_entry`, btrfs 0, headless on, watcher running.

## 2026-11-07 06:26 Naeem Malik's real S2R on the M1 (malik-na/m1-power-lab, branch omarchy-live-power, 11-06/07)
The owner pointed to his post: 0.05 W averaged over a 3-hour sleep on the M1 Air. His evidence log (`docs/evidence/2026-11-06-mac27-hv/README.md`), read locally in `~/Work/ref/m1-power-lab`:
- **try23:** macOS 27 runs its whole sleep entry as an m1n1 guest. In order: device domains off, PMP/DCP `SET_AP/IOP_POWER 0x201`, the AON AP watchdog disabled, PMU boot stage `0x50`, SMC `slpa`, CPUSTART bits, the clkgen muxes parked (`0x23b040140..154`), cluster controls 0, CPM power gating `0x23b71c080/088 = 0x80000000`, cluster PS `0x23b718000/4 = 0`, **the S2R-timer commit**, the PMU RTC alarm over SPMI, the commit written twice more, then each core ACC_OVRD deep sleep + CYC_OVRD `0x3000001` + WFI.
- **try24–31, a reset about 5 s after the commit, the same kind of wall as ours:** with stage markers in PMU scratch (as image 60), the cause was his own last core. It **hung on the first MMIO access to the USB controller** after macOS had parked its clock, so it never reached its final WFI and an external timer reset the SoC.
- **try32:** nothing touched hardware after the commit, and **the M1 really slept**. The RTC alarm brought the boot core back at the locked RVBAR (marker `Z`). try33 completed a round trip, and try46 held a 3-hour sleep at about 0.05 W.
- **For us:** the same lesson. The SoC sleeps once the last core reaches its deep WFI with nothing pending, and the entry is otherwise what we already do. R10 shows our boot core gets to `18`. What it does after that (a set/way flush, then `cpu_sleep(true)`) and whether the secondaries and CPU clusters are really down by then are the open points. Image 60c answers both.

## 2026-11-07 06:26 image 60c: code `19` after the flush and a CPU-side snapshot; run R11 armed
- **Image 60c** (Aura `8716b085b8ad97a0`, `boot.bin.psci-test60c` `59049072223cef33`, diff `wip-image60c.diff`; `psci_dbg` still `+0x137980`; `install.sh` uses it):
  - `19` after `dcsw_op_all` + `dsb`, right before `cpu_sleep(true)`.
  - **A snapshot** 2 ms after the secondaries' release, before `18`, in the free keys:
    - `0x6010`/`0x6011`: the PMP request and ack words bits 8–15 (`0x28e3c2000`, `+0x80`). macOS ends at 0; Linux's TEST log showed `0xf300` when the PCPM bits were asserted.
    - `0x6012`/`0x6013`/`0x601b`: the ECPM, PCPM0 and PCPM1 power words bits 4–11 (`0x28e080060`, `68`, `70`; `0x1f` live).
    - `0x601c`–`0x601e`: the EACC, PACC0 and PACC1 soc-cluster controls (`0x28e088000`, `+4`, `+8`).
  - The SPMI write takes 1 to 4 bytes now; `0x28e3c2000` is added to the runtime MMIO list. `0x6017` (iBoot's, presumably) is left alone.
- **Run R11** = R10 on 60c (`attended.sh R11`, aura-ctl `0x5b3f`). It is a self-recovering variation. `0x6004` and the snapshot keys read 0 before it.

## 2026-11-07 06:34 run R11 (image 60c): the boot core reaches its deep WFI; P-complex 0 is still on, P-complex 1 is off; image 60d, run R12 armed
- **Dead-man pushes:** none. No hand reset. `echo mem` 06:29:17 (`aura ctl ... 0x5b3f`, `SetAPPower 0x201`); next kernel 06:30:43: **86 s**, the timer's reset.
- **PMU scratch after the reset:** `0030005019000000 0000000000000000 00001f1f00000001 000000000f101000` (`0x6000`–`0x601f`):
  - `0x6004` = **`0x19`**: the flush finished and the boot core executed `cpu_sleep(true)`. It never woke.
  - `0x6010`/`0x6011` = **`00`/`00`**: the PMP request and ack words are 0, as at the end of macOS's entry (PCPM0/1 and the display bits all released).
  - CPU complexes' power words (bits 4–11): ECPM `0x1f` (on: the boot core's), **PCPM0 `0x1f` (on)**, **PCPM1 `0x00` (off)**.
  - Cluster controls: EACC `0x0f`, PACC0 `0x10`, PACC1 `0x10`: targets 0, bit 4 (the bit macOS polls until it clears) set on both.
- **Reading:** 2 ms after the release, P-complex 1 was off and P-complex 0 was not. That is the first concrete difference from a completed entry.
- **Likely cause, found in the code:**
  - Linux's own secondary wait loop clears the fast-IPI pending bit `IPI_SR` after each wake (`smp.c:246`). Aura's `psci_park_c` never does.
  - The release is a fast IPI (`IPI_RR_GLOBAL`), so a released secondary keeps `IPI_SR` pending. Each deep WFI can then end at once, and the core loops through flush + `cpu_sleep` instead of powering down.
  - Why P-complex 1 got down anyway is not explained (timing, or which cores were still looping). Image 60d measures it.
- **Image 60d** (Aura `d0d0c55253260d69`, `boot.bin.psci-test60d` `040cefaccda4b569`, diff `wip-image60d.diff`; `psci_dbg` `+0x137980`; `install.sh` uses it):
  - In the S2R branch of `psci_park_c` only (normal hotplug parking unchanged): `IPI_SR` cleared before each `cpu_sleep(true)`, and a per-core counter of those sleeps (one cache line each, cleaned).
  - The boot core waits up to 500 ms for the PCPM0 and PCPM1 power words to read 0, then takes the snapshot. New keys:
    - `0x6014`: the wait in 2 ms units (`ff` = timeout);
    - `0x6015`/`0x6016`: the cores that never reached the sleep (bit = Aura CPU index);
    - `0x600c`/`0x600d`: the cores that slept more than once;
    - `0x600e`: the highest count (capped at 255).
- **Run R12** = R11 on 60d (`attended.sh R12`), a self-recovering variation.
- Clean before it: flags removed, `/boot` mounted, default `boot.bin` `76f850895fed53d1`, no `next_entry`, btrfs 0, headless on, watcher running.

## 2026-11-07 06:45 run R12 (image 60d): both P complexes power down, cpu3 never reaches its S2R sleep; image 60e, run R13 armed
- **Dead-man pushes:** only the R11 result and the R12 start. No hand reset. `echo mem` 06:36:23 (`aura ctl ... 0x5b3f`); the Pi saw the Mac down at 06:36:30 and up at 06:38:20; uptime from 06:37:49. That is **86 s**, the timer's reset again.
- **PMU scratch after the reset:** `0030005019000000 0000000000000000 00001f10ff88f801 000000000f000000` (`0x6000`–`0x601f`):
  - `0x6004` = **`0x19`**, as in R11: the boot core reached `cpu_sleep(true)` and never woke.
  - `0x6010`/`0x6011` = `00`/`00`: the PMP requests are released.
  - Power words (bits 4–11): ECPM `0x1f`, **PCPM0 `0x10`**, PCPM1 `0x00`. PCPM0 is `0x100`: the actual-state nibble (bits 4–7) is **0, so P-complex 0 is off**. Bit 8 is the PMGR's was-power-gated flag (`APPLE_PMGR_WAS_PWRGATED` in Linux's pmgr-pwrstate), set on PCPM0 whenever it is read live (`0x1f0`). So both P complexes were down this time; in R11 PCPM0 read `0x1f` (actual state f) 2 ms after the release.
  - Cluster controls: EACC `0x0f`, **PACC0 `0x00`, PACC1 `0x00`**: bit 4, the one macOS polls until it clears, has cleared on both P clusters (it was set in R11).
  - `0x6014` = `ff`: the 500 ms wait timed out. It waited for the whole power word to read 0, and bit 8 never clears, so the timeout is my condition's fault, not a stuck complex.
  - **`0x6015`/`0x6016` = `f888`: the indices that never reached the S2R sleep are 3, 7 and 11–15.** Aura's index is the ADT `cpu-id` (13.5 ADT: E cores 0–3, P cluster 0 4–7, P cluster 1 8–11). This J414s runs P cores 4–6 and 8–10; 7 and 11 are not used (macOS's trace writes CPUSTART for 1–6 and 8–10 only), and 12–15 do not exist. So **every P core and E cores 1 and 2 slept; E core 3 (MPIDR 3, Linux cpu3) never did**.
  - `0x600c`–`0x600e` = 0, which cannot be right: at least one core slept, so the highest count is at least 1. The last scratch write was dropped: `qs_crumb_write` skips a write when the SPMI TX FIFO is not empty, and it waited only about 1 ms for each reply. Whether any core slept more than once is unknown.
- **Reading:** clearing `IPI_SR` worked. The P complexes now power down, which is the R11 difference gone. What is left is cpu3 and the reset itself. cpu3 is in the E cluster, which stays on for the boot core anyway, but Naeem's M1 only slept once **every** core was in its final WFI. cpu3 was either not CPU_OFF in Aura's table at the release (so it got no IPI), or it was and never left its park WFI, or it is somewhere else entirely.
- **Image 60e** (Aura `1d975e14ecf8abf4`, `boot.bin.psci-test60e` `7b444f57629d6a98`, diff `wip-image60e.diff`; `psci_dbg` still `+0x137980`; `install.sh` uses it):
  - Scratch writes wait up to about 5 ms for the TX FIFO and for the reply, instead of dropping the write.
  - The P-complex wait checks only the actual-state nibble (bits 4–7) of PCPM0/1. `0x6014` becomes a real time.
  - New keys `0x6005`/`0x6006`: the cores Aura held as `CPU_OFF` when it sent the release (bit = index). `0x6007`: the lowest valid secondary that never slept (bits 4–7) and its PSCI state (bits 0–3: 0 parked, 1 on, 2 off), `ff` if none.
  - Everything else is as 60d.
- **Run R13** = R12 on 60e (`attended.sh R13`), a self-recovering variation. The scratch keys `0x6004`–`0x6016` and `0x601b`–`0x601e` are zeroed before it.
- Clean before it: flags removed, `/boot` mounted, default `boot.bin` `76f850895fed53d1`, no `next_entry`, btrfs 0, headless on, watcher running.

## 2026-11-07 06:53 run R13 (image 60e): cpu3 was CPU_OFF and got the release IPI but never left its park WFI; P complexes off in 6 ms; image 60f, run R14 armed
- **Dead-man pushes:** only the R12 result and the R13 start. No hand reset. `echo mem` 06:48:36; the Pi saw the Mac down at 06:48:41 and up at 06:50:31; uptime from 06:50:02. **86 s**, the timer's reset.
- **PMU scratch after the reset:** `00300050197e0732 0000000000000000 00001f100388f801 000000000f105000` (`0x6000`–`0x601f`):
  - `0x6004` = `0x19` again: the boot core reached its deep WFI.
  - **`0x6014` = 3: both P complexes read actual state 0 within 6 ms of the release.** With the fixed condition (bits 4–7 only) the wait is short; R12's timeout was the condition.
  - PMP request/ack `00`/`00`; ECPM `0x1f`, PCPM0 `0x10` (off, was-gated flag), PCPM1 `0x00`.
  - Cluster controls at 6 ms: EACC `0x0f`, PACC0 `0x10`, PACC1 `0x50`. Bit 4 is still set at 6 ms; in R12 it had cleared by 500 ms. PACC1 also shows bit 6.
  - Never slept `f888` as in R12: **cpu3** (index 3), with 7, 11 (unused) and 12–15 (absent).
  - **`0x6005`/`0x6006` = `077e`: Aura held cores 1–6 and 8–10 as `CPU_OFF` and sent each the release IPI.** cpu3 is among them.
  - **`0x6007` = `0x32`: the first never-slept core is index 3, PSCI state 2 (`CPU_OFF`).** So cpu3 went through `smp_psci_cpu_off`, was sent the same IPI as cpus 1 and 2 (same cluster, same path), and still never ran the S2R branch of its park loop.
  - `0x600c`–`0x600e` = 0 again, though at least one core slept, and the writes after it (`0x6005`) landed. So either those keys are cleared over a reset, or that write is still lost. `0x600c` reads back a write fine from Linux; I left `a5 5a 3c` in it before R14. After R14, `a5 5a 3c` = write lost, `00` = cleared over the reset, anything else = real values.
- **Reading:** the release reaches every core but cpu3. cpu3 is either stuck before its park WFI (between setting `CPU_OFF` and the loop), in a WFI the IPI does not end, or the IPI goes elsewhere (the spin table's MPIDR for index 3 is the one cpu3 wrote itself at its first start). An E core still awake, or in a shallow state, would block the SoC sleep the way Naeem's last core did.
- **Image 60f** (Aura `e56f88f23748ca11`, `boot.bin.psci-test60f` `6dfefe678261390d`, diff `wip-image60f.diff`; `psci_dbg` still `+0x137980`; `install.sh` uses it). For the first never-slept core:
  - `0x6010`/`0x6011`: the spin-table MPIDR the release IPI used (bits 0–15). R11–R13 show the PMP request/ack are 0, so these keys are reused.
  - `0x600c`: its park entries since boot (`psci_park_c` calls); `0x600d`: its park-loop WFI returns since the S2R clear.
  - `0x600e`: its S2R sleep count 2 ms after a second IPI, built from the reset table's MPIDR.
  - All `ff` if every core slept.
- **Run R14** = R13 on 60f (`attended.sh R14`), a self-recovering variation.
- Clean before it: flags removed, `/boot` mounted, default `boot.bin` `76f850895fed53d1`, no `next_entry`, btrfs 0, headless on, watcher running. Scratch `0x6004`–`0x600b`, `0x6010`–`0x6016`, `0x601b`–`0x601e` zeroed; `0x600c`–`0x600e` = `a5 5a 3c`.

## 2026-11-07 06:59 run R14 (image 60f): cpu3 entered its park WFI once and never came out, not even for a second IPI; run R15 (no CPUSTART stop request) armed
- **Dead-man pushes:** only the R13 result and the R14 start. No hand reset. `PM: suspend entry` 06:55:38; the Pi saw the Mac down at 06:55:45 and up at 06:57:35; uptime from 06:57:04. **86 s**, the timer's reset.
- **PMU scratch after the reset:** `00300050197e0732 0000000001000000 03001f100388f801 000000000f105000`:
  - `0x6004` `0x19`, `0x6014` 6 ms, never slept `f888`, CPU_OFF mask `077e`, first never-slept `0x32` (cpu3, `CPU_OFF`): all as R13.
  - **`0x6010`/`0x6011` = `0x0003`:** the release IPI went to MPIDR 3, cpu3's own.
  - **`0x600c` = 1:** cpu3 entered `psci_park_c` once since boot (its `CPU_OFF` at the suspend).
  - **`0x600d` = 0:** it never returned from the park loop's WFI after the S2R clear.
  - **`0x600e` = 0:** 2 ms after a second IPI (from the reset table's MPIDR) it still had not slept.
  - The `a5 5a 3c` marker was overwritten by these values, so `0x600c`–`0x600e` survive a reset and take writes. The zeros in R12 and R13 were values written, not drops. That leaves the old again/max reading unexplained, but nothing depends on it.
- **Reading:** cpu3 is in its park WFI (or below it) and nothing wakes it: neither the release IPI nor a second one. cpus 1 and 2, in the same cluster, on the same code path, wake on the first. What differs is what was done to the E cluster between their `CPU_OFF` and the release, all of it before the IPIs:
  - aura-ctl bit 5 (`STOPREQ`): CPUSTART + 0 written with each secondary's bit right before its IPI. Aura's own `smp_psci_cpu_off` comment says a core stopped that way did not come back from any start strobe (boot tests 2026-10-25).
  - bit 4 (`CLUSTERS`), the cluster targets to 0, and bit 3 (`CLOCKS`), the ClkGen muxes and PLL-off, both before the release.
- **Run R15** = R14 with only `STOPREQ` removed (aura-ctl `0x5b1f`), image 60f. It is a one-step reduction of a self-recovering setup. If cpu3 then sleeps (`0x6015`/`16` without bit 3, `0x6007` = `ff`), the stop request is what holds it; if not, the cluster or clock step is next.
- Clean before it: flags removed, `/boot` mounted, default `boot.bin` `76f850895fed53d1`, no `next_entry`, btrfs 0, headless on, watcher running, scratch `0x6004`–`0x6016` and `0x601b`–`0x601e` zeroed.

## 2026-11-07 07:06 run R15 (60f, no CPUSTART stop request): every core reaches its S2R sleep, still the 86 s reset; image 60g (quiet commit), run R16 armed
- **Dead-man pushes:** only the R14 result and the R15 start. No hand reset. `PM: suspend entry` 07:02:03; the Pi saw the Mac down at 07:02:08 and up at 07:03:58; uptime from 07:03:29. **86 s**, the timer's reset.
- **PMU scratch after the reset:** `00300050197e07ff 00000000ff000000 ffff1f100380f801 000000000f105000`:
  - **Never slept `f880`: only 7, 11 (unused) and 12–15 (absent). cpu3 slept.** `0x6007` = `ff` (no never-slept core) and the per-core keys `0x6010`/`11`, `0x600c` read `ff`. (`0x600d`/`0e` read 0, not `ff`. The snapshot writes `ff ff ff` when every core slept, so **keys `0x600d` and `0x600e` do not survive a reset** (they read back fine from Linux, but are 0 after every reset so far); `0x600c` does.)
- **Correction to R12–R14:** the zeros in `0x600d`/`0x600e` are the reset clearing them. R12/R13's "max 0" is explained by that; **R14's "no WFI returns" and "no sleep 2 ms after a second IPI" are not data.** R14's `0x600c` = 1 (one park entry) and `0x6010`/`11` = MPIDR 3 stand. R15's result does not depend on them.
  - CPU_OFF mask `077e`; `0x6004` `0x19`; P complexes off in 6 ms; PMP requests 0. All as R13/R14.
- **So the CPUSTART stop request (aura-ctl bit 5) is what held cpu3.** Aura wrote each secondary's bit in CPUSTART + 0 just before its release IPI. cpus 1–2 and the P cores still woke; cpu3 never did. Without it, **for the first time every core is in its final deep sleep**: 9 secondaries in `cpu_sleep(true)` after flushing, the boot core at `0x19`, both P complexes off. The SoC still did not sleep.
- **What is left against Naeem's working M1 order** (try23/try32: clkgen muxes, cluster controls, CPM power gating, cluster PS, commit, PMU RTC alarm, commit twice more, then every core WFI with nothing touched after the commit):
  - Ours writes the commit (the S2R timer word) **before** the AIC mask, the release IPIs, the 2 ms wait and the snapshot (PMGR reads + SPMI writes), plus crumbs `0x13`–`0x18`. That is a lot of MMIO and SPMI after the commit, where his M1 slept only once nothing was touched.
  - We write the commit once; macOS writes it three times.
- **Image 60g** (Aura `9664a8fe1c37a12b`, `boot.bin.psci-test60g` `e75fe2baf56c3e09`, diff `wip-image60g.diff`; `psci_dbg` still `+0x137980`; `install.sh` uses it). New aura-ctl bit **`0x8000` "quiet commit"** (with TIMER and CORESOFF):
  - right after crumb `0x12`: the AIC mask, crumb `0x17`, the release IPIs, 2 ms, the snapshot, then **crumb `0x16`, the last access before the commit**;
  - then WD1 disarmed (bit 12), the timer word written **three times**, `psci_dbg[18]` = 3, the set/way flush and `cpu_sleep(true)`. **No MMIO, no SPMI after the commit**, so no `0x13`–`0x15`, `0x18`, `0x19` crumbs on this path.
  - if `cpu_sleep` ever returns, the old timer and release blocks are skipped (straight to the heartbeat loop).
  - `aura-ctl.c` takes bits 0–15 now; `/usr/local/lib/deepidle/aura-ctl` rebuilt.
- **Reading the next scratch:** `0x16` = the quiet path ran up to the commit. `0x21`/`0x22` = the SoC slept and woke through RVBAR (the alarm). A timer reset at 86 s with `0x16` = the commit alone, nothing after it, is still not enough.
- **Run R16** = R15 + `0x8000` (aura-ctl `0xdb1f`), image 60g. It is a new kind of step (a reordering), so it gets one attended run, owner notified first. It stays self-recovering: the timer still resets the SoC 60 s after the commit.
- Clean before it: flags removed, `/boot` mounted, default `boot.bin` `76f850895fed53d1`, no `next_entry`, btrfs 0, headless on, watcher running, scratch `0x6004`–`0x6016` and `0x601b`–`0x601e` zeroed.

## 2026-11-07 07:19 run R16 (image 60g, quiet commit): every core sleeps with nothing touched after the commit, still the 86 s reset; static: Aura never set the boot cluster's (EACC) target to 0; image 60h, run R17
- **Dead-man pushes:** only the R15 result and the R16 start. No hand reset. `PM: suspend entry` 07:09:37; the Pi saw the Mac down at 07:09:42 and up at 07:11:32; uptime from 07:11:03. **86 s**, the timer's reset.
- **PMU scratch after the reset:** `00300050167e07ff 00000000ff000000 ffff1f100380f801 000000000f105000`:
  - **`0x6004` = `0x16`:** the quiet path ran to its last access before the commit, as designed (nothing after the commit writes a code).
  - Never slept `f880` (only 7, 11 and 12–15, unused or absent), `0x6007` = `ff`, CPU_OFF mask `077e`, wait 6 ms: every core in its final deep sleep, both P complexes off, as R15.
  - ECPM `0x1f` (on, the boot cluster), PCPM0 `0x10` and PCPM1 `0x00` (off); **EACC `0x0f`**, PACC0 `0x10`, PACC1 `0x50` (targets 0).
  - `boot-error-stage` `0x50` again: the SMC side took macOS's AP-sleep messages.
- **So Naeem's order alone is not it on T6020:** everything before the commit, the timer written three times, nothing after it but the flush and the boot core's deep WFI, and the SoC still stays up until the timer resets it.
- **Static, the one cluster write left: EACC.**
  - Naeem's newer evidence (try33–52, `~/Work/ref/m1-power-lab`): his wake restore calls `enableCPUComplex`, writing `0x23b718000/004 = 0xf` (both clusters on). So the entry's "cluster PS `0x23b718000/4 = 0`" is **both CPU complexes' enable, the boot core's own cluster included**, written before the commit while that core still runs.
  - 13.5 `AppleT6020PMGR::configCPUComplexPowerState(complex, on)` = `enableCluster(complex % 3 + 1, on, …)`. So enableCluster's logical clusters 1, 2, 3 are the E, P0 and P1 complexes.
  - `getPhysicalClusterID(c)` looks `c` up in a table that init fills from **byte 3** of each ADT pmgr `soc-clusters` entry (28 bytes each). Raw entries from `DeviceTree.j414sap.bin`: EACC `00 00 00 01`, PACC0 `01 01 01 02`, PACC1 `02 02 01 03`, ANE0 `03 03 05 06`, AVEMSR `06 04 05 09`, DISPLAY `04 00 00 08`. Byte 0 is the word index at `0x28e088000`, **byte 3 the logical number: EACC 1, PACC0 2, PACC1 3, ANE0 6, DISPLAY 8, AVEMSR 9.**
  - `AppleT6020PMGR::quiesceHW` (unless hibernating): `for die: for c = 1..N: enableCluster(c, false, c > 3, die)`, N from a runtime table. **It starts with EACC (c = 1), no poll**, then PACC0 and PACC1 (no poll), then ANE0 and up (polled).
  - **Correction to the 2026-11-06 00:07 entry:** "clusters 1..5" were read by entry position (byte 0), so image 54's `PSCI_S2R_CLUSTERS` (ids 1, 2, 3, 6, 4) writes PACC0, PACC1, ANE0, AVEMSR and DISPLAY and **never EACC**. R16's snapshot agrees: EACC `0x0f`, PACC0/1 targets 0. PACC0/1 were right by luck; AVEMSR and DISPLAY are extra (macOS reaches them only if N ≥ 8) and harmless so far.
  - So on both the M1 and T6020 macOS sets the boot cluster's target to 0 before the commit; the PMGR can then take the E complex down once its last core sleeps. Ours stays at target `0xf`, which may be what keeps the SoC from finishing the entry.
- **Image 60h** (Aura `2ae99f724dfb8115`, `boot.bin.psci-test60h` `4bdc26ae2b5a1c55`, diff `wip-image60h.diff`; `psci_dbg` still `+0x137980`; `install.sh` uses it). New aura-ctl bit **`0x10000` (`PSCI_S2R_EACC`)**: right after the cluster step, EACC's word (`0x28e088000`) is saved and written with target 0, no poll, as quiesceHW's c = 1. Undone with the other clusters on any resume (the RVBAR path included). The page was already in the runtime map. No WFI on the boot core between that write and its final `cpu_sleep` (the quiet path only busy-waits). `aura-ctl.c` takes bits 0–16; `/usr/local/lib/deepidle/aura-ctl` rebuilt.
- **Reading the next scratch:** `0x601c` (EACC, read at the snapshot) should show target 0 (low nibble 0). `0x16` + 86 s = still not enough; `0x21`/`0x22` = slept and woke through RVBAR.
- **Run R17** = R16 + `0x10000` (aura-ctl `0x1db1f`), image 60h. A new kind of write, so one attended run, owner notified first. Still self-recovering: if the boot core died before the commit, WD1 (still armed until just before the timer) resets at about 145 s; otherwise the timer resets 60 s after the commit.
- Clean before it: flags removed, `/boot` mounted, default `boot.bin` `76f850895fed53d1`, no `next_entry`, btrfs 0, headless on, watcher running, scratch `0x6004`–`0x6007`, `0x600c`, `0x6010`–`0x6016`, `0x601b`–`0x601e` zeroed.

## 2026-11-07 07:28 run R17 (image 60h, EACC target 0): the write took, still the 86 s reset; static: macOS sends the SEP a SLEEP message, Linux never does (owner asked before trying it)
- **Dead-man pushes:** only the R16 result and the R17 start. No hand reset. `aura ctl … 0x1db1f` read back, `echo mem` 07:22:59 (Pi kmsg); the Pi saw the Mac down at 07:23:01 and up at 07:24:58; uptime from 07:24:25. **86 s**, the timer's reset.
- **PMU scratch after the reset:** `00300050167e07ff 00000000ff000000 ffff1f100380f801 0000000010105000`:
  - code `0x16`, never slept `f880`, `0x6007` `ff`, CPU_OFF mask `077e`, wait 6 ms, `boot-error-stage` `0x50`: all as R16;
  - **EACC (`0x601c`) = `0x10`** (R16: `0x0f`): its target was 0 at the snapshot, like PACC0 (`0x10`) and PACC1 (`0x50`). The write took.
- **So EACC's target was not what held the entry either.** Read live afterwards (awake, read-only): ECPM/PCPM0/PCPM1 PS words `0x28e080060/68/70` = `0x1f0` each, i.e. **target 0 even awake**: the CPU complexes are under hardware control, with no forced-on target left to clear.
- **What R11–R17 have established:** at the commit every core is in its final deep sleep, both P complexes are off, every soc-cluster target is 0 (EACC included), every device domain is off (S6/S8), the AMCC errors are disabled, the AIC masked, WD1 off, fabric and DCS at macOS's states, the SMC has macOS's AP-sleep messages (`0x50`), and nothing is touched after the commit. The PMGR S2R engine still never finishes.
- **New lead, static: the SEP.** 13.5 `AppleSEPManager::_sleepSEPAsync` (`fffffe00099b2edc`) sends, before system sleep, **`AppleSEPControl::cmsgSLEEP(type, data)`** on the SEP's control endpoint (0): the message's byte 2 = opcode **`0x0c`**, byte 3 = the sleep type (**2**, or 3 when `_getSleepMode` reports platform mode 7), data = `[this+180]` × 15000. A good reply moves the manager's SEP state from 9 to 1 (asleep). Its neighbours are `NAP` (`0x13`) and `NAP_OK` (`0x12`).
  - **Linux never sends it.** Aurora's `apple-sep` (Rust, `drivers/soc/apple/sep.rs`, `pm.rs`) only stops Touch ID captures and refuses requests across a suspend. Its control endpoint has no SLEEP opcode. It also keeps the SEP's extra power domains on through system sleep on purpose (`pm_shim.c` `sep_pm_keep_domains`: "once one of them is switched off, it stops reading its mailbox for good").
  - So at every one of our commits the SEP is fully awake and was never asked to sleep. If the S2R engine waits for the SEP (as it may wait for the clusters), that alone would explain an entry that never completes with everything else in place. The SEP sits in an always-on domain, so genpd's dumps could not show it.
  - **Why this one waits for the owner:** the SEP holds state it shares with macOS (the xART records, Touch ID enrolment, keybags; the driver guards those writes). A SLEEP may make the SEP save state through the AP. With the SoC then reset by the timer, an interrupted save could touch that state. That risk is a different kind from our PMGR writes, which a reset fully undoes.
  - **Proposed test (not built yet):** a test-only `apple-sep` switch, off by default. For a `mem` suspend only, in `suspend_late` (after captures stop, before `slpa`), it sends SLEEP type 2 on EP 0 and logs the reply. Only R-series runs set it. A resume or reset reboots the SEP through iBoot.
- Clean afterwards: flags removed, `/boot` mounted, default `boot.bin` `76f850895fed53d1`, no `next_entry`, btrfs 0, headless on, watcher running, scratch zeroed. Nothing armed.

## 2026-11-07 07:33 SEP SLEEP test built, not armed (run R18 waits for the owner's OK)
- **What macOS sends** (13.5, read from the kext, local analysis only):
  - `AppleSEPControl::cmsgSLEEP(SleepType, u32)` builds the 8-byte message `0x000c0000` with the type in byte 3: EP 0 (control), op `0x0c`, param = type, data 0. That is the same layout as Linux's `encode_control` (type << 16, param << 24, data << 32).
  - The `u32` is not data. It is passed to `_cmsgSend` by pointer as the reply timeout: `[this+180] × 15000` ms.
  - `[this+180]` comes from `_initTimeoutMultiplier`. It is 1 unless the platform is a simulator (then 20), so the timeout is 15 s.
  - The type is 2 (3 only when `_getSleepMode` says mode 1). So the message is EP 0, op 0x0c, param 2, data 0, with a 15 s wait.
- **The J414s SEP node has one power domain** (`ps_sep`, `apple,always-on`), so `sep_pm_keep_domains` does nothing here. The SEP is kept powered by the always-on domain itself, not by the driver.
- **Test kernel change** (~/Work/linux-psci-efi-72, uncommitted like the other TEST switches; diff in `patches/psci-efi/linux/test-sep-sleep-msg.diff`):
  - `proto.rs`: `op_sleep(type)`.
  - `pm_shim.c`: `apple_sep.test_sleep_msg` (int, 0644, default 0).
  - `pm.rs`: at PM_SUSPEND_PREPARE, after entropy and captures are held, it sends SLEEP with that type and logs `TEST SLEEP type N: reply tag .. data ..` or the error.
  - Nothing wakes the enclave again, so this is for reset-ending runs only (R18 keeps `reboot-after`).
- **Harness:**
  - `run.sh` writes `/var/lib/deepidle/sep-sleep` into the parameter (log `sep sleep: N`).
  - `attended.sh` has **R18** = R17 + `SEP=2`, and `sep-sleep` joins the flags removed after a run.
- **Not armed.** The module is not installed into `/usr/lib/modules/7.2.11-psci-efi+` until the owner answers. Even with the switch off by default, it replaces the module every psci-efi run uses.

## 2026-11-07 07:37 SIO IDLE: a second coprocessor that runs into every commit awake; test switch and run R19 built, not armed
- **macOS's trace covered only the SMC and the PMP** (`docs/hv-boot-trace-reference.md`: `trace_smc.py`, `trace_pmp.py`). Messages to the other coprocessors (SEP, SIO, MTP, ANS, GPU) at sleep were never seen, so "every macOS step is reproduced" holds only for the SMC, the PMP and the CPU side.
- **In macOS every RTKit coprocessor goes through one generic sleep path.** `RTBuddy::setPowerState` (`_setPowerStatePerformChangeGated`, `RTBuddyEndpoint::isGoingToSleep`) runs at system sleep for each IOP RTBuddy manages. AppleSmartIO2 (SIO) has no power methods of its own. The exact state RTBuddy sends each IOP is not decoded yet.
- **What Linux sends at our commit (test kernel, R17's settings):**

  | Coprocessor | What it gets before the commit |
  |---|---|
  | SMC | `SetAPPower` 0x201 |
  | PMP | `SetAPPower` / `SetIOPPower` 0x201 |
  | AOP | queues stopped, `SetAPPower` 0x201 |
  | DCP x3 | shut down (`dcp-off`) |
  | ANS | power cut by the SMC at `slpa` |
  | ANE | not bound |
  | **SEP** | nothing (R18) |
  | **SIO** | nothing: `sio_suspend` is `/* TODO: SIO coproc sleep state */` |
  | **MTP** (`rtkit-helper`) | nothing: no PM ops |
  | **GPU** (asahi) | its own firmware power handling; `afr` kept on |

- **Test kernel change:** `apple_sio.test_sleep_idle` (bool, 0644, default off). The system-sleep `.suspend` (which now wraps `pm_runtime_force_suspend`) calls `apple_rtkit_idle` (AP and IOP power 0x201, "sleeping, retain state") and logs `TEST: firmware IDLE for system sleep: N`. It is in `.suspend`, so it runs before every `suspend_late` (macsmc's `slpa`). Runtime PM is unchanged. The diff is in `patches/psci-efi/linux/test-sio-sleep-idle.diff`.
- **MTP is left out for now.** `CONFIG_APPLE_RTKIT_HELPER=y` is built in, so changing it needs a new test kernel image, not just a module.
- **Harness:** `/var/lib/deepidle/sio-idle` (run.sh log `sio idle: Y`). `attended.sh` has **R19** = R17 + `SI=1`, and `sio-idle` joins the flags removed after a run.
- **R19 needs no special OK.** It touches no state shared with macOS, and the SIO is reset with the SoC. It is still a new kind of step, so it gets one attended run with the owner notified first.
- 07:41 R19 armed (attended.sh R19: aura-ctl 0x1db1f, sio-idle; apple-sio.ko installed, old one in /var/lib/deepidle/mods-pre-sioidle/). The owner was told first.

## 2026-11-07 07:48 run R19 (image 60h + SIO IDLE): still the 86 s reset; the SIO's reply could not be seen
- **Dead-man pushes:** only my 07:40 note and the R19 start; no resume push. No hand reset.
- **Timing:** `echo mem` 07:43:03 (Pi kmsg), next kernel from 07:44:28 (uptime): **85 s**, the timer's reset, as R15 to R17.
- **Harness lines (Pi kmsg; run.log stops at "filesystems ro", root is read-only):** `sio idle: Y`, `dcp off: Y`, `pcpm: 768`, `sleep keep: afr`, `aura ctl ... 0x1db1f`, then the AOP and dwc3 TEST lines.
- **The SIO's own line (`TEST: firmware IDLE for system sleep: N`) is not in the kmsg copy.** Both R17's and R19's streams end at the same place (`dwc3-apple f02280000.usb: TEST: core stopped`, at PM_SUSPEND_PREPARE). The device `.suspend` phase comes after the stream has stopped, and the journal is lost (root read-only, then the reset). So whether the SIO acked IDLE is unknown from this run.
- **PMU scratch after the reset:** identical to R17 (code `0x16`, CPU_OFF mask `077e`, never-slept `f880`, `0x6007` `ff`, wait 3 ms, EACC/PACC0/PACC1 `10/10/50`, `boot-error-stage` `0x50`). The SIO step changed nothing visible.
- **Next:** confirm the SIO takes IDLE on a normal-path run that resumes, so its line reaches the journal (**S9**, unattended per the owner's 11-06 rule: S-series normal path, no `slpa`, `reboot-after`). If it acks 0, R19 is a real negative: the SIO is not what the entry waits for. The SEP test (R18) still waits for the owner.
- Clean afterwards: flags removed, scratch zeroed, `/boot` mounted, default `boot.bin` `76f850895fed53d1`, no `next_entry`, btrfs 0, headless on, watcher running.
- 07:49 S9 armed unattended (attended.sh S9: deep_steps 32, no slpa, no Aura steps, sio-idle, reboot-after); the owner was told first.

## 2026-11-07 07:53 run S9 (normal path, SIO IDLE): the SIO acks IDLE, so R19 was a real negative
- **No dead-man push** (a resume with the disk alive sends none). No hand reset.
- **Result, journal of the S9 boot:**
  - `echo mem` 07:51:17;
  - `apple-sio 39bc00000.sio: TEST: firmware IDLE for system sleep: 0`, logged on the way down;
  - the PMP release and re-assert lines as S3;
  - `back, rc=0, elapsed 32.43`, online 0-9, PMGR SLP_S2R 0 (normal path, as expected);
  - `reboot-after` sysrq-rebooted at 07:52:15. No errors around the SIO on the way back.
- **So the SIO firmware accepts RTKit IDLE (0x201) in `.suspend`.** R19 sent it before the commit and the entry still reset at 86 s: the SIO is not what the PMGR S2R entry waits for.
- **Left among the coprocessors that run into the commit with no sleep message:**
  - the SEP: R18, built, waits for the owner;
  - MTP (`rtkit-helper`, built into the kernel, so testing it needs a new test Image);
  - the GPU (asahi, `afr` kept on).
- Clean afterwards: flags removed, `/boot` mounted, default `boot.bin` `76f850895fed53d1`, no `next_entry`, btrfs 0, headless on, watcher running.

## 2026-11-07 08:00 issue #9: maralcbr's macOS 15.6.1 sleep-entry trace on J314s (T6000); replied
- CoreyH's 11-05 comment on #9 (unanswered until now) points to [maralcbr/linux `macsmc-reboot.c`](https://github.com/maralcbr/linux/blob/37be2668e36f5e95bfb7132231b7700e3c0fa568/drivers/power/reset/macsmc-reboot.c#L231-L311). It is a lab-only replay of macOS 15.6.1's sleep entry on a J314s, traced under the m1n1 hypervisor. T6000 addresses; the trace itself and its results are not public. Read at commit `37be266`, copy in the scratchpad only.
- **It confirms the SEP lead (R18) independently:**
  - macOS sends `0x00000000020c0700` on the SEP mailbox (`0x396408000`): EP 0, tag 7, op 0x0c, param 2, data 0, exactly our static decode. It replies `0x10700`.
  - macOS then clears OUTBOX_CTRL ENABLE (`+0x114` bit 0) and writes the SEP PMGR domain (`0x28e580c00` on T6000) off.
  - Our R18 sends only the message.
- **Before `slpa` (T6000):**
  - the PMGR request word `0x28e3d8328` = 4 before `slpw`;
  - SMC `MBSE`=`slpw`, `pmVC`=0x100, `WKTP`=2;
  - then `1 << 61` to `0x28e3d0860` (SOC-DEV-DVFS + 4) and `0x28e3d8328` = 1;
  - the internal-PCIe ports powered down;
  - the PMGR domains macOS has off: PCIE0_REF, APCIE_GP_SYS, the AFNC LW domains, ATC*_PCIE/COMMON, the display FE/CPU0 domains, the UARTs, SEP, NUB_SPMI1, MSG, ATC*_USB_AON.
- **After `slpa`: 74 writes, in order:**
  - the PCIe root complex (`apcie[2]+0` 0x8f, 0x8c);
  - WD0 ctl 0;
  - the error handlers (`+0xa00` of four, many in error-handler[1]/[2]);
  - each cluster's CPM/DVFS blocks (`pmgr[8/15/24]+0x20`, `pmgr[10/17/26]+0x240/0x250/0x8400/0x8080`, `+0x660`);
  - `pmgr[56]` (`+0x8014`, `+0x82bc` 1, 2, 4);
  - `pmgr[2]+0x58000/0x60000/0x64000/0x188`;
  - `pmgr[38]+0x800` (0x557, 0x775);
  - the `pmgr[46]` sequence (0x219, 0x21b, 0x8000021a, 0x21a x3);
  - **last, 1 to `0x2925c4000`, T6000's S2R timer.**
- **What we have never done** on J414s: the error-handler masks, the cluster CPM/DVFS writes, `pmgr[38]`/`pmgr[46]`/`pmgr[56]`, the PCIe RC/port power-down, the pre-`slpw` request word and the DVFS bit. On T6020 `0x28e3d…` is the PMP's mailbox block, so the request word may belong to a different unit here.
- **Next:** map T6000's ADT `pmgr` reg indexes and error-handler nodes to T6020's (`DeviceTree.j414sap.bin`, static). Then build the post-`slpa` writes into Aura before the timer, as a new attended step.
- Replied on #9 (as asked by the owner): our J414s state, what the tables add, two cautions for their s2idle runs (ANS dead after `slpa`; the 86 s timer reset as a signature), and a question on which unit owns `0x28e3d8328`/`0x28e3d0860`.

## 2026-11-07 08:02 maralcbr's post-slpa writes mapped to J414s (static, first pass)
Sources: `pmgr-regs.txt` (J414s ADT `pmgr` reg list) and the J414s ADT `error-handler` node (`compatible = [error-handler,t6020]`). No hardware touched.

| T6000 (trace) | T6020 / J414s | Confidence |
|---|---|---|
| `error-handler[1]` 0x28e000000 (+0x70000, +0x3815c..0x38170) | error-handler reg[1] 0x28e000000: **same address** | address yes, function not checked |
| `error-handler[2]` 0x28e080000 (+0x2d000, +0x78000..0x7d000, +0x48000..0x48600, +0x18000..0x18020, +0x1e8) | error-handler reg[2] 0x28e080000: **same address** (it overlaps PMGR reg 0, the PS block) | address yes |
| `error-handler[7..10]` 0x282000000, 0x304000000, 0x383000000, 0x402000000 (+0xa00) | reg[8..11] 0x280000000, 0x300000000, 0x380000000, 0x400000000 (T6020 has one extra entry at reg[0], 0x394c40000) | index shift likely; offsets within differ (T6000 bases are not 32 MB aligned): **check before use** |
| cluster blocks `pmgr[8/10]` 0x210e20000 / 0x210e40000, `[15/17]` 0x211e2/4, `[24/26]` 0x212e2/4 | pmgr reg 8/10, 17/19, 26/28: **same addresses** (T6020 has nine regs per cluster, T6000 seven) | address yes |
| `pmgr[38]+0x800` 0x28e20c800 | pmgr reg 40 0x28e20c000: **same address** | address yes |
| `pmgr[46]` 0x28e224000 | pmgr reg 46 0x28e224000: **same address and index** | yes |
| request word 0x28e3d8328, SOC-DEV-DVFS+4 0x28e3d0860 | inside pmgr reg 45 0x28e3c0000 (size 0x20000): **same addresses**. Our PMP mailbox registers (0x28e3d12a0/12c0) are in the same block. | address yes |
| `pmgr[36]+0x4000` 0x2925c4000 (timer), WD0 0x2922b000c | pmgr reg 38 0x29e5c0000 (our timer 0x29e5c4000); AON shifts 0x292… → 0x29e…, so WD0 = 0x29e2b000c (already off in our runs) | yes |
| `pmgr[2]` 0x28e580000 (+0x58000, +0x60000, +0x64000, +0x188), `pmgr[56]` 0x58c008014/0x58c0082bc, apcie[2] 0x580080000 | not mapped: T6020's reg 2 is 0x290280000 (SOC-East), and PCIe moved | **open** |

- **Most of the trace's targets are at the same physical addresses on T6020.** These are the cluster CPM/DVFS blocks, `0x28e224000`, `0x28e20c800`, the two error-handler blocks in `0x28e0…`, and the request/DVFS pair in `0x28e3c0000`. What each register does there is still to be checked (read-only on the normal kernel, within ADT-declared ranges, after confirming their clock gates are on).
- **Next:** read the same-address registers live (values only), compare with the trace's written values, then build a new Aura image with the same-address writes in trace order before the timer (new aura-ctl bit), as one attended run.
- **Also pending:** a test Image with `apple_rtkit_helper.test_sleep_idle` (MTP IDLE) is built (`f573144a4452768c`, `depmod -e` clean against all installed modules) but **not installed**. The trace makes it a lower priority.

## 2026-11-07 08:11 Unplanned reboot at about 08:07 (not a test; looks like a hand reboot)
Nothing was armed (no flags, normal kernel 7.2.11-14-1-ARCH). The last command from this session ran at 08:02:15 (a worklog commit) and none ran again until the new boot at 08:09.
- The Pi kmsg shows `sudo` PAM events from user session 1 (tty1/Hyprland, i.e. the desktop or a herdr pane, not this agent) at 08:06:37, 08:06:42 and 08:07:18, then the stream ends at 08:07:52. The ping went down at 08:07:21 and came back up at 08:09:04.
- No clean shutdown: `last` marks the 07:53 session `crash`, and the persistent journal stops at about 08:06:14, before those sudo calls. The PMU reports "1 boot error(s) and 0 panic(s)" (the same message as earlier boots). The scratch keys are all zero except 0x6017=01.
- Health: boot.bin `76f850895fed53d1`, `/boot` mounted, `grub-editenv list` empty, no btrfs errors or device-stat counts, headless active, Pi watcher running.

Per the standing rule (stop after a hand reset), nothing gets armed and no live register reads happen until the owner says what happened. Asked the owner.

## 2026-11-07 08:16 maralcbr's post-slpa list, second pass: most of it is already in Aura; the new piece is the cluster DVFS teardown
Static only (DTs in linux-psci-efi-72, m1n1/Aura `cpufreq.c`, J414s ADT); no hardware touched. This corrects the first-pass table above.

**Already done by Aura's quiesce steps (independent match with our macOS 13.5 J414s RE):**
- Trace `error-handler[1]+0x3815c/64/68/6c/70 = 0x80100000` (T6000) is Aura's CLOCKS step (`QS_CLKGEN` 0x28e000000 + `{0x38160, 0x38168, 0x38164, 0x38158, 0x3816c}`, `(v & 0x70ffffff) | 0x80000000`). It's the same order, with each T6000 offset +4 from T6020's.
- Trace `pmgr[46] 0x28e224000 = 0x219, 0x21b, 0x8000021a, 0x21a` is Aura's PLL-off (`QS_PLLOFF`: bits 5:3 = 3, set bit 1, clear bit 0, wait bit 31).
- Trace `error-handler[2]+0x18000..0x18020` (0x28e098000 + 4k) is Aura's CLUSTERS/EACC soc-cluster words (`QS_CLUSTER` 0x28e088000 + 4·id), shifted −0x10000 on T6020.
- Trace `pmgr[2]+0x188 = 0x400024f` is `ps_sio_cpu` (T6000 `pmgr_east` 0x28e580000 + 0x188, T6020 `pmgr_east` 0x290280000 + 0x1e0). The value decodes as TARGET f, PS_AUTO 4, WAS_CLKGATED (W1C), AUTO_ENABLE clear: a read-back write that clears AUTO_ENABLE, which is what Aura's DOMAINS step does to `QS_SIO_CPU`.
- Trace `wdt[0]+0x0c = 0` is WD0_CTRL. T6000's Linux `wdt` is 0x2922b0000 = T6020's 0x29e2c4000 (ADT `wdt,t6020` reg 0), so the J414s address is **0x29e2c400c** (the first pass said 0x29e2b000c, which is wrong). Image 59 found WD0 already 0 at entry.

**Not at the same address on J414s (do not replay):**
- `apcie[2] 0x580080000`: on T6000 that is the PCIe `rc` block (0x580000000, 0x100000). On T6020, 0x580000000 is PCIe **config space**, and `rc` is 0x591000000 (size 0x4000).
- `error-handler[7..10]+0xa00` (0x282000a00, 0x304000a00, 0x383000a00, 0x402000a00): J414s error-handler regs 8..11 are 0x280000000/0x300000000/0x380000000/0x400000000, each only 0x4000 long, so these targets are outside every reg.
- `0x28e3d0860` and `0x28e3d8328` (pre-slpa): they are in `pmp_report` (0x28e3c0000, 0x20000) and the `pmgr_dcp` window. The DCP bw-scratch offsets in that window differ by chip (T6000 0x988/0x990/0x998, T6020 0x1208/0x1210/0x1218), so the same offset probably isn't the same register. These wait for CoreyH's answer on #9.
- The remaining `error-handler[1]/[2]` zero writes (0x28e0ad000, 0x28e0f8000..fd000, 0x28e0c8000..600, 0x28e0801e8, 0x28e070000), `pmgr_east` +0x58000/+0x60000/+0x64000 (would be 0x2902d8000.. on T6020), `pmgr_misc+0x800` (0x557, 0x775) and `pmgr[56]` 0x58c0080xx: the three blocks above show the layout shifts between chips, so their T6020 offsets are unknown. Not replayed.

**New and translatable: the cluster DVFS teardown** (cluster bases 0x210e00000/0x211e00000/0x212e00000, the same on both chips per m1n1's tables):
- `+0x48400` (ppt-thrtl), `+0x40250` (amx-thrtl), `+0x40240` (T6000 llc-thrtl; **T6020 has it at +0x40270**): macOS writes values with **bit 63 clear**. m1n1/Aura set bit 63 on all three at boot (`t6020_features`), so macOS turns the throttles off before sleep.
- `+0x20020` (CLUSTER_PSTATE): macOS writes `0x100101` then `0x40000500101` = DESIRED1 1, bit 42 (FIXED_FREQ_PLL_RECLOCK), **bit 22 = M1_APSC_DIS** and bit 20 = UNK_M1. The T6020 equivalent is **bit 23 (M2_APSC_DIS)**, with UNK_M2 at bit 22. m1n1/Aura clear APSC_DIS at boot ("cpu-apsc" feature), so macOS disables APSC before sleep. Linux already drops each cluster to its lowest pstate (`suspend_freq`); nothing turns APSC or the throttles off.
- `+0x20660` and `+0x48080` = 0: unknown registers, left out.

**Next:** Aura image 61 with a new step bit 17 `PSCI_S2R_DVFS`, placed before the timer as in the trace: per cluster, clear bit 63 at +0x48400/+0x40270/+0x40250, set bit 23 at +0x20020 and wait for APSC_BUSY (bit 7) to clear; save and undo on the way back. Build only. Installing and running it is a new kind of step: one attended run after the owner answers about this morning's reboot.

## 2026-11-07 08:25 Owner: the 08:07 reboot was not them (no other agents); R20 approved (attended), SEP tests approved; run R20 armed
- **08:07 reset: still unexplained.** The `sudo` PAM events at 08:06:37, 08:06:42 and 08:07:18 came in pairs with `terminal=?`. That matches `omarchy-headless`, which runs `sudo -n true` and then `sudo -n iw …` / `systemctl`, so something in the session re-ran headless three times in the 75 s before the reset. This session ran nothing between 08:02:15 and 08:09:19 (the context compaction), and its background wait loop belonged to the S9 boot. The Wi-Fi guard did nothing (count 0), and the telemetry timer uses no sudo. The kernel logged nothing but audit lines, and 98 audit records were rate-limited away. "PMU logged 1 boot error(s)" appears on every boot, so it tells nothing. If it happens again, look at the jjr.headless shell plugin first.
- **Found while arming:** `harness/mmio/aura-ctl.c` refused any value above bit 16, so R20's `0x3db1f` would have been rejected and the run would have tested nothing. It now accepts bits 0–17. `install.sh suspendall` rebuilds it.
- The installed psci-efi kernel stays `1a1105ae670401b0` (`install.sh` copies the staged kernel only when none is installed).
- **Run R20 armed** = R17 + `0x20000` (aura-ctl `0x3db1f`), image 61 (`boot.bin.psci-test61` `4b272bdd49094b8a`). Before it: flags clean, `/boot` mounted, default boot.bin `76f850895fed53d1`, no next_entry, btrfs 0, headless on, watcher running, scratch zero except 0x6017. The owner is attended.
- Next (SEP approved): R18 = R17 + SEP SLEEP type 2. Install the `apple-sep.ko` test module (check its vermagic against the installed kernel first), then one attended run.

## 2026-11-07 09:24 run R20 (image 61, cluster APSC off): the first run the timer did not reset; it hung until the owner held power (28 min); most secondaries never slept; R18 (SEP) prepared
- **What happened:** `PM: suspend entry` 08:28:05 (Pi kmsg); the Pi saw the Mac down at 08:28:09. No 86 s reset: the Mac stayed down, black screen, the headless keybind did nothing, and the owner held power. Up at 08:56:29. No dead-man push (the disk was fine). **The first hand reset of the R series**; the owner reported it themselves and said to continue.
- **PMU scratch after the reset:** `00300050167e0712 0000000001000000 01001f1fffeefe01 0000000010101000` (R17: `00300050167e07ff 00000000ff000000 ffff1f100380f801 0000000010105000`):
  - code `0x16`: the quiet path still ran to its last access before the commit, and the CPU_OFF mask is `077e` as before;
  - **never slept `feee`** (R17 `f880`): of the nine secondaries only Aura cpus 4 and 8 (the first core of each P cluster) reached their final deep sleep. E cores 1–3, P0 5–6 and P1 9–10 never did;
  - `0x6007` = `0x12`: the first of them is cpu1, CPU_OFF. Its release IPI went to MPIDR `0x0001`, it entered the park loop once and its park-loop WFI never returned (`0x600c` 1, `0x600d` 0, and a second IPI did not wake it, `0x600e` 0);
  - `0x6014` = `ff`: the 500 ms wait for the P complexes timed out. PCPM0 reads `0x1f` (on), ECPM `0x1f`. The soc-cluster targets are all 0 (`0x601c`–`0x601e` = `10 10 10`).
- **Reading:**
  - The DVFS step runs before the release IPIs (after the AMCC step). With APSC disabled, the cores parked in deep WFI do not come back on the IPI, so they never reach their S2R sleep and PCPM0 stays on. macOS disables APSC only after its secondaries have already put themselves to sleep.
  - **The timer's reset never came.** R13 had a core that never slept and still reset at 86 s, so awake cores alone do not stop the reset. Between crumb `0x16` and the timer there is only the WD1 disarm. So the likely cause is the APSC disable itself: the timer's reset path seems to need the clusters' DVFS machinery. Unproven, since `psci_dbg[18]` (the timer write count) is in DRAM and was lost.
  - **aura-ctl bit `0x20000` is not self-recovering.** It must never run unattended, and only with the owner ready to hold power.
- **Possible R20b** (not built, owner present only): disable APSC after the snapshot, i.e. after the secondaries have slept, right before crumb `0x16`. It may still block the timer's reset, so it waits until R18 is read.
- **Cleanup:** flags removed, `~/.local/state/deepidle/resume` gone, scratch `0x6004`–`0x6007`, `0x600c`, `0x6010`–`0x6016`, `0x601b`–`0x601e` zeroed (`0x6017` left), default `boot.bin` `76f850895fed53d1`, no `next_entry`, `/boot` mounted, btrfs stats 0, headless on, Pi watcher running.
- **R18 prepared** (the owner approved SEP tests):
  - The stock `apple-sep.ko` (`2c0350bce545c75d`) was backed up to `/var/lib/deepidle/mods-pre-sepsleep/`.
  - The test module (`test_sleep_msg`, debug stripped, `69d85dd42dcdb888`) is installed in `/lib/modules/7.2.11-psci-efi+`, followed by `depmod`.
  - Checks: the vermagic matches; there is no MODVERSIONS or module signing; and its only import beyond the stock module's is `param_ops_int`, which is in the kernel.
  - The initramfs carries only `blacklist apple_sep`. The rootfs loads the driver later (it was bound in R20's dmesg at 14.9 s), so the parameter is set by `run.sh` before the suspend.
  - `install.sh` is back on image 60h (`4bdc26ae2b5a1c55`), so R18 = R17 + SEP SLEEP type 2 and nothing else.

## 2026-11-07 23:27 run R18 (R17 + SEP SLEEP): the enclave replied, still the 86 s reset; macOS's next SEP step (ps_sep handed to the PMGR) built as R18B, not armed
- **What happened** (recorded late: the session stopped on the plan's usage limit after the 09:29 boot):
  - `sep sleep: 2`; `apple_sep: TEST SLEEP type 2: reply tag 0x11 data 0x0` at 66.79 s, i.e. the enclave answered.
  - `echo mem` and `PM: suspend entry` at 09:27:54 (Pi kmsg). The kmsg stream ends right after `Freezing user space processes`.
  - The Pi saw the Mac down at 09:27:58 and up at 09:29:55; uptime from 09:29:20. **About 86 s: the timer's reset.**
  - No dead-man push, no hand reset.
- **PMU scratch after the reset:** `00300050167e07ff 00000000ff000000 ffff1f100380f801 0000000010105000`, **byte for byte R17's** (code `0x16`, never slept `f880`, CPU_OFF `077e`, wait 6 ms, EACC/PACC0/PACC1 targets 0, `boot-error-stage` `0x50`).
- **So the SEP SLEEP message alone was not what the entry waited for.**
- **The SEP probe on this normal boot failed** (`trusted` key type registered and unregistered 2 ms later, then the retry refused with `-16`, marker property present). That is not R18's doing: the same pattern was in the normal-boot dirs from 11-06 23:38 and 23:45 and the boots at 11-07 06:38, 07:08 and 07:22, before any SEP test. It is an intermittent probe flake, so Touch ID is unavailable on this boot. It matters for R18B: `run.sh` now logs whether `apple_sep` is bound before the suspend.
- **What macOS does next** (maralcbr's 15.6.1 J314s replay, `lab_sep_sleep`, refetched): after the SLEEP ack it clears OUTBOX_CTRL ENABLE (mailbox `+0x114` bit 0) and writes **`0x1000030f`** to the SEP's PMGR word (T6000 `0x28e580c00`).
  - That value is AUTO_ENABLE (bit 28), PS_AUTO 0 (27:24), the W1C bits 9:8 and target f. It does not force the domain off; it lets the PMGR gate the SEP once the enclave is idle.
  - J414s now (read-only, normal kernel): `ps_sep` (`pmgr_east` `0x290280000` + `0xc00` = `0x290280c00`) = **`0x1f0000ff`**, i.e. AUTO_ENABLE with **PS_AUTO f**, so the PMGR is never allowed to gate it. The mailbox control words are `0x396408110` = `0x00024401` and `0x396408114` = `0x00815d01`.
- **Test module change** (`apple-sep.ko` `5be0d264b91d8757`, built, not installed; diff in `patches/psci-efi/linux/test-sep-sleep-msg.diff`): `pm_shim.c` adds `apple_sep.test_sleep_psoff` (bool, default off). At PM_SUSPEND_PREPARE, after the Rust SLEEP, it clears `0x396408114` bit 0, writes `0x1000030f` to `0x290280c00` and logs `TEST PSOFF` with ps_sep at +10..100 ms. These are J414s addresses only; nothing turns it back on, so it is for reset-ending runs only.
- **Harness:** `run.sh` writes `/var/lib/deepidle/sep-psoff` into the parameter (log `sep psoff: Y`) and logs `bound: Y/N`. `attended.sh` **R18B** = R18 + `SPO=1`, and `sep-psoff` joins the flags removed after a run.
- **Not armed:** it is a new kind of write, so it gets one attended run, and since R20 a hang is possible. It waits for the owner to be at the Mac (asked at 23:27).
- Clean: flags removed, scratch zeroed (except `0x6017`), default `boot.bin` `76f850895fed53d1`, no `next_entry`, `/boot` mounted, btrfs 0, headless on, Pi watcher running. The installed test `apple-sep.ko` is still R18's `69d85dd42dcdb888` (the stock one is in `mods-pre-sepsleep/`).

## 2026-11-07 23:31 Static: macOS's sleep-entry PMGR dump vs J414s: three fabric lanes are never allowed to auto-gate; image 62 (aura-ctl 0x40000) and run R21 built, not armed
- **Source:** maralcbr's `lab_ps_off` table, "PMGR power states Linux leaves on but macOS has off at sleep entry (j314s, hv dump), with macOS's value" (32 domains, T6000). I mapped each to J414s by its DT label (`t602x-pmgr.dtsi`; bases pmgr `0x28e080000`, pmgr_south `0x28e680000`, pmgr_east `0x290280000`, pmgr_mini `0x29e280000`) and read the current values read-only on the normal kernel. Table: `data/psmap.txt`.
- **Device domains** (ATC*, DISP*, DISPEXT*, UART, MSG): on now, but Linux's genpd turns them off by the commit (the R11–R17 genpd dumps, S6/S8). They are not the gap.
- **The always-on, auto-PM ones:**

  | Domain | J414s word | macOS at sleep | J414s now |
  |---|---|---|---|
  | AFNC1_LW2 | `0x28e080210` | `0x1000030f` | `0x1f0000ff` |
  | AFNC2_LW1 | `0x290280178` | `0x1000030f` | `0x1f0000ff` |
  | APCIE_GP_SYS | `0x290280418` | `0x1000030f` | `0x1f0000ff` |
  | SEP | `0x290280c00` | `0x1000030f` | `0x1f0000ff` (R18B) |
  | AFNC3_LW0 | `0x290280190` | `0x1000030f` | `0x1000030f` (already) |
  | NUB_SPMI1 | `0x29e280068` | `0x1400024f` | `0x1400024f` (already) |
  | PMP | `0x28e0802c8` | `0x0f0f0300` (off) | `0x1f0f03ff` (ours runs the PMP sleep) |
  | PMS_SRAM | `0x28e0802d0` | `0x0f000300` (off) | `0x1f0003ff` |

- **Reading:**
  - Bits 27:24 are PS_AUTO, the state the PMGR may drop an auto-PM domain to (`pmgr-pwrstate.c` `APPLE_PMGR_PS_AUTO`). Linux never writes them; it only toggles AUTO_ENABLE. So these lanes keep the boot value f and are never gated.
  - macOS has PS_AUTO 0 on all of them at sleep entry, and maralcbr's replay even forces three of the fabric lanes to target 0 (`lab_force_fabric_off`: "the PCIe/fabric domains macOS has gated").
  - AFNC3_LW0 already at macOS's value shows the value is legitimate on T6020 too.
  - **If the S2R engine waits for the fabric to gate, this is the kind of thing that would hold every commit.** It is also a plain idle-power gap while awake (worth a GH-10 note).
- **Image 62** (Aura `8efa42c682324b38`, `boot.bin.psci-test62` `049be76f9245b347`, diff `patches/psci-efi/aura/wip-image62.diff`; `psci_dbg` now `+0x1379a8`; `install.sh` has it commented, still on 60h):
  - New aura-ctl bit **`0x40000` `PSCI_S2R_FABRIC`**: after the domains step, the three fabric words are saved and written with macOS's `0x1000030f` (auto-PM with floor 0, target f). It is not a forced off: the PMGR gates a lane only while it is idle.
  - Restored (without the W1C bits) on any resume.
  - At the crumb snapshot, when every core slept, `0x600d` = their state (bits 0–2 gated, bits 4–6 below f).
  - All three addresses sit on pages already in the PSCI map, so the 64-entry table gains nothing.
  - `aura-ctl.c` accepts bits 0–18.
- **Run R21** = R17 + `0x40000` (aura-ctl `0x5db1f`, image 62). A new kind of write, so one attended run, owner present (R20's hang shows a post-commit hang is possible).
- **Order proposed to the owner:** R18B (SEP hand-off, Linux module) and R21 (fabric, Aura). Either first; both are one variable each on top of R17.

## 2026-11-08 07:54 R18B first try stopped before suspend: the SEP probe failed again, and the cause of that flake is found and fixed (two loader units race)
- 07:50 R18B armed (owner present; the owner's reply also allows unattended repeats of configurations that already self-recovered). Module `5be0d264b91d8757` installed stripped (`fab84a8853571004`) in the psci-efi tree, R18's `69d85dd4` replaced.
- 07:51 test kernel up, but `apple_sep` failed to bind (`-16`), so neither the SLEEP nor the psoff step could run: it would only have repeated R17. I killed `psci-efi-run.sh` during its first 45 s wait, before it touched anything (root still rw, no suspend).
- **The flake's cause:**
  - The kernel log shows two module inits. The first (15.107 s) attaches and finishes probe. It is torn down at 15.126 s (trusted key source unregistered), and the second init's probe refuses: "already booted or registered on this boot by an earlier load (marker property present)", `-EBUSY`.
  - Two units load the driver: `apple-sep.service` (package aurora-touchid, `modprobe apple-sep`, 15.090–15.124 s) and the local `aurora-sep.service` → `/usr/local/sbin/aurora-sep-load` (2026-09-26, started 15.101 s). That script does `modprobe -r apple_sep` whenever `/dev/sep-bio` doesn't exist yet. That unloads the packaged load mid-attach, and the reload hits the one-shot marker.
  - The last 12 boots: every `-EBUSY` boot (0, -1, -6, -11) has 2 inits and `aurora-sep.service` failed; every good boot has 1 init and it finished. It is a race, not the SEP.
- **Fix** (local system file, backup `/var/lib/deepidle/aurora-sep-load.orig`): `aurora-sep-load` now loads the driver only when `/sys/module/apple_sep` doesn't exist, and otherwise just waits for `/dev/sep-bio`. The packaged load already gives "writes ENABLED" and the APFS-resolved .gl extent (this boot's first init), so its default parameters are enough.
- Next: re-arm R18B. That boot also checks the fix: 1 init, `aurora-sep.service` finished.

## 2026-11-09 GH-5 start: status brought up to date; a USB test install planned so crash runs need no one at the Mac
- **Status files:** `docs/s2r-status.json` had images 53 to 57 missing and no outcome on 61 and 62 (image 37 was already `fail`). Added them, brought Phase 5's summary, done and next up to R20, R18, S9 and the SEP-loader fix, and added two findings. `overall` stays 45.
- **Disk:** the internal NVMe has no free space (p6, the main btrfs root, takes it), so the test install goes on the owner's 64 GB USB drive (it held the Sonoma installer; the owner OK'd wiping it). It was unplugged when I went to wipe it, and `sudo -n` needs a password, so nothing was written.
- **Design (not built):** a one-shot GRUB `next_entry` on main boots a kernel and initramfs from the USB drive; the test root runs from RAM with the USB device opened read-only, and the NVMe is never mounted. Any reset (watchdog, dead-man, Aura's WD1) falls back to the default entry on main, where `deepidle-resume` reopens the session. The Pi keeps streaming kmsg. Not covered: a hang before any watchdog (iBoot, early m1n1) still needs the power key.

## 2026-11-09 evening GH-5: USB test root built (no tests run)
- **Drive:** the 64 GB USB drive (serial 48149776, was the Sonoma installer) is wiped (the owner OK'd it) and has `DEEPTEST_BOOT` (1 GB ext4, `sda1`) and `DEEPTEST_ROOT` (57.6 GB ext4, `sda2`). Main's NVMe and boot chain were not touched.
- **Root:** `pacstrap` put an aarch64 Arch base on `DEEPTEST_ROOT` with base-devel, git, python, openssh, btrfs-progs, dtc, rust, clang/llvm/lld, bc, cpio, libelf, pahole, iwd and dhcpcd, plus the Wi-Fi and Apple firmware; hostname `deeptest`, fstab read-only. It uses 2.6 GB. On main I installed `arch-install-scripts` and `gptfdisk`.
- **Drafted, not installed:** `harness/usbtest/44_deepidle_usb`, a one-shot GRUB entry (`next_entry`, never the default) that boots the test kernel with `root=LABEL=DEEPTEST_ROOT ro usbtest.overlay=1 panic=10`. Any reset falls back to main's default entry.
- **Still to do:** the test kernel's module tree and an initramfs with the read-only root and tmpfs overlay hook (neither is on main now; `install.sh` makes them when an image is armed), Wi-Fi and the Pi's ssh key in the test root, the runner that arms one image per boot, and the dead-man switch for a USB root.
- **Status blurb:** `S2R_STATUS_TOKEN` is not set in this session's environment, so I could not post the blurb.

## 2026-11-09 night GH-5: this main is a new install on Limine, so the old GRUB harness is gone; one-shot boot found
- **Finding:** this main is the new Omarchy install the owner mentioned. It boots **Limine** (UKI `/EFI/Linux/omarchy_linux-aurora.efi`, `default_entry: 2`, config in the ESP's `limine.conf` generated by `limine-entry-tool`), not GRUB. `/boot/grub`, `/etc/grub.d`, `~/Work/psci-test` (the Aura `boot.bin` images) and `~/Work/staging-psci-efi` (the test kernel) do not exist here. `harness/psci-efi/install.sh`, `43_deepidle` and `harness/usbtest/44_deepidle_usb` all assume GRUB and the old paths, so none of them run as is.
- **One-shot on Limine:** Limine 12.9.6 implements the Boot Loader Interface `LoaderEntryOneShot` (CONFIG.md). From Linux, `bootctl set-oneshot <entry>` created the variable in efivarfs (tested with a name that matches no entry, then removed; no reboot done). Not yet known: whether U-Boot keeps the variable across a reset (to `ubootefi.var`). If it does not, the boot falls back to main's default, which is the safe direction. That check is the first thing the attended boot proves.
- **What the attended run needs, in order:** (1) a Limine entry for the USB kernel (partition UUID path to `DEEPTEST_BOOT`, root `LABEL=DEEPTEST_ROOT`), added so `limine-entry-tool` does not erase it; (2) a kernel and initramfs on `DEEPTEST_BOOT` (the stock `linux-aurora` 7.2.11-15 modules are on main; the PSCI test kernel, Aura images, U-Boot and m1n1 must be rebuilt from `patches/psci-efi/` and the linux-aurora source in `/usr/src/linux-aurora`); (3) the initramfs overlay hook; (4) a port of `run.sh`, `early.sh` and `deadman.sh` off GRUB.
- **First attended boot, planned:** stock `linux-aurora` kernel on the USB root, stock `boot.bin`, no Aura steps. It only proves one-shot, RAM overlay and automatic fall-back to main.
- Status blurb posted (HTTP 200). Cleared the test `LoaderEntryOneShot` variable.

## 2026-11-09 22:30 GH-5: DeepTest boot path built (RAM root from the USB drive, Limine one-shot); three things need the owner
- **The drive drops off USB by itself.** It disconnected at 21:01:12 while idle (`usb 3-1: USB disconnect`, port `f02280000.usb`, no command of mine in the 11 s before), the second time today. Software could not bring it back: the data-role and power-role writes are refused (not a PD device), an xHCI unbind/bind found no device, and the two steps left are unsafe on this kernel (`cd321x_remove`'s own comment says a reprobe can reset the SoC; `dwc3-apple` unbind has the known oops). It needs a physical replug.
- **Design changed because of that:** the root is no longer an overlay on the drive. `initcpio/hooks/usbtest` copies a squashfs image (`/deeptest/root.sfs`, sha256 checked) from `LABEL=DEEPTEST_ROOT` into RAM, unmounts the drive, and boots the image under a tmpfs overlay. The drive is needed for about a minute per boot and may drop or be powered down afterwards. Any failure in the hook reboots; with the one-shot consumed, that lands on main. `panic=10`, a 60 s systemd watchdog and a hard deadline (900 s, sysrq b) cover the rest.
- **Built (all in `harness/usbtest/`):**
  - `build-root.sh`: lean Arch root (base, iwd, openssh, curl, python, dtc, …; 156 packages, this Mac's firmware, the 7.2.11-15 modules, main's Wi-Fi profile and ssh keys) in `~/Work/deepidle-usbtest/root`, packed as `root.sfs` (314 MB, `008623c56da1ccc9`).
  - `build-uki.sh`: UKI of the stock `linux-aurora` 7.2.11-15 kernel with the usbtest initramfs (`deeptest.efi`, 48 MB, `d5e3f22299d823fc`).
  - `install-limine.sh`: the `/DeepTest` entry in the ESP's `limine.conf` after main's entries (`default_entry: 2` untouched). No config hash is enrolled in any Limine binary on the ESP (the signature field is all zeros), so the edit trips no check.
  - `arm.sh`: checks the drive, image, UKI, entry and default, then `bootctl set-oneshot DeepTest` and reboots. Limine's entry ids are the config path with dots (`LoaderEntries` = `Omarchy.linux-aurora`); `LoaderFeatures` `0x200f` has the one-shot bit.
  - In the image: `usbtest-run.sh` runs one job per boot (none = a hello report), pushes to ntfy, saves results to `DEEPTEST_BOOT`, reboots.
  - On main: `usbtest-return.service` (installed) records the return, clears a one-shot Limine never took, pulls the test boot's ntfy reports; the Omarchy post-boot hook `deepidle-resume` (installed, not armed) reopens the session.
  - `write-usb.sh`, `luks-autounlock.sh`.
- **Needs the owner:**
  1. Replug the drive.
  2. **Main's LUKS root has one keyslot, the passphrase** (`crypttab`: `root … none luks`), so every return to main stops at the unlock prompt. The old install had a keyfile slot for this (worklog 2026-10-15). `luks-autounlock.sh add` does the same for sd-encrypt (`/etc/cryptsetup-keys.d/root.key` in the UKI); it needs the passphrase once and is the owner's security call.
  3. SDDM has no autologin, so the session only resumes after a login.
- **Also:** today's system update (Limine 12.9.6 in `BOOTAA64.EFI`, kernel 7.2.11-15) has not been booted; the running boot is Limine 12.9.3 and 7.2.11-14. The first reboot tests that as well.
- **Not started:** the PSCI test kernel, the Aura images and U-Boot (gone with the old install; to rebuild from `patches/psci-efi/`), and porting `run.sh`/`deadman.sh` into DeepTest jobs.

## 2026-11-09 23:10 GH-5: drive back, image on it; ready for the first attended DeepTest boot; test kernel branch rebuilt to 3 patches short
- **Drive:** the owner replugged it (23:00). Both filesystems clean; the stale v1 kernel and initramfs removed from `DEEPTEST_BOOT` (now the results partition); `write-usb.sh` put `root.sfs` on `DEEPTEST_ROOT` and read it back (`008623c56da1ccc9`, 24 s).
- **Dry run:** `arm.sh --no-reboot --allow-prompt` passed every check and set `LoaderEntryOneShot` = `DeepTest`; I removed the variable and the armed flag again. Nothing rebooted.
- **First attended boot (waits for the owner):** `sudo bash harness/usbtest/arm.sh --allow-prompt`. Expected: Limine takes the one-shot, the RAM root comes up on the stock 7.2.11-15 kernel, pushes "DeepTest RAM root booted" to ntfy, reboots after 15 s, and main asks for the passphrase. It proves the one-shot survives U-Boot, the RAM root, Wi-Fi from the test root and the fall-back to main.
- **Test kernel branch** (`~/Work/src/linux-aurora`, `psci-efi-test-72` on today's `integration/aurora` `49a8c150d6be`, 7.2.11): the GH-1 series 44 of 44, `aic-syscore-save-restore` and `deepidle3-smc-s2idle-handshake` (the `deep_steps` patches build on its `s2idle_steps`), Sven Peter's RFC 1 to 5 from lore (6 is the t8103 DTS), then 33 of the 36 files in `patches/psci-efi/linux`.
  - Not applying: the two `rtc-macsmc` alarm patches (upstream now has its own `rtc: macsmc: Add the PMU alarm`, `0d8a55c70a26`, with nvmem cells; to check whether it covers T602x's three registers) and `TEST: drm/apple/dcp: test_sleep_off` (context moved in `dcp.c`).
  - Not built yet.

## 2026-11-09 23:40 GH-5: auto-unlock in place; a limine.conf bug of mine caught before any reboot; first DeepTest boot armed
- **Auto-unlock:** the owner ran `luks-autounlock.sh add`. Status: 2 keyslots, the key file opens the disk, the key is in the rebuilt main UKI. SDDM autologin was already on (`autologin.conf`, `sddm-autologin` in this boot's log); my earlier "no autologin" was wrong.
- **Bug, fixed before any reboot:** `limine-entry-tool` rewrote `limine.conf` during the UKI rebuild and kept the DeepTest entry without its begin marker, so the re-add made a duplicate. My first fix (a sed range) then left the entry's indented lines orphaned under main's `//linux-aurora` entry, where a second `path:` could have made main boot the test UKI. `limine-strip.py` now removes markers, entries and orphans; checked: one `/DeepTest` block after main's, `default_entry: 2`, both UKI hashes in the file match the files on the ESP.
- **Drive:** attach and disconnect times this boot: 18 s, 22 s, 52 min (while mounted), 74 s. Cause unknown; a udev rule now keeps it out of runtime suspend on main (`61-deepidle-usbtest.rules`). The test boot only needs it for the first minute, and a missing drive reboots to main.
- **Armed:** the hello job, with the session-resume flag set. Expected: report from the RAM root in 2 to 3 min, back on main by about 5 min with no passphrase and no login.

## 2026-11-09 23:59 GH-5: the USB drive dropped; the image now lives in main's /boot; headless on boot; ready for the first attended DeepTest boot
- **Owner's decision:** no USB drive (it dropped off the bus four times this boot: after 18 s, 22 s, 52 min and 74 s). The image goes on the internal disk instead.
- **Where:** `/boot/deeptest/root.sfs` on `nvme0n1p5` (`LABEL=OMARCHY_BOOT`, ext4, 2 GB, 1.5 GB still free). No partition change. Main boots from the UKI on the ESP, not from this partition.
- **How the test boot uses it:** the initramfs hook mounts the partition `ro,noload`, copies the image to RAM, checks its sha256, unmounts, and boots the image under a tmpfs overlay. No NVMe partition is mounted while a test runs, and the LUKS root is never opened. Results leave through ntfy and the kernel log only.
- **Changed:** hook default source, `build-uki.sh` (cmdline, `nvme-apple` and `apple-sart` in the initramfs; UKI `c307f24c5845a968`), `write-image.sh` replaces `write-usb.sh`, `disarm.sh` added, the Limine entry reinstalled (one `/DeepTest` block, hashes match).
- **Headless on boot:** post-boot hook `deepidle-headless` runs `omarchy-headless-mode on` after every boot while `~/.local/state/deepidle/headless-on-boot` exists (set).
- **Dry run:** `arm.sh --no-reboot` passed with no `--allow-prompt` (auto-unlock key in the UKI), then `disarm.sh`. Nothing rebooted.

## 2026-11-09 22:26 GH-5: first DeepTest boot passed, and the Mac came back to main by itself (owner attended)
(The clock times in the three entries above are an hour ahead; this one is from the logs.)
- **Run `first-boot`** (hello job, stock 7.2.11-15 kernel, stock `boot.bin`, UKI `c307f24c5845a968`, image `008623c56da1ccc9`): armed 22:24:39, report from the RAM root 22:25:14, back on main 22:25:52. **73 s away, no hands.**
- **What it proves:**
  - Limine took the one-shot (`oneshot_taken=yes`), so `LoaderEntryOneShot` survives a reboot under U-Boot, and it was consumed: the next boot was main's default entry.
  - The RAM root works: `root: overlay … lowerdir=/run/usbtest/lower`, `nvme opened: 0 mounts`, all 10 CPUs, 31677 MB. The image came from `/boot` (`LABEL=OMARCHY_BOOT`) and the partition was released.
  - Wi-Fi works from the test root (the report arrived over ntfy).
  - Main unlocks its LUKS root from the key in the UKI, SDDM logs in, the headless hook turned the screen off (22:25:57) and the resume hook reopened this session (22:25:57). `usbtest-return.service` recorded the result in `/var/lib/deepidle/usbtest/results/20261109-222552/`.
  - Today's update (Limine 12.9.6, kernel 7.2.11-15) boots.
- **Small things:** the report's `wdt:` and `wifi:` fields were empty because of how I read them (`watchdog0` has no `identity` file; the address query ran with the wrong scope), not because they were missing. `mem_sleep` is `[s2idle]` only, as expected without the PSCI kernel and Aura.
- **Not yet proven:** the failure paths (image missing, hang in the test root, hang in the initramfs).

## 2026-11-09 22:40 GH-5: watchdog from the initramfs, failure-path switches; chain P1, P2, P3 armed one by one
- **Hook:** `run_hook` now starts the SoC watchdog (`echo 1 > /dev/watchdog0`, no magic close) before anything else, so a hang in the initramfs resets the Mac; systemd's 60 s `RuntimeWatchdogSec` takes it over. `arm.sh --failtest missing|hang` writes `/boot/deeptest/failtest`, which the hook reads after mounting the source: `missing` runs the hook's own failure path (reboot after 10 s), `hang` sleeps forever for the watchdog. `usbtest-return.sh` and `disarm.sh` remove the file.
- **Report fields fixed** (`wdt`, `wifi`). Image `4395491f1b6adc7a`, UKI `3eebbbcf44e0e3ec`.
- **Chain (each is armed by the resumed session after the one before is recorded):**
  - **P1** `hello2`: the hello job on the new image and UKI. Checks that the early watchdog does not reset a good boot.
  - **P2** `fail-missing`: expect no report, main back in about 1.5 min, `reports_from_test_boot=0`.
  - **P3** `fail-hang`: expect no report and a watchdog reset. If the dog does not fire, the Mac hangs in the initramfs and the owner has to hold the power key, so P3 is announced to the owner first.
- After the chain: build the PSCI test kernel (`~/Work/src/linux-aurora`, branch `psci-efi-test-72`, 3 patches still to port), then Aura and U-Boot.

## 2026-11-09 22:30 GH-5 run P1 (hello on the new image, early watchdog): passed, 74 s
- Armed 22:28:02, report 22:28:37, back on main 22:29:16; `oneshot_taken=yes`. `wdt: watchdog0 …, systemd 1min`: the dog started in the initramfs did not reset a good boot, and systemd holds it at 60 s. No disk mounted. The `wifi:` field is still empty though the push arrived over Wi-Fi (my query; cosmetic).
- Next: P2 (`--failtest missing`), armed now.

## 2026-11-09 22:31 GH-5 run P2 (`--failtest missing`): the hook's failure path brought the Mac back to main in 49 s
- Armed 22:29:59, back on main 22:30:48; `oneshot_taken=yes`, `reports_from_test_boot=0` as expected. The hook said the image was missing, waited 10 s, `reboot -f`, and Limine booted the default entry. `usbtest-return.sh` removed the `failtest` file.
- (The session then stopped on the plan's usage limit; resumed by the owner.)
- Next: P3 (`--failtest hang`), the watchdog path. The apple watchdog's default timeout is not readable here (no sysfs attributes), so the time to the reset is the measurement.

## 2026-11-09 22:43 GH-5 run P3 (`--failtest hang`): the watchdog started in the initramfs reset the hung test boot; back on main in 76 s
- Armed 22:40:45, back on main 22:42:01; `oneshot_taken=yes`, no report from the test boot, no hands. With about 20 s of reboot before the hang and about 20 s of boot after the reset, the dog fired roughly 30 to 40 s into the hang.
- **The DeepTest recovery paths are all proven, 1 of 1 each:** a good boot (first-boot, P1: 73 s, 74 s), image missing (P2: 49 s), a hang before userspace (P3: 76 s). Each ended on main with the disk unlocked, the session logged in, headless on and the agent session reopened.
- **Still not covered:** a hang before the kernel starts (iBoot, m1n1, U-Boot, Limine). A test `boot.bin` (Aura) is the next thing that can hang there, and unlike the UKI it is not one-shot: it stays on the ESP until Linux puts the stock one back.
- Next: build the PSCI test kernel, then Aura and U-Boot.

## 2026-11-09 23:05 GH-5: test kernel building; the Aura test branch cannot be rebuilt from the repo alone
- **Kernel:** installed rust, rust-src, bindgen, clang 23.1.4, lld and bc on main; `psci-efi-test-72` builds with the running kernel's config and `LOCALVERSION=-psci-efi` (in progress, `~/Work/src/kbuild.log`). The stock kernel was built with clang 18.1.8, so compiler differences may show. Main's stock kernel has no `wakealarm` (`/sys/class/rtc/rtc0/wakealarm` missing), so the T602x alarm still has to be ported onto upstream's `rtc: macsmc: Add the PMU alarm`.
- **Aura:** cloned `aurora-silicon/aura`. The four exported commits apply on `bf6a6417` (2026-10-21; found by matching the blob ids in the first patch). The `wip-image*.diff` files do **not** apply on top: they expect `src/smp.c` blob `4c866a6c` and `src/start.S` `e66a83bd`, and the tree has `45567938` and `c5ab6f5d`. The old `psci-efi` branch had commits that were never exported to `patches/psci-efi/aura`: at least the RVBAR core-index fix (a local cherry-pick of `90b2155e`, which is not in upstream under that id), `psci_enter` and `reset_dbg`. Only 3 hunks in `smp.c` and 1 in `start.S` are rejected, so it can be reconstructed, but an exact copy of images 60h/62 needs the old tree or the old `boot.bin.psci-test*` files.
- **Asked the owner:** is there a copy of the old install's `~/Work/psci-test/` (the `boot.bin.psci-test*` images), `~/Work/aura-psci` or `~/Work/u-boot-asahi` anywhere (the Pi's `~/deepidle`, a backup, the old disk)?
- **Unattended risk to settle before any Aura run:** a test `boot.bin` replaces the stage 2 on the ESP and stays there until Linux restores the stock one. A hang in it comes before any watchdog and repeats on every reset.

## 2026-11-09 23:15 GH-5: test kernel built (7.2.11-psci-efi+); run K1 armed (does the build boot?)
- `make LLVM=1` finished with exit 0 (clang 23.1.4, rust 1.99.1). Modules installed stripped in `/usr/lib/modules/7.2.11-psci-efi+` (142 MB, `.keep`), and the `keep-pinned` drop-in for `linux-modules-cleanup.service` is back so a reboot does not move the tree away.
- Root image now carries both module trees (350 MB, `7b7213ee6a3addb2`); UKI of the test kernel `66d347d65fe10557`.
- **Run K1** (`jobs/k1-testkernel`): the test kernel on the stock `boot.bin` (no PSCI node, spin-table, as the old `step1a`). It reports CPUs, the PSCI/EFI lines, which `TEST:` parameters exist, the RTC and the error lines. A kernel that hangs before the initramfs has no watchdog behind it, so the owner was told when to hold the power key.

## 2026-11-09 22:55 GH-5 run K1: the rebuilt PSCI test kernel boots (74 s away, no hands)
(Clock note: the 23:05 and 23:15 entries above were written at about 22:45 and 22:52.)
- Armed 22:53:13, job report 22:53:48, back on main 22:54:27; `oneshot_taken=yes`.
- `Linux version 7.2.11-psci-efi+ … clang version 23.1.4`, `online 0-9`, 31678 MB, `mem_sleep [s2idle]` (stock `boot.bin`, no PSCI node, as expected).
- The `TEST:` switches are there: `macsmc_reboot` `deep_steps`, `s2idle_steps`, `wake_extra`; `macsmc` `ap_idle_in_suspend`, `pmp_sleep`; `pmp_report` `test_pcpm`, `test_release_aon`, `test_release_ids`; `pm_genpd` `test_dump`; `dwc3_apple` `test_deep_teardown`; `nvme_apple` `iorvbar_phys`. Not listed, to check: the AOP, SART and `pmgr-pwrstate` (`test_sleep_keep`) switches, which may sit under other module names or be built in.
- `wakealarm no`: the PMU alarm is still to port. 4 error lines: the watchdog's "did not stop" (my initramfs start, expected) and the ANE firmware missing from the lean image (harmless).
- So the kernel side is back except the alarm and `dcp test_sleep_off`. Aura and U-Boot are what is missing for `deep`.

## 2026-11-10 07:00 GH-5: Aura, U-Boot and the alarm rebuilt; a one-shot loader so a test `boot.bin` cannot stick
Owner (2026-11-09 night): no copies of the old trees exist outside this repo; push straight to `main`, no PRs; when blocked on an answer, switch to another step.

- **Aura test branch rebuilt.** The `wip-image*.diff` files are diffs against local commits that were never exported. Rebuilt that base from the diffs' context lines and the 2026-10-25 worklog: `RVBAR_ADDR` `GENMASK(43, 12)` (the core-index fix), `smp_psci_restart()` gone, CPU_OFF parks the core in `psci_park_c()` on its Aura stack, CPU_ON of an OFF core dispatches like a parked one, `psci_enter` (MMU and caches off at EL2, HCR_EL2 = RW|E2H, branch to the entry), and the `reset_dbg` breadcrumbs. With it `wip-image62.diff` applies with no rejects. **Not byte-identical**: about 12 lines of `psci_enter` and the tail of `psci_park_c` were never in any diff, so they are written from the description. Saved as real patches in `patches/psci-efi/aura/rebuilt/` so this cannot be lost again.
- **Toolchain.** The system gcc 16 and clang 23 builds do not link or do not fit; the repo's own `Dockerfile` (Debian bookworm, gcc 12.2, rustup 1.99.1) builds both trees. Test Aura: `make RELEASE=1`, `aura.bin` 3538944 B, tag `v0.1.0-11-g41a93eba`.
- **What the stock chain is** (new install): stage 2 is package `m1n1-aurora 1.6.1.aurora22`, built from `omacom/m1n1` `bc79acc4` with `RELEASE=1 CHAINLOADING=1 ESP_STAGE2=1` (the logo option does not fit the 0x120000 file limit); U-Boot is `aurora-silicon/u-boot` `d30213eadcaa`. `boot.bin` = 4259840 B image + 115 DTBs (J414s is #31) + gzipped U-Boot.
- **U-Boot:** the two PSCI patches on `d30213eadcaa` (one include hunk refitted), `apple_m1_defconfig`, `u-boot-nodtb.bin` 706600 B. Patches in `patches/psci-efi/u-boot/rebuilt/`.
- **PMU wake alarm ported** onto the alarm code now upstream in `rtc-macsmc` (`patches/psci-efi/linux/0037-*`). Upstream's model is T6030's (event bit in the control byte); T602x has the event in its own byte (0x14c0 bit 0, write 1 to clear), so the driver takes an optional `rtc_alarm_event` cell and then only ever changes the enable bit of the control byte (0x1401 bit 6). DT: cells for 0x1401, 0x140c, 0x14c0, 0x14c2 bit 0; `nub_spmi0` is an interrupt controller on AIC 724; the RTC uses SPMI interrupt 2 and is a wakeup source. Kernel, modules, UKI (`56a5b5514024dd0d`) and root image (`b721ca9f063fbad2`) rebuilt. Not yet run.
- **The `boot.bin` problem and its answer.** A test `boot.bin` runs before any watchdog and on every boot, so one bad image means recoveryOS. The Pi's proxy link would do it per boot, but this install has no route to the Pi. Instead `m1n1/boot.bin` becomes a **one-shot loader** (`harness/usbtest/bootbin.sh`, `patches/psci-efi/selector/`): the stock stage 2 source plus one patch. On T6020 it reads PMU legacy scratch key 0x10 (register 0x6010, PMU at SPMI address 0xb; one of the free keys named in the image 60 notes, and a SoC reset does not touch it). If it reads 0xa5 the loader writes 0, reads it back, starts the watchdog at 120 s and chainloads `m1n1/boot-test.bin` from the ESP; anything else and it boots its own payloads as the stock image does. The flag is cleared before the test image is read, so the boot after a test boot is always the normal one, and a test chain that hangs anywhere (Aura, U-Boot, Limine, early kernel) is reset by the watchdog. The test Aura keeps a watchdog it finds running (fresh 120 s) instead of disabling it; the kernel's driver takes a running watchdog over.
  - Checked from main: the byte reads and writes through `/sys/bus/nvmem/devices/spmi_nvmem2/nvmem` on the stock kernel (wrote 0xa5, read it back, cleared).
  - `arm.sh --chain` sets the flag together with the Limine one-shot; `disarm.sh` and the return hook clear it; the return summary records the flag it found and the stage 2 version.
  - Limit: the loader itself is a new stage 2 (same source as stock, different compiler: the unpatched source built here is not byte-identical to the package either). Its first boot is the one **attended** step left; after that only `boot-test.bin` changes. `update-m1n1` (package updates) puts the stock image back; `bootbin.sh install` again.
- Built: `~/Work/psci-test/boot-selector.bin` (`44eef99b068d02af`, loader `22cbe6fe` + stock payloads) and `boot-test.bin` (`5508187c0493747d`: Aura image 62 rebuilt, `t6020-j414s-psci-pmp.dtb` with the alarm cells as DTB #31, patched U-Boot).
- **Run K2 armed** (`jobs/k2-alarm`, stock `boot.bin`, unattended): does the ported alarm fire awake (`+12 s`, interrupt counts before and after)?
- Next: S1 (attended): install the loader, plain reboot, expect a normal boot. Then C1 (`jobs/c1-chain`, unattended): first boot of the rebuilt chain.

## 2026-11-10 06:55 GH-5 run K2: no result for the alarm (my test was wrong); back on main in 75 s
- Armed 06:51:57, report 06:52:33, back 06:53:12, `oneshot_taken=yes`, flag left `00`, stage 2 `bc79acc4-dirty`.
- `wakealarm no`. That says nothing about the port: the alarm cells and the SPMI interrupt are in the device tree, and the device tree comes from `boot.bin`, which was the stock one. The new `rtc-macsmc` probed and set the clock as before, so the driver change does no harm without the cells. The alarm gets its first real test in C1, on the test chain.
- (The notice before the run was not sent: `agent-notify send` needs `-m`.)

## 2026-11-10 07:10 GH-5: the session continues by itself after a usage limit
Owner: do not just stop at a usage limit; wait for the reset and continue.
- Claude Code has this built in: `autoContinueAtUsageLimit` ("wait for the limit to reset and continue the task automatically"). Now set to `true` in `~/.claude/settings.json`. It did not act on the limit of 2026-11-09 night, when the key was unset; whether it does now is not yet seen.
- Fallback, in case it does not: a `StopFailure` hook (`harness/usbtest/claude-limit-hook.sh`, installed in `~/.claude/hooks/`) logs every API-error stop to `~/.local/state/deepidle/limit.log`. On a usage-limit stop of the unattended session (the directory in `~/.local/state/deepidle/resume`) it starts `claude-limit-wait.sh`: every 10 min it checks whether the transcript moved on, else asks the API a one-word question; when that works it waits 5 min more for the built-in continue, then closes the stuck `claude` and reopens the session with a continue prompt. Gives up after 26 h. Tested only with made-up hook input (other error, other directory: both ignored); what the hook receives on a real usage limit is not known until one happens, and the log will show it.
- Found on the way: after the K2 reboot two `claude` processes had this one session open, the restored terminal (`--resume`) and the post-boot hook's (`--continue`). The hook's copy did the K2 write-up and is waiting for "go"; the owner typed in the other. Both write the same transcript. To settle: one of the two launches has to go.

## 2026-11-10 07:25 GH-5: Opus 5.5 takes over when Fable runs out; run S1 (loader, owner present) started
Owner: ready for the attended run; do not stop to wait for one again, work on other parts of the plan; then the PMP checklist (to be posted as an issue); switch to Opus 5.5 by itself when Fable 5.2 runs out.
- Claude Code's `fallbackModel` setting (same as `--fallback-model`) only acts when the model is overloaded or not available, not on a usage limit (read from the 2.1.321 binary: triggers are `overloaded`, `server_error`, `model_not_found`, `permission_denied`, `model_blocked`, `last_resort`). Set to `["claude-opus-5-5"]` in `~/.claude/settings.json` all the same; a session already on Opus is not harmed by it (tried with `-p`).
- The usage-limit case is done by `claude-limit-wait.sh`: every 10 min it asks the session's own model a one-word question. If the session ran on Fable, Fable still refuses and Opus 5.5 answers, it closes the stuck `claude` and reopens the session with `--model claude-opus-5-5`. If Opus refuses too (the 5-hour or weekly limit), it keeps waiting as before. Going back to Fable after its reset is by hand (`/model`). Like the rest of the hook this has not met a real limit yet, and it only acts on the unattended session.
- The two-windows problem after a reboot is still open (a change that closed the restored copy from the post-boot hook was refused by the permission check; the owner decides which launch goes).
- **S1 started 07:25, owner at the Mac:** `bootbin.sh install ~/Work/psci-test/boot-selector.bin` (`44eef99b068d02af`; its payloads, 115 device trees and U-Boot, are byte-identical to the stock file's), PMU flag `00`, then a plain reboot. Expected: a normal boot to main in about a minute, `bootbin.sh status` says `(one-shot loader)` and stage 2 is no longer `bc79acc4-dirty`. If the Mac is not back in 3 min: power off, startup options, Terminal, `diskutil mount disk0s4`, `cp '/Volumes/EFI - OMARC/m1n1/boot-stock.bin' '/Volumes/EFI - OMARC/m1n1/boot.bin'`.
- Next after S1 (all unattended): `sudo bash harness/usbtest/bootbin.sh status`; write the S1 result here; `bootbin.sh test ~/Work/psci-test/boot-test.bin`; run C1 (`sudo bash harness/usbtest/arm.sh --chain --job harness/usbtest/jobs/c1-chain --label C1-chain`, after `jobs/build-tools.sh`), then C2, then the old S2R runs as jobs (R18B, R21). Between runs: the PMP checklist issue.

## 2026-11-10 10:45 GH-5 run S1: the one-shot loader boots main normally (1 of 1)
- Reboot 07:24:50, kernel up 07:25:17, session reopened 07:25:27. `bootbin.sh status`: `boot.bin 44eef99b068d02af (one-shot loader)`, PMU flag `00`, booted with stage 2 `22cbe6fe` (the stock image says `bc79acc4-dirty`), U-Boot unchanged. No hand recovery was needed.
- So a stage 2 built here (docker gcc 12) boots this Mac, and the loader's normal path works. The flag path (chainload `boot-test.bin` under a 120 s watchdog) is first used by C1.
- The usage limit hit at 07:25 right after the reboot. First real data on the limit hook: the `StopFailure` input has `"error":"rate_limit"` and a message starting "You've hit your 5-…", the hook matched and started the waiter. The waiter then quit at 07:35 with "the session moved on by itself": the second window on the same session (still two after each boot) wrote to the transcript. Claude Code's own `autoContinueAtUsageLimit` did the job: it continued the task at 10:41 when the limit reset. So the built-in works; the fallback's "moved on" test is fooled by a second window.

## 2026-11-10 10:45 GH-5 run C1: the rebuilt test chain boots through the loader (1 of 1), back on main in 76 s
- Armed 10:41:50, report 10:42:28, back 10:43:06, `oneshot_taken=yes`. Under test: stage 2 `v0.1.0-11-g41a93eba` (the rebuilt Aura, image 62), U-Boot `2026.07-g568034fcca96` (patched), kernel `7.2.11-psci-efi+`. Back on main: stage 2 `22cbe6fe` (the loader), so the flag was used once and cleared.
- All 10 CPUs online, `psci: PSCIv1.0 detected in firmware`, `mem_sleep` is `s2idle [deep]`, **`wakealarm yes`** (the PMU alarm cells are bound; whether the alarm fires is C2's question), PMP on (`PMP manages fabric and DCS p-states`).
- Errors: `watchdog0: watchdog did not stop!` (expected: the loader starts it, Aura keeps it, the kernel takes a running one over) and the ANE firmware missing in the test root (not needed).
- Bug found: on main the PMU's nvmem device was `spmi_nvmem1` this boot, `spmi_nvmem2` the boots before, so `bootbin.sh status` showed an empty flag and the return script logged `bootbin_flag_left=` (empty). Both now find it by SPMI address (`/sys/bus/spmi/devices/0-0b/spmi_nvmem*`). A wrong name could not arm a test by mistake: setting the flag reads it back and stops if it did not take.
- Next: C2 (`jobs/c2-suspend`): 3 `echo mem` cycles on control word 0, woken by the PMU alarm; the watchdog (120 s) is the net if the alarm does not fire.

## 2026-11-10 15:15 GH-5 run C2: the Mac slept 4 h 23 min until the owner pressed the power button (my harness had no net for this)
- Armed 10:44:16, back 15:07:53 (`away=15817s`), no report from the test boot. Owner: screen off, no answer to the headless shortcut; the power button brought a picture up (photo to come); then a power-hold reboot. Main booted normally, flag `00`, loader intact.
- What the code says happened: cycle 1's `echo mem` reached Aura's SYSTEM_SUSPEND and the boot core slept. The PMU alarm (+12 s) never asserted wake line 724. Aura's heartbeat (image 49) wakes every 60 s and re-arms the 120 s watchdog for as long as no wake line shows, so the watchdog never bit; the job's deadline timer is frozen during suspend. The power button (line 865) then woke it.
- So the deep suspend itself held for 4 h 23 min and woke on a wake line (good news for the chain), and the alarm port does not work as built (unknown why: K3).
- Two faults of mine: (1) C2 trusted an alarm that had never been seen to fire; (2) nothing bounds a suspend that no wake line ends. Also the job's log is only sent at the end, so a hang leaves no report.
- Fixes in progress: job K3 (alarm awake on the test chain, no suspend, with the PMU registers dumped); Aura: a cap on the sleep (resume by itself after a few heartbeats); jobs push a line before each risky step.

## 2026-11-10 15:20 GH-5 run C2: deep suspend and resume work 3 of 3 on the rebuilt chain; the alarm woke the first cycle only, the second slept 4 h 20 min
- Armed 10:44:16, back 15:07:53 (`away=15817s`), no report received. The owner found the screen off, pressed keys and the power button, photographed the console, then held power. From the photo (`PXL_20261110_200659232.jpg`):
  - cycle 1: `rc=0, 13.0 s, online 0-9`, `PM: suspend entry (deep)` → `PM: suspend exit`. **The PMU alarm (+12 s) woke the Mac: the T602x alarm port works, and the baseline deep suspend works on the rebuilt chain.**
  - cycle 2: `rc=0, 15580.8 s` (4 h 20 min). The alarm set for +12 s did not wake it; the owner's key press did. All CPUs back, console alive.
  - cycle 3: `rc=0, 114.9 s`, again ended by the owner. `job ended rc=0` at 15:06:46; the power-hold came seconds later, before the report was pushed and the job's own reboot.
- So: suspend/resume 3 of 3, including one of 4 h 20 min; alarm wake 1 of 3. The second alarm is the bug (candidates: the event latch or the AIC line is left asserted or masked after the first wake, so Aura sees no new edge on line 724).
- Why it could sleep for hours: Aura's heartbeat (image 49) wakes every 60 s and re-arms the 120 s watchdog as long as no wake line shows, and the job's deadline timer is frozen in suspend. Nothing bounded a suspend that no wake line ends. That was a hole in my harness, and I ran C2 unattended on an alarm seen to fire zero times; 4 h 20 min of the day went to it.
- Fixes: job K3 (three alarms in a row, awake, on the test chain, PMU registers and interrupt counts logged; no suspend). Aura: cap the sleep (resume by itself after a few heartbeats). Jobs push a line before each risky step so a hang still leaves a report.

## 2026-11-10 15:45 GH-5 run K4: the alarm never raised an interrupt because of the PMU's “fired” latch; fixed, and Aura's sleep is capped
- **K4** (awake, back in 82 s). Around two alarms: the SPMI controller's mask word 0 is `0x4` (interrupt 2 on), its pending words never change (word 1 reads `0x0d000000` all the time), event `0x14c0` stays `00`, the handler count stays 0. Control byte `0x1401` reads `0x43` armed and `0x03` after the alarm time.
- **Cause: known since 2026-10-19 and lost in my port.** When an alarm fires, the PMU clears the enable bit (6) and sets bit 1 of the control byte. While bit 1 is set, a later alarm clears bit 6 at its second but sets no event and raises no interrupt. The 2026-10-19 driver wrote the whole byte with bit 1 cleared. The port onto upstream's alarm code (`0037`) changed only the enable bit, so bit 1 stayed set for ever. Run C2's first cycle woke only because the latch was still clear after the power-on; every later alarm was silent.
- **Fix** (`patches/psci-efi/linux/0038-*`): on T602x every write of the control byte clears bit 1. Module rebuilt and put in the test root (`5abfbef391e8ca1f`).
- **Aura sleep cap** (`patches/psci-efi/aura/rebuilt/0004-*`, Aura `v0.1.0-12-g876622bf`): after 5 heartbeats (5 min) with no wake line, Aura resumes the kernel by itself with wake line -1. `psci_ctl[3]` sets another count for one boot (`aura-ctl <value> <mask> <cap>`; `0xffff` = no cap). This closes the hole that let C2 sleep 4 h 20 min. `boot-test.bin` rebuilt and staged: `d0ee55407f0362ee`.
- **Job K5** (`jobs/k5-alarm-suspend`): two awake alarms must raise two interrupts, or the job stops with no suspend. Then one deep suspend with no alarm and the cap at 1 heartbeat (expected back after about 60 s), then three deep suspends with a 15 s alarm. A line is pushed before every suspend. Deadline 1500 s.

## 2026-11-10 15:40 GH-5 run K5: stopped itself, the fixed module was not the one loaded (my build slip)
- Back in 81 s. Aura `v0.1.0-12-g876622bf` boots. Awake alarms: 0 of 2 interrupts, control byte still `0x43` when armed, so the job stopped before any suspend, as designed.
- Cause: `rtc-macsmc` is loaded from the UKI's initramfs (the `asahi` hook adds it), and I rebuilt only the root image. The UKI still held the old module.
- UKI rebuilt with the fixed module: `f77e8512a5034b5b`. K5 runs again unchanged.

## 2026-11-10 15:45 GH-5 run K5b: the rebuilt module did not load (no RTC at all); second build slip
- Back in 138 s. No `wakealarm`, and the clock read 2026-10-18: `rtc-macsmc` never probed. Job stopped before any suspend.
- Cause (not seen in a log, inferred): `make modules` relinked `vmlinux`, so the new module's BTF belongs to a kernel that is not the `Image` in the UKI (built 2026-11-09), and this config refuses a module whose BTF does not match (`MODULE_ALLOW_BTF_MISMATCH` off). I also installed it unstripped.
- Fix: the module with debug info and BTF sections removed (15 KB), in the root image (`31b1274f84c857eb`) and the UKI (`b245ddb078d28c75`). K5 now prints the RTC lines of dmesg if there is no `wakealarm`.

## 2026-11-10 15:45 GH-5 run K5c: PASS. The alarm interrupts, wakes 3 of 3 deep suspends, and Aura's cap ends a sleep with no wake source
- Away 214 s, back on main by itself. Aura `v0.1.0-12-g876622bf`, kernel `7.2.11-psci-efi+`, stripped fixed `rtc-macsmc`.
- Awake: 2 alarms, 2 interrupts (control byte now reads `0x01` after an alarm: the latch is cleared).
- Cap test: deep suspend with no alarm, cap 1 heartbeat: `rc=0`, back after 63.3 s, all 10 CPUs online.
- Alarm: three deep suspends with a 15 s alarm: 15.6, 15.7, 15.7 s, one alarm interrupt each, `rc=0`, CPUs 0-9 online each time.
- Seen, not looked at yet: 30 error lines in dmesg, among them `macsmc 2a2400000.smc: Failed to send command` around each resume and brcmfmac errors (-52) after it.
- The unattended deep suspend baseline (old Phase 2 gate) is back on the rebuilt chain, with a bounded sleep. Next: port the S2R runs (R18B, R21) as jobs on this base.

## 2026-11-10 15:50 GH-5 read: aurora-silicon/linux `feat/s2r` (T8140) and the M4 Pro sleep PR, against Aura image 62
Owner asked for this before the next run. Read-only: 25 branches fetched into `~/Work/src/linux-aurora` as remote `as`, plus PR 1477 as `as/pr1477`. Nothing built from them.

- **What exists there.**
  - `feat/s2r` (linux PR 1445, DJ, one commit, 200 files): suspend-to-RAM on T8140 (A18 Pro, J700), kernel at EL2, no PSCI. Core is `drivers/soc/apple/sleep.c` (3563 lines). Real sleeps and returns on hardware.
  - linux PR 1477 (`j616s/el2-sleep`, stacked on 1445): M4 Pro (T6040), `drivers/soc/apple/t6040-sleep.c` (6440 lines, 77 module parameters, work in progress). Three complete S2R resumes reported. This is the closest SoC to ours with a working entry.
  - aura PR 117 and 148: the return path. Aura publishes a mailbox (`AURAS2R1`, resume address) only where RVBAR is locked (M4 on). T6020 does not lock RVBAR, so that part does not apply: our PSCI and RVBAR path stays.
  - `j514s/sleep-20261022` (M3 Pro): s2idle and display work only, no S2R entry.
- **Confirmed by their code, already ours.**
  - The PMU control byte's bit 1 "fired" latch: `0dd76c9db67a` (2026-11-09) clears it on every control write, armed value `0x41` not `0x43`. Same bug and same fix as our patch 0038 (run K4, K5c).
  - The commit is the write of 1 to MPMGR_AON + 0x4000 on T6040 too (`0x508904000`), with PMU boot stage `0x50`, WD0 off, clusters to 0, clock muxes parked before it and the AIC masked after it. Aura does all of these.
  - "go hib" is the alarm being re-programmed; they also mark its need as unproven.
- **New for us: steps T6040 needed that Aura image 62 does not do.** Ordered by how well they fit our symptom (the timer is taken, the SoC resets instead of sleeping).
  1. **The axi2af gate.** macOS's `quiesceHW` panics unless every "axi2af" fabric-bridge domain reads actual state 0. On T6040 a commit with some still on **reset the SoC about a second after the timer** (their runs el2.37/38). Their list: atc0-3_common, disp_sys, dispext0-3_sys, **ans**, avd_sys, venc0/1_sys, jpg, **apcie_sys_gp**. Aura lowers the display chains and atcN_usb only. It never checks ans, the PCIe domains or atcN_common. So ANS and PCIe are probably on at our commit.
  2. **ANS and PCIe taken down inside the commit.** They stop ANS in its driver, then lower its two PCIe lanes and shared PHY, stop the GP ports (Wi-Fi, SD), then lower apcie_sys_gp and apcie_gp, each with its bridge's `+0x104`/`+0x108` bit 0 cleared first. On wake the same bits are set again or the bridge drops traffic.
  3. **Keep-alive bits:** bit 0 of 32 words (stride `0x44`) in each of two PMGR windows, cleared before the timer (`_enableKeepAlive`).
  4. **SPMI notify enable** `0x2000001` written on both SPMI controllers with the boot stage.
  5. **SMC AP watchdog deadline** word zeroed right after WD2 is set (we noted macOS doing it, Aura does not).
  6. Smaller ones: the thermal monitors (TVM) disabled and polled idle, ACC PLL relock off, the PMC AP DCS floor vote dropped, the AOP and MTP islands off, PTD requests withdrawn.
  - T6040's entry is short. They found macOS writes **none** of T8140's DCS ladder, MCC lane stop, PMC voters, CLLT or DVFM park there. T6020 is the same family as T6040 here (our 13.5 `quiesceHW` reading has no such steps either), so those T8140 steps are not candidates.
- **Useful diagnostics they built.** A crumb with the 15-bit mask of axi2af domains still on at the commit; the S2R-lo entry counter (ours: the PMGR `SLP_S2R` counter); the wake mask and status words read after a failed sleep; `pm_async=0` for every test so an SError is not blamed on the wrong device.
- **Other pieces worth taking later.** `43cf63fb4781` (alarm as a wake IRQ instead of `IRQF_NO_SUSPEND`), `c81000fb2880` and `99696ed7aaf7` (SPMI acks read back, unused pending sources cleared), `567a28f1d9a4` (shorter macsmc waits; may relate to our `Failed to send command` lines), `fix/brcmfmac-resume-association` (our -52 lines).
- **Plan change.** Before R18B and R21, one cheap read-only job: at the commit point, record the actual state of the T6020 counterparts of the axi2af domains (names from the ADT and `t602x-pmgr.dtsi`). If any is on, that is the first thing to lower. Mapping the T6040 addresses to T6020 is the work; no address above is valid on our SoC.

## 2026-11-10 15:51 GH-5 image 63: Aura lowers the USB-C complexes (aura-ctl `0x80000`); job A1 armed
- **Why.** Our own data already answers the "which fabric-bridge domains are on at the commit" question from the 15:50 entry. Run S8's genpd dump lists `atc0-3_common`, `atc0-3_pcie` and `apcie_gp_sys` on at syscore suspend (the DT marks them always-on). `data/psmap.txt`: macOS has ATCn_COMMON and ATCn_PCIE at target 0 at sleep entry. So every commit from R6 to R18 ran with them on. On T6040 that made the timer reset the SoC.
- **Image 63** (Aura `v0.1.0-13-ga1215d2f`, patch `patches/psci-efi/aura/rebuilt/0005-…`, `boot-test.bin` `771d5491dacae658`, staged; the previous one is kept as `boot-test.bin.62cap`):
  - New step `PSCI_S2R_ATC` (bit 19): `atc0-3_pcie` (`0x28e080278/288/298/2a8`), then `atc0-3_common` (`0x28e080228/230/238/240`): AUTO_ENABLE and target cleared, actual state polled to 0 (10 ms each; timeouts in `psci_dbg[23]` bits 44-51). It runs before the fabric step.
  - Written back on any resume, parents first.
  - At the crumb snapshot PMU scratch `0x600e` = which of the eight are still on.
  - `aura-ctl` accepts bit 19.
- **Job A1** (`harness/usbtest/jobs/a1-atc-off`, unattended, **normal path: no `slpa`, no S2R timer**, so the SoC stays on and nothing can be left half asleep):
  1. USB-C wakeup off and the dwc3 cores stopped (as S5 to R17), so `atcN_usb` are off first.
  2. Deep suspend with `0x80000` alone, 20 s alarm. Logged: the eight words before and after, Aura's debug words, genpd's list.
  3. Deep suspend with `0xc0000` (ATC + image 62's fabric step, which never ran).
- Expected away time 4 to 6 min. A hang before the deep WFI ends at the 120 s watchdog; a sleep the alarm does not end, at Aura's 5 min cap.
- If A1 passes, the next run is R17 with both steps (`0xddb1f`) on the new chain. That needs the R17 Linux switches in the test kernel first (the DCP shut-down switch is not ported yet).

## 2026-11-10 15:56 GH-5 run A1: the ATC step takes and the resume survives it; both sleeps ended after 3 s on the SMC line; the fabric write changes nothing; job A2 armed
(The two entries above carry guessed times; they were written at about 15:47 and 15:51. My notification for A1 also said 16:20; it started at 15:51.)
- Away 103 s, back on main by itself. Stage 2 `a1215d2f`. Both suspends `rc=0`, all 10 CPUs online, USB still lists 6 devices afterwards.
- **ATC step (`0x80000`):** Aura read the control word, no poll timeout (`psci_dbg[23]` 0): all eight words reached actual state 0 within 10 ms each, with `atc1_usb` and `atc2_usb` (children) still on in genpd's list. After the resume the words read `0x3ff` (on).
- **Both sleeps lasted 3.3 and 3.2 s, not 20.** Aura's wake record: line 865 (the SMC mailbox), 0.52 s after entry, which is just past Aura's 500 ms hold-off. No alarm interrupt. K5c's three sleeps ran to their alarm, so something in A1 makes the SMC talk: the ATC step, or the USB-C wakeup-off and dwc3 teardown. A1 changed both at once, my mistake.
- **Fabric step (`0x40000`) does nothing.** `psci_dbg2[51]`: `AFNC1_LW2` read `0x1f0000ff` before and `0x1f0000ff` right after Aura wrote `0x1000030f`. Bits 27:24 did not change. So they are not a plain writable field, and run R21 as built would have been a no-op. How macOS gets `0x1000030f` there is open.
- genpd's list at suspend, of the domains in question: `atc1_usb atc2_usb apcie_gp apcie_gpshr_sys` and the always-on `atcN_usb_aon atcN_pcie atcN_common apcie_gp_sys apcie_phy_sw afnc1_lw2 afnc2_lw1`.
- The job's attachment held only the last 25 log lines, so the "before" values are lost. A2 pushes its own summary.
- **Job A2** (`harness/usbtest/jobs/a2-atc-wake`, normal path, unattended): four suspends, 20 s alarm, one variable each: base; ATC step; USB wakeup off + teardown; both. Per suspend: duration, Aura's wake line and time, alarm interrupts. About 3 to 4 min away.

## 2026-11-10 16:02 GH-5 run A2: the alarm wakes all four sleeps; neither the ATC step nor the USB teardown makes the SMC wake early
- Away 183 s, back on main by itself. Image 63, four deep suspends on the normal path, 20 s alarm each:

| Suspend | aura-ctl | USB-C wakeup off + teardown | Result | Time | Aura's wake line | In Aura | Alarm irqs | Poll timeouts |
|---|---|---|---|---|---|---|---|---|
| 1 base | 0 | no | rc=0 | 9.0 s | 724 (PMU alarm) | 6.3 s | +1 | 0 |
| 2 atc | `0x80000` | no | rc=0 | 21.1 s | 724 | 18.2 s | +1 | 0 |
| 3 usb | 0 | yes | rc=0 | 20.7 s | 724 | 18.0 s | +1 | 0 |
| 4 usb+atc | `0x80000` | yes | rc=0 | 21.1 s | 724 | 18.2 s | +1 | 0 |

- Suspend 1 is short because the job sets the alarm before its push, and the first push took about 11 s. It still ended on the alarm.
- **So A1's 3 s sleeps (line 865, the SMC mailbox, at 0.52 s) do not come from the ATC step or the USB teardown.** Suspend 4 is A1's first suspend and ran to the alarm. What A1 had and A2 did not: `pm_genpd.test_dump=Y`, and more log lines before the suspend. Not explained. It does not block the commit runs (there the S2R timer ends the wait, not a wake line), but a wake line that fires 0.5 s in would end a real sleep, so it stays on the list.
- The ATC words read `0x3ff` after every resume; USB lists 6 devices at the end.
- **Next: run R17A** = R17's Linux side on the new chain + Aura's ATC step (`0x9db1f`). `appledrm.test_sleep_off` was the one R17 switch missing in the rebuilt test kernel; ported (same 35 lines as `patches/psci-efi/linux/0001-TEST-drm-apple-dcp-test_sleep_off-…`), module building.

## 2026-11-10 16:07 GH-5: job R17A written; Aura image 64 built (PCIe chain and AON words off before the commit), not staged
- **Job R17A** (`harness/usbtest/jobs/r17a-commit-atc`): R17's Linux side set at run time from the job (`deep_steps` 62, `pmp_sleep`, `test_release_aon`, `test_release_ids` `0x1000`, `test_pcpm` `0x300`, `test_sleep_keep` afr, genpd dump, USB-C wakeup off and teardown, `appledrm.test_sleep_off`), `aop.sleep_ap_idle=3` from the UKI's command line, aura-ctl `0xddb1f` = R17's `0x1db1f` + the ATC step + the fabric step. The fabric write did nothing in A1; it is in for its crumb (which lanes read gated at the commit). The job stops before the suspend if any switch is missing or the control word does not read back. It pushes "R17A committing" right before `echo mem`, and "R17A resumed" if it ever comes back into the job.
- **After a reset:** `sudo bash tools/pmu-scratch.sh` (new) reads and decodes Aura's crumbs from the PMU scratch on main; `zero` clears them. `0x600e` = which ATC words were still on at the commit, `0x600d` = the fabric lanes.
- **Scratch `0x6010` is shared:** Aura's snapshot writes `0x6010/11` (`ff ff` when every core slept) and the one-shot loader reads `0x6010` (`a5` = boot the test image once). Aura never writes `a5` there unless a core fails in a specific way, and a stray `a5` costs one test-chain boot under the watchdog. Left as is.
- **`appledrm.test_sleep_off` build:** `make M=…` and the single-module target both fail here, and `make modules` started a full rebuild (the 15:28 module build ran without `LLVM=1`, so the tree had switched to gcc). The full clang rebuild is running. Only the stripped `appledrm.ko` goes into the root image; the UKI keeps the 2026-11-09 kernel image.
- **Aura image 64** (`v0.1.0-14-g99f6e082`, patch `patches/psci-efi/aura/rebuilt/0006-…`, `~/Work/psci-test/boot-test.bin.64` `68e565ce97d2911b`, **not staged**; the staged test image is still 63):
  - `0x100000` `PSCI_S2R_PCIE`: `apcie_gp_sys` (`0x290280418`, always-on in the DT), then its parents `apcie_gpshr_sys` (`0x2902803f8`) and `apcie_gp` (`0x290280198`) to target 0, each polled 10 ms. All three are on at every commit so far (S8's list). The M4 Pro code lowers the same pair before its commit.
  - `0x200000` `PSCI_S2R_AON`: `atc1-3_usb_aon` (`0x29e280098/a0/a8`) and `msg` (`0x29e280078`) to target 0, as macOS has them at sleep entry (`data/psmap.txt`).
  - Poll timeouts in `psci_dbg[23]` bits 52 to 58; crumb `0x600c` = which are still on. Written back on a resume, but nothing retrains the PCIe links, so these two bits are for commit runs only.
  - With `0x100000` the fabric step skips `apcie_gp_sys` (it would set its target back to f).
  - `aura-ctl` accepts bits 0 to 21.
- **Order after R17A,** one step per run: R17B = R17A + `0x100000` (image 64), R17C = R17B + `0x200000`.

## 2026-11-10 20:45 GH-5: `appledrm.test_sleep_off` in the test root, `aop.sleep_ap_idle=3` in the UKI; run R17A armed
- Work stopped from 16:10 to 20:40 (usage limit); the module build had finished at 16:10.
- **Kernel:** `patches/psci-efi/linux/test-dcp-sleep-off.diff` (`appledrm.test_sleep_off`: on a deep suspend the DCP firmware is shut down and its CPU stopped, never restarted; R17's `DO=1`). Only the module is new: built with clang against the same tree, debug info and BTF removed (1.1 MB), installed in `/usr/lib/modules/7.2.11-psci-efi+`. The old module is in `~/Work/psci-test/appledrm.ko.before-sleep-off`. The kernel image in the UKI is still the 2026-11-09 one.
- **Root image** `1c0acb77edb3e8f5` (in `/boot/deeptest`), **UKI** `6ee0da2aecd4f602` with `aop.sleep_ap_idle=3` added to the command line. That parameter is now set for every DeepTest job, not only R17A: AOP is told at probe to let the AP idle state go to 3. K5c and A2 ran without it.
- **Run R17A armed** (`--chain`, image 63 `771d5491dacae658`, job `r17a-commit-atc`). Expected: "R17A committing" on ntfy, then (a) a reset about 86 s later, as R17, or (b) a wake on the 40 s alarm and "R17A resumed". After it: `sudo bash tools/pmu-scratch.sh` on main, `0x6004` should read `16`, `0x600e` which ATC words were still on, `0x600d` the fabric lanes.

## 2026-11-10 20:52 GH-5 run R17A: the same reset as R17 with the USB-C blocks off; image 64 staged, run R17B armed
- Armed 20:42:22, "R17A committing" on ntfy at 20:43:00, main's kernel started 20:44:16, no "resumed" push. That is 76 to 88 s from the suspend to the next kernel (the test root's clock and the push time differ by 12 s), R17's 86 s within that error. **Same outcome as R17: the SoC did not power down, the S2R timer reset it.**
- All R17 switches were present and took (`deep_steps=62 pmp_sleep=Y test_release_aon=Y test_release_ids=4096 test_pcpm=768 test_sleep_keep=afr test_dump=Y test_deep_teardown=Y test_sleep_off=Y`), aura-ctl `0xddb1f` read back. So R17 is reproduced on the rebuilt chain (Aura rebuilt from patches, new loader, DeepTest) and `appledrm.test_sleep_off` works as a runtime switch.
- **PMU scratch:** `00300050167e07ff 00000000ff000000 00ff1f100380f801 0000000010105000`: R17's bytes (code `0x16`, CPU_OFF `077e`, never slept `f880`, wait 6 ms, EACC/PACC0/PACC1 `10/10/50`) except `0x6010`, which the loader clears.
- **Mistake in the plan:** I meant to read the ATC and fabric state from `0x600e` and `0x600d`. Those two keys read 0 after every reset (noted on 2026-11-07, R15). So this run does not show whether the ATC words were off at the commit. A1 and A2 showed they go off within 10 ms on the normal path.
- **Fix, Aura `ec1e8686`** (patch `0007`): crumb `0x600c`, which survives, now has bit 7 = some ATC word still on, beside image 64's PCIe bits 0 to 2 and AON bits 3 to 6. Image 64 rebuilt: `boot-test.bin` `767527b8149c77d5`, **staged** (image 63 kept as `~/Work/psci-test/boot-test.bin.63`). `tools/pmu-scratch.sh` updated; crumbs zeroed.
- **Run R17B armed:** R17A + `0x100000` (PCIe chain to target 0). Expected `0x600c` = `00` if PCIe and ATC were all off at the commit.

## 2026-11-10 20:50 GH-5 run R17B: PCIe chain and USB-C blocks confirmed off at the commit, the same reset; R17C armed
- Armed 20:46:04, "R17B committing" 20:46:42, main's kernel started 20:47:58 (76 s after the push; R17A the same), no "resumed" push. aura-ctl `0x1ddb1f` read back on image 64 (`ec1e8686`).
- **PMU scratch:** R17's bytes again, and **`0x600c` = `00`**: at the last access before the commit `apcie_gp_sys`, `apcie_gpshr_sys`, `apcie_gp` and all eight ATC words read actual state 0. (The key was `ff` after R17A and zeroed before this run; the snapshot writes `ff` there first, so `00` is the step's own write.)
- **So neither the USB-C complexes nor the PCIe chain is what keeps the SoC from powering down.** Two of the largest differences from macOS's sleep-entry map are gone.
- **R17C armed:** + `0x200000` (`atc1-3_usb_aon`, `msg` to target 0). Expected `0x600c` = `00` again if they all went off.

## 2026-11-10 20:53 GH-5 run R17C: `atc1-3_usb_aon` and `msg` off too, the same reset
- Armed 20:48:55, "R17C committing" 20:49:33, main's kernel started 20:50:49 (76 s after the push, as R17A and R17B), no "resumed" push. aura-ctl `0x3ddb1f` read back.
- PMU scratch: R17's bytes, `0x600c` = `00`: the PCIe chain, `atc1-3_usb_aon`, `msg` and the eight ATC words all read actual state 0 at the last access before the commit.
- **Three candidate blockers ruled out in three runs** (USB-C complexes, PCIe chain, the AON-side USB and `msg` words). The reset after the S2R timer is unchanged.
- Next: go back to the list of what still differs from macOS at the commit (S8's list, `data/psmap.txt`) and to the M4 Pro code's steps this chain does not have (keep-alive bits, SPMI go-hib, SMC), and pick by evidence rather than by size.

## 2026-11-10 20:53 GH-5: what is left of the macOS map; image 65 (PMP power words off), run R17D armed
- **What is still different at the commit.** Run S6's list of 83 domains on at syscore suspend, minus what R17A to R17C now switch off, against `data/psmap.txt` (macOS at sleep entry) leaves three entries: **`pmp` and `pms_sram`** (macOS: off, `0x0f0f0300` and `0x0f000300`; ours: on, Linux only sends the PMP its RTKit sleep) and **`sep`** (macOS `0x1000030f`, R18B, not run yet). ANS is not in S6's list: its domains are already off.
- **Reminder from run T0 (2026-11-06):** the timer write alone, with nothing else, resets the Mac after about 85 s. So the reset is the default outcome of the write, and a missing precondition and a missing later step look the same from here.
- **Image 65** (Aura `v0.1.0-16-gb22c3766`, patch `0008`, `boot-test.bin` `a2664063226f6489`, staged): aura-ctl `0x400000` `PSCI_S2R_PMP`: `pmp` (`0x28e0802c8`) then `pms_sram` (`0x28e0802d0`) to target 0, polled 10 ms each. Crumb `0x6011` = `40` if both read off at the snapshot, `41` to `43` if not. Commit runs only (nothing boots the PMP again).
- **Run R17D armed:** R17C + `0x400000`, and **without `0x1000`**, so WD1 (120 s after the suspend) stays armed. Reason: R20 showed a step can stop the timer's reset and leave the Mac dark until someone holds power. With WD1 on, a hang ends by itself after about 2 min. Outcomes: reset at about 86 s = no change; reset at about 125 to 145 s = the step changed the commit (WD1 ended it); "R17D resumed" = it slept and the alarm woke it.

## 2026-11-10 20:58 GH-5 run R17D: `pmp` and `pms_sram` off at the commit, the same reset; the SEP hand-off (R18B) is next
- Armed 20:53:55, "R17D committing" 20:54:33, main's kernel started 20:55:49 (76 s after the push, as R17A to R17C), no "resumed" push, away 121 s. aura-ctl `0x7dcb1f` read back on image 65 (`b22c3766`).
- PMU scratch: R17's bytes, `0x600c` = `00` and **`0x6011` = `40`**: `pmp` and `pms_sram` both read actual state 0 at the last access before the commit, with the PCIe chain, the AON-side USB words, `msg` and the eight ATC words.
- WD1 was armed in this run (120 s from the suspend) and did not fire first: the reset came 89 s after the suspend by the test root's clock, the S2R timer's time. So the PMP step neither hangs the commit nor changes it.
- **Four candidate blockers ruled out in four runs.** Of the differences from macOS's sleep-entry map (`data/psmap.txt`) one is left: `sep` (macOS `0x1000030f`, ours `0x1f0000ff`).
- **Next, R18B as a DeepTest job:** R17D's entry plus the SEP SLEEP message and the `ps_sep` hand-off (`apple_sep.test_sleep_msg=2`, `test_sleep_psoff=1`, patch `test-sep-sleep-msg.diff`). The test `apple-sep.ko` is not in the rebuilt module tree (the installed one has neither parameter), so the modules are being rebuilt with the patch (clang, incremental). The owner approved SEP tests on 2026-11-07. Crumbs zeroed.

## 2026-11-10 21:00 GH-5: test `apple-sep.ko` in the test root, run R18B armed (the SEP hand-off before the commit)
- **Module:** `test-sep-sleep-msg.diff` applied to the test kernel tree, modules rebuilt with clang (rc 0; the UKI keeps the 2026-11-09 image). Only `apple-sep.ko` installed, stripped (`18a3b5edc5f97443`, with `test_sleep_msg` and `test_sleep_psoff`); the previous one is `~/Work/psci-test/apple-sep.ko.before-sleep-msg`. Root image `127848cd5acaec83` in `/boot/deeptest`.
- **Job `r18b-commit-sep`** = R17D (image 65, aura-ctl `0x7dcb1f`, WD1 left armed) plus the SEP step:
  - The test root does not load the SEP driver by itself. The job loads it with `xart_writes=0 provision_keybag=0`, so this boot cannot write the shared xART store, and stops if it does not bind.
  - New: the SEP step runs in a **freezer-only suspend pass** first (`pm_test=freezer`, 5 s, no device or CPU goes down). The PM_SUSPEND_PREPARE notifier sends SLEEP type 2, clears OUTBOX_CTRL enable and writes `0x1000030f` to `ps_sep` (`0x290280c00`). The job then pushes the kernel's `TEST SLEEP` and `TEST PSOFF` lines and the word read back ("R18B sep asleep"), clears both parameters and does the real suspend. So the result of the SEP step is known before the quiet commit, with no new Aura crumb. It stops if the step did not run.
  - The other notifiers run twice (AOP's 0x201 and its restart among them), as in any two suspends.
- Outcomes: "R18B sep asleep", "R18B committing", then a reset about 76 s after that push = no change; about 110 to 130 s = WD1 ended a changed commit; "R18B resumed" = it slept and the alarm woke it. If only "DeepTest job ended" arrives, the driver did not bind or the step did not run, and the Mac comes back by itself.

## 2026-11-10 21:04 GH-5 run R18B did not reach the suspend: the test boot reset about 10 s after loading the SEP driver; diagnostic job S3 armed
- Armed 21:00:51, main's kernel started 21:02:00, away 76 s. **No push at all**, PMU scratch still zero (no Aura crumb, so no `SYSTEM_SUSPEND`), loader flag cleared, main's own SEP probe fine on this boot (writes enabled, 14 live records as before).
- Timing: R17D's job reached its "committing" push 38 s after arming. Here the Mac reset about 45 s after arming (69 s minus the 24 s firmware chain). The job's first push comes only after the driver is bound plus 10 s, so the reset fell between the `modprobe apple_sep xart_writes=0 provision_keybag=0` and that push. Nothing of the test boot's log survives (RAM root; the Pi watcher is not set up on the new install).
- Not known yet: a kernel panic with a reboot, or the enclave resetting the SoC. Differences from R18 (2026-11-07, where the driver ran in the test kernel): `xart_writes=0`, the rebuilt module tree, and Aura's device tree (whether it carries the `sep-firmware` reservation is not checked yet).
- **Job `s3-sep-load`** (no suspend, no aura-ctl): pushes the SEP node, the reserved-memory nodes and `kernel.panic` before the modprobe, then pushes the kernel's new SEP lines every second for 40 s. The last push received shows how far the driver got. Either it ends with "S3 done" and returns to main, or it resets as R18B did; back by itself in about 80 s both ways.

## 2026-11-10 21:07 GH-5 run S3: the SEP driver loads and binds in the test root; R18B's reset was in the SEP step itself; `ps_sep` already reads macOS's value here; R18C armed
- S3 (armed 21:04:09, back after 113 s, "S3 done" pushed): the driver bound within 1 s of the modprobe, 12 endpoints discovered, hwrng registered 3.4 s later, the Mac stayed up for the 40 s watched. xART read-only as asked (APFS-resolved extent, 14 live records). The `sep-firmware` reservation is present under Aura's device tree.
- **So R18B did not die at the load** (my reading in the last entry was wrong: the job's first push came after the freezer pass, not before it). Redone with S3's times: R18B's modprobe was about 21:01:16, bound by :17, the 10 s wait, the SEP pass at about 21:01:27, the reset at about 21:01:36. The test boot runs with `panic=10`. **A kernel panic at the SEP step and its reboot 10 s later fits to the second.**
- **`ps_sep` (`0x290280c00`) read `0x1000030f` in S3 with the driver bound**: macOS's sleep-entry value (auto-enable, PS_AUTO 0). On main it read `0x1f0000ff` on 2026-11-07. So in this boot the PMGR is already allowed to gate the enclave, and R18B's write of that value changes nothing.
- Likely cause of the panic: after the SLEEP the enclave goes idle, the PMGR gates it, and R18B's next access (the read of the mailbox's OUTBOX_CTRL) faults. Not proven: no log left the Mac.
- **Job `r18c-commit-sep-sleep`:** the SLEEP alone in the freezer pass, no mailbox or `ps_sep` write. It pushes "R18C sep bound" before the pass (with `ps_sep` before the driver and after the bind) and "R18C sep asleep" after it (`ps_sep` right after and 2 s later, the kernel's reply line), takes the SEP hwrng out of use first so nothing asks the sleeping enclave for entropy, then R17D's commit. It stops if the SLEEP got no reply.
- Outcomes after "R18C committing": reset about 76 s later = no change; about 35 s = a panic in the suspend path; 110 to 130 s = WD1; "R18C resumed" = it slept and woke.

## 2026-11-10 21:11 GH-5 run R18C: the enclave acknowledged SLEEP, `ps_sep` stayed on, the same reset; reboots paused by the owner
- Armed 21:07:48. Pushes: "R18C sep bound" 21:08:28, "R18C sep asleep" and "R18C committing" 21:08:37. Main's kernel started 21:09:52, 75 s after the commit push: the S2R timer's reset, as R17A to R17D. Away 131 s. PMU scratch: R17D's bytes (`0x600c` 00, `0x6011` 40).
- **The SLEEP worked:** `TEST SLEEP type 2: reply tag 0xd data 0x0`, the freezer pass returned rc 0, no panic. So R18B's panic came from its extra step (OUTBOX_CTRL clear and the `ps_sep` write), or from something that used the enclave afterwards (this run took the SEP hwrng out of use first: `rng_current apple-sep -> none`).
- **`ps_sep` did not move:** `0x1f0000ff` before the driver, `0x1f0002ff` bound, and the same right after the SLEEP and 2 s later: actual state f, PS_AUTO f. The enclave slept but its domain stayed on and not gateable. So this run did **not** have macOS's SEP state at the commit, and the SEP difference is still open.
- **Correction to the S3 entry:** S3 read `0x1000030f` 40 s after the bind (about 60 s of uptime), not from the start. Something changes the word between about 8 and 40 s after the bind, with no SLEEP sent: possibly genpd switching unused domains off late in boot. Then the enclave was gated (actual state 0) while the driver was idle, and nothing crashed. To check next: read the word every second after the bind, and whether `pmgr_pwrstate` owns it.
- **21:10 the owner asked to pause reboots** (they need the Mac). Nothing is armed: loader flag `00`, crumbs zeroed. Queued for when reboots are allowed again, **R18D**: SLEEP in the freezer pass, then wait until `ps_sep` reads `0x1000030f` by itself (or write it), then R17D's commit.
- Meanwhile, no-reboot work: the T6020 addresses of the M4 Pro code's extra steps, a re-read of DJ's and Naeem's sequences against what the chain now does, and the build parts of the PMP checklist (issue #12).

## 2026-11-10 21:26 GH-5: the enclave runs its own power word (read on main, no reboot); job R18D ready, not armed
- Read-only on main (`mmio-read 0x290280c00`, 13 min after boot, driver bound, genpd "on"): `ps_sep` = **`0x1000030f`**, macOS's sleep-entry value, with nothing written by Linux. No Linux driver writes PS_AUTO (`pmgr-pwrstate.c` only sets the target and AUTO_ENABLE; nothing in `drivers/soc/apple` but the test patch).
- Log of every change for 90 s after a 4 KiB read from `/dev/hwrng` (served by the enclave): `+0.32 s 0x1400034f` (floor 4, actual 4), `+0.42 s 0x1000030f`, then at `+60.7 s` `0x1f0003ff` → `0x1400034f` → `+60.8 s 0x1000030f`. **So the enclave raises and lowers its own floor (PS_AUTO) as it works, drops back to floor 0 within 0.1 s, and wakes by itself about once a minute.**
- That explains R18C: its SLEEP went out 9 s after the bind, while the enclave was still busy with its start-up work (`0x1f0002ff`, floor f), and it stayed so for at least 2 s after. S3's `0x1000030f` 40 s after the bind was the same enclave after it settled. It also suggests R18B's write of `0x1000030f` was harmless and its read of the mailbox's OUTBOX_CTRL faulted (the mailbox is in the enclave's domain), which fits the panic.
- **Job `r18d-commit-sep-idle`** (not armed; reboots are paused): R18C, but it waits up to 90 s for the floor-0 word before the SLEEP and up to 30 s after it, and stops if the word is not idle after the SLEEP. Pushes "R18D sep bound" (seconds to idle) and "R18D sep asleep" (seconds to idle again).
- Open: whether the once-a-minute self-wake continues after SLEEP. macOS sends SLEEP and its sleep-entry map shows floor 0, so the commit should see the gateable state either way; whether the PMGR waits for the actual state to reach 0 is what R18D can tell.

## 2026-11-10 21:36 GH-5: macOS 15.7.1's own T6020 kernelcache and J414s ADT read from this Mac (no reboot); what they say about the M4 Pro steps
- **Source.** The Pi that held the 13.5 and 14.8.9 kernelcaches is not reachable from this install (no Tailscale). New `tools/macos-preboot-read.sh`: builds apfs-fuse in a work dir (two local fixes: `<cstdint>`, and a container whose key manager does not parse is still opened for the unencrypted volumes) and mounts one macOS volume **read-only**. From Preboot (volume 3): the boot kernelcache of the 15.7.1 volume group (`Darwin 24.6.0, xnu-11417.140.69.701.11~1/RELEASE_ARM64_T6020`, IM4P to a 114.9 MB fileset with `tools/im4p-extract.py`) and `DeviceTree.j414sap.im4p` (LZFSE ADT, 315 KB). Unmounted after each copy; copies in the session scratchpad only.
- **The S2R timer is fired by the PMU driver.** In the ADT, `spmi-mpmu` (and `btm`) carry `function-suspend_helper` = pmgr `S2RT`. In `AppleSPMIPMU`'s platform-action handler (15.7.1), the sleep path does, in order: schedule the RTC wake alarm (`scheduleRTCWakeAlarm`), one call on another PMU-side object (not decoded), log `pmu go hib (<sleep type>)` (the value is `IOPMSystemSleepType`, 2 by default: "go hib" is only a log line, not a PMU command), then call the suspend helper, i.e. the PMGR's S2RT. `AppleT6020PMGR`'s S2RT is still the single write of 1 to MasterMini `+0x4000` plus the log line "Starting S2R timer", as in 13.5. So the timer is the last PMU step, after the AIC quiesce; Aura writes it before masking the AIC. Small order difference, noted, not a lead by itself.
- **Keep-alive bits (T6041 `_enableKeepAlive`): no T6020 counterpart found.** No keep-alive string in the PMGR kexts, no `+0x1dc000`/`+0x50000` window and no 32-word stride-`0x44` loop in `ApplePMGR` or `AppleT6020PMGR`. Most likely a T6041-only step. Dropped from the list unless the M4 Pro code shows it is generic.
- **Power-gate sleep depth and retention.** `ApplePMGR::_setPSLevel` calls `_setPwrGateSleepDepth`/`_setPwrGateRetention` on each power-state change when the domain's ADT `power-domains` record has flag bit 0 or bit 2. On J414s all 57 records have flags 0, so that path does nothing on T6020. The `PwrGateRetentionV2` write in the default branch is still open (its table is not from the pmgr node).
- **SMC AP watchdog deadline.** J414s ADT `wdt`: reg[2] = `0x9e2a002c` (Linux `0x29e2a002c`), `reconfig-wdog-support`, `wdt-version` 2, so the 13.5 reading holds: the deadline guards the reconfig (wake) path. Not an entry-side lead.
- **SPMI.** ADT `nub-spmi0` `0x9e114000`, `nub-spmi1` `0x9e154000` (the T6040 code's "NOTIFY_ENABLE 0x2000001 on both controllers' +0x40" maps to these); the PMU is `spmi-mpmu` on nub-spmi0 (`info-has_slpsmc` 1, `info-leg_scrpad` 0x6000, the scratch our crumbs use). Whether 15.7.1 writes `+0x40` at sleep is the next thing to look up in `AppleSPMI`.

## 2026-11-10 21:39 GH-5: SPMI notify enable, the one M4 Pro entry step with a T6020 match; image 66 and job R17E built, not armed
- **What T6040 does** (aurora-silicon `t6040-sleep.c`, marked "HW"): right before its quiesce and the S2R timer, WD0 off, WD2 armed, the SMC AP deadline 0, PMU boot stage `0x50`, then **NOTIFY_ENABLE (`+0x40`) := `0x2000001` on both PMU SPMI controllers**.
- **T6020:** macOS 15.7.1's `AppleSPMI` has the same `0x2000001` in each of its three per-SoC controller configs (one field next to the queue setup). On main, read-only now: `0x29e114040` (nub-spmi0, the PMU) = **0**, `0x29e154040` (nub-spmi1, spmi-spmu) = **0**, `0x29e114080` (NOTIFY_ACK) = 1. So Linux runs with notifications off, and nothing in our entry turns them on. If the SoC's sleep sequencer has to hear from the PMU over SPMI to finish the S2R entry, that would give exactly our symptom (the timer is taken, the entry never completes, the timer resets). The controller layout is the old one (no `gen` in the ADT: status `+0x00`, cmd `+0x04`, reply `+0x08`), the same as T6040's code assumes.
- **Aura `7f8a122e`** (`v0.1.0-17`, patch `0009`): `PSCI_S2R_SPMINOTIFY` = bit 23 (`0x800000`). In the quiet commit, after the last crumb (`0x16`), it writes `0x2000001` to both words and keeps the read-back in `psci_dbg2[46]` (lost on a reset; it only helps if Linux resumes). nub-spmi1's page joins the runtime MMIO map. `aura-ctl` now accepts bits 0 to 23.
- **Image 66** `~/Work/psci-test/boot-test.bin.66` `be46a11e5cd24846`, **not staged** (image 65 still is). Without bit 23 it behaves as image 65.
- **Job `r17e-commit-spmi`**: R17D + `0x800000` (aura-ctl `0xfdcb1f`), checks stage 2 `7f8a122e`, WD1 left armed. To run when reboots are allowed: `sudo bash harness/usbtest/bootbin.sh test ~/Work/psci-test/boot-test.bin.66`, then `arm.sh --chain --job harness/usbtest/jobs/r17e-commit-spmi --label R17E`. Outcomes as R17D: reset about 76 s after the commit push = no change; 110 to 130 s = WD1 (the step changed the commit); "R17E resumed" = it slept and woke.
- **Order proposed for the next reboots:** R17E first (one write, its own variable), then R18D (the SEP idle word), then both together.

## 2026-11-10 22:37 GH-5: reboots allowed again (owner); image 66 staged, run R17E armed
- Work stopped from 21:40 to 22:05 (usage limit). The owner then said reboots are fine again.
- Image 66 (`be46a11e5cd24846`, Aura `7f8a122e`) staged. **R17E armed**: R17D + NOTIFY_ENABLE `0x2000001` on both PMU SPMI controllers before the commit (aura-ctl `0xfdcb1f`), WD1 left armed. Outcomes: reset about 76 s after the "committing" push = no change; 110 to 130 s = WD1; "R17E resumed" = it slept and woke. R18D (the SEP idle word) follows.

## 2026-11-10 22:41 GH-5 run R17E: SPMI NOTIFY_ENABLE on before the commit, the same reset; R18D armed
- Armed 22:38:01, "R17E committing" 22:38:39 (aura-ctl `0xfdcb1f` read back on image 66, the job checks stage 2 `7f8a122e`), main's kernel started 22:39:55: 76 s after the push, as every R17 run. Away 121 s, no "resumed" push, WD1 did not fire first. PMU scratch: R17D's bytes (`0x600c` 00, `0x6011` 40).
- The write's read-back (`psci_dbg2[46]`) is lost with the reset, so that it took is not shown; the code path is the quiet commit's, after crumb `0x16`, which was reached.
- **So NOTIFY_ENABLE on the two PMU SPMI controllers is not what the entry waits for either.** The M4 Pro entry steps with a T6020 counterpart are now all tried.
- **R18D armed** on image 66 without bit 23 (aura-ctl `0x7dcb1f`, i.e. R17D's entry): the job now accepts stage 2 `b22c3766` or `7f8a122e`. It waits for the enclave's idle word (`0x1000030f`) before the SLEEP and again after it, and stops if it is not idle after the SLEEP. Pushes "R18D sep bound", "R18D sep asleep", "R18D committing". Outcomes as before: reset about 76 s after the commit push = no change; about 35 s = a panic in the suspend path; 110 to 130 s = WD1; "R18D resumed" = it slept and woke. The boot can take up to 2 min longer than the others (the waits).

## 2026-11-10 22:44 GH-5 run R18D: after SLEEP the enclave holds its power floor up, so the host has to lower it; R18E armed
- Armed 22:41:08, back after 120 s; the job stopped before the suspend, as designed (no commit, no crumbs).
- "R18D sep bound": `ps_sep` `0x1f0000ff` before the driver, **idle (`0x1000030f`) 20 s after the bind**. SLEEP sent then: `reply tag 0xd data 0x0`, freezer pass rc 0.
- **After the SLEEP the word read `0x1f0003ff` and stayed there for the 32 s watched** (floor f, actual state f). So the SLEEP does not let the enclave be gated: it does the opposite, the enclave pins its domain on and waits. R18C's reading was the same state, not start-up work.
- That gives macOS's next step its meaning (maralcbr's 15.6.1 trace): after the SLEEP ack macOS itself writes `0x1000030f`, i.e. **the host lowers the floor to 0** and the PMGR may then gate the enclave. R18B did that, with the mailbox's OUTBOX_CTRL step, and panicked; which of its accesses faulted is not known.
- **Job `r18e-commit-sep-psoff`:** R18D up to the SLEEP ack, then `ps-sep-write 0x1000030f` (new `harness/mmio/ps-sep-write.c`: one write to `0x290280c00` through `/dev/mem`, nothing else), the word read at 200 ms steps and after 4 s, a push "R18E sep word written", then R17D's commit if the floor stayed 0. No mailbox access after the SLEEP, the SEP hwrng out of use. A panic reboots the Mac 10 s later.
- Outcomes after "R18E committing": reset about 76 s later = no change; about 35 s = a panic in the suspend path; 110 to 130 s = WD1; "R18E resumed" = it slept and woke.

## 2026-11-10 22:48 GH-5 run R18E: the host's `ps_sep` write alone does not lower the enclave's floor; R18F armed
- Armed 22:44:38, back after 93 s; the job stopped before the suspend, as designed (no commit, no crumbs).
- Bound and idle (`0x1000030f`) 20 s after the bind, SLEEP acked (`reply tag 0xd data 0x0`), the word `0x1f0003ff` right after and 2 s later, as R18D.
- **`ps-sep-write 0x1000030f`: `0x1f0003ff -> 0x1f0000ff`**, and `0x1f0000ff` at 200 ms steps for 1 s and at 4 s. So the write took nothing but the two flag bits (8, 9: write-1-to-clear); the floor (f), the target and the actual state stayed. `0x1f0000ff` is the word's value before the driver loads. No panic: so R18B's panic was not this write but its OUTBOX_CTRL access (in the driver, with the mailbox in use) or the hwrng.
- Reading: while the enclave holds its floor, the host cannot lower it through this word. macOS's order after the SLEEP ack is the mailbox's OUTBOX_CTRL enable cleared first, then `0x1000030f`. The enclave may drop its floor once its outbox is shut (nothing more to send), or some other step releases it.
- **Job `r18f-commit-sep-outbox`:** R18E up to the SLEEP ack, then `sep-outbox-off` (new `harness/mmio/sep-outbox-off.c`: clears bit 0 of `0x396408114` through `/dev/mem`, nothing else), the word watched for 1 s, push "R18F sep outbox off", then `ps-sep-write 0x1000030f`, push "R18F sep word written", then R17D's commit only if the word reads `0x10…`. Pushes in order: "sep bound", "sep asleep", "sep outbox off", "sep word written", "committing". If the Mac comes back after "sep asleep" with no "outbox off" push, the OUTBOX_CTRL write panicked (back 10 s later).
- Outcomes after "R18F committing": reset about 76 s later = no change; about 35 s = a panic in the suspend path; 110 to 130 s = WD1; "R18F resumed" = it slept and woke.

## 2026-11-10 22:52 GH-5 run R18F: OUTBOX_CTRL off makes the enclave drop its floor, the word reaches macOS's value; Linux's suspend then dies before Aura
- Armed 22:48:16. "sep bound" (idle after 20 s), "sep asleep" (SLEEP acked, word `0x1f0003ff`), then:
- **`sep-outbox-off`: OUTBOX_CTRL `0x00021101 -> 0x00021100`, and `ps_sep` read `0x1000070f` 200 ms later** (floor 0, target 0, actual 0, flag bit 10 set) and stayed. No panic. So the enclave releases its floor as soon as its outbox is shut: this is the step that lets it be gated, and it is why macOS does it before the word write.
- **`ps-sep-write 0x1000030f`: `0x1000070f -> 0x1000030f`**, stable for 4 s. The SEP is now as macOS has it at sleep entry: SLEEP acked, outbox off, word `0x1000030f`.
- "R18F committing" 22:49:14 (aura-ctl `0x7dcb1f`). Main's kernel started 22:50:23: **69 s after the push** (every R17 run: 76 s). Away 134 s, no "resumed" push.
- **PMU scratch: no crumbs at all** (`0x6004` 00, `0x6011` 00; zeroed before the run) and the boot-stage byte `0x6003` is `0x30`, not the `0x50` the entry sets. So `echo mem` never reached Aura's `SYSTEM_SUSPEND`: Linux's suspend path died first (a hang or a panic in a callback, most likely `apple_sep`'s or the mailbox's with the outbox off), and the reset 69 s later is not the S2R timer. Not WD1 either (120 s). What reset it is not known (a panic late in a timeout chain plus `panic=10` fits).
- So the SEP hand-off works from the host; what is wrong is doing it while Linux's driver still has to go through suspend. macOS does it late, after its drivers are quiet.
- **Job `r18g-sep-ladder`** (armed next): the same SEP steps, then no commit: pm_test levels `devices`, `platform`, `processors`, `core`, each a suspend to that depth and back after 5 s, a push "R18G level X done" after each with the `PM:`/`apple_sep` lines. The last push that arrives names the phase that dies. Back by itself in 2 to 4 min.
- **After it: image 67**, the two writes (OUTBOX_CTRL bit 0 off, `ps_sep` := `0x1000030f`) in Aura's quiet commit behind a new aura-ctl bit 24, with the SLEEP still sent from Linux (R18C's path, which reaches Aura).

## 2026-11-10 22:55 GH-5 run R18G: the first pm_test level never reports; both resets are 74 to 75 s after the outbox went off
- Armed 22:52:16. The SEP steps as R18F to the second (outbox off 22:53:09, word `0x1000030f` 22:53:13). Then `pm_test=devices` + `echo mem`: **no "level devices done" push**, main's kernel started 22:54:24, away 135 s. No crumbs (none expected: no commit).
- Timing, both runs: R18F outbox off 22:49:09, reset 22:50:23 = 74 s; R18G 22:53:09 to 22:54:24 = 75 s. From the start of the suspend 69 and 71 s. The two are not separable yet: either the device-suspend phase hangs and something resets the Mac about 70 s on, or the Mac resets about 75 s after the outbox goes off whatever Linux does (the enclave wakes about once a minute, S3; with its outbox shut or its domain gated that wake may be fatal), and the missing push is only the network being down in the suspend.
- R18F's finding stands either way: `echo mem` did not reach Aura in 69 s, where every R17 run reaches the commit within seconds. So Linux's device suspend does stall with the SEP in this state.
- **Job `r18h-sep-idle-watch`** (armed next): the same SEP steps, then no suspend at all: a push every 10 s for 150 s with `ps_sep`, OUTBOX_CTRL and the SEP/mailbox kernel lines. A reset at about 75 s = the SEP state alone kills a running system (so in the real entry the two writes belong at the very end, in Aura, seconds before the power-down); still up at 150 s = it is Linux's suspend that dies.
- Then image 67 as planned (the two writes in Aura's quiet commit, aura-ctl bit 24).

## 2026-11-10 23:01 GH-5 run R18H: Linux hangs within 10 s of the SEP hand-off, suspend or not; image 67 (the hand-off in Aura's commit), R18I armed
- **R18H** (armed 22:55:47): the SEP steps as before (outbox off 22:56:39, word `0x1000030f` 22:56:44, that push arrived), then no suspend, a push every 10 s. **Not one watch push arrived**; main's kernel started 22:57:53, 74 s after the outbox went off, as R18F (74 s) and R18G (75 s).
- The test root has `RuntimeWatchdogSec=60`, so the reset is systemd's watchdog: the last kick was at about +14 s, and the whole system (PID 1 included) hung between +5 s (the last push) and +14 s. No panic (`panic=10` would have been back sooner).
- **So with the outbox off and `ps_sep` at `0x1000030f`, a running Linux hangs within 10 s, whatever it is doing.** R18F's missing crumbs and R18G's missing level are that hang, not the suspend path. Why it hangs is not known (the enclave gated under a kernel that still uses it; a mailbox interrupt that can no longer be delivered). It does not matter for the entry: macOS does these two steps last, and so must we.
- **Aura `6cbae457`** (`v0.1.0-18`, patch `0010`): `PSCI_S2R_SEP` = bit 24 (`0x1000000`). In the quiet commit, after the cores are released and before the crumb snapshot: OUTBOX_CTRL (`0x396408114`) bit 0 off, poll `ps_sep` up to 500 ms for floor 0 (`0x10……`), write `0x1000030f`, read back. Crumb `0x6011` gains bits: `+0x10` the step ran, `+4` the outbox enable did not clear, `+8` the word is not `0x10….0f`; with the PMP step `0x50` = all as macOS. The mailbox page joins the runtime MMIO map (`ps_sep` is on `ps_sio`'s page, already there). `aura-ctl` accepts bits 0 to 24; `tools/pmu-scratch.sh` decodes the byte.
- **Image 67** `~/Work/psci-test/boot-test.bin.67` `87a7c21fe4786ff1`, staged. Without bit 24 it behaves as image 66.
- **Job `r18i-commit-sep-aura`:** R18C's Linux side (idle word, hwrng out of use, SLEEP in a freezer pass, pushes "sep bound" and "sep asleep") then R17D's commit with aura-ctl `0x17dcb1f`. Outcomes after "R18I committing": reset about 76 s later = no change (then `0x6011` says whether the SEP step took); about 35 s = a panic in the suspend path; 110 to 130 s = WD1; "R18I resumed" = it slept and woke.

## 2026-11-10 23:06 GH-5 run R18I: Aura stops at the SEP step when it comes after the PMGR quiesce; image 68 (the step first), R18J armed
- Armed 23:01:09, "sep bound", "sep asleep" (SLEEP acked), "R18I committing" 23:02:01 (aura-ctl `0x17dcb1f` read back on image 67). Main's kernel started 23:04:16: **135 s after the push**, away 194 s. Not the 76 s of the S2R timer: WD1's reset (120 s).
- **PMU scratch: last stage `0x17`** ("before the secondaries are released"), no `0x16`, and none of the snapshot's bytes (`0x6005` to `0x6007`, `0x6011` all 0). The SEP step sat between the release and the snapshot, so Aura hung in it or at the first SPMI write after it, before the timer was written.
- Reading: by that point the PMGR quiesce has run (held domains, domains, clocks). The mailbox at `0x396408000` most likely has its bus power or clock off by then, so the first access to OUTBOX_CTRL never returns. From Linux the same access works because everything is still on.
- **Aura `d293ee5b`** (`v0.1.0-19`, patch `0011`): the SEP step is now the **first** step of the quiesce, before `psci_quiesce_held`, with crumb `0x18` before it and `0x19` after. `0x6011` still carries its result at the snapshot. This is still milliseconds before the commit, with Linux done and interrupts masked.
- **Image 68** `~/Work/psci-test/boot-test.bin.68` `cf6d090a58b7a236`, staged. **Job `r18j-commit-sep-first`** = R18I on it.
- Outcomes after "R18J committing": about 135 s and crumb `0x18` = the mailbox access itself hangs from Aura (then the map or the access is wrong); crumb `0x19` or later with a 135 s reset = a later step hangs with the SEP gated; reset about 76 s with `0x6004` 16 and `0x6011` 50 = the SEP is as macOS has it and the entry still does not complete; "R18J resumed" = it slept and woke.

## 2026-11-10 23:10 GH-5 run R18J: Aura still stops inside the SEP step; the cause is the mailbox read after the enclave is gated; image 69, R18K armed
- Armed 23:06:09, "R18J committing" 23:07:01 (aura-ctl `0x17dcb1f` on image 68), main's kernel started 23:09:15: 134 s after the push (WD1), away 193 s. **Last crumb `0x18`**: Aura entered the SEP step, now the first of the quiesce, and never left it.
- So the order was not the cause (R18I's reading was wrong). Inside the step the accesses are: OUTBOX_CTRL write, `ps_sep` polls, `ps_sep` write, then **OUTBOX_CTRL read again** (twice, for the crumb and the debug word). By then the enclave has dropped its floor and the PMGR has gated it (`0x1000070f`, actual state 0, within 200 ms in R18F). The mailbox at `0x396408000` sits in the enclave's domain: once gated it does not answer, and the read never returns.
- **That is also the Linux hang of R18F to R18H:** R18H's watch read `0x396408114` at +10 s through `/dev/mem`, and in R18F/R18G the suspend path's mailbox or SEP callback touched it. In R18F the tool's own read-back worked only because it came microseconds after the write. So "Linux hangs within 10 s" was our own access, not something the SEP state does to a running system.
- **Aura `a0538eee`** (`v0.1.0-20`, patch `0012`): OUTBOX_CTRL is read back right after the write (kept for the crumb), and nothing touches the mailbox afterwards. The step stays first in the quiesce.
- **Image 69** `~/Work/psci-test/boot-test.bin.69` `4b4e9c451e302614`, staged. **Job `r18k-commit-sep-nomailbox`** = R18I on it.
- Outcomes after "R18K committing": reset about 76 s with `0x6004` 16 and `0x6011` 50 = the SEP as macOS has it, the entry still does not complete; about 135 s = Aura hung again (the crumb says where); "R18K resumed" = it slept and woke. A resume would meet a gated enclave: Linux's mailbox resume may then hang, which the 120 s watchdogs cover.

## 2026-11-10 23:14 GH-5 run R18K: the SEP exactly as macOS has it at the commit, and the same S2R-timer reset; R18L armed
- Armed 23:10:43, "sep bound", "sep asleep", "R18K committing" 23:11:35 (aura-ctl `0x17dcb1f` on image 69). Main's kernel started 23:12:50: **75 s after the push**, as every R17 run. Away 134 s, no "resumed".
- **PMU scratch:** `0x6004` 16 (the commit's last access), every core slept, wait 6 ms, EACC/PACC0/PACC1 `10/10/50`, `0x600c` 00, and **`0x6011` = `50`**: the SEP step ran, OUTBOX_CTRL read back with the enable off, `ps_sep` read `0x10….0f` after the write, `pmp` and `pms_sram` off. So image 69's step works: the hang of images 67 and 68 was the mailbox read after the gate, as read.
- **So the enclave asleep and gated, as macOS has it, does not let the SoC power down either.** With this, every word of macOS's sleep-entry power map (maralcbr's 15.6.1 trace, `data/psmap.txt`) that ours left different has been matched: USB-C, PCIe, the AON-side words, `msg`, `pmp`, `pms_sram`, SEP. Plus the SPMI notify enable. The result has not moved once: the timer is taken, the entry does not complete, the timer resets 75 to 76 s after the push.
- What that says: the blocker is not a domain left on. Left on the list: (1) the order and place of the last writes: macOS fires the S2R timer from the PMU driver after the AIC quiesce and with its own SPMI traffic around it, ours writes it three times from Aura with the AIC already masked; (2) `PwrGateRetentionV2`; (3) cluster APSC off (R20, the only run with no timer reset, hung; R20b attended only); (4) whatever the PMP/SMC is told that we do not send (`slpa` is sent; the T6020 SMC sleep keys beyond it are not checked against 15.7.1).
- **R18L armed:** R18K + bit 23 (SPMI NOTIFY_ENABLE), aura-ctl `0x1fdcb1f`: the two last additions together, one reboot. Same outcomes.

## 2026-11-10 23:17 GH-5 run R18L: the SEP hand-off and the SPMI notify enable together, the same reset
- Armed 23:14:09, "R18L committing" 23:15:01 (aura-ctl `0x1fdcb1f` on image 69), main's kernel started 23:16:16: 75 s after the push. Scratch as R18K (`0x6004` 16, `0x6011` 50).
- So the two do not combine into anything. The power-map line of work is finished: no reboot is armed. Next is reading, not running: the last writes of macOS's entry on T6020 (where the PMU driver fires the timer relative to the AIC quiesce and its SPMI traffic), `PwrGateRetentionV2`, and the SMC sleep keys, in the 15.7.1 kernelcache.

## 2026-11-11 03:00 GH-5: macOS 15.7.1's PMU driver and retention code hold no missing step; image 70 and job R20b (APSC off late) built, not armed
- The headers of the eight entries above (R18E to R18L) ran a few minutes ahead of the clock; they now carry their commit times. Work stopped from 23:22 to 03:00 (usage limit).
- **Kernelcache again, kept this time:** `~/Work/macos-re-work/kc/` (15.7.1 fileset `kc.1571.macho`, J414s ADT `dt.j414s.adt` from `boot/<hash>/usr/standalone/firmware/devicetree.img4`), read with `tools/macos-preboot-read.sh` (mounted read-only, unmounted after each copy).
- **`AppleSPMIPMU` sleep action, whole:** read the VBUS detect function, schedule the RTC wake alarm, disable one of its own event sources (the undecoded call of 21:36: field `+312`, re-enabled on wake), log `pmu go hib`, call `function-suspend_helper` (the PMGR's S2R timer). `info-has_slpsmc` is only read in the shutdown path. **No PMU register is written for sleep beyond the alarm.** Lead (1) is down to the order alone (the timer after the AIC quiesce).
- **`PwrGateRetentionV2`:** its table (16-byte records: reg, on value, off value) is filled from a `retention_config_ff` property, and the related ones are `conditional-retention-*`, `require-conditional-retention`, `pwrgateretention-workaround`, `device-check-ps-b4-sleep`. **None of them is in the J414s ADT** (its pmgr node has only `ps-regs`, `perf-regs`, `pwrgate-regs`). Lead (2) is closed: nothing to write on T6020.
- `SLP_S2R`, `SLP_DDR`, `AWAKE` in `ApplePMGR` are only names for its state statistics.
- **What is left is lead (3), the cluster APSC disable.** macOS sets it (CLUSTER_PSTATE bit 23) before the timer, and R20 (image 61) is the only run where the timer's reset did not come; but R20 did it before the secondaries' release, so most of them never slept, and it ran with WD1 off.
- **Aura `8b6229e3`** (`v0.1.0-21`, patch `0013`): `PSCI_S2R_DVFSLATE` = bit 25 (`0x2000000`): the same APSC step run after the secondaries have slept and the snapshot is taken, right before the commit. Crumb `0x6004` = `1b` instead of `16` when it ran. Undone on resume as bit 17's.
- **Image 70** `~/Work/psci-test/boot-test.bin.70` `1b771ed7c079cad5`, not staged. **Job `r20b-commit-apsc-late`**: R18K + bit 25 (aura-ctl `0x37dcb1f`), WD1 armed. Outcomes: reset about 76 s after the push = no change; 110 to 140 s = WD1, i.e. APSC off stops the timer's reset; "R20B resumed" = slept and woke; no return = power has to be held.
- **Plan (owner, 03:00: more may run unattended, never stop for permission):** R20b can leave the Mac down until someone holds power, which would end the night's work, so it runs last, about 06:30. Until then: issue #12 (PMP), whose test boots recover by themselves.

## 2026-11-11 03:05 issue #12 (PMP): m1n1 PR 63 and the PR 933 DTB built; run P12A armed
- **m1n1** `2c324f27` (PR 63 head, `pmp-tunables-fit`), `~/Work/src/pmp-check/m1n1/build/m1n1.bin` (4325376 B). The `aura-build` container's GCC cannot link it (`__popcountdi2` from `mcc.c` and the GPU files; its Rust has no `rust-src` either), so: `librust.a` from the container (with `rustup component add rust-src` inside the throwaway container), the C side with the host's clang 23.1.4 and lld (`make RELEASE=1 USE_CLANG=1 TOOLCHAIN=/usr/bin/ LLDDIR=/usr/bin/`).
- **DTB** `t6020-j414s.dtb` from linux PR 933's head `8f590c4d` (sources by `git archive`, cpp + the kernel tree's dtc, no `-@`): `~/Work/src/pmp-check/t6020-j414s.pr933.dtb`, 114995 B, sha256 `524e185e5e1d94f2af39c6a90cb6ab8de9be99ee887727447efa4b521d287b76`. Its PMP node is `status = "disabled"` in the file; m1n1 enables it once the tunables are in.
- **Image** `~/Work/psci-test/boot-test.bin.p12a` `a2684f8d0d94681a` (m1n1 in Aura's place, the DTB at index 31, the same U-Boot), staged.
- **Job `p12a-pmp-m1n1-pr63`** (steps 1, 3 and 4 of the issue's list in one boot): the PMP node as m1n1 left it (status, tunable count and bytes, FDT total and used size = the headroom), the kernel's PMP lines, the `pmp-*` domains, warnings and errors, then 10 s2idle cycles (RTC alarm, 20 s) with display, Wi-Fi ping and USB after each. The test kernel is the DeepTest root's (not 933's own build); main's 7.2.11 warnings saved as the baseline (`~/Work/src/pmp-check/main-7.2.11-dmesg-warn.txt`, 723 lines). m1n1's own console lines cannot be captured (no serial); the FDT it hands over is the evidence.
- No S2R step and no MMIO write: a boot that fails ends at the 120 s watchdog and returns to main. Expected away about 9 min.

## 2026-11-11 03:07 issue #12 run P12A: m1n1 PR 63 boots the PR 933 DTB with the PMP on (step 1 done); the s2idle part needs 933's own kernel and a wake source
- Armed 03:04:44, back on main 03:06:02 (away 78 s). The job stopped itself before the cycles (below).
- **Step 1 (m1n1 PR 63, `2c324f27`): passed.** `/chosen/asahi,m1n1-stage2-version` = `2c324f27`; the payload (U-Boot, then the kernel) started; the PMP node arrived `status = "okay"` with **81 `apple,tunable-*` properties, 11896 bytes of values**; `apple_pmp 28e700000.pmp: PMP firmware and endpoint ready` at 0.55 s. So no "failed to transfer pmp tunable" and no "Failed to prepare FDT" (either would have stopped the boot in proxy mode).
- The headroom cannot be read from Linux: the FDT m1n1 hands over is packed (total size 218665 = used size). m1n1's console lines are not captured (no serial on this setup).
- `pmp-*` domains: `pmp-disp0`, `pmp-dispext0`, `pmp-dispext1`, `pmp-isp-sys` on, `pmp-avd-sys` off, `pmp` on. `PM domain pmp-isp-sys will not be powered off` present, as expected. 27 warning/error lines at boot (not kept: see below).
- **Two things this boot could not do:**
  - `pmgr-misc "PMP manages fabric and DCS p-states"` did not appear. The 933 DTB's node is `compatible = "apple,t6020-pmgr-misc"` alone, and only 933's own tree (7.3.0) has a `t6020` entry in `apple-pmgr-misc.c`; the DeepTest kernel (7.2.11-psci-efi+) and main's 7.2.11-15 match only `apple,t6000-pmgr-misc`. Steps 3 and 4 therefore need a kernel built from the 933 branch, not just its DTB.
  - No `/sys/class/rtc/rtc0/wakealarm`: the PMU alarm is this repo's test addition (driver patch and `rtc-alarm` nvmem cells), absent from 933. Unattended s2idle cycles need it (the issue allows "RTC wake alarm or lid").
- Also: in chain mode there is no results drive, so the job's files (`/run/usbtest/results`) are lost. The next job pushes what matters as text.
- **Next:** build 933's kernel (`8f590c4d`, 7.3.0) with the test root's config, plus the RTC alarm patch (inert without its DT cells); run P12B = that kernel + the pure 933 DTB (PMP lines, domains, warnings against 7.2.11), then P12C = the same with the alarm cells added to the DTB for the 10 cycles. R20b stays planned for about 06:30.

## 2026-11-11 03:20 issue #12 run P12B: PR 933's own kernel (7.3.0) on its DTB under m1n1 PR 63: all three PMP lines, 16 warning lines
- Kernel built from PR 933 (`8f590c4d` + the two T602x RTC alarm commits, `7.3.0-pr933+`, the test root's config, `~/Work/src/linux-pr933`); modules in `/usr/lib/modules/7.3.0-pr933+` and in the test root (image `c674520d52fc965d`, which keeps both 7.2.11 trees); UKI `62e491c574842374` (`deeptest.efi.pr933`; the S2R one is kept as `deeptest.efi.psci-6ee0da2a`).
- Armed 03:18:25, back 03:19:41 (away 76 s). Stage 2 `2c324f27`, pure PR 933 DTB (image `p12a`).
- **PMP lines, all present:** `apple-pmgr-misc 28e20c000.power-management: PMP manages fabric and DCS p-states` (0.07 s), `apple-dart 3860e8000.iommu: PM domain pmp-isp-sys will not be powered off`, `apple_pmp 28e700000.pmp: RTKit: Initializing (protocol version 12)`, `PMP firmware and endpoint ready` (4.95 s, the module's load), `RTKit: syslog message: io.cpp:41: PMP started`. Node `okay`, 81 tunables, 11896 bytes.
- Domains: `pmp-disp0`, `pmp-dispext0`, `pmp-dispext1`, `pmp-isp-sys` on, `pmp-avd-sys` off. cpufreq: 3 `apple-cpufreq` policies.
- **Warnings and errors at boot: 16 lines**, of which the test root's own messages are 7, systemd's two `LoaderSystemToken` lines, and from the kernel: `PM domain pmp-isp-sys will not be powered off`, `watchdog: watchdog0: watchdog did not stop!` (the test root keeps the dog armed on purpose) and `ane_t6021 284000000.ane: error -ENODEV: firmware preflight failed` (main's 7.2.11 fails the same preflight: the ANE firmware is not installed). Nothing from the PMP, RTKit, DCP or the fabric.
- No wakealarm, as expected for the pure DTB. **Next: P12C** (image `p12c` `98558a46cff1d363`: the same plus the alarm cells) for the 10 s2idle cycles.

## 2026-11-11 03:27 issue #12 run P12C: 10 of 10 s2idle cycles pass on PR 933's kernel with the PMP on (steps 3 and 4 done)
- Armed 03:20:39, back 03:26:46 (away 367 s). Same kernel and stage 2 as P12B; DTB = PR 933's plus only the T602x RTC alarm cells (image `p12c` `98558a46cff1d363`), so the wake source is the PMU alarm.
- Boot: PMP node `okay`, 81 tunables, ready line, `PMP manages fabric and DCS p-states`, 16 warning lines as in P12B.
- **Cycles (20 s alarm each):** asleep 20.2, 19.9, 20.1, 20.0, then 19.9 s six times; `echo mem` returned 0 every time; eDP `connected/enabled`, backlight 140; Wi-Fi answered a ping on the second try (about 2 s after wake) every time; USB device count 3 throughout; **0 new warning or error lines in every cycle**.
- After the cycles the `pmp-*` domains are as at boot (`pmp-disp0`, `pmp-dispext0`, `pmp-dispext1`, `pmp-isp-sys` on, `pmp-avd-sys` off).
- The run log's per-cycle lines did not come back (the closing push is over ntfy's size limit, and a chain boot has no results drive); the table above is from the job's own summary push.
- Issue #12 now has steps 1, 3 and 4. Left: the optional fit check, the aura port as stage 2 (aura here already carries the fit fix), results to linux #933.
- **Next: S2R run R20b** (image 70, APSC off late), WD1 armed, with the S2R UKI put back.

## 2026-11-11 03:33 run R20b (APSC off late, image 70): the 75 s timer reset did not come; Aura stopped inside the APSC step; image 71 and R20c
- Run brought forward from 06:30 (owner notified at 03:27); the S2R UKI `6ee0da2a` put back, root image `c674520d52fc965d` (now with three module trees).
- Armed 03:27:58, "sep bound" 03:28:43, "sep asleep" 03:28:50, **"R20B committing" 03:28:51** (aura-ctl `0x37dcb1f` read back). Main's kernel started 03:31:05: **134 s after the push**, the WD1 window (R17 to R18L: 75 s). No "resumed". It came back by itself.
- **PMU scratch: `0x6004` = `17`**, neither `16` nor `1b`; the snapshot bytes are there and are R17's (CPU_OFF `077e`, never slept `f880`, wait 6 ms, ECPM/PCPM0/PCPM1 `1f/10/00`, cluster words `10/10/50`, `0x6011` 50). So the secondaries slept as before, the snapshot was written, and **Aura never got out of `psci_quiesce_dvfs()`**: the next crumb (`1b`) was not written, and the timer was not started (no 75 s reset).
- Reading: the step reads and writes CLUSTER_PSTATE of all three clusters, and at that point both P complexes are power-gated (the snapshot). An access to a gated cluster's block most likely never returns. R20 (image 61) did it while everything was still on, which is why it got through there. A second reading cannot be excluded from this run alone: the step finished, and it is the SPMI crumb write that hangs once the E cluster's APSC is off.
- The loader flag read `ff` at the return (it reads `00` after the earlier runs); main cleared it. Noted, not followed up.
- **Aura `80360e1c`** (patch `0014`): the late step touches only the clusters whose complex reads on (in practice the boot core's E cluster), saves the others as skipped for the undo, and writes crumb `1c` before the step (`1b` after it, as before). **Image 71** `~/Work/psci-test/boot-test.bin.71` `8fd4f0ccfc4062e0`. **Job `r20c-commit-apsc-late-ecl`**, same ctl word.
- R20c tells the two readings apart: `1c` = hangs on the E cluster too (or at the crumb write); `1b` + 75 s = APSC on the E cluster does not matter; `1b` + about 134 s = the timer's reset is stopped by it.

## 2026-11-11 03:36 run R20c (image 71, APSC off late on the powered E cluster only): the step runs, the same 75 s reset; the APSC lead is closed
- Armed 03:33:25, **"R20C committing" 03:34:18**, main's kernel started 03:35:33: **75 s after the push**, the S2R timer's reset as in R17 to R18L. Away 136 s, no "resumed".
- **PMU scratch: `0x6004` = `1b`**: the late step was entered (`1c`) and finished, then the commit. Snapshot as always (CPU_OFF `077e`, never slept `f880`, ECPM/PCPM0/PCPM1 `1f/10/00`, `0x6011` 50).
- So R20b's first reading was the right one: image 70 hung on a gated P cluster's CLUSTER_PSTATE, never wrote the timer, and WD1 reset it at 134 s. The missing 75 s reset there was only the missing timer write.
- **With APSC off on the one cluster that is still powered, the reset is unchanged.** The P clusters are gated by then, so their APSC bit cannot matter at the commit; R20's (image 61) missing reset is explained the same way as its hang: the secondaries never slept. Lead (3) is closed.
- **State of the entry:** every step found in macOS's map, the M4 Pro branch and the 15.7.1 PMU and PMGR code has now been done at the commit (domains, clocks, clusters, AMCC, AIC, USB-C, PCIe, AON words, PMP words, SEP hand-off, SPMI notify, APSC), and the timer still ends in its reset about 60 s after it is written. (Corrected at 03:52: the SMC's sleep messages are not unread. `slpw`, `WKTP`, `slpa`, the boot stage and SetAPPower were traced and are sent since run L; see the next entry.)

## 2026-11-11 03:52 GH-5: a step every earlier pass missed: macOS clears each core's EDPRCR before its deep WFI; image 72, run R21 armed
- **Correction to the R20c entry.** It named the SMC's sleep messages as unread. They are not: `MBSE` = `slpw`, `WKTP` = 2, the PMU boot stage `0x50`, `MBSE` = `slpa` and SetAPPower `0x201` have been sent since run L (2026-11-06). 15.7.1's `AppleSMC` was read again now (`~/Work/macos-re-work/kc/smc.s`): the same keys, `slpa` or `hiba` chosen by the sleep type, nothing new for the entry.
- **Where the new lead came from.** aurora-silicon's M4 Pro sleep code (linux PR 1477, re-fetched) has, in every core's last steps, "unlock its external debug and clear EDPRCR, as xnu", with the source: `ml_arm_sleep` in xnu's `osfmk/arm64/cpu.c`, "tell debugger to not prevent power gating". The 2026-11-10 15:50 read of that code listed PMGR steps only and did not pick this up.
- **Checked in macOS 15.7.1's own kernel** (`com.apple.kernel` of the T6020 kernelcache, `kernel.s`): `ml_arm_sleep` writes `0xc5acce55` to `+0xfb0` (EDLAR) and then 0 to `+0x310` (EDPRCR) of the CPU's CoreSight block, at two sites, one before the secondaries' sleep and one on the boot core's path. So the release build does it on this SoC.
- **Why it fits.** EDPRCR bit 0 (CORENPDRQ) asks the core's power controller to emulate power-down instead of removing power. If it is set here, the PMGR's sleep engine sees cores that never really go down: the S2R timer is taken, the entry never finishes, the timer resets the Mac. That is the symptom of every commit run. Nothing in Aura or our kernel has ever touched these blocks.
- **J414s addresses** (ADT `coresight-reg` of the 12 CPU nodes): `0x210010000 + cluster * 0x1000000 + core * 0x100000`, the same layout as T6040.
- **Aura `d93a57cd`** (`v0.1.0-23`, patch `0015`): `PSCI_S2R_EDPRCR` = bit 26 (`0x4000000`). Each released secondary and then the boot core unlocks its own block and writes EDPRCR := 0 right before its deep WFI (only a core's own block, which is powered while it runs). The debug pages join the runtime MMIO map (the list's limit goes from 64 to 96). Crumb `0x601f`: bit 7 = ran, bits 0-2 = the boot core's CORENPDRQ, CWRR, COREPURQ before the write, bit 3 = read-back not 0, bits 4-6 = the same three bits ORed over the secondaries. `tools/pmu-scratch.sh` decodes it; `aura-ctl` accepts bit 26.
- **Image 72** `~/Work/psci-test/boot-test.bin.72` `f8575276c765d698`, staged. **Job `r21-commit-edprcr`**: R18K + bit 26 (aura-ctl `0x57dcb1f`), stops unless the runtime map holds the debug pages. WD1 armed.
- **Outcomes after "R21 committing":** "R21 resumed" = it slept and the alarm woke it; a reset about 75 s after the push = no change (the crumb then says what EDPRCR held); 110 to 140 s = WD1 (a core faulted on its debug block, or the timer's reset stopped; the never-slept mask tells which); no return = power has to be held.
- Aside: the loader flag `0x6010` read `ff` after R20b and R20c because the crumb snapshot writes two bytes at `0x6010` (`ff ff` when every core slept). The loader acts on `a5` only, so it is harmless.

## 2026-11-11 03:54 GH-5 run R21, first try: the job stopped before the suspend (its own check failed); fixed, armed again
- Armed 03:52:28, back on main 03:53:58, away 90 s. Stage 2 `v0.1.0-23-gd93a57cd` (image 72) booted, the SEP slept (reply tag 0xd), then the new check of the runtime MMIO map failed: `find` does not descend `/proc/device-tree` (a symlink), so the property was not found and the job ended, rc 1. No commit, no crumbs. Nothing learned about EDPRCR.
- Fix: the job searches `/sys/firmware/devicetree/base` and stops with a message if the property is missing. Same image, same word (`0x57dcb1f`). Outcomes as in the entry above.

## 2026-11-11 03:57 GH-5 run R21 (image 72, EDPRCR := 0 on every core before its deep WFI): the step ran, the register was already 0, the same 75 s reset
- Armed 03:54:46, **"R21 committing" 03:55:38** (aura-ctl `0x57dcb1f` read back; runtime map 45 ranges with the 10 debug pages), main's kernel started 03:56:53: **75 s after the push**, the S2R timer's reset. Away 135 s, no "resumed".
- **PMU scratch `0x601f` = `80`:** the step ran on the boot core and nothing was set before it: CORENPDRQ, CWRR and COREPURQ read 0 on the boot core and on every secondary, and the boot core's read-back was 0. No core faulted on its debug block: `0x6004` = `16`, every core slept (`0x6007` ff), snapshot as always (CPU_OFF `077e`, ECPM/PCPM0/PCPM1 `1f/10/00`, `0x6011` 50).
- **So no debug power request was holding the cores up.** macOS writes the register, but on this Mac under Aura it is 0 already. The lead is closed. The step is harmless and stays available (bit 26).
- Useful by-product: the secondaries can reach MMIO from their sleep path through the runtime map, and a per-core value can be carried into the crumbs, which the next per-core checks can reuse.


## 2026-11-11 08:02 GH-5: is the reset still independent of the alarm? Runs R22A (alarm +20 s) and R22B (+70 s) on image 72
- The rule "the S2R timer resets the Mac whatever the alarm does" rests on run D2 (2026-11-05), when the cores were still in retention and nothing of macOS's entry was done. Every commit run since used one alarm (+40 s) and came back 75 to 76 s after the push. With the usual 24 s firmware chain that puts the reset about 51 s after the push, 10 s after the alarm, and less than the 60 s D2 measured for the timer. So the times no longer separate the two readings.
- **R22A and R22B are R21 with only the alarm changed.** Main's kernel 75 s after the push in both = the timer, as assumed. A start that moves with the alarm (about 55 s for +20, about 105 s for +70) = the SoC does sleep now and the alarm wake ends in a cold boot, so the work moves to the wake path. 110 to 140 s = WD1.

## 2026-11-11 08:06 GH-5 run R22B (R21 with the alarm at +70 s): the reset does not follow the alarm; R22A not needed
- Armed 08:03:06, **"R22B committing" 08:03:59** (alarm +70 s, due 08:05:09), main's kernel started **08:05:15: 76 s after the push**, as with the +40 s alarm in every run since R17A. Away 136 s, no "resumed". Scratch as R21 (`0x6004` 16, `0x6011` 50, `0x601f` 80).
- An alarm-driven cold boot would have put the kernel start near 08:05:33 or later (alarm plus the firmware chain). It came before the firmware chain could even have started from the alarm. **So in the current state too, the reset is the S2R timer's and the SoC is not asleep when the alarm is due.** Run D2's rule holds with all of macOS's entry steps in place.
- R22A (+20 s) would only repeat this answer; its job stays in the tree, not run.

## 2026-11-11 08:11 status page brought fully up to date (owner asked)
- The page's top text and image list were current, but four parts had fallen behind: Phase 5's summary stopped at R18D, the "PMGR quiesce, S2R timer" piece at run R (2026-11-06), the first open question still said Aura does not do the S2R entry, and there were no findings for today's runs. All rewritten to R22B.
- Percentages reviewed: Phase 3 (macOS trace) 55 to 60 (15.7.1's own kernel and device tree read), Phase 4 (devices) 15 to 20 (USB-C lowered and restored 4 of 4, the enclave gated as macOS has it). **Phase 5 stays 10 and the overall figure stays 45:** no sleep has completed, and closing leads is not progress on the bar.


## 2026-11-11 08:16 GH-5: the observer run. Aura image 73 and job R23: does the boot core's cluster power down after its last WFI?
- **Why.** Every run since R10 changed one input and read the same reset. None measured what happens after the boot core's last instruction: the snapshot is taken by the boot core itself, so its own complex always reads on (ECPM `1f`). The P complexes are seen going off because the boot core watches them; nobody watches the boot core's.
- **Aura `29890b1b`** (`v0.1.0-24`, patch `0016`): aura-ctl bit 27 (`0x8000000`, `PSCI_S2R_OBSERVE`). The highest CPU_OFF core (a P core) is released with the others but does not sleep. It waits for a flag the boot core sets after the three timer writes, then reads the boot complex's power word (`0x28e080060`) for 3 s, then the boot core's EDPRSR (`0x210010314`, bit 0 = core powered), writes the result to the PMU scratch and goes into its own deep sleep. The boot core's snapshot will show that P complex on and the wait timed out (`0x6014` ff): expected.
- **Crumbs:** `0x6004` a1 = the observer saw the commit, a2 = 3 s sampled, a3 = EDPRSR read, af = no commit seen in 5 s. `0x6008` the power word >> 4 at 20 ms, `0x6009` after 3 s, `0x600a` first read off (x 16 ms, ff never), `0x600b` EDPRSR. `0x6008`-`0x600b` have not been shown to survive a reset, so copies go to proven bytes: `0x6012`, `0x6013`, `0x601f`. `tools/pmu-scratch.sh` decodes them.
- **Image 73** `~/Work/psci-test/boot-test.bin.73` `9940c2b16e9177ff`. **Job `r23-commit-observer`**: R21 with aura-ctl `0xd7dcb1f`, stage 2 check `29890b1b`.
- **Readings.** Boot complex still on after 3 s: the boot core's own sleep does not take (something pending on it, or its final sequence), and the work is on that core. Off within ms: the cores are fine and the block is above them (PMGR/SoC level). Stage a1 only: the observer lost SPMI or the PMGR after the commit, itself a sign that something went down. With one P core up the SoC cannot sleep in this run; the timer's reset (75 s, or later since the observer sleeps 3 s after the commit) brings it back, WD1 as the outer net.

## 2026-11-11 08:20 GH-5 run R23 (image 73, the observer): the boot core's cluster powers down within 16 ms of the commit. The block is above the cores
- Armed 08:16:51, "R23 committing" 08:17:45 (aura-ctl `0xd7dcb1f` read back), main's kernel started 08:19:02: 77 s after the push, the timer's reset. Away 138 s, no "resumed".
- **The observer ran to its end (`0x6004` = `a3`)**, so SPMI and the PMGR still answer for at least 3 s after the commit. Its record:
  - boot complex power word (`0x28e080060`) >> 4: **`10` at 20 ms and `10` after 3 s**: actual state 0 (off) with the was-power-gated flag, the same value PCPM0 has shown since R12. First read off in the first 16 ms.
  - boot core EDPRSR: `0` (PU 0, core not powered). Not calibrated yet against a powered core, so on its own it is weak; it agrees with the power word.
- The boot core's own snapshot shows the observer as designed: never-slept core index 10, state CPU_OFF (`0x6007` = `a2`), the P-complex wait timed out (`0x6014` ff). `0x600c` and `0x6011` hold that core's diagnostics in this run, not the PMP/SEP byte.
- `0x6008` to `0x600b` survive the reset: four more usable scratch bytes.
- **So the boot core's last sleep takes, and so does its complex.** The cores are not what holds the entry: 15 runs of "what else does a core or a domain need" were looking below the block. With every complex off the SoC still stays up until the timer resets it, so the missing piece is at SoC level: what the PMGR's sleep engine waits for after the last complex is gone.
- **One doubt this run raised.** The boot core's snapshot read PCPM1's word (`0x28e080070`) as `00` while the observer, a core of that complex (MPIDR cluster 2), was running. Awake it reads `1f`. So `00` there is not proof that P complex 1 is off; in every earlier run it read `00` too. Next run: the observer reads every other core's EDPRSR and all three complex words after the commit, once from each P complex, with its own EDPRSR as the calibration.


## 2026-11-11 08:21 GH-5: Aura image 74, jobs R24A and R24B: the observer reads every core's power bit and all three complex words
- **Aura `d2b4755c`** (`v0.1.0-25`, patch `0017`). After its 3 s the observer writes the three complex words as it reads them (`0x6012` ECPM, `0x6013` PCPM0, `0x601b` PCPM1), its own EDPRSR as the calibration (`0x600a`, PU must be 1), then every other core's EDPRSR: `0x6008/9` = the cores that read powered, `0x600b` = the index being read, written first, `ff` at the end. New aura-ctl bit 28 (`0x10000000`): the observer is the lowest P core (first P complex) instead of the highest.
- **Image 74** `~/Work/psci-test/boot-test.bin.74` `86e3773c5108221c`. **R24A** = aura-ctl `0xd7dcb1f` (observer in the second P complex, as R23); **R24B** = `0x1d7dcb1f` (first P complex). Between them every core and both P complexes are seen from outside.
- **Readings.** Calibration PU 1 and every other core 0, the observer's own complex word on and the other two off, in both runs: all cores are verifiably down at the commit and the block is at SoC level for certain. Any core reading powered: that core (or its complex) is what the sleep engine waits for. Stage stuck at `a2` with an index in `0x600b`: that core's debug block does not answer when it is off (then EDPRSR is no use for it, the complex words still count). Reset as before, about 77 s after the push; WD1 as the outer net.

## 2026-11-11 08:25 GH-5 run R24A (image 74, observer in the second P complex): two of the three indicators fail their own check; R23's conclusion is weaker than written
- Armed 08:21:52, "R24A committing" 08:22:45 (aura-ctl `0xd7dcb1f`), main's kernel started 08:24:02: 77 s after the push. Away 137 s.
- Observer stage `a2`, stopped at index `04`. Words 3 s after the commit: ECPM `10`, PCPM0 `10`, **PCPM1 `00`**. Own EDPRSR: **`0` (PU 0)**. Cores read powered: none of 0 to 3; the read of core 4's block never returned.
- **What fails.**
  - **EDPRSR is no use on this SoC.** The observer's own block reads PU 0 while the core is running. So R23's "boot core EDPRSR 0" proves nothing, and R21's "EDPRCR already 0" may be the same kind of read (the register may simply read 0 here; the write was still done).
  - **PCPM1's word (`0x28e080070`) reads `00` with a core of that complex running**, as it has in every run since R11. It is not a live state. "Both P complexes read off" was only ever shown for PCPM0.
- **What holds.** ECPM's word goes from `1f` (the boot core's own snapshot) to `10` once the boot core sleeps, the same change PCPM0's word made between R11 (cores spinning, `1f`) and R12 (cores asleep, `10`). So the boot complex changes state at the boot core's last WFI. That is weaker than "the cores are proven off".
- **A new indicator, by accident.** The debug blocks of cores 0 to 3 (the E complex, word `10`) answered 3 s after the commit; the block of core 4 (first P complex, word `10`, asleep) did not answer at all. If an unpowered core's block does not answer, then the first P complex is really off and **the E complex, the boot core's, is not**, whatever its word says. R24B (observer in the first P complex) reads the same blocks from the other side: it shows whether the second P complex's blocks hang too and what PCPM0's word reads with a live core in it.

## 2026-11-11 08:30 GH-5 run R24B (observer in the first P complex): the second P complex's debug blocks answer while the first's do not. P complex 1 may never go down
- Armed 08:25:51, "R24B committing" 08:26:44 (aura-ctl `0x1d7dcb1f`), main's kernel started 08:28:00: 76 s after the push. Away 136 s.
- Observer (index 4, MPIDR cluster 1) ran to `a3`, every block read (`0x600b` ff). Words at 3 s: ECPM `10`, **PCPM0 `1f`** (the observer's own complex: so this word is live), PCPM1 `00`. EDPRSR again 0 everywhere including its own: useless, as in R24A.
- **The asymmetry.** From the second P complex (R24A) the read of a sleeping first-P-complex core's block hung. From the first P complex (R24B) the blocks of the three sleeping second-P-complex cores (8, 9, 10) all answered, as did the E cores' in both runs. Read on main, awake, all three words are `0x1f0`.
- **Reading.** A core that has really lost power does not answer on its debug block (P complex 0, whose word also reads the plausible `10`). The second P complex answers and its word is the odd `00`, which it also showed in R24A with a core running in it. So it is likely that **P complex 1's cores never power down at the commit**: they sit in the final WFI loop, which cannot be told from a powered-down core by anything recorded so far (the loop never returns to count, and the byte that would hold cores 8 to 10 of the "woke again" mask, `0x600d`, is one the reset clears). The E complex is undecided: its word says off, its blocks answer.
- **Next (image 75):** make the final WFI loop count. Each core, after its last WFI, bumps a per-core counter and stores ISR_EL1 if the WFI ever returns; the boot core writes the mask of such cores to `0x6008/9` before the commit and the observer writes it again 3 s after, with the boot core included. A core that spins shows up by name, with whether an IRQ or FIQ is pending on it.

## 2026-11-11 08:35 GH-5 run R25A (image 75, the final WFI loop counts): no core's last WFI ever returns. Nothing is spinning
- Armed 08:32:17, "R25A committing" 08:33:10 (aura-ctl `0x1d7dcb1f`), main's kernel started 08:34:26: 76 s after the push. Away 136 s.
- Both reports were written (bit 15 set) and both are empty: before the commit no secondary's final WFI had returned (`0x6008/9` = `8000`, count 0), and 3 s after the commit none had either, the boot core included (`0x6005/6` = `8000`, boot count 0, ISR 0). Observer stage `a3`; words as in R24B (ECPM `10`, PCPM0 `1f`, PCPM1 `00`).
- **So the R24B guess "P complex 1's cores spin in the WFI loop" is wrong.** Every core executes its last WFI once and does not come back. What is still open is the difference between a core that lost power and one that is only clock-stopped in WFI with its state kept: both look the same to a counter. The debug-block asymmetry (P complex 0's blocks hang, P complex 1's and the E complex's answer) still points at the second.
- **Next (image 76): wake them and see how they come back.** 3 s after the commit the observer sends an IPI to one sleeping core per complex. A core that was only clock-stopped returns from WFI (the image 75 counter goes up); a core that had lost power restarts through its reset vector (the RVBAR counter goes up) or does not come back at all. That separates the two states with a positive signal for each.

## 2026-11-11 08:40 GH-5 run R26A (image 76, wake probe after the commit): no core answers an IPI, in either way. Needs its control before it means anything
- Armed 08:36:46, "R26A committing" 08:37:40 (aura-ctl `0x1d7dcb1f`), main's kernel started 08:38:57: 77 s after the push. Away 138 s.
- Observer ran to `a4` (probe finished, `0x600b` ff). After an IPI to each of the nine sleeping cores (100 ms apart, the boot core last): **none returned from its WFI** (`0x6005/6` = `8000`) and **none came through its reset vector** (`0x6008/9` = `8000`, `reset_dbg[0]` 0). The reset came at the usual time.
- **Not a result yet.** The probe has no positive control: nothing so far shows that this IPI reaches a core in its final deep WFI at all, or that a reset-vector entry gets recorded. Read alone it would say "after the commit no core can be woken", which is exactly the kind of strong claim R23 got wrong.
- **Control, R26B (image 77, Aura `c7df5ab2`, aura-ctl `0x3d7dcb1f`):** the identical run with the three S2R timer writes skipped (new bit 29). If the cores answer there (WFI return or reset vector) and not in R26A, then the commit is what takes the cores away from the IPI, and the SoC's sleep sequence has really started on them. If they do not answer there either, the probe is blind and R26A says nothing. No S2R timer in this run, so it ends in WD1's reset (110 to 140 s after the commit).

## 2026-11-11 08:45 GH-5 run R26B (image 77, the control without the commit): identical to R26A. The wake probe is blind, and the complex words do not depend on the commit
- Armed 08:40:47, "R26B committing" 08:41:41 (aura-ctl `0x3d7dcb1f`, the three timer writes skipped), main's kernel started 08:43:57: **136 s** after the push, WD1's reset. So the control held: no S2R timer, no 76 s reset. (Again: the 76 s reset is the timer's.)
- Observer `a4`. Probe: no WFI return, no reset-vector entry, exactly as in R26A. **So R26A says nothing about the commit**: a core in its final deep WFI does not answer this IPI with or without it. (Fits the older note in `psci_park_c`: a core powered down without retention is not woken by an IPI; it needs the PMGR's start.)
- **The useful part of the control:** the words 3 s later read the same as in every commit run: ECPM `10`, PCPM0 `1f` (observer's), PCPM1 `00`. So the boot complex's word going to `10` is the boot core's own deep WFI, not the SoC acting on the commit. **R23's "the cluster powers down within 16 ms of the commit" was true but had nothing to do with the commit.** Nothing measured so far differs between a commit run and a no-commit run except the reset time.
- **What this leaves, critically.** Four observer runs today produced corrections, not progress toward the block: the cores sleep the same either way. The one thing the observer can still do that nothing else can is a differential: snapshot the PMGR's power words before the commit and 3 s after, in a commit run and in this control, and report which words differ only when the commit was written. That is the SoC's sleep engine's visible footprint, if it has one. If the diff is empty, the engine does nothing visible in the PMGR in 3 s and the observer line is finished.

## 2026-11-11 08:50 GH-5 run R27A (image 78, PMGR diff across the commit): the observer stopped inside its first snapshot
- Armed 08:46:52, "R27A committing" 08:47:44 (aura-ctl `0x1d7dcb1f`), main's kernel started 08:49:01: 77 s after the push.
- `0x6004` is still the boot core's `16`: the observer never wrote `a1`, which comes right after the first snapshot. So reading one of the PMGR's power words, taken from the device tree's own list, hung or faulted the observer core, at the moment of the commit.
- Open: is that word unreadable always, or only once the commit is written? Image 79 (Aura `a1da54ab`) writes each index to `0x6008/9` before its read; R28A (commit) and R28B (control) give the word and the answer. R27B is skipped: it would hang the same way without naming the word.

## 2026-11-11 09:09 GH-5 run R28A (image 79, snapshot with progress): the observer stops reading entry 99, ANE_SYS_MPM
- Armed 08:50:25, "R28A committing" 08:51:17, main's kernel started 08:52:34: 77 s after the push. (The owner then used the Mac for about 15 minutes; this entry is written after that.)
- Table: 410 power words. Last index started: 99 (`0x6009 0x6008` = `80 63`), no `a1`. Rebuilt from the saved J414s device tree, entry 99 is **ANE_SYS_MPM**, the first word of ps-reg group 8 (`0x28e084000`), where the ANE's domains sit. Entries 0 to 98 (groups 4 to 7) read fine.
- Whether that word is unreadable always (ANE logic off) or only after the commit is what the control R28B answers, with the same image.

## 2026-11-11 09:13 GH-5 run R28B (control): the same stop at ANE_SYS_MPM without the commit
- Armed 09:09:38, "R28B committing" 09:10:35 (no timer writes), main's kernel started 09:12:51: 136 s, WD1. Snapshot again stopped at index 99.
- So the ANE's power word (ps-reg group 8, `0x28e084000`) cannot be read from the observer whether or not the commit was written. Not a footprint of the commit. Image 80 (Aura `6b45dd44`) leaves group 8 out; the table it then walks is in `data/pmgr-ps-table-image80.txt`. Runs R29A (commit) and R29B (control).

## 2026-11-11 13:02 GH-5 run R29A (image 80): the snapshot stops at entry 202, ISP_CPU
- Armed 09:14:02, "R29A committing" 09:14:56, main's kernel started 09:16:13: 77 s. (Then the session's usage limit; this entry is written at 13:02.)
- 404 words in the table, 202 read; the read of entry 202, ISP_CPU (the first word of group 14, `0x290284000`), hung. Same shape as the ANE's group 8: a second page of a PMGR block (+0x4000) that belongs to a subsystem whose parent is off by then. Likely our own quiesce steps make those pages unreadable, not the commit (R28B showed that for the ANE's).
- Image 81 (Aura `1a9621ad`) also leaves out groups 14 to 16 (ISP, VENC, PRORES): 391 words, `data/pmgr-ps-table-image81.txt`. Runs R30A and R30B.

## 2026-11-11 13:05 GH-5 run R30A (image 81): the snapshot stops at entry 263, SMC_GPIO
- Armed 13:02:32, "R30A committing" 13:03:26, main's kernel started 13:04:42: 76 s.
- 263 of 391 words read; entry 263 is SMC_GPIO (group 3, the SMC's words in the AON block; SMC_FABRIC just before it read). Every group Linux's own device tree lists has now been read; what is left after group 3 is group 0, which already read at entries 205 to 261.
- Image 82 (Aura `707704ef`) leaves group 3 out: 374 words, `data/pmgr-ps-table-image82.txt`. Runs R31A and R31B. Three runs spent finding unreadable words; that is the cost of having no console after the commit.

## 2026-11-11 13:09 GH-5 run R31A (image 82): the diff completes. Two of 374 PMGR power words change in the 3 s after the commit
- Armed 13:06:00, "R31A committing" 13:06:52, main's kernel started 13:08:09: 77 s. Observer `a4`, snapshot finished (`0x6008` f8 is a diff byte, written later).
- Changed (CPU complex words left out), both in group 0 (the AON block's first page): offset `0x0c` **NUB_SPMI0** actual `f` -> `4` (target still `f`), and offset `0x16` **MTP_FABRIC** actual `f` -> `0` (target still `f`). Upper bits changed in both. Raw: `0c f8 4f`, `16 f8 0f`.
- Nothing else moved: no domain in the main PMGR blocks changes state in those 3 s. Whether these two are the commit's doing or happen anyway (NUB_SPMI0 is the bus the crumbs themselves go over; MTP may idle on its own) is what the control R31B shows.

## 2026-11-11 13:13 GH-5 run R31B (control for the diff): two words change without the commit as well. The commit has no clear footprint in the PMGR's power words
- Armed 13:09:10, "R31B committing" 13:10:03 (no timer writes), main's kernel started 13:12:18: 135 s, WD1. Observer `a4`.
- Changed: **NUB_SPMI0** exactly as in R31A (`0c f8 4f`), so that one is not the commit's (it is the bus the crumbs use). And **NUB_FABRIC** actual `f` -> `0` (`11 f0 0f`), where R31A had MTP_FABRIC instead.
- So the only difference between commit and control is which of two AON fabric words reads gated 3 s later: MTP_FABRIC with the commit, NUB_FABRIC without. One run each; both are auto-gating fabric words, so this may be timing noise. It is not a domain being powered down by a sleep engine.
- **Critical reading of the whole observer line (R23 to R31B, nine runs today).** What it established: (1) every core executes its last WFI once and never returns; (2) the complexes' words, the debug-block behaviour and the PMGR's 374 readable power words look the same with and without the commit; (3) the only thing the commit changes is the reset: 76 s instead of WD1's 136 s. What it cannot establish, by construction: anything the SoC does only once *every* core is down, because the observer is itself a running core. If the sleep engine waits for the last core, the observer blocks the very thing it is trying to watch. That limit was not thought through before R23, and it means "nothing visible happens in 3 s" does not show the engine is stuck.
- The observer line is closed here. It cost a morning and removed two wrong beliefs (R23's, R24B's) but did not move the block. The next step has to be one that can tell "the SoC never went down" from "it went down and the way back up failed", with no core awake.

## 2026-11-11 13:15 GH-5 a measurement with no core awake: the PMU's whole register space after each kind of reset
- New `tools/pmu-dump.sh` (read-only, 9 s): all 65535 PMU registers through the nvmem file. 602 of 4096 rows are non-zero. Two dumps 30 s apart on main differ in 34 rows (ADC, RTC, counters): those are the volatile ones to ignore. Dumps in `data/pmu-dumps/`.
- The PMU is the one part that stays powered and keeps state through whatever happens after the commit (the scratch bytes prove it). If the SoC really goes down and comes back by a failed wake, the PMU sequences rails and should record it somewhere (event, fault or state registers); if the SoC is simply reset by a timer, those should look like a watchdog reset's. Runs R32A (commit, aura-ctl `0x57dcb1f`) and R32B (no commit, `0x257dcb1f`), both without the observer, each followed by a dump on main; the rows that differ between A and B and are not volatile are the answer.

## 2026-11-11 13:18 R32A: commit run without observer, PMU dump taken

R32A (image 82, aura-ctl `0x57dcb1f`) pushed "committing" at 13:16:04 and the main kernel started at 13:17:20, 76 s later, as on every commit run. Last crumb is stage 16 (the boot core's last access before the commit). The PMU dump is in `data/pmu-dumps/after-R32A-commit.txt`.

Against the dump after R31B (no commit, watchdog reset), three rows outside the known volatile set differ:

- `1030` byte 0: `40` after the watchdog reset, `00` after the commit reset.
- `1550` byte 0 `40` and byte 9 `01` after the watchdog reset, all zero after the commit reset.
- `1410` bytes 8 to 11: `00013d2b` against `0002bdc1` (looks like a counter).

If R32B (the control, same boot chain and image) shows `40` in `1030` and `1550` again, those are reset-cause flags, and the commit reset is not a watchdog reset. R32B is armed next.

## 2026-11-11 13:24 R32B: the flag idea was wrong; the PMU stamps the reset time, and the commit reset comes 21 s after the alarm

R32B (image 82, aura-ctl `0x257dcb1f`, no commit, no observer) pushed "committing" at 13:19:58; the main kernel started at 13:22:13, 135 s later (watchdog). Dump: `data/pmu-dumps/after-R32B-nocommit.txt`.

**Correction to the R32A entry.** Rows `1030` and `1550` read `00` after R32B as well, so the `40` after R31B is not a watchdog flag. Rows `1020`, `11b0`, `11e0` differ only in R32B (R31B, also a watchdog reset, matches R32A), so they do not follow the commit either. No register in the dump separates the commit reset from the watchdog reset by a flag.

**What the dumps do give: a reset timestamp.** The 6 bytes at `0x1419` (right after `rtc_offset`) are a time in the PMU counter's units (1/32768 s; shifted right by 15 they give counter seconds, the same scale as the counter at `0x1406` and the alarm at `0x140c`). It changes once per boot and sits shortly before the main kernel starts, so it is the time of the reset or of the boot that followed. Against the alarm the job set (commit + 40 s):

| Run | Alarm (`0x140c`) | Stamp (`0x1419` >> 15) | Stamp minus alarm | Stamp minus commit |
|---|---|---|---|---|
| R31B, no commit | `0x56ea05` | `0x56ea56` | 81 s | 121 s |
| R32A, commit | `0x56eb6e` | `0x56eb83` | 21 s | 61 s |
| R32B, no commit | `0x56ec58` | `0x56eca9` | 81 s | 121 s |

The no-commit runs reset 121 s after the commit point, which is the watchdog (`suspend_timeout` 120). The commit run resets 61 s after the commit, which is also 21 s after the alarm. One run cannot tell those two readings apart:

- the reset follows the **alarm**: the SoC did go down, the alarm started a wake, the wake failed and something reset the machine 21 s later;
- the reset follows the **commit**: something set off by the three timer writes resets the machine after 61 s, whatever the alarm does.

**Next: R33A**, the same commit run with the alarm at +70 s instead of +40 s (job `r33a-commit-alarm70`). A stamp at alarm + 21 s (commit + 91 s) means the alarm drives it; a stamp at commit + 61 s (before the alarm) means the commit drives it. Both are below the 120 s watchdog.

## 2026-11-11 13:27 R33A: the reset follows the commit, not the alarm

R33A (image 82, aura-ctl `0x57dcb1f`, alarm at +70 s) pushed "committing" at 13:25:22; the main kernel started at 13:26:38, 76 s later, the same as with the alarm at +40 s. Dump: `data/pmu-dumps/after-R33A-commit-alarm70.txt`.

| Run | Alarm (`0x140c`) | Stamp (`0x1419` >> 15) | Stamp minus alarm | Stamp minus commit |
|---|---|---|---|---|
| R32A, commit, alarm +40 | `0x56eb6e` | `0x56eb83` | +21 s | 61 s |
| R33A, commit, alarm +70 | `0x56edba` | `0x56edb1` | −9 s | 61 s |

The machine reset 9 s **before** the alarm was due. So the alarm plays no part: this is not a failed wake from the alarm. Something resets the machine 61 s after the commit. (`0x14c0` reads `01` afterwards: the alarm fired during the boot that followed.)

61 s is half of the 121 s the watchdog takes without the commit. That may be chance, or the watchdog (set to 120 s by `suspend_timeout`) may count twice as fast once the three timer writes are done, which would itself be a sign that the SoC changed state.

**Next: R33B**, the commit run with `suspend_timeout` 200 instead of 120 (job `r33b-commit-wd200`). A reset at about 101 s after the commit means the watchdog is the one resetting, running at double rate; a reset at 61 s again means a separate timer that does not depend on the watchdog setting.

## 2026-11-11 13:34 R33B: the 61 s do not depend on the watchdog setting. R33A repeated R22B. A new measurement: the PMGR's state counters (image 83)

R33B (image 82, aura-ctl `0x57dcb1f`, `suspend_timeout` 200 instead of 120) pushed "committing" at 13:28:54; the main kernel started at 13:30:10, 76 s later. PMU stamp `0x56ee85`, alarm `0x56ee70` (commit + 40 s): the reset came 61 s after the commit again. So Aura's watchdog (WD1) at double rate is not the cause; the 61 s belong to the timer write.

**Being critical about R32 and R33.** R33A was a repeat: R22B (08:06 today) had already moved the alarm to +70 s with the same answer, and runs D2 and T0 said it on 11-05 and 11-06. I did not reread the log before arming it. What these four runs added:

- the PMU's reset stamp at `0x1419` (6 bytes, 1/32768 s), which times a reset to the second without relying on boot-chain timing: 61 s after the commit, three times, against 121 s for the watchdog;
- no PMU register flags the commit reset differently from a watchdog reset;
- the 61 s do not move with `suspend_timeout`.

None of it says why the entry does not complete. The state of knowledge is the one of 11-06: the timer write is taken, something resets the SoC about 60 s later, and W1 (11-06) moved that to about 90 s by stopping WD2 right after the write.

**The next measurement, chosen for what it can decide.** The PMGR keeps residency counters for its own system states (`AWAKE`, `DEEP_WAIT`, `SLP_S2R`, `SLP_DDR` and the `SYS_` ones, `harness/mmio/pmgrcnt.c`). They were only ever read after a resume, and they are zero after a reset (read on main at 13:32: all 0, `ctl` `0x30000`). They have never been read **after the commit**. Image 83 lets the observer core read them as it sees the commit and 3 s later, with WD2's control, alarm and count:

- only `AWAKE` advances, as in the control: the PMGR's state machine does not react to the timer write at all, and the timer is just a 60 s reset timer here;
- `DEEP_WAIT` (or another state) advances with the commit and not in the control: the state machine started the entry and waits; the observer core being awake may be what it waits for in that run, but the state it stops in is then known;
- WD2's control or alarm differ from the control run: the timer write arms WD2 as on the M1 and T8140, and the 61 s are its period.

Limit, as before: the observer is an awake core. Here that matters less, because the question is whether the state machine moves at all.

- Aura `d2e1a86f` (`v0.1.0-34`, patch `0026`), `boot-test.bin.83` sha `39f3a5e98f3d6bcf`. The power-word diff of images 78 to 82 is removed. Scratch layout in `tools/pmu-scratch.sh` (image 83 section).
- Jobs `r34a-observer-state-counters` (aura-ctl `0x1d7dcb1f`) and `r34b-nocommit-state-counters` (`0x3d7dcb1f`, the control).

## 2026-11-11 13:37 R34A (image 83, observer, commit): AWAKE keeps counting; WD2 reads alarm 60 s, count 0 after the commit. Control next

R34A pushed "committing" at 13:35:43, the main kernel started at 13:37:00 (77 s). Stage `a4`: the observer finished. Raw scratch `0x6000` to `0x601f`: `00 30 00 50 a4 c2 42 00 44 00 00 00 00 00 00 00 00 01 10 1f ff 44 00 3c 00 00 00 00 10 10 50 80`.

- State counters over the 3 s after the commit: `AWAKE` +68 units (the full 3 s) and `SYS_SLP_DDR` +68, with their twins; `SLP_S2R`, `DEEP_WAIT`, `SLP_DDR`, `SYS_AWAKE`, `SYS_S2R_AOP` did not move. (That `SYS_SLP_DDR` counts and `SYS_AWAKE` does not looks like a naming slip in the counter list, to be checked against the control.)
- WD2 3 s after the commit: alarm **60 s**, count **0 s**, control low nibble 0 (also 0 at the commit). On 11-06 WD2 read alarm 90 s with a running count of about 87 s before the timer write (iBoot's leftover).

Nothing can be read from this without the control R34B (the same without the three timer writes), armed now.

## 2026-11-11 13:42 R34B (control): the commit moves the PMGR's system state from SYS_AWAKE to SYS_SLP_DDR and reloads WD2 to 60 s. The SoC-level state stays AWAKE

R34B (image 83, aura-ctl `0x3d7dcb1f`, no commit) pushed "committing" at 13:38:57, the main kernel started at 13:41:13 (136 s, watchdog). Stage `a4`. Raw scratch: `00 30 00 50 a4 92 12 00 44 00 00 44 00 00 00 00 00 01 10 1f ff 00 00 5a 00 00 00 00 10 10 50 80`.

| Over the 3 s after the commit point | R34B, no commit | R34A, commit |
|---|---|---|
| `AWAKE` | +3 s | +3 s |
| `DEEP_WAIT`, `SLP_S2R`, `SLP_DDR` | 0 | 0 |
| `SYS_AWAKE` | +3 s | **0** |
| `SYS_SLP_DDR` | 0 | **+3 s** |
| `SYS_S2R_AOP` | 0 | 0 |
| WD2 alarm | 90 s (iBoot's leftover) | **60 s** |
| WD2 count | under 1 s | under 1 s |

This is the first register-level footprint of the commit, and it has a control beside it.

- **The timer write is taken as a sleep request at once.** The system-level counter switches from `SYS_AWAKE` to `SYS_SLP_DDR` for the whole 3 s (the naming is right: the control counts `SYS_AWAKE`).
- **The SoC-level state does not follow.** `AWAKE` keeps counting; `DEEP_WAIT` and `SLP_S2R` never start. In this run one core (the observer) was awake, which may by itself hold `AWAKE`. But the runs without an observer end in the same reset, so the SoC-level state most likely never leaves `AWAKE` there either.
- **The 61 s are WD2.** The commit sets WD2's alarm to 60 s (it reads 90 s without it). That is the "reconfig watchdog" DJ and Naeem describe on the T8140 and M1 (5 s there): the sleep engine loads it at the commit and stops it when the entry completes. So "reset 61 s after the commit" means exactly "the entry did not complete within 60 s". W1's 11-06 result (WD2 stopped, reset at 90 s) fits.
- The system target is `SYS_SLP_DDR`, not `SYS_S2R_AOP`. Whether macOS's normal sleep on this machine is the one or the other is not known; noted.

**What changed for the work.** Until now each try had one bit of output (reset at 76 s or not). Now there is an instrument: a core can read which state the PMGR is in after the commit. And there is an older fact that now looks like the centre: the SoC-level counters have **never** shown anything but `AWAKE` on Linux, not in s2idle, not with all ten cores in deep sleep under Aura. `DEEP_WAIT` is by its name the state before sleep. The question to answer is what lets the PMGR leave `AWAKE`, and that can be tested without a commit and without a reset.

## 2026-11-11 13:46 image 84: the observer diffs the whole always-on PMGR block across the commit; jobs R35A/R35B
- **Why.** R34 showed the commit is taken (`SYS_AWAKE` → `SYS_SLP_DDR`, WD2 reloaded to 60 s) and the SoC-level state then stays `AWAKE`. The sleep engine lives in `MPMGR_AON` (pmgr reg 38, `0x29e5c0000`, `0x14000`), of which only the timer word at `+0x4000` has ever been read. Whatever status or "waiting for" bits the engine has should be in that block and should change with the commit.
- **Image 84** (Aura `148fecec`, `v0.1.0-35`, `boot-test.bin.84` sha `907f6723a000e8ff`, patch 0027). Before the commit the boot core asks the observer for a snapshot and waits up to 2 s; the observer reads the 20 480 words twice 50 ms apart (words that differ are marked volatile and left out), waits for the commit and 3 s more, reads again. Scratch: number of changed words, the first two (index, lowest changed byte, old and new value), the last one's index, the page being read (names a region that hangs), the state-counter mask as in image 83. `aura-ctl` word 2 bits 12–27 give a start index, to page through more changes in later runs. Whole block added to the runtime map.
- **Correction to image 83:** it read WD2's control at `+0x28`; the control is at `+0x2c` (as the STOPWD2 step always used). The "ctl 4 → 4" in R34 was therefore not the control word. The alarm (`+0x24`, 90 s → 60 s) and count were read correctly; image 84 reads `+0x2c`.
- **Risk.** Reading unimplemented words of the block may fault or hang the observer core; the boot core then goes on after 2 s and `0x600c` names the page. R35A = with the commit (`0x1d7dcb1f`), R35B = control (`0x3d7dcb1f`).

## 2026-11-11 13:51 run R35A: the observer stopped reading in page 8 of the block (`0x29e5c8000`); image 85 diffs pages 0 to 7 and probes the rest afterwards
- Armed 13:46:26, "R35A committing" 13:47:18, main's kernel 13:48:37 (79 s after the push: the usual 76 s plus the 2 s the boot core waited for the snapshot). Away 138 s.
- **Scratch:** `0x6004` 16, no observer stage, `0x600c` = `88` = "before" snapshot, page 8. Every other byte is the boot core's own snapshot. So words `0x29e5c0000`–`0x29e5c7fff` read without trouble and the first access in `0x29e5c8000` either faulted or never returned. The boot core went on after its 2 s and committed, as designed. (Not certain: the boot core's snapshot also writes `0x600c`, but with an observer present it puts a park count there, with zeros in `0x600d/e`; `88` as that count is unlikely.)
- **Image 85** (Aura `b539476d`, `v0.1.0-36`, `boot-test.bin.85` sha `ef96cf0414e6a880`, patch 0028): the pages to diff are a mask (default pages 0 to 7, which hold the timer word at `+0x4000`); after the report the observer reads the remaining pages one at a time with the page number in `0x600d` first, leaving out page 8, so each run also names the next page that cannot be read. `aura-ctl` takes a fourth word for this (start index, page mask, pages not to probe).
- Jobs: **R35B** = commit (`0x1d7dcb1f`), **R35C** = control (`0x3d7dcb1f`), both on image 85.

## 2026-11-11 13:54 run R35B: five words of the always-on block change with the commit; two are named, `+0x14` 3 → 1 and `+0x100` 8 → 0xa
- Armed 13:51:16, "R35B committing" 13:52:09, main's kernel 13:53:26 (77 s after the push). Away 136 s. Image 85 read back.
- **The observer finished** (`0x6004` a4, `0x600c` ff): pages 0 to 7 of `MPMGR_AON` (8192 words) read three times without trouble, no volatile words.
- **Five words differ 3 s after the commit** (`0x6006` 05):
  - word 5, **`0x29e5c0014`: low byte `03` → `01`** (one byte differs);
  - word 64, **`0x29e5c0100`: low byte `08` → `0a`** (one byte differs);
  - two more between word 65 and 4095, not reported (two entries per run);
  - the last is word 4096, `0x29e5c4000`, the S2R timer word itself.
- State counters over the same time (`0x6005` d2): `AWAKE`, `SYS_AWAKE` and `SYS_SLP_DDR` advanced. `SYS_AWAKE` shows here because this image takes the "before" reading ahead of the commit; otherwise as R34.
- **`0x600d` and `0x600e` are cleared by the reset** (noted for image 64, forgotten): the probe page and the WD2 byte I put there are lost. Image 86 (Aura `b41fcb54`, `v0.1.0-37`, `boot-test.bin.86` sha `1ee46452563aa108`, patch 0029) reports three entries (`0x6007`, `0x6012`, `0x601b`) and puts the probe page in `0x600c`.
- **What this is worth.** These are the first status words of the sleep engine seen on this SoC: a small block at the start of the always-on PMGR that reacts to the commit. Their meaning is not known yet. Next: **R35D** = the same with the report starting at word 65 (the two missing words, and the next unreadable page), then **R35C** = the control without the commit (which of these change anyway).

## 2026-11-11 13:59 run R35D: the timer word reads 1 before the commit and 0 after, `+0x4008` changes too; page 9 cannot be read either; one entry is ambiguous (image 87)
- Armed 13:54:59, "R35D committing" 13:55:52, main's kernel 13:57:09 (77 s). Away 137 s. Image 86, report from word 65.
- **Three words from 65 on differ** (`0x6006` 03), so with R35B's words 5 and 64 the five are accounted for:
  - word 4096, `0x29e5c4000` (the S2R timer word): low byte **`01` before the commit, `00` 3 s after it**. Not what I assumed (0, then 1 after writing 1): the word already reads 1 when Linux hands over, and the three writes of 1 leave it reading 0.
  - word 4098, **`0x29e5c4008`: low byte `00` → `01`**, two bytes of the word differ.
  - third slot: bytes `00 10 10 00 01`, which read as "word 4096, 00 → 01". The same word cannot be listed twice, and the first three of those bytes are also what the slot holds when nothing is written (zeroed `0x601b`, then the boot core's `10 10`), so I do not trust this entry. For the same reason **R35B's "last changed word = 4096" was not evidence**; its "two more between 65 and 4095" is withdrawn.
- **Probe:** `0x600c` = `29`: the observer stopped while reading page 9 (`0x29e5c9000`), as it did in page 8 in R35A. Pages 0 to 7 are fine.
- **Image 87** (Aura `9ed3db93`, `v0.1.0-38`, `boot-test.bin.87` sha `47b9fb566ee9a827`, patch 0030): the three slots are filled with `ff` before the report, so a leftover cannot pass for an entry. **R35E** = commit, report from word 4097, probe leaving out pages 8 and 9. Then **R35C**, the control.

## 2026-11-11 14:02 run R35E: the five words the commit changes are now all named; page 10 cannot be read either
- Armed 13:59:25, "R35E committing" 14:00:18, main's kernel 14:01:34 (76 s). Away 136 s. Image 87, report from word 4097; unused slot reads `ff` as intended.
- **Two words from 4097 on** (`0x6006` 02): word 4098 **`0x29e5c4008` `00` → `01`** (two bytes differ, as R35D) and word 4099 **`0x29e5c400c` `00` → `01`**. R35D's doubtful third entry was this word 4099 with its first byte lost.
- **The whole set, 3 s after the commit** (pages 0 to 7 of `MPMGR_AON`, 8192 words, R35B + R35D + R35E agree):

  | word | before | after |
  |---|---|---|
  | `0x29e5c0014` | low byte `03` | `01` |
  | `0x29e5c0100` | low byte `08` | `0a` |
  | `0x29e5c4000` (S2R timer) | `01` | `00` |
  | `0x29e5c4008` | `00` | `01`, a second byte differs too |
  | `0x29e5c400c` | `00` | `01` |

- **Probe:** `0x600c` = `2a`: stopped in page 10. Pages 8, 9 and 10 each stop the observer, so I take everything from `0x29e5c8000` up as not readable from here and stop probing.
- Next: **R35C**, the control without the commit (do any of the five move anyway?), and reading macOS's PMGR code for these five offsets.

## 2026-11-11 14:17 run R35C (control, no commit): none of the always-on words change; the five are the commit's doing
- Armed 14:02:41, "R35C committing" (no timer write) 14:03:35, main's kernel 14:05:50 (no commit, so the reset is not WD2's 61 s). Away 196 s. Image 87, `0x3d7dcb1f`, report from word 0, no probing.
- **Scratch:** observer finished (`0x6004` a4, `0x600c` ee), **`0x6006` 00: no word of pages 0 to 7 of `MPMGR_AON` differs** over the same 3 s. All three slots still `ff`.
- State counters (`0x6005` 92): `AWAKE` and `SYS_AWAKE` only; `SYS_SLP_DDR` (bit 6 in R35B's d2) stays still without the commit, as R34's control.
- **So the five words of R35B/D/E are the sleep engine's answer to the commit**, not drift: `+0x14` 3 → 1, `+0x100` 8 → 0xa, `+0x4000` 1 → 0, `+0x4008` 0 → 1, `+0x400c` 0 → 1. Next: what macOS's PMGR driver does with these offsets, and whether macOS's own sleep path writes any of them before the timer.

## 2026-11-11 14:20 macOS's PMGR code for the five words; image 88 traces them over time; job R36A
- **macOS (T6020 PMGR driver, 15.7.1 kernelcache).** Registers are addressed as (map, offset); the map table in `AppleT6020PMGR` binds **map 4 to ADT pmgr reg 38 = `MPMGR_AON`** and map 0x42 to reg 7 (`0x29e004000`). The only direct map-4 write found is "Starting S2R timer": map 4, `+0x4000` := 1. `setAPWakeupSources` writes "`0x400c`…`0x402c`", but through `writeAOPGlobalReg` (offset − 0x4000 in map 0x42), i.e. the AP wake-source mask at `0x29e00400c`…, **not** `MPMGR_AON+0x400c`; the look-alike offsets are a coincidence of that helper's encoding. So macOS's driver does not write `+0x14`, `+0x100`, `+0x4008` or `+0x400c` directly: they are the engine's own status, set by hardware or firmware. (Indirect accesses through the generic `ApplePMGR` paths are not fully traced.)
- **Image 88** (Aura `3228b550`, `v0.1.0-39`, `boot-test.bin.88` sha `f606b49243eefec2`, patch 0031): observer word bit 63 = trace mode. The observer reads the five words at the commit and then polls them until the reset (or 120 s), logging each change as id, new value (low 5 bits) and time since the commit in 4 ms units. First five events in `0x6005`, `0x6008`, `0x6011`, `0x6014`, `0x601b` (3 bytes each: `id<<5|val`, time low, time high; ids 0 `+0x14`, 1 `+0x100`, 2 `+0x4000`, 3 `+0x4008` b0, 4 `+0x4008` b1, 5 `+0x400c`, 6 other byte); `0x600b` = events seen; live values: `0x600c` = `+0x100`, `0x601e` = `+0x14`, `0x601f` bits 0–2 = timer / `+0x4008` / `+0x400c` non-zero.
- **Why this and not another random poke.** The five words are the only view into the engine. One snapshot at 3 s says where it is, not how it got there or whether it moves on. If the words step through a sequence and stop, the last step names what the engine waits for; if everything changes within the first milliseconds and then nothing for 58 s, the engine is parked from the start and the wait is for something outside it (a core, the SMC/PMP handshake). Both outcomes cut the search space.
- **R36A** = commit (`0x1d7dcb1f`) with the trace.

## 2026-11-11 19:03 run R36A did not run: the job's stage-2 check still named image 87; fixed and re-armed
- Armed 14:21:05, back 14:22:23 (78 s): the job read "stage 2 is not image 87: stopping" (v0.1.0-39-g3228b550 is image 88) and ended before the SEP step, so no commit was made. The scratch bytes are R35C's leftovers. The template sed in image 88's job missed the hash; fixed to `3228b550`.

## 2026-11-11 19:06 run R36A (image 88, trace): all five words change within 4 ms of the commit, then nothing for the rest of the run
- Armed 19:03:21, "R36A committing" 19:04:14, main's kernel 19:05:30 (76 s). Away 136 s. Stage 2 `v0.1.0-39-g3228b550` ran (the earlier abort was the job's hash check).
- **Scratch** `00 30 00 50 a2 01 00 00 2a 00 00 06 0a … 40 00 00 61 00 00 … 01 06`: `0x600b` = **6 events** in total. Logged: `+0x14` → 1 (time 0), `+0x100` → 0xa (0), `+0x4000` → 0 (0), `+0x4008` b0 → 1 (0). The other two (`+0x4008` byte 1, `+0x400c`) fall past the five-event cap's slots I read but are counted in the 6; live values at the end: `+0x100` = 0a, `+0x14` = 1, timer 0, `+0x4008` and `+0x400c` non-zero (`0x601f` = 06).
- **Time stamps are all 0, i.e. under 4 ms after the commit, and the count stayed 6 to the end.** So the engine does everything it does with these words at once and then parks; for the next ~58 s none of them moves. It is not stepping through a sequence waiting on something that would show here.
- **What this means.** The sleep engine accepts the commit and finishes its visible bookkeeping within milliseconds; what keeps the SoC at AWAKE is not a later step of this block. The wait is for something outside it: a core entering its deep WFI the way the engine expects (R25A: no core's last WFI ever returns, but the engine may sample something else), the SMC/PMP handshake, or a condition in a block the observer cannot read (pages 8 to 10 of this block hang the reader). Caveat: the observer core is awake and could itself be that condition.
- Next: read the remaining unread parts of the PMGR S2R path in macOS (what `SYS_SLP_DDR` waits for before DEEP_WAIT), and decide whether the observer core must sleep too.

## 2026-11-11 19:07 reading R36A against the earlier runs: the awake observer is probably not the blocker
- R22A/R22B/R33A ran the commit with **no observer core awake** and the RTC alarm at +20/+40/+70 s: no wake, the same WD2 reset at +61 s. So "the observer holds AWAKE" would have shown as a wake there; it did not. The caveat in the R36A entry stays, but it is weak.
- macOS's `SLP_S2R`/`SLP_DDR`/`AWAKE` strings in `pmgr.s` (around `fffffe0009f38578`) are the ADT state-name parser, not the sleep logic; nothing found there about what `SYS_SLP_DDR` waits for.
- Remaining candidates for the missing condition, in order of what is still untested: (1) the cores' idle state at the commit: R25A says no last WFI returns, but Aura parks the nine secondaries in CPU_OFF, not in macOS's `CYC_OVRD` deep WFI; (2) pages 8 to 10 of the block (unreadable from here); (3) how the SMC's reply to the sleep messages is consumed. Correction to my first draft of this entry: the SMC sleep messages (MBSE slpw/slpa, WKTP, SetAPPower 0x201) are already sent at every commit (worklog, R20c correction), so the handshake is not an untested candidate in its sending half. Next: check whether Aura waits for and checks the SMC's replies before the commit, and make the observer read the SMC's own state if the mailbox allows.

## 2026-11-11 20:55 the five words at rest (read from main Linux), and R36A's sixth event
- Resting values from main (`mmio-read`, no sleep in progress): `+0x10` 0x08000000, **`+0x14` 0x3**, **`+0x100` 0x8**, **`+0x4000` 0x1**, `+0x4004` 0, **`+0x4008` 0x00010000**, **`+0x400c` 0**, `+0x4010` and `+0x4014` 0. So the words that R35 reported as "00 → 01, two bytes differ" for `+0x4008` are 0x00010000 → 0x00000001: bit 16 clears and bit 0 sets. That is a one-hot position moving from bit 16 to bit 0, i.e. a state machine stepping, not a flag being set. R36A's sixth event (count 6 in `0x600b`) is that byte-2 change (id 6); its slot (`0x601b`) reads zero in the scratch, a slot the earlier boot snapshot and the reset-survival rules make unreliable, so this is read from the count and the resting value, not from the slot.
- So after the commit, within 4 ms: `+0x14` 3 → 1 (bit 1 clears), `+0x100` 8 → 0xa (bit 1 sets), the timer word 1 → 0, `+0x4008` bit 16 → bit 0, `+0x400c` 0 → 1. No second step follows. Hypothesis: the engine went from "idle" to the first state of its sequence and is waiting there for an input (a core-sleep or SMC-ready line) that never arrives.
- Next (no image change needed): see whether any other run changes these words differently, e.g. a commit with fewer writes or the boot core not entering its deep WFI. Both are cheap job variants of image 88; to be armed in the following slot.

## 2026-11-11 20:56 critical check (owner asked for one): progress or random leads?
- **Progress:** since R34 each run narrowed a definite question: the commit is taken (R34), it changes five engine words and nothing else in the readable block (R35), it does so in under 4 ms and then stops (R36A), macOS writes none of them itself (kernelcache). That rules out "late step of the engine" and "observer core holds AWAKE" (no-observer runs R22/R33 already agree).
- **Not progress:** none of it has moved the machine closer to sleeping; the entry still ends in WD2's reset 61 s after the commit. Every sleep-entry step found in macOS (domains, clusters, SEP, SMC messages, AIC, wake mask, APSC, EDPRCR, timer written 3 times, nothing after) is already matched, so what is left is either below what the readable registers show (pages 8 to 10 of the block hang the reader) or an input the engine takes from a core that Aura parks differently from macOS (CPU_OFF park vs macOS's CYC_OVRD deep WFI on the nine secondaries; but that is already what runs: the parked secondaries sit in a deep WFI with CYC_OVRD WFI_MODE 3 and retention (`psci_park_c` in smp.c), released with an IPI and `sev` at the commit and idling again, as macOS's cores do. So this lever is spent too (corrected after reading smp.c).
- **Plan:** no commit variant is left that I can justify; stop touching the commit and work the issue #12 leftovers (Aura as stage 2 with the PMP fit fix, reconcile with aura#88, results to linux#933). If the owner has an idea for the engine's missing input, it is the only thing that restarts the S2R runs.

## 2026-11-11 21:53 issue #12 step 4, run P12E: Aura with the PMP fit port as stage 2 boots the PR 933 DTB and kernel; 10 of 10 s2idle cycles pass
- **Port:** `~/Work/src/aura-pmpfit` (worktree of aurora-silicon/aura `origin/main` bb45ca3b, branch `pmp-tunables-fit`, commit `6fb6a87e`, only `src/kboot.c`, +65 lines): `pmp_tunables_size()`, `pmp_node_to_fill()` (the pmp alias node, or on T6000/T8112 the node found by compatible as aura#88 does; the extra headroom is keyed on it) and `pmp_tunables_fit()` (checked before both copies: `dt_set_pmp()` and `dt_fill_pmp()`; if the tunables + 16K do not fit, the node keeps its DT status and the log says why).
- **Build:** the docker image's toolchain is too old for current main (`armv9.4-a`), so on the host: `RUSTC_BOOTSTRAP=1 make BUILDSTD=1 RELEASE=1 LD=ld.lld` with clang 23.1.4, default `-Os` (so the issue's `-Oz` snag did not show on 23.1.4 with this tree). `__popcountdi2` is missing from this host's link (no compiler-rt), so a local stub `src/zz_local_popcount.c` plus a Makefile line was used and **not committed**; those two files are the only dirt in the worktree, and the build tag reads `1.0.0b10-gbb45ca3b-dirty` because the binary was built before the commit. Image `p12d` sha `8c2e965fe6c6397e`.
- **Run:** armed 21:46:40, back 21:52:46 (away 366 s). Stage 2 `1.0.0b10-gbb45ca3b-dirty`, kernel 7.3.0-pr933+, DTB = PR 933's with the T602x alarm cells (`p12c.dtb` sha `31aeec088f4d8489`).
- **Result:** PMP node `okay`, **81 tunables, 11896 bytes**; `PMP manages fabric and DCS p-states`, `PMP firmware and endpoint ready`, `pmp-disp0`/`dispext0`/`dispext1`/`isp-sys` on; 16 boot warning lines as P12B. **10 of 10 s2idle cycles**: asleep 19.8 to 19.9 s, rc 0, eDP connected/enabled, backlight 140, Wi-Fi ping on the second try each time, 3 USB devices, 0 new warning lines; domains unchanged after. Same as P12C under m1n1 PR 63.
- **What this does not show (critical):** (1) no control: I have not shown that unfixed Aura main fails here, so this does not yet say the port is what makes it boot; (2) the fit-fail path (tunables that do not fit) never ran; (3) FDT headroom is not visible (the tree Linux sees is packed: free 0); (4) a hand-patched build environment (stub, host clang).
- Next: **P12F** = the same boot with unfixed Aura main (control, image `p12f` `36d72e410cd77758`, binary checked to lack the new message).

## 2026-11-11 22:01 issue #12 step 4, control P12F: unfixed Aura main boots the same DTB with all 81 PMP tunables and passes the same 10 cycles, so the port is not shown to be needed
- Armed 21:54:01, back 22:00:06 (away 365 s). Stage 2 = unfixed `origin/main` kboot.c (binary checked: no "pmp left disabled" string; build tag `g6fb6a87e-dirty` only because HEAD of the worktree was the port commit), image `p12f` `36d72e410cd77758`, otherwise as P12E.
- **Result identical to P12E:** PMP `okay`, 81 tunables / 11896 bytes, same three PMP lines, same domains, 16 boot warning lines, **10 of 10 s2idle cycles** (19.9 to 20.4 s asleep, rc 0, display/Wi-Fi/USB back, 0 new warning lines).
- **So the issue's premise for step 4 is not reproduced:** "aura main still bails in dt_set_pmp() with the fixed 96K headroom" does not happen with `bb45ca3b` on this J414s with PR 933's DTB (whose tunables are the same 81). Reasons I can think of, none checked: Aura's main headroom is already larger (it adds 16K for SMBIOS and its tree is built differently from m1n1's), or the bail needs a bigger DTB than this one. What P12E does show: the port is harmless on the pass path. What nothing shows: that the fit-fail path works (never ran), or that the port is needed.
- Housekeeping: the UKI in the work dir is back to the S2R one (`6ee0da2a`); worktree `~/Work/src/aura-pmpfit` keeps a local popcount stub and a Makefile line that are not committed.
- Not done on purpose: no PR to aurora-silicon/aura (the control says the premise may not hold; the owner or Ryan should decide); no comment on aurora-silicon PRs. A comment with the P12E/P12F numbers goes on our issue #12.

## 2026-11-11 22:03 run R37A (S2R step 1): MPMGR_AON page 8 (`0x29e5c8000`) kills the machine from the test Linux too, so it is not an observer-core quirk
- Armed 22:01:56, back 22:03:09 (away 73 s). Image 88, 7.2.11-psci test kernel, `/dev/mem` O_SYNC reads one address at a time, each pushed before it was read.
- **Answered:** `0x29e5c4000` → 0x00000001 (the timer word at rest, as on main), `0x29e5c7ffc` (last word of page 7) → 0. **`0x29e5c8000`: "about to read" was pushed, no "read" followed, the Mac was back on main 35 s later** (a fault or hang, then the test root's panic=10 reset). The remaining nine addresses were never reached.
- So the readable part of the block ends at `0x29e5c8000` for every core and every kind of access seen: from an Aura core (R35A/D/E: pages 8, 9, 10 each stop it) and from Linux. That reads as "nothing answers there" (unimplemented or clock/power gated) rather than "the observer is special". **Step 1 is closed:** the engine's state is not in a readable page of this block, and I will not try to read more of it.
- Left: step 2 (compare against a macOS trace) needs the owner: there is no macOS trace of these words on this Mac in `~/Work`, and booting macOS under the hypervisor touches the boot chain. Step 3 (SMC replies) was already covered: every sleep message returns 0 (worklog, "Step 3 ... every write 0").

## 2026-11-11 22:06 issue #12 step 4, run P12H: the port's fit-fail path works (forced): PMP left disabled, kernel boots
- Armed 22:04:36, back 22:05:50 (away 74 s). Stage 2 = the port plus a **local, uncommitted** test line (`pmp_tunables_fit()`: need + 1 MB, headroom unchanged; a first attempt with the 1 MB in `pmp_tunables_size()` would have grown the headroom too and tested nothing, caught before running), image `p12h` `088e33200683f04d`; PR 933 kernel and DTB as P12E.
- **Result:** PMP node `status=disabled`, **0 tunables, 0 board-id props** (nothing half copied), all 10 CPUs online, no `apple_pmp` lines, `pmp-disp0`/`dispext0`/`dispext1`/`isp-sys` domains still on (those belong to the pmgr/DART side), 2 err/crit lines. I did not read Aura's own message (no console), so "Aura prints why" is unseen; the node state is the evidence.
- With P12E (pass path, 10/10 cycles) and P12F (control passes too), step 4 stands as: port works on both paths, harmless, **not shown to be needed** on this Mac. UKI back to the S2R one (`6ee0da2a`).

## 2026-11-11 22:07 macOS's "Quiesce PS check" is a dead end on this Mac: the property it reads is not in the J414s ADT
- `ApplePMGR::quiesceHW` (`pmgr.s` around `fffffe0009f43370`) can check, before sleep, that a per-sleep-mode list of PS devices is off ("Quiesce PS check, %s PS device(%d:%s) not powered off(0x%x) before entering sleep"). Its table (52-byte entries: device id, sleep-mode number, up to 24 device ids) is built at init from the pmgr node's property `device-check-ps-b4-sleep` (`site.DevicePSCheckB4SleepData`).
- That property **is not in `dt.j414s.adt`** (no string containing "check", "b4-" or "ps-" of that kind in the ADT at all), and the init code skips the table when the lookup returns null. So on this Mac macOS does not run that check; it is not a hidden list of domains that must be off. Our earlier map comparison (`data/psmap.txt`, maralcbr's trace) therefore remains the only domain-level reference, and it is matched.
- **State at 22:30 of the overnight plan:** issue #12 done as far as it can be without the owner (comments on #12, nothing posted on aurora-silicon); S2R step 1 closed (R37A), step 3 already covered, step 2 needs a macOS trace under the hypervisor (owner), the question for Naeem is in `docs/question-for-naeem.md`. I have no further experiment I can justify without one of those.

## 2026-11-11 23:02 Naeem's reply: he is working on the driver; his commits give a concrete lead (cores arm deep sleep only AFTER the commit); image 89, job R38A
- The owner sent the question; Naeem (GitHub `malik-na`) answered that he is working on the driver. New `tools/watch-naeem.sh` baselines and reports pushes to `malik-na/linux-aurora` (`m1power/s2r-mem`, `m1power/s2r-pmp`) and `malik-na/m1-power-lab` (`omarchy-live-power`) with an agent-notify.
- **macOS test:** the owner approved it with the MacOSTest volume (macOS 14.8.9, boots through the proxy). It runs from the Pi over USB (`harness/remote/hv-run.sh`), and **the Pi is not reachable from this install** (no Tailscale, no key to it; worklog 2026-11-08), so I cannot start it tonight; it needs the owner to start `hv-run.sh` on the Pi or give this machine a route to it. Even then the earlier HV traces never covered MPMGR_AON, so a tracer for `0x29e5c0000..0x29e5c8000` would have to be added first.
- **The lead (his `bd01a988d`, `b6b2ea1d1`, 2026-11-08):** XNU's global sleep (`__ARM_GLOBAL_SLEEP_BIT__`, `ml_arm_sleep`, `arm64_stall_sleep`) and his macOS 27 traces on t8103: all secondaries write their CPU-start stop request about 40 ms before the commit and then **stall in WFE; only after CPU0's last pre-commit PMGR writes (the commit) do all cores write `ACC_OVRD` deep sleep, `CYC_OVRD` 0x3000001 and WFI, together.** His old order (secondaries into the deep WFI at once, the last P core arming its cluster's deep sleep) left the P cluster down long before the commit. That is **exactly our quiet path**: Aura releases the parked cores (they go into `cpu_sleep(true)`) and waits 2 ms before the commit; the R23/R24 observer runs showed the first P cluster read as off before the commit. And R36A's picture (the engine takes the commit in under 4 ms, then parks) fits an engine waiting for the cores' deep-WFI events that already happened before it was armed. I wrote in the 20:56 entry that no commit variant was left; this is one, found in someone else's commits, and it is a different thing from the non-quiet path of images up to 60 (there the commit came first but with MMIO and SPMI traffic after it).
- **Image 89** (Aura `4d774aae`, `v0.1.0-40`, `boot-test.bin.89` sha `cdf72028f031bb11`, patch 0032): `PSCI_S2R_LATEREL` (psci_ctl bit 30). In the quiet path the pre-commit release of the parked secondaries (and its 2 ms wait) is skipped; after the three commit writes (no MMIO or SPMI after them) the secondaries are released (IPI + `sev`), the boot core flushes and sleeps right after, so every core arms its deep sleep together after the commit.
- **R38A** = `aura-ctl 0x417dcb1f` (the quiet commit family, **no observer**, no EDPRCR step because it is done in the release, bit 30), alarm +40 s. Outcomes: the alarm wakes it ("R38A resumed", the S2R works at last) or the usual WD2 reset 61 s after the commit (no change, the order is not it).
