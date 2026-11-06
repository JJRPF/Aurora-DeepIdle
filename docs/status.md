# Where the work stands (2026-11-05, 21:40, after runs C, G and H)

This is the summary of the whole effort: what was measured, what was built,
what works, what does not, and what comes next. Each section points to the
detailed write-up (`deep-idle-research.md`), the plan (`s2r-plan.md`), the
firmware interface (`psci-efi.md`), the run-by-run log (`worklog.md`) and the
raw data (`data/`).

The machine is a 14-inch MacBook Pro, M2 Pro (T6020, `apple,j414s`). It runs
Aurora Silicon Linux:
* default kernel `7.2.11-14-1-ARCH`; the S2R test kernel is 7.2.11 with the
  PSCI-via-EFI patches (`psci-efi-test-72`);
* m1n1 stage 1 v1.5.2, then stage 2 (Aura's PSCI build on test boots);
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
* **Suspend to RAM works, with the SoC still on.** Linux offers `deep`.
  PSCI `SYSTEM_SUSPEND` through Aura's EFI runtime handler passes 20 of 20
  cycles with all 10 CPUs and the PMP on, 0 device errors, waking on the
  PMU alarm and the power key (Phase 2, done 2026-11-04). The nine
  secondaries go off through CPU_OFF and come back through CPU_ON every
  cycle. Long sleeps on battery work too (1 h 46 min, 90 min). But it
  draws 1.37 to 1.49 W, the same as s2idle: parking the CPUs saves almost
  nothing while the SoC stays up.
* **The SoC does not power down yet, and now it is known why not.** Ten
  owner-attended `slpa` runs (2026-11-04 and 05). Every one without the
  S2R timer came back on the alarm with the storage controller (ANS)
  dead, and the dead-man switch reset the Mac each time. The PMGR's own state counters, readable from
  Linux since 2026-11-05, show the SoC in `AWAKE` for the whole cycle
  (`SLP_S2R` 0). So the SMC's `slpa` takes the storage controller's power
  but does not start the SoC's sleep. That entry belongs to the PMGR (the
  S2R timer and the PMGR quiesce), which Aura has to do.
* **2026-11-05 evening: the PMGR's S2R timer, the first PMGR write the SoC
  acts on.** Image 52 adds macOS's last PMGR step (1 to MPMGR_AON + 0x4000)
  and macOS's all-core deep sleep to Aura's suspend. In owner-attended runs
  the timer reset the Mac about 60 s after it was written whatever the alarm
  did (D, D2), also with every core powered down (E). The cores alone ended
  in Aura's watchdog reset (F). So the S2R entry starts but does not
  complete; the rest of macOS's PMGR quiesce (clock gates, PLL-off, GPU) is
  next.
* **Estimate: about 45% of the way to working S2R** (risk-weighted guess,
  wide error bar; 33% earlier on 2026-11-04, before Phase 2 closed). Per
  phase: remote hands 100 (replaced by software), CPU_ON and CPU_OFF 85,
  SYSTEM_SUSPEND 100, macOS trace 55, devices 15, full S2R 10, daily use 0.
* **2026-11-05, late evening (unattended):** the rest of macOS's PMGR
  quiesce is decoded and built (image 53: the GPU fabric domain `afr` off,
  the SmartIO domains' auto power-on off, the clock-generator and PLL-off
  writes), and a lead for the storage controller: Apple coprocessors boot
  from a boot-address register (IO RVBAR) that iBoot sets once and macOS
  rewrites on every start, and Linux never does. The test kernel now saves
  and restores it; both pass their normal-path checks.
* **2026-11-05, 18:00:** the PMP crash in run C was a bug in the test
  kernel, not a missing step: it told the PMP the AP's sleep state twice,
  and the PMP firmware (read from macOS 13.5) panics ("Invalid AP power")
  when given the state it already has. Fixed (one IDLE request, macOS's
  order) and checked in a normal suspend, 2 of 2. One difference is left
  on the PMP side: before `slpa`, macOS has released every PMP power
  request but the two CPU complexes (`0x300`); Linux still holds ISP and
  the three display ones (`0xf000`).
* **2026-11-05, 18:04: run A again, attended:** `slpa` does not clear the
  storage controller's boot address, so that lead is wrong. Its firmware
  does start after `slpa` (it answers the first handshake), but it never
  acknowledges power-on. Most likely the storage power the SMC cut at
  `slpa` only comes back with a real SoC sleep and wake. So the SoC sleep
  comes first. The Mac reset itself, and the disk is clean.
* **2026-11-05, 18:16: the PMP's display requests released for sleep, as
  macOS has them at `slpa`.** A test kernel switch withdraws the three
  display requests in each suspend and asserts them again on resume. In a
  normal suspend the PMP acks both (requests `0xf000` → `0x1000` → back to
  `0xf000`), 2 of 2, 0 device errors, the panel still connected. Only ISP's
  request differs from macOS now. The sleep A/B on battery with it is next.
* **2026-11-05, 20:27: the sleep A/B the owner asked for.** What we have
  now (suspend to RAM through Aura, every CPU parked, the PMP's display
  requests released) drew 1.458 W for an hour on battery; s2idle in the
  same boot 1.504 W. That is 3% less, the same small gap as in the
  morning, and the display release added nothing measurable. macOS: 0.24 W.
  The rest of the gap needs the SoC itself to sleep.
* **2026-11-05, 21:20 to 21:35: owner-attended runs C, G and H.** C: the
  PMP now accepts macOS's sleep request (no crash), but without the S2R
  timer the SoC stays awake. G and H: macOS's whole PMGR quiesce (power
  domains, clock generator, PLL-off) before the timer, with every core
  powered down. Both reset 85 s after `echo mem`, as D and E did: the S2R
  entry still does not complete. What none of the runs did together is the
  PMP's sleep request and the PMGR steps in the same sleep, which macOS
  does: that is run I. The Mac reset itself each time, and the disk is
  clean.
* **Next (owner-attended):**
  * run I: C and H together, the PMP's sleep request and the whole PMGR
    quiesce before the S2R timer, as macOS does both;
  * if the entry still does not complete: the cluster power-off step and
    the PMU's SPMI quiesce;
  * then the devices that lose power (Phase 4), DCP above all.

## The last two days

* **2026-11-04 evening: Phase 2 done on the full system.** 20 of 20 cycles on
  the boot CPU alone (image 41) and **20 of 20 with all 10 CPUs** (image 47;
  the nine secondaries go through CPU_OFF into a retention park and come back
  with CPU_ON every cycle), 0 device errors. The hotplug failures of October
  came from two things: parked cores used deep WFI *without* retention (never
  woken back properly), and a re-onlined core inherited CYC_OVRD WFI_MODE 3
  from the park. Kernel side, two unwinds of the EFI call that never returns
  (SYSTEM_SUSPEND, CPU_OFF). Image 48 is the clean reference build.
* **2026-11-04, 21:32: the first `slpa` inside a real suspend** (image 48,
  all CPUs, `macsmc_reboot.deep_steps=6`) did not power the SoC down. Every
  NVMe read and write failed afterwards (btrfs `-5`, root read-only); no
  watchdog fired, and the owner reset the Mac by hand after about 15 min. A
  read-only scrub found no errors. A dead-man switch now covers every
  `slpa` run: it reads the disk directly after the wake and, if it is gone,
  pushes the evidence to the owner and resets the Mac.
* **2026-11-05, early: why the disk died, and a fix to try.** The SMC cuts
  the ANS's power after `slpa`, and it never boots again. macOS rewrites
  the ANS's SART (its DMA windows) every time it starts the ANS; Linux never
  did. The test kernel now saves the SART at suspend and restores what
  changed (a no-op on 4 of 4 normal wakes). Drain A/B on battery: suspend to
  RAM 1.37 W, s2idle 1.39 to 1.41 W.
* **2026-11-05, 07:01: the second `slpa` run** (image 49, SART restore, 60 s
  alarm) came back on the alarm with the ANS dead again, and the dead-man
  switch reset the Mac. It was first read as a reset without a resume; its
  push to the owner's phone, read at 15:57, shows the resume.
* **2026-11-05, morning (static, from macOS 13.5):** macOS tells the PMU the
  AP is asleep (boot stage 0x50) and gives the SMC a 10 s deadline as it
  sleeps. The PMGR's AP wake-source mask is all open under Linux; macOS's
  narrower mask stops even Aura's normal deep-WFI wake, so it is not a
  drop-in. The AIC restore is already covered, and the system cache needs no
  flush before S2R.
* **2026-11-05, day (unattended):** long suspends on battery under Aura:
  1 h 46 min at 1.44 W and 90 min at 1.49 W, against s2idle's 1.48 W. The
  PMGR's state counters work: through every suspend and awake idle so far
  only `AWAKE` counts. Image 51 resumes Linux if a real S2R wake reaches
  Aura, even with no wake line showing.
* **2026-11-05, afternoon: owner-attended runs A, B and C** (image 51,
  `slpa`, 30 s alarm). A: `slpa` alone. B: plus the PMU boot stage 0x50.
  C: plus macOS's PMP IDLE steps. All three resumed on the alarm with the
  ANS dead, and the dead-man switch reset the Mac. Boot stage 0x50 changed
  nothing. In C the PMP firmware crashed on IDLE (a test kernel bug, found at 18:00), the SART was intact (not
  the cause), and the PMGR counters showed the SoC `AWAKE` throughout. A
  first reading of run A ("the AP went down and booted cold") was wrong and
  is corrected in the worklog (15:57). Disk and filesystem clean after
  every run.

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
| 10-23 | PMP wake tests (RUN only: 0/3; SRAM gate: no restart; `ps_pmp` reset: SoC crash); **S2R plan**; macOS data collected for the hypervisor run |
| 10-24 | Overnight s2idle (8.3 h, clean); **Phase 1 built** (PSCI CPU_ON/CPU_OFF through EFI in kernel, Aura and U-Boot) |
| 10-25 | macOS 14.8.9 guest under the Aura hypervisor; **macOS's sleep entry traced in order** (runs 7 to 11); Aura as the stage 2 boots Linux; **CPU_ON of all nine secondaries works** |
| 10-31 | CPU hotplug tests limited to a RAM-only boot (they had damaged the filesystem); **SYSTEM_SUSPEND on the boot CPU, 20 of 20** (image 16, `maxcpus=1`) |
| 11-03 | Kernel moved to 7.2.11; Phase 2b, Aura waiting for a wake line, starts |
| 11-04 | Aura wakes on the RTC alarm (through the AIC's `HW_STATE`) and the power key; hardware watchdog around SYSTEM_SUSPEND, proven by a deliberate hang; **Phase 2 done: 20 of 20 with all 10 CPUs and the PMP on**; first `slpa` in a real suspend: NVMe dead, reset by hand; dead-man switch |
| 11-05 | SART save/restore; drain A/B on battery; long suspends (1 h 46 min, 90 min); **PMGR state counters readable from Linux**; owner-attended `slpa` runs 07:01, A, B, C: the SoC stays `AWAKE`, the ANS does not boot after `slpa`; image 52, runs D to F: **the PMGR's S2R timer acts** (a reset about 60 s later unless the entry completes); image 53 (the rest of macOS's PMGR quiesce, attended runs pending); run C's PMP crash traced to a test kernel bug; run A again: the ANS boot address is not the cause; the PMP's display requests released for sleep |

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
| Suspend to RAM, image 49, all CPUs in Aura’s deep WFI | 1.365 W over 30 min (the first cycle, 0.80 W, started at a full battery and is not counted); s2idle in the same boot 1.390 and 1.413 W | `data/drain-ab/` |
| Suspend to RAM, image 50, all CPUs, one long cycle (2026-11-05) | 1.444 W over 1 h 46 min on battery, 106 watchdog heartbeats, 0 device errors; woke early on an SMC mailbox event | `data/drain-ab/` |
| s2idle, image 51 test kernel, one long cycle (2026-11-05) | 1.478 W over 1 h 45 min on battery, the A/B partner of the row above: suspend to RAM with parked CPUs saves about 0.03 W | `data/drain-ab/` |
| Suspend to RAM, image 51, 90 min, PMGR counters on (2026-11-05) | 1.489 W on battery; the PMGR’s counters show the SoC in AWAKE for the whole sleep. The three long runs (1.44 to 1.49 W) put suspend to RAM and s2idle within the run-to-run spread | `data/drain-ab/` |
| Sleep A/B, image 53, 1 h each, same boot (2026-11-05 evening) | **suspend to RAM 1.458 W** (every CPU parked, the PMP's display requests released) against **s2idle 1.504 W**: 0.046 W (3%) less. Releasing the display requests saved nothing measurable (1.444 W without it in the morning). The SoC stayed `AWAKE` in both | `data/drain-ab/` |
| macOS 15.7.1 sleep | 0.24 W over 5.9 h, 98.7% of it in S2R | issue #3 |
| Overnight s2idle, 10-23 to 10-24 | 8.33 h, a clean wake; 3.4 SoC wakes a second, 72% from the AOP mailbox; drain hidden by the charge limit (only a 0.57 W lower bound) | `data/overnight/` |

What wakes the SoC in s2idle is the AOP. Its ambient-light and lid-angle
reports arrive every 200 ms, and those drivers have no suspend hooks. The
wakes cost milliwatts. The 1.4 W is power left on.

## S2R, piece by piece

| Piece | State | What is known | Next |
|---|---|---|---|
| Linux entry | **works** | PSCI `SYSTEM_SUSPEND` through EFI gives `deep` with no new core code; `echo mem` and `systemctl suspend` both work | |
| Secondary CPUs | **works inside suspend** | CPU_OFF parks each core in Aura in deep WFI with retention; CPU_ON hands it the kernel's entry. 180 pairs per 20-cycle gate, 0 errors | Runtime hotplug outside suspend (RAM-only boot); a core that really loses power |
| Boot CPU hand-back | **works with the SoC on** | Aura waits in deep WFI, watches the alarm and SMC lines, re-arms the watchdog every 60 s, and resumes the kernel. Its RVBAR path resumes the kernel after a real power loss too (image 51), not reached yet | The first real S2R wake |
| Timed wake | **works** | The PMU RTC alarm, SPMI irq 2 on AIC 724. The PMU's "fired" bit must be cleared before re-arming | Shape it for upstream; the PMU power-on from off is untested |
| Key wake | **works** | The SMC mailbox line 865 wakes Aura on the power key (1 of 1, owner at the Mac) | Lid wake, expected the same way, not tested |
| AIC | **works** (kernel 1ac4376) | Save and mask every bank, restore on resume (syscore); runs every suspend | |
| Recovery | **works** | SoC watchdog around SYSTEM_SUSPEND (proven by a deliberate hang); dead-man switch after `slpa` runs | |
| SMC handshake | **tested** | `WKTP` and `slpw` are harmless. `slpa` makes the SMC cut the ANS's power; the Mac still resumes on the alarm | `slpa` goes last, after the PMGR's own entry |
| PMGR sleep entry | **started** (images 52, 53) | Aura writes the S2R timer (`MPMGR_AON` + 0x4000); it resets the SoC about 60 s later unless the entry completes, and it does not complete with `slpa` and every core powered down (runs D to F). Image 53 adds the rest of `quiesceHW` (the GPU fabric domain off, the SmartIO auto power-on off, the clock-generator and PLL-off writes), built and regression-checked | G and H (11-05 21:30): the whole quiesce before the timer still resets at 85 s. Next: run I (with the PMP's IDLE), then the cluster power-off step (likely `0x28e080060` to `0x70`) |
| NVMe (ANS) | **fails after `slpa`** | Clean in every Phase 2 cycle. After `slpa` the ANS firmware starts (answers the RTKit HELLO) but never acks IOP power-on (`-62`), CPU status 0x08. The SART and its boot address (IO RVBAR) are intact (run A, 11-05 18:04). Likely waits on the storage power the SMC cut, which only a real S2R wake restores | Comes after the SoC sleep (runs C, G, H) |
| PMP | IDLE works, the wake does not | IDLE acks in about 400 us in s2idle. Run C's crash after `slpa` was the test kernel's double SetAPPower (fixed 11-05). The display requests are released for sleep and come back (test switch, 2 of 2); only ISP's stays. RUN alone: 0 of 3. A PMGR reset of `ps_pmp` crashes the SoC | Run C again (attended), with the release |
| Devices (PCIe L2, Wi-Fi, DCP) | s2idle only | DCP cannot resume from power loss today | Phase 4 |

The phases are in `s2r-plan.md`:
* **0** remote hands: replaced by software recovery;
* **1** CPU_ON and CPU_OFF: 85%;
* **2** SYSTEM_SUSPEND with the SoC still on: done;
* **3** the macOS sleep trace under the hypervisor: 55%;
* **4** devices that survive power loss: 15%;
* **5** full S2R: 10%;
* **6** daily use: not started.

## Built and booted (test kernel and images)

| What | Where |
|---|---|
| Kernel: the PSCI-via-EFI RFC's 6 patches, `t6020-j414s-psci.dts`, the two EFI unwind fixes, the PMU alarm, and the `TEST:` S2R options (`macsmc_reboot.deep_steps`, `macsmc.pmp_sleep`, the SART save/restore, the PMU boot stage, the PMGR wake mask, the ANS IO RVBAR restore, `pmp_report.test_release_aon`), all off by default | local branch `psci-efi-test-72`; `patches/psci-efi/linux/` |
| Aura: CPU_ON, CPU_OFF, AFFINITY_INFO, SYSTEM_SUSPEND (image 51); the PMGR S2R steps behind a control word set from Linux (images 52, 53, `harness/mmio/aura-ctl.c`) | Aura branch `psci-efi`; `patches/psci-efi/aura/` |
| U-Boot: publishes Aura's PSCI table, keeps its runtime ranges | `asahi-v2026.07-2` plus 2 commits; `patches/psci-efi/u-boot/` |
| Harness: one-boot images, early restore, run, dead-man switch, attended runs | `harness/psci-efi/` |
| PMGR state counters, read from Linux | `harness/mmio/pmgrcnt.c` |
| Hypervisor sleep trace: CYC_OVRD logged and masked, not refused | Aura branch `hvsleep-trace`; `patches/hvsleep-trace/` |
| macOS guest setup | `tools/macos-hv-testvol.sh`, `tools/macos-hv-prep.sh`, `harness/hv/`, `harness/remote/hv-run.sh`, `tools/im4p-extract.py` |

## Built, not yet booted

| What | Where |
|---|---|
| HDMI rails off in sleep | `patches/hdmi-rails-off-in-sleep.patch` |
| The PMP in s2idle (IDLE) | `patches/deepidle2-pmp-s2idle-idle.patch` (the hook is off; the wake is not solved) |

## How the testing works

* **The harness** (`harness/`, machine-specific, as run): one step per boot
  through a root runner. Every test boot image is used once, and an early
  unit puts the default `boot.bin` back and checks its hash. The hardware
  watchdog is armed by systemd, and by Aura inside SYSTEM_SUSPEND. The
  results stay on disk for the next session.
* **The dead-man switch** (`harness/psci-efi/deadman.sh`): for `slpa` runs.
  It runs from RAM, reads the disk directly after the wake, and if the disk
  is gone pushes the kernel lines, the PMGR counters and Aura's debug words
  to the owner's phone, then resets the Mac. Those pushes are the record of
  what happened.
* **Owner-attended runs** are one command each (`harness/psci-efi/attended.sh`):
  it checks the boot partition and image, arms the run, tells the owner by
  push when to hold the power key, and reboots.
* **The Raspberry Pi 5** (`docs/pi-handoff.md`):
  * `pi-watch.sh` streams the Mac's kernel log off the machine during risky
    runs. It kept the only record of the first `slpa` and PMP failures.
  * It is the USB host for Aura's proxy mode and the hypervisor.
  * It reaches the Mac over Wi-Fi.
* **Rules learned the hard way:**
  * Never remove and rescan PCI devices: it kills Wi-Fi until a reboot.
  * `slpa` runs only when the owner is at the Mac, ready to reset by hand.
  * CPU hotplug tests only in a boot that cannot touch the root filesystem.
  * Never reset `ps_pmp`.
  * Booting another kernel can delete module trees that pacman does not
    own: keep a `.keep` file in them.
  * Keep the screens off after every reboot. Turn Omarchy's stay-awake off
    only for a self-suspend, and back on right after.
* **Owner decisions:**
  * no extra hardware;
  * unattended PMP tests allowed;
  * boot steps may proceed without asking, except `slpa` runs;
  * the macOS guest is a separate volume.

## Where things live

Everything public is in this repo: the docs, tools, harness, data and
patches. The kernel branch is `GH-1-DeepIdle` of linux-aurora (`patches/`).
Not pushed anywhere, and so carried here as patches: the PSCI test branch,
the two Aura branches and the U-Boot branch. The README's layout table lists
each path. Work is tracked in the GitHub Project "S2R on M2 Pro (J414s)".
