# T6020 on sleep.c: port plan (linux#3336)

Route agreed with the maintainers: a `drivers/soc/apple/sleep-t6020.h` profile in `sleep.c` (kernel at EL2, no PSCI, `aurora,s2r-mailbox`), `sleep-t8103.h` as the template. No PSCI conduit, no `-psci.dtb`. Worktree `~/Work/src/linux-port` (branch `gh5/port-main`, on aurora-silicon/linux main `66fbacc`). Aura main (`~/Work/src/aura-main`, 8521ad7c) already publishes the mailbox on the J414s (step 1, worklog 2026-11-26 21:35).

## Where the working sequence lives today
Our Aura `src/psci.c` on `gh5-wakemask` (`psci_system_suspend()` and the `psci_quiesce_*`, `qs_*` helpers): the PMGR quiesce, the SEP/PMP/AOP handshakes, the commit and the wake. The kernel side (rtkit keep-state, ANS, SEP DART, PMP SRAM, DCP/GPU warm restart, ATC, ASoC) is in `~/Work/src/linux-aurora-73` branch `gh5/s2r-7.3-upstream`.

## Steps
1. Test DT for the J414s with spin-table CPUs and no psci node (the boot.bin's DT is the PSCI one today), so a sleep.c kernel can start all CPUs. Needed for every test boot below.
2. Build main's kernel (`gh5/port-main`) for T6020: `apple,t6020-sleep` node in `t602x` DT (reg blocks as t8103's node: pmgr, ps-aon, wake, clk-mux, spmi, cluster), compatible entry in sleep.c, empty profile that reports `unavailable_reason` (inventory only). Boots, nothing hardware.
3. Fill the profile from the Aura sequence, one `apple_sleep_ops` hook at a time (map_regs, begin, check, display_off, prepare_regs, commit_regs, wake, finish, cpu_prepare/restore, deep_wfi_arm), with a dry run first, then a real sleep on a dead-man boot. Wake sources: `apple,wake-enable` on the sleep-controller node, filled by Aura from the ADT (generalise aura#214's `dt_set_t6050_sleep()`), not `/chosen`.
4. Check aura#529's wake-time PCIe replay on T6020; prefer main's port-restore path over our unbind/rescan.
5. Device-side pieces `main` still lacks, as separate small PRs, each tested on the J414s: AIC2, SEP DART and PMP SRAM backup, DCP/G14S warm restart, ATC, ASoC/NCO, T602x PMU alarm, the bcm4377 probe fix. Diff against main first: #3172 already landed shared rtkit/sart/nvme/macsmc/pm_shim/pcie-apple/NCO hooks.
6. Close aura#539 once the node-based wake sources are in a PR.

## Rules that apply
Default cmdline, no module parameters, no hardcoded model gating, read a register before writing it with a dead-man on each test boot, PR bodies with Tested/Risk/Not yet, no AI attribution, nothing derived from Apple binaries in public text (use values measured on the Mac itself).
