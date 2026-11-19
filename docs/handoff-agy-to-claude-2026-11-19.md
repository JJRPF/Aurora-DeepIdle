# Handoff: AGY (Antigravity) back to the Claude Code session, 2026-11-19 15:15

Written at the owner's request after AGY stopped work. Worktree `/home/jjr/dev/Aurora-DeepIdle/GH-5-S2R-DjNaeemPaths` (branch `GH-5-S2R-DjNaeemPaths`), pushed to main up to `0ccf0fd`.
The Mac is on main (Omarchy), nothing is armed (`bootbin.sh status`: one-shot loader intact, PMU flag `00`), and `boot-test.bin` is still image 105 (`39980e97b1c1bb80`).

## Where S2R stands (all measured, details in `docs/worklog.md` from "R56A" on)

| Run | Image | Alarm | Result |
|---|---|---|---|
| R56A | 102 | +40 s | First RVBAR return (`0x6004 = 0x22`), but an immediate wake (see R56B) |
| R56B | 103 | +90 s | Telemetry: `SLP_DDR` entered, woke in under 1 s on wake bit 54 (`NUB.SPMI0Sw3IRQ`) |
| R56C | 104 | +80 s | `SLP_S2R` 77 s, woke on the alarm; Linux reached `macsmc_reboot_pm_resume_early` (`0x6003 = 0x30`) |
| R57A | 105 | +25 s | `SLP_S2R` 22 s, alarm wake; Linux never reached userspace (marker not written) |
| R57B | 105 | +25 s | Same, with the NVMe unbound (your job); `0x6003 = 0x50` this time; NVMe-resume hypothesis not supported |

So the SoC now really sleeps and wakes on the alarm, repeatably. What is open is the Linux side after the wake: `echo mem` never returns and the kernel is reset by `panic=10` or a watchdog 25 to 70 s later. There is no log from the woken kernel.

What changed the sleep from "reset after 60 s" to "real sleep" (the two causes, both shown by PMU crumbs):
1. Image 102 (`psci_ctl[5]` bit 7 = fifth word 241): all 110 macOS-OFF PMGR domains lowered including AUTO_ENABLE (`BIT(28)`), early `psci_quiesce_asc()`, early PCIe RC teardown, filtered MCC replay, and the 9 secondaries held in WFE until cpu0's edge. Not bisected, so which of these matters is unknown.
2. Image 104: my own `qs_crumb_write()` left `SPMI_IRQ_NOTIFY` (`0x29e114080` bit 0) unacked while `0x29e114040` bit 0 was enabled, which woke the SoC at once on wake bit 54. Acking it fixed the early wake.

## Changes AGY made to the Claude Code testing setup

Repo (all committed and pushed, git identity unchanged, trailer `Co-Authored-By: Antigravity <antigravity@google.com>`, no `Claude-Session` trailer):
- `docs/worklog.md`, `docs/s2r-status.json` (text inserts only, validated), `docs/status.md`: entries R55B result through R57A result. R57B's entries are yours plus mine (the R57B result).
- Jobs added under `harness/usbtest/jobs/`: `r56a-clean-alloff`, `r56b-confirm-90s`, `r56c-spmi-ack-80s`, `r57a-resume-25s`. `r57b-nonvme` and `r54a-commitorder` are yours.
  - `r57a-resume-25s` stamps `0x601f = 0xaa`, `0x6014 = rc`, `0x600c = nproc` into the PMU scratch right after `echo mem` returns. In R57B `0x601f` read `0xc0`, so something other than that job writes there; unexplained.
- Aura patches saved as `patches/psci-efi/aura/wip-image101.diff` to `wip-image105.diff` (plus 100).
- `docs/system-changes.md`: entries for local commits of images 102 to 105.

Outside the repo:
- **The post-boot resume hook now starts AGY, not Claude.** `~/.config/omarchy/hooks/post-boot.d/deepidle-resume` (repo copy `harness/usbtest/deepidle-resume`) runs `agy --conversation <id from ~/.local/state/deepidle/agy-conversation> --remote-control --dangerously-skip-permissions -i "$(cat ~/.local/state/deepidle/prompt.txt)"`. It is still armed (`~/.local/state/deepidle/resume` exists), so the next reboot launches AGY with conversation `9d371504-2971-4b20-916e-4dfc6cee21a8`. To give it back to Claude: `git show ed779b6:harness/usbtest/deepidle-resume > ~/.config/omarchy/hooks/post-boot.d/deepidle-resume` and delete `~/.local/state/deepidle/agy-conversation` (logged in `docs/system-changes.md`).
- Aura tree `~/Work/src/aura-img99` (branch `gh5-img99-local`, local only, never push): commits `5700a13b` (102), `206fad03` (103), `4e5f33cc` (104), `86776585` (105). Rule kept: commit before `make` so the embedded version has no `-dirty`. Images staged and packaged: `~/Work/psci-test/boot-test.bin.102` to `.105` (105 = `39980e97b1c1bb80`).
- Build warnings seen on every build: the `psci_efi_table` initializer overrides (old) and a misleading-indentation warning in `smp_psci_mmio_ranges` (`if (chip_id == T6020)` guards only its first `smp_psci_add_range`; the rest of that block runs on any chip; harmless on this Mac, not fixed).

Image changes in detail (all on top of your image 101, entry word `0xc17dcb3f 0 0 0 <fifth>`):
- 102 (fifth word 241): see above; also `cpu_sleep_boot_irq_route` in `utils.c` (note `smp_psci_edge_release_and_sleep()` calls `cpu_sleep(true)` directly, so the CPU0 IRQ-route change never took effect and CPU0 woke anyway with `IRQ/FIQ_MODE=2`); crumbs `0x600c` bit 7, `0x6014`, `0x601f`.
- 103: `qs_rvbar_telemetry()` in `psci_suspend_rvbar()`: elapsed s (`0x6005/6`), PMGR state counters (`0x6007..0x600b`, `0x6012/13`), first AP wake bit and count (`0x6015/16`, from `0x29e004030`), WD2 count/ctl (`0x601b/c`), RVBAR count (`0x601d`), wake line (`0x601e`).
- 104: W1C ack of `0x29e114080` and `0x29e154080` in `qs_crumb_write()` and around `NOTIFY_EN`; samples nub-spmi0 pending IRQs before the first crumb into `0x601e` when no line shows.
- 105: `psci_force_ps_lower()` domains saved in `qs_lower_save` and restored in `psci_quiesce_undo()`; secondaries marked cold after the RVBAR wake and started through `CPUSTART+4/+8` in `smp_psci_cpu_on()`; `smp_secondary_entry()` calls `psci_enter()` when the runtime is quiet. Not shown to help or hurt. The crumbs `0x26/0x27` it writes are overwritten by `0x22`, so they prove nothing.

## Things to know before trusting the notes

- `0x6003` reading: "0x30 = Linux ran `macsmc_reboot_pm_resume_early` before the reset, 0x50 = it did not" is an inference from the driver code, not tested directly.
- AGY used a planning-model step (plan then execute) for large edits; where its prose says "historic" or "first ever", the numbers behind it are the PMU bytes quoted in the worklog.
- A worklog statement worth re-checking: R56A's "CPU0 kept IRQ_MODE=0" was wrong; see the `smp.c:1346` note above (corrected in the R56A result entry).

## Pi and the network (unfinished, AGY was stopped mid-step)

- The owner said the Pi was reconnected to dd-wrt and is on `192.168.5.111`, and asked for it to be switched back to `LiveFreeOrDie`. `~/.local/state/deepidle/pi-ssh` still points at `192.168.1.112`.
- Done: SSH to `192.168.5.111` worked (key `~/.ssh/id_ed25519_pi`, host `core-node`). The Pi has saved NetworkManager connections `netplan-wlan0-dd-wrt` (active) and `LiveFreeOrDie` (inactive). Its tailscale address is `100.101.204.127`.
- Then AGY started a detached `nmcli con up LiveFreeOrDie || nmcli con up netplan-wlan0-dd-wrt` on the Pi (log `/tmp/wifi-switch.log` on the Pi). The command was cancelled on the Mac side before AGY saw the result. At 15:11 neither `192.168.1.112` nor `192.168.5.111` answered ping from the Mac, so the Pi has probably left dd-wrt but has not been confirmed on LiveFreeOrDie, and its new address is unknown. Next steps: check the router's DHCP leases or `tailscale status` for core-node, reach it at its new address, update `pi-ssh` if the address changed, and confirm `nmcli con show --active` there.
- Not touched on the Pi: `~/deepidle/hv-run.sh` and the hypervisor runs.

## What AGY was about to do (not started, nothing built or armed)

The owner chose "a definite cause over guessing": get a log out of the woken kernel instead of more unbind runs. Plan: a ramoops/pstore region (DT `reserved-memory` plus the kernel option) in the DeepTest kernel and device tree so the panic or hang after the wake is readable after the reset, with `panic=0` or a watchdog reset so the log is kept; or the Pi's kmsg stream once the Pi is reachable again. Open question to check first: whether DRAM contents survive the reset and iBoot's reuse on this machine, and whether Aura's own memory (`psci_dbg`) is already a safe place for the ring buffer. Without a console, a ring buffer in Aura's reserved region read by `scan-magic` after the return to main is another route.
