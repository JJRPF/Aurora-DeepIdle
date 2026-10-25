# Run 5 (2026-10-25 12:12-12:20): what the trace says about the hang

Offline reading of `~/deepidle/hv/20261025-121153-fifth/` (console.txt 98822 lines, hv.log; no wall-clock stamps in that run).

## Facts
* Start 12:12:49 ("starting the guest"); last console line (before the Pi's USB reopen) 12:20:45: 7 min 56 s in. The Aura USB proxy stopped
  answering; reboot via proxy failed twice (12:24 guard, ~12:29 agy); the owner found a blank screen and used the power key.
* All 10 CPUs ran in the guest. The tracers logged throughout: SMC (key reads, `MSX0`/`MSX2` polled 1152 times each, `MSxb` writes),
  PMP (`PMP started` at line 20985; mailbox traffic and `DEV_STATUS_TGT_WR` writes, 7435 PMP register writes in total).
* Near the end: `DEV_STATUS_TGT_WR` 0x2700 then 0x700 (PCPM0=1, PCPM1=1, ATC0-3_COMMON=0 in both), mailbox doorbell writes
  `0x28e3d12a0/c8/c0` with the sequence number at `0x28e3d12c0` going 0x46b..0x472, the last write of the run. No PMGR writes after boot,
  no CPUSTART after boot, no SMC sleep keys (`slpw`/`slpa`/`WKTP` write), no CYC_OVRD.

## Hypotheses (ranked) and what separates them
1. **macOS began to sleep and the machine did not wake. (Most likely, see docs/hv-boot-trace-reference.md: the display domain DISP0_FE went off 6 s before the end.)** For: 7:56 is guest boot (~2.5 min) plus the 5-minute `hvsleep` delay; the screen was blank;
   the SoC and its USB went away together. Against: no SMC sleep keys, no PMGR writes. (On T6020 sleep may go through the PMP only.)
   Test: after a run, the guest's own `/var/log/hvsleep.log` and `pmset -g log` say whether the job fired and why/when it slept
   (rerun `macos-hv-prep.sh` in the guest: it uploads the pmset data).
2. **The guest powered down the proxy's USB port or its PHY** (PMP/PMGR target writes for ATC), so the SoC kept running but the Pi lost it.
   Test: the screen would still be on, and the guest's console (serial=3) would still be live; a USB analyzer or `lsusb` at the Pi cannot tell.
3. **Tracer load.** The PMP/SMC tracers trap every register access (98 k lines in 8 min); a PMP or SMC timeout could hang the guest.
   Test: run with the PMP tracer off.
## Control run (needs a reboot and the owner at the Mac for the autologin step)
`HVSLEEP=0 hv-run.sh ...` (no sleep job) for about 12 minutes, same tracers. If it hangs too: hypotheses 2 or 3, not sleep. If it stays up:
hypothesis 1, then the sleep sequence is the data to record (it is in the log up to the last line).

## Run 6 result (2026-10-25 17:03-17:19, control: HVSLEEP=0, owner at the Mac)
* 15 minutes (906 s of PMP target writes, 104 578 console lines, now with wall-clock stamps), no hang. The display domain (DISP0_FE) was off from
  about +13:58 for over a minute (the owner was not touching the Mac then) and the guest and proxy stayed up. Display-off alone is not the trigger.
* The run ended at 17:18:54 when the owner restarted the guest from its Apple menu: the PMP targets ramp to 0x0 (DISPEXT0/1, DP0-3 on briefly,
  then everything off: 0x4700, 0xc700, 0xe700, 0xe300, 0xc300, 0x8300, 0x300, 0x200, 0x0 within a second), the proxy lost the Mac
  (SerialException) and the Mac booted its default, Linux, at 17:19:35. A guest restart under the hypervisor works end to end.
* So with the sleep job off the guest lives; with it on (run 5) it stops 7 min 56 s in after the display goes off. Together with the PMP
  sequence this points at macOS system sleep entering and not coming back (wake alarm or not). Caveat: run 6 had owner input, which also
  keeps macOS awake; the clean comparison is a hands-free sleep-job-on run with autologin (run 7) and a hands-free sleep-off run.
* Every sleep-job run ends with a hung SoC and needs the power key. Ideas to remove that need: wake the Mac from the Pi by cutting and restoring
  the USB-C cable's VBUS (Pi 5 per-port power switching, `uhubctl`, needs sudo on the Pi) if the SMC wakes on attach; or arm the SoC watchdog so the
  hung machine resets itself (needs the guest or Aura to arm it; Aura's own HV watchdog is a software one on a CPU that the sleep powers down).
