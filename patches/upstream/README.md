# Staged upstream changes (GH-10) — NOT posted

Nothing here has been opened, pushed or commented upstream. Posting needs the owner's OK.
All numbers: M2 Pro J414s (T6020), kernel 7.2.11.aurora14-1, headless idle, `tools/idle-ab.py`;
raw data in `data/idle_erikwb/`. Cross-boot comparisons are one boot per image (drift not in the
error bars); same-boot comparisons are paired.

## 1. arm64: dts: apple: t602x: add opp-microwatt for the CPU energy model
File: `0001-arm64-dts-apple-t602x-add-opp-microwatt-energy-model.patch` (t602x-common.dtsi).
Text: The CPU cluster OPP tables have no power numbers, so no energy model exists and EAS is inert.
Add `opp-microwatt` per OPP (values from `tools/t6020-cpu-em.py`), as the T8103/T600x trees do.
Result on a J414s with the PMP booted: `sched_energy_aware=0` costs +0.230 W total / +0.156 W SoC
(12 paired rounds, lower in 0 of 12), i.e. the energy model is worth 0.23 W at idle; without the
PMP the cross-boot figure is -0.18 W total (SoC change not significant).
Caveat to state: the microwatt values are fitted, not measured per OPP.

## 2. t6020-j414s-pmp.dts + m1n1 tunables fit check
Files: `0002-t6020-j414s-pmp.dts`, `0003-m1n1-pmp-tunables-fit-check.patch`.
Text: Booting the PMP (alias `pmp`, via APPLE_USE_PMP) lets it own fabric/DCS p-states and the
DCP/AVD/ISP power domains. m1n1's FDT headroom is too small for the PMP tunables on T6020, so
dt_set_pmp() must check the free space before copying and leave the PMP disabled if they do not fit.
Result: -0.919 +- 0.014 W total / -0.649 W SoC vs a stock boot (16 x 30 s each); with the energy
model -1.107 W total / -0.831 W SoC. Same image installed as default: 2.39 W total, 1.16 W SoC, held
for a 1 h soak (120 windows, mean 2.36 W / 1.13 W, 0 of 3695 pings lost, no new dmesg errors).
Caveat: the m1n1 patch is the test build (it also records the outcome in /chosen); trim to the
fit check before posting. The dts must not be added to the Makefile next to t6020-j414s.dtb (same
compatible, m1n1 boots the last match); ship it as the DTB for J414s only when the PMP is wanted.

## 3. cpuidle PD-always (userspace opt-in)
File: `0004-cpuidle-pd-always.tmpfiles.conf`.
Text: On a plain boot (no PMP, no EM) disabling WFI so every idle entry is CPU PD saves 0.54 W
(10 of 10 paired rounds), at +~17 us p50 wake latency (timer 7.7 -> 24.9 us, ipi E-E 8.3 -> 17.7 us).
On top of the PMP + EM it saves nothing measurable (-0.015 W, sd 0.07, lower in 7 of 12): the
default already sits in PD 79% of the time. So: useful without the PMP, pointless with it.
