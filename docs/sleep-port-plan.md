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

## Step 2 result and the step 3 mapping (2026-11-26 night)

Step 2 is built, not yet booted: `apple,t6020-sleep` (disabled node in `t6020.dtsi`, six register blocks: ps 0x28e080000, ps-east 0x290280000, ps-mini 0x29e280000, ps-aon 0x29e5c0000, wdt 0x29e2c4000, spmi 0x29e114000), a match entry and an inventory-only profile in `sleep.c`, and the binding. Branch `gh5/port-step2` in `~/Work/src/linux-port`, commit c56412f1cd15. `sleep.c` and the three T6020 DTBs build; the binding passes `dt-doc-validate`. Not booted: the node is disabled, so a boot shows nothing until step 3 gives it a profile.

What main's T8103 profile is: macOS's last 14 ms replayed in macOS's order, every offset measured from a macOS sleep under Aura. We hold no such T6020 trace. We hold Aura's `psci.c`, whose order is empirical and proven on this Mac (R61P-R61R, a 4 h run). The port therefore transliterates the proven recipe instead of replaying a macOS trace. That is a different claim from T8103's, and the PR text has to say so.

The proven default recipe (`psci_ctl[1] = 0xc16dcb3f`, `[5] = 241`) enables these steps, in `psci_system_suspend()` order:

| Aura step | bit | T8103 hook it lands in |
|---|---|---|
| SEP quiesce (ps_sep 0x290280c00) | 24 | `before_enclave`/`commit_regs`, framework SEP stop first |
| held domains lowered (qs_held, 0x28e080000 words) | 6 | `prepare_regs`/`commit_off` list |
| domains, ATC (atc0..3 pcie/common), AON (atc1..3_usb_aon, msg), PMP (0x28e0802c8/d0) | 2, 19, 21, 22 | `commit_off`, `aon_commit_off` |
| fabric auto-PM floor (0x28e080210, 0x290280178, 0x290280418) | 18 | `commit_regs` |
| clusters (0x28e088000/4/8) then EACC | 4, 16 | `cluster` list, 3 clusters |
| clocks (PLL-off mode 3 at 0x28e224000) | 3 | `commit_regs` mux step |
| AMCC error enables | 9 | `dcs_quiesce` |
| cluster DVFS teardown (CLUSTER_PSTATE at 0x210e00000/0x211e00000/0x212e00000 + 0x20020) | 17 | `t8103_quiesce` ACC step |
| SPMI notify enable 0x2000001 on nub-spmi0/1 | 23 | `commit_regs` E12 |
| WD1 off, S2R timer write at 0x29e5c4000 (two writes), AIC mask, cores off | 12, 0, 1 | `commit_regs`, `post_timer`, `deep_wfi_arm` |
| secondary stop requests | 5 | `cpu_down` |
| resume: PS restore, GPIO block restore, apcie PS off and re-init, ps_sep write-back | n/a | `wake` |

Open for the T6020 profile:
- Aura's resume path does PCIe port restore (qs_pport) and a GPIO snapshot in firmware. In `sleep.c` these belong in `wake`, or in the kernel's own drivers (aura#529).
- The wake mask (`apple,wake-enable`) and the wake block address are Aura's `wakemask` (0x29e00400c).
- Nothing here is booted on the kernel side. The test needs a UKI of the port kernel with its own module tree; the `deeptest` machinery exists (`build-uki.sh` with `MODROOT`), but patched-kernel boots have been fragile before (worklog, R57P to R57U).
