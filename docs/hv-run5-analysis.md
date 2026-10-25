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
1. **macOS began to sleep and the machine did not wake.** For: 7:56 is guest boot (~2.5 min) plus the 5-minute `hvsleep` delay; the screen was blank;
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
