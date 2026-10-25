# Where the work stands (2026-10-24)

This is the summary of the whole effort: what was measured, what was built,
what works, what does not, and what comes next. Each section points to the
detailed write-up (`deep-idle-research.md`), the plan (`s2r-plan.md`), the
run-by-run log (`worklog.md`) and the raw data (`data/`).

The machine is a 14-inch MacBook Pro, M2 Pro (T6020, `apple,j414s`). It runs
Aurora Silicon Linux:
* kernel `7.1.12-2-11.35-sep-ARCH+`;
* m1n1 stage 1 v1.5.2, then stage 2;
* U-Boot `2026.07.asahi2`, then GRUB.

There are two goals:
* lower the awake and idle power;
* get the lid-closed drain from s2idle's 1.4 W towards macOS's 0.24 W,
  which needs real suspend to RAM (S2R).

## The short version

* **Awake idle: three changes are proven on this machine.**

  | Change | Saving |
  |---|---|
  | Booting the PMP | 0.9 to 1.15 W |
  | A 100 us CPU PD residency in `cpuidle-apple` | up to about 0.6 W on a busy desktop; PD always gets 0.9 to 1.1 W |
  | A T602x CPU energy model, so EAS runs | 61 mW at idle |

  Each was booted and measured in paired A/B runs.
* **Lid closed: s2idle drains about 1.4 W. macOS sleeps the same machine at
  0.24 W.** The gap is SoC sleep itself, not the devices. Awake idle matches
  macOS once the PMP runs.
* **S2R is a stack of pieces, and most of them now have an answer.**
  * Working in a test kernel: the timed wake (the PMU RTC alarm) and the
    AIC save/restore.
  * Understood and tested: the SMC handshake, which also showed that `slpa`
    must come last.
  * Understood, fix untried: the PMP wake.
  * Built, waiting for their first boot: CPU_OFF and CPU_ON (Phase 1).
  * Open: PMGR's last steps and the boot CPU's wake hand-back, which the
    macOS hypervisor trace (Phase 3) is meant to answer, and DCP resume,
    the long pole.
* **Next:** Phase 1's boot test (not started: each boot step needs the
  owner), and finishing the macOSTest guest runs. State on 2026-10-25: the
  guest is **macOS 14.8.9** (14.8.3 is gone from Apple's catalog), installed
  on its own volume with Aura as its boot object; it boots under the
  hypervisor with all 10 CPUs and the SMC and PMP tracers (three Aura/tracer
  fixes were needed, `patches/hvsleep-trace`). Run 5 ended with the display
  domain going off and then the whole SoC hanging, probably the guest's
  sleep (`docs/hv-run5-analysis.md`, `docs/hv-boot-trace-reference.md`); the
  control run without the sleep job and the autologin step are next. Work
  is tracked in the GitHub Project "S2R on M2 Pro (J414s)" and the repo is
  now pushed to directly (no PR per step).

## Timeline

| Date | Milestone |
|---|---|
| 10-14 | Research started: idle states, CPU PD residency A/B (`idle_ab3` to `idle_ab6`), EAS found off on T602x |
| 10-15 | Repo split out; unattended reboot-per-step harness; campaign runs 1 and 2 (E6 energy model, E7 residency, E4 no external DCPs); a module-tree deletion incident, fixed with `.keep` |
| 10-16 | Runs 3 and 4: the PMP boot hang explained (m1n1 DT headroom), PMP booted, **0.9 to 1.15 W saved** |
| 10-17 | s2idle night with the PMP (1.4 W); macOS 13.5 sleep path read statically; deepidle2 (PMP IDLE in s2idle: idle works, wake does not); macOS 15.7.1 live (issue #3): **0.24 W** |
| 10-18 | s2idle suspects one by one; the all-off night (2.1 W, SD link without L1); PCI remove/rescan kills Wi-Fi (banned); HDMI rails 0.13 W |
| 10-19 | Issue #5 checked; the **PMU RTC alarm wakes s2idle** (deepidle3, after the "fired" bit fix) |
| 10-21 | No USB on 11.3x kernels: `CONFIG_USB4_APPLE_SOC` was missing; deepidle3 rebuilt with it |
| 10-22 | Raspberry Pi 5 controller; harness-only passwordless sudo; screens stay off across reboots; the **SMC handshake** in s2idle (`slpa` takes the storage away) |
| 10-23 | PMP wake tests (RUN only: 0/3; SRAM gate: no restart; `ps_pmp` reset: SoC crash); **S2R plan**; macOS data collected for the hypervisor run; the guest becomes a 14.8.3 volume |
| 10-24 | Overnight s2idle (8.3 h, clean); **Phase 1 built** (PSCI CPU_ON/CPU_OFF through EFI in kernel, Aura and U-Boot) |

## Awake and idle power

| Result | Numbers | Where |
|---|---|---|
| PMP booted (E1) | quiet desktop 6.28 to 5.38 W on battery and 6.67 to 5.61 W on AC at the wall; busy 7.52 to 6.36 W. Needs 160 KiB of m1n1 DT headroom: the 81 tunables need 15,850 bytes, and 12,936 are left | research "Unattended campaign"; `m1n1/`; `dts/` |
| CPU PD residency (E7) | 2 ms saves 53 mW, 500 us 330 mW, 200 us 526 mW, 100 us 591 mW, PD always 628 mW; wake latency about 20 to 25 us p50 at any threshold | `cpuidle_apple.pd_residency_us` patch; `data/campaign/` |
| PD always on a long-running desktop | 0.9 to 1.1 W at 6.5 to 8.6 W, and 1.3 to 2.5 W under load | `data/idle_ab*` |
| CPU energy model (E6) | the EM registers, EAS moves light work to the E cores, idle 61 mW lower (15 of 15 rounds) | `tools/t6020-cpu-em.py` |
| No external DCPs (E4) | nothing measurable at idle | `dts/` |
| HDMI rails | 0.13 W with nothing plugged in (12 of 12 rounds) | `harness/hdmi-power/`; `patches/hdmi-rails-off-in-sleep.patch` (built, not booted) |
| SD reader link without ASPM L1 | 0.37 W | `harness/awake-ab/` |

## Sleep

| Result | Numbers | Where |
|---|---|---|
| s2idle, PMP running | 1.39 to 1.46 W over 9.6 h (23% of the battery a night) | `data/s2idle/` |
| s2idle, stock, on battery | 1.41 W | research "Overnight s2idle with the PMP" |
| s2idle, everything optional off | 2.1 W (the SD link without L1) | `data/s2idle/` |
| macOS 15.7.1 sleep | 0.24 W over 5.9 h, 98.7% of it in S2R | issue #3 |
| Overnight s2idle, 10-23 to 10-24 | 8.33 h, a clean wake; 3.4 SoC wakes a second, 72% from the AOP mailbox; drain hidden by the charge limit (only a 0.57 W lower bound) | `data/overnight/` |

What wakes the SoC in s2idle is the AOP. Its ambient-light and lid-angle
reports arrive every 200 ms, and those drivers have no suspend hooks. The
wakes cost milliwatts. The 1.4 W is power left on.

## S2R, piece by piece

| Piece | State | What is known | Next |
|---|---|---|---|
| Timed wake | **works** (deepidle3) | The PMU RTC alarm, SPMI irq 2 on AIC 724. The PMU's "fired" bit must be cleared before re-arming. `rtcwake -m freeze` woke 3 of 3 | Shape it for upstream; the PMU power-on from off is untested |
| AIC | **built** (kernel 1ac4376) | Save and mask every bank, restore on resume (syscore) | Inert until a `deep` state exists |
| SMC handshake | **tested** | `WKTP` and `slpw` are harmless. `slpa` makes the SMC take the storage down: NVMe I/O fails after resume, it outlasts a warm reboot, and only a full power off clears it | `slpa` goes last, on the real S2R path only |
| PMP | IDLE works, the wake does not | IDLE acks in about 400 us. RUN alone: 0 of 3. Gating `ps_pms_sram`: no restart. A PMGR reset of `ps_pmp` crashes the SoC. `ps_pmp` is pinned on (PS_MIN 0xf) | macOS's DART off/on and outbox steps around RUN, no reset |
| Secondary CPUs | **built, not booted** (Phase 1) | PSCI-via-EFI. CPU_OFF is Aura's PMGR stop plus `cpu_sleep(true)`; CPU_ON restarts through PMGR and RVBAR | The first boot test |
| Boot CPU hand-back | designed | Its RVBAR entry lands in resident Aura, which today runs `m1n1_main()` again | SYSTEM_SUSPEND (Phase 2) |
| PMGR quiesce, S2R timer | read statically from macOS 13.5 | The last write goes to an always-on PMGR block that Linux does not map | The hypervisor trace (Phase 3) |
| Devices (PCIe L2, NVMe, Wi-Fi, DCP) | s2idle only | DCP cannot resume from power loss today | Phase 4, in the order the trace gives |
| Linux entry | `mem_sleep` shows only `s2idle` | PSCI SYSTEM_SUSPEND gives `deep` with no new core code | Phase 2 |

The phases are in `s2r-plan.md`:
* **0** remote hands: dropped, no extra hardware;
* **1** CPU_ON and CPU_OFF;
* **2** SYSTEM_SUSPEND with the SoC still on;
* **3** the macOS sleep trace under the hypervisor;
* **4** devices that survive power loss;
* **5** full S2R;
* **6** daily use.

## Built, not yet booted

| What | Where |
|---|---|
| Phase 1 kernel side: the RFC's 6 patches plus `t6020-j414s-psci.dts` | local branch `psci-efi-test` (on GH-1-DeepIdle); the DTS patch in `patches/psci-efi/linux/`; the RFC on lore, `20260708-efi-psci-v1-0-9efb3abf0e4c@kernel.org` |
| Phase 1 Aura side: `psci.c`, `smp_psci_*`, `dt_set_psci()` | Aura branch `psci-efi`; `patches/psci-efi/aura/` |
| Phase 1 U-Boot side: `efi_platform_register()` | `asahi-v2026.07-2` plus 1 commit; `patches/psci-efi/u-boot/` |
| Hypervisor sleep trace: CYC_OVRD logged and masked, not refused | Aura branch `hvsleep-trace` |
| macOS 14.8.3 guest setup | `tools/macos-hv-testvol.sh`, `tools/macos-hv-prep.sh`, `harness/hv/`, `harness/remote/hv-run.sh`, `tools/im4p-extract.py` |
| HDMI rails off in sleep | `patches/hdmi-rails-off-in-sleep.patch` |
| The PMP in s2idle (IDLE) | `patches/deepidle2-pmp-s2idle-idle.patch` (the hook is off; the wake is not solved) |

## How the testing works

* **The harness** (`harness/`, machine-specific, as run): one step per boot
  through a root runner. Every test boot image is used once, and an early
  unit puts the stock `boot.bin` back. The hardware watchdog is armed by
  systemd. The results stay on disk for the next session.
* **The Raspberry Pi 5** (`docs/pi-handoff.md`):
  * `pi-watch.sh` streams the Mac's kernel log off the machine during risky
    runs. It kept the only record of the `slpa` and PMP failures.
  * It is the USB host for Aura's proxy mode and the hypervisor.
  * It reaches the Mac over Wi-Fi.
* **Rules learned the hard way:**
  * Never remove and rescan PCI devices: it kills Wi-Fi until a reboot.
  * No `slpa` without the owner at the power key and the Pi watcher on.
  * Never reset `ps_pmp`.
  * Booting another kernel can delete module trees that pacman does not
    own: keep a `.keep` file in them.
  * Keep the screens off after every reboot. Turn Omarchy's stay-awake off
    only for a self-suspend, and back on right after.
* **Owner decisions:**
  * no extra hardware;
  * unattended PMP tests allowed;
  * every boot or proxy-mode step is announced and approved first;
  * the macOS guest is a separate 14.8.3 volume.

## Where things live

Everything public is in this repo: the docs, tools, harness, data and
patches. The kernel branch is `GH-1-DeepIdle` of linux-aurora (`patches/`).
Not pushed anywhere, and so carried here as patches: the PSCI test branch,
the two Aura branches and the U-Boot branch. The README's layout table lists
each path.
