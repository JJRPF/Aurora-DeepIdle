# Draft comment for aurora-silicon/linux#933 (NOT posted; needs the owner's OK)

S2R status with the PMP enabled on J414s (M2 Pro), from GH-8 testing on 2026-11-04:

- With this PR's PMP node active, a PSCI `SYSTEM_SUSPEND` (implemented in the Aura/m1n1 stage and called
  through an EFI runtime PSCI handler) suspends and resumes cleanly: 20 of 20 cycles on the boot CPU alone
  and 20 of 20 with all 10 CPUs (the nine secondaries go through PSCI CPU_OFF/CPU_ON each cycle), woken by
  the PMU RTC alarm, 0 device errors after resume. The SMC power-key line also wakes it.
- That is suspend with the CPUs in deep WFI and the devices suspended; the SoC and DRAM stay powered.
  The real SoC sleep steps (what macOS does after `slpa`) are not implemented yet, so S2R with the PMP is
  qualified only at this level. Nothing seen so far points at the PMP being a problem for it.
