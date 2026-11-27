# M2 Max (J414c, T6021) on top of the M2 Pro S2R patches

Diffs that go on top of the M2 Pro diffs in the parent folder. With them, the R62Y-4 recipe gives a real suspend-to-RAM and wake on a 14-inch M2 Max (J414c, T6021, 12 CPUs).

| File | Apply after | What it does |
|---|---|---|
| `kernel-t6021-j414c.diff` | `../kernel-on-omacom-linux-aurora-7.3-8ca67c75ff52.diff` | Adds `t6021-j414c-psci-pmp.dts` (PSCI through EFI, PMP booted, modelled on `t6020-j414s-psci-pmp.dts`). Lets `macsmc` set WKTP and the wake mask on `apple,t6021` as it does on `apple,t6020`. |
| `aura-t6021.diff` | `../aura-on-omacom-m1n1-bf6a6417.diff` | Lets T6021 use the T6020 suspend path, and adds what the Max has on top: a sixth soc-cluster (DISPLAY2), the dispext2/3 power words, five gate words macOS 13.5 zeroes at sleep entry, two more IOA error enables, memory-cache controllers 4-7, and room for their runtime MMIO ranges. |
| `kernel-cancelled-sleep.diff` | the two above | Not Max-specific. Keeps the display and GPU alive when a sleep is cancelled on the way down; see below. |
| `kernel-commit-late.diff` | any of the above | Not Max-specific. Stops a wake event from cancelling a firmware suspend once its late stage has begun, which avoids a panic in the SEP driver; see below. |
| `kernel-rtc-rearm.diff` | `kernel-commit-late.diff` | Re-fires an RTC alarm that arrives after the commit point, 15 s later, so it wakes the machine after the cut instead of being lost; see below. |
| `kernel-bcm4377-probe.diff` | any kernel | Not Max- or sleep-specific. Fixes a Bluetooth probe failure and the use-after-free behind it, reached when a suspend is cancelled at the freeze stage; see below. |

**Base:** all six diffs were made and tested on the parent diffs at `c2b1eac`. The kernel diffs below were last tested as a kernel built from exactly the parent diffs at `c2b1eac` plus the five kernel diffs here, with no other changes.

No change to the R62Q-R62Y kernel code was needed. The `apple,t6020-pmp-v2` and `apple,t6020-pcie` matches and the disp0 power cycle apply to the Max as they are.

The device tree is left out of the Makefile because it has the same compatible as `t6021-j414c.dtb`; build it by name (`make apple/t6021-j414c-psci-pmp.dtb`).

## What was tested

One J414c, nothing plugged in. Kernel: this repo's 7.3 diff at `c2b1eac` plus the diffs here. Aura: image 129 from the Aura diff at `c2b1eac` plus `aura-t6021.diff`. Counts are runs.

RAM root (initramfs only, root and home never mounted), nothing unbound, `pm_async=0`:

- Two real sleeps in one boot, both back, `echo mem` returned 0 (first on the diffs at `eacbc56` with Aura 128, then again at `c2b1eac` with Aura 129).
- Real S2R: `SLP_S2R` advanced on every sleep; CPUs 0-11 back.
- Internal display: `internal DCP A500: 0`, `disp0 cycle complete: cpu0 0x1f0403ff fe 0x3ff sys 0x3ff (0 0 0 0 0 0)`, `internal DCP warm restart complete (0)`; eDP-1 connected and enabled, backlight back.
- GPU (`aurora 406400000.gpu`): kept bound, `GPU firmware idled for sleep`, `GPU firmware restarted warm (kick Ok(()))`.
- SEP: `the enclave is back from its sleep request`; the second sleep was accepted.
- PMP: restarts after the wake, no ack timeouts.
- PCIe: `unbound 3 endpoint(s) before freeze`, both dart-apcie tunables restored, rescan finds the devices; Wi-Fi scans after the wake. NVMe live.

The same kernel and Aura also run the daily desktop (Hyprland), where sleeps ended by an RTC alarm and by opening the lid came back. Those results are in issue #5.

## Cancelled sleeps (`kernel-cancelled-sleep.diff`)

A sleep cancelled on the way down (a wake event, or a device refusing) left the display and GPU firmware down: both had been idled early in the suspend, and neither answered the wake that followed (`RTKit: IOP power acknowledgment failed: -62`). On the desktop the compositor then exits. Reproduce with `echo devices > /sys/power/pm_test; echo mem > /sys/power/state`.

The diff:

- **Internal DCP:** on the cancelled path, restart it as after a real sleep (disp0 cycle, warm restart, run, boot), reusing the R62W restart. `appledrm.s2r_refused_cycle=0` gives the old behaviour.
- **GPU:** idle its firmware in `suspend_late` instead of `.prepare`, so a cancel in the device stage never touches it. This is @nekolyanich's approach from `m2pro-s2r-wip`. `aurora.g14_s2r_idle_late=0` gives the old behaviour.

Tested (counts are runs):

- This diff, on the desktop with Hyprland: a `pm_test=devices` cancel left the compositor up with 0 failed GPU submits and Wi-Fi and Bluetooth back, 2 of 2; a real sleep after it came back (`GPU firmware idled for sleep`, `restarted warm (kick Ok(()))`), 2 of 2. In a RAM root on the clean build: sleep, cancel, sleep, 1 of 1.
- The same two changes in an earlier build that also carried the recovery experiments below: DCP restart, 16 of 16 cancelled sleeps in a RAM root and 1 of 1 on the desktop. Later GPU idle, 2 of 2 device-stage cancels in a RAM root and 1 of 1 on the desktop; real sleeps restarted the GPU warm 3 of 3 in a RAM root and 1 of 1 on the desktop.

Not fixed:

- **A GPU that was idled and then not slept stays down.** Plain wake, warm restart, CPU stop then warm restart, and CPU stop, `apple_pmgr_ps_cycle()` of the GFX domain, then warm restart all ended in ETIME, with the GFX power word at `0x1f0003ff`. None of them is in the diff; that path is unchanged.
- **A cancel after the late stage hangs until the watchdog** (`pm_test=platform`, 2 of 2). The SEP is the last device in the suspend crumbs. Not investigated.

## A wake after the late stage (`kernel-commit-late.diff`)

With `kernel-cancelled-sleep.diff`, a cancel in the device stage is safe. A later cancel is not:

- The GPU firmware is idled in `suspend_late` and has no way back without a real sleep (above).
- The SEP is told to sleep in its `suspend_noirq` (`noirq_direct`). If the suspend is cancelled after that, `sep_pm_commit_finish()` in `pm_shim.c` panics: `SEP SLEEP was sent without a physical sleep/wake`.

The diff: from the start of `dpm_suspend_late()`, `pm_wakeup_pending()` returns false for a firmware-driven suspend until the resume begins. `pm_s2r_commit_late=0` (`/sys/module/kernel/parameters/`) gives the old behaviour.

Tested (counts are runs). The alarm cases used one extra test-only delay of 3 s after the noirq stage, so an RTC alarm could be timed into it:

| Case | Without the diff | With the diff |
|---|---|---|
| `pm_test=platform` cancel | did not come back, 3 of 3 (came back 1 of 1 with `module_blacklist=apple_sep`) | not tested |
| RTC alarm landing after the noirq stage | panic, 1 of 1; Aura's reset record holds `vpanic` → `emergency_restart` → `do_kernel_restart` | sleep completed, no panic, 2 of 2 |
| Desktop (Hyprland): device-stage cancel, then a real sleep | | both as before, 1 of 1 |

Cost: the event that would have cancelled the suspend is dropped. An RTC alarm landing after the late or noirq stage did not wake the machine afterwards; it slept until a key press, 4 of 4. Two causes:

- In the late stage device interrupts are still on (`suspend_device_irqs()` runs in `dpm_suspend_noirq()`), so `macsmc_rtc_alarm_irq()` runs as usual: it clears and disarms the PMU alarm and reports no wakeup event. That is also why the suspend wasn't cancelled there even without this diff.
- After the noirq stage the alarm IRQ is an armed wake IRQ: with this diff it is ignored, its handler never runs, and no new alarm interrupt follows the cut.

## RTC alarm during the sleep entry (`kernel-rtc-rearm.diff`)

Reduces that cost for the first case. When the alarm fires while `pm_wakeup_abort_held()` (from `kernel-commit-late.diff`) is true, `macsmc_rtc_alarm_irq()` re-arms it 15 s later instead of consuming it, so it fires after the cut and wakes the machine. 15 s because the SEP's `suspend_noirq` alone waits 5 s on every sleep here.

Tested: an RTC alarm timed into a 3 s test-only delay after the late stage. The driver logged `alarm during sleep entry: fired again 15 s later`, and the machine woke by itself after 7.8 s of `SLP_S2R`, 1 of 1 (without this diff it slept until a key press, 3 of 3). On the desktop, a device-stage cancel and a real sleep behaved as before, 1 of 1 each.

Not covered: an alarm firing after the noirq stage. No kernel code runs between that interrupt and the cut, so re-arming it would have to happen in Aura's entry.

## Bluetooth after a suspend cancelled at the freeze stage (`kernel-bcm4377-probe.diff`)

A lid-open about a second after closing cancelled a suspend while tasks were being frozen. `apple_pcie_s2r_post_thaw()` re-attached the Bluetooth function, and its probe failed with `Driver probe function unexpectedly returned 1`. The next wake crashed in `bcm4377_enqueue()`, the next suspend crashed in `bcm4377_hci_wakeup()` inside the suspend notifier, and every suspend after that failed with `-EBUSY` until a reboot.

Cause: `bcm4377_probe()` treats any nonzero return from `hci_register_dev()` as an error, but it returns the new device index on success. After the cancel, user space had been frozen right after the unbind and thawed just before the re-attach, so the old `hci0` was still held; the new device became `hci1`, the probe returned 1, devres freed the device's data, and `hci1` stayed registered. The same check is in upstream `hci_bcm4377.c`.

Repro without a sleep: `bt-rebind-frozen.sh` here pauses `bluetoothd` and `obexd`, unbinds and rebinds `0000:01:00.1`, then resumes them. Without the fix: `hci1` and the probe failure, 1 of 1 (without pausing the daemons the old index is released in time, 1 of 1).

The fix checks `ret < 0`. With it: the same repro gave a working `hci1` with no probe failure, and a real sleep right after came back with Bluetooth re-probed as `hci0`, 1 of 1.

## External displays after a sleep (`kernel-dcpext-sleep.diff`)

After the first real sleep, external displays stay dark until a reboot. `dcp_fw_s2r_suspend()` gives the internal DCP the warm stop (firmware idled, CPU stopped, memory kept), but it shuts the two external DCPs down and marks them dead (`ext_dead`), and resume skips them. Docking after a sleep logs `RTKit: Endpoint 0x2a is not running` and `dcp_dptx_connect: failed to validate DPTX target 0:2: -110`, and no display is detected. After a fresh boot the same dock brings up both displays.

The external DCPs have the internal one's power layout: `dispextN_cpu0` inside `dispextN_fe` inside `dispextN_sys`. The diff gives them the same stop and restart (power cycle through those domains, warm restart, run, boot), without the internal display's A500, then runs their usual resume (Type-C work, audio service). `appledrm.s2r_fw_restart_ext=0` brings back the shutdown.

## On the current parent diffs

Against the parent diffs at `929cd58` (Aura 130). Applied only; not built or booted there:

- `aura-t6021.diff` applies.
- `kernel-cancelled-sleep.diff` applies.
- `kernel-commit-late.diff` applies.
- `kernel-rtc-rearm.diff` applies.
- `kernel-bcm4377-probe.diff` applies.
- `kernel-t6021-j414c.diff` does not; use `kernel-t6021-j414c-dts-only.diff` (see the update below).

## Update 2026-11-26: on the current (gating) diffs

The `macsmc` hunk of `kernel-t6021-j414c.diff` no longer applies to the refreshed `../kernel-on-omacom-linux-aurora-7.3-8ca67c75ff52.diff` and is no longer needed: macsmc has no `apple,t6020` check or wake table any more. The wake mask address and sources now come from `/chosen` (`aurora,ap-wake-mask-reg`, `aurora,ap-wake-sources`), which Aura fills from the ADT `pmgr` `ap-wake-sources`, for any chip whose ADT has it. Use `kernel-t6021-j414c-dts-only.diff` (the device tree alone) with the refreshed diffs. `aura-t6021.diff` still applies to the refreshed Aura diff. Neither combination has been booted on a J414c; whether the T6021 ADT carries `ap-wake-sources` is not checked.

## Caveats

- **The Max needs `echo 0 > /sys/power/pm_async` before sleeping.** With the default (parallel device suspend) it hangs during device suspend. Cause unknown.
- `aura-t6021.diff` still carries a WFI-only retention path for T6021 (`psci_j414c_retention`). It runs only when the Aura control word has no entry steps, which is not the default.
- `apple-pmgr-pwrstate ...power-controller@c000: PS prores: resync after sleep failed: -5` appears after every real wake. Nothing uses that domain in this build.
- Not tested: speakers, external displays or a dock, SD card, Bluetooth pairing, a heavy GPU job across a completed sleep.

## Credits

- @JJRPF: the sleep itself, the warm DCP and GPU restarts, the PMP and SEP handling and the PCIe detach, all in the parent diffs. The diffs here extend them to T6021 and to the cancelled path.
- @nekolyanich: the later GPU idle, from `m2pro-s2r-wip` and his notes in issue #5.
- Aurora base kernel: the comment on `apple_rtkit_sleep_return()` that an idled firmware does not come back with its power kept.
