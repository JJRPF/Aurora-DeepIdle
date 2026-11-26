# Draft PR: aurora-silicon/linux

**Title:** `soc: apple: suspend-to-RAM on the T6020 (M2 Pro) through PSCI-via-EFI`
**Base:** `main` (the series is written on `integration/aurora-7.3`; it has to be rebased: 6 of the 10 commits apply to current main without conflict, the PCIe, DCP, Asahi GPU and ANS/SEP commits conflict with main's own S2R code and need a port). **Draft until that port is built and run on the J414s at the new head.**
**Branch:** `feat/t6020-s2r` (from `gh5/s2r-7.3-upstream`, 5 commits by Sven Peter carried unchanged + 10 of ours, each with `Signed-off-by`)

---

**What:** Real suspend-to-RAM (the SoC enters the firmware S2R state, `SLP_S2R` counts, wake by RTC alarm or lid) on the MacBook Pro 14" M2 Pro (J414s, T6020), by entering `SYSTEM_SUSPEND` through Sven Peter's PSCI EFI conduit and bringing the display, GPU, NVMe, PCIe devices, SEP and PMP back after the power cut. Fixes #<issue>.
**Tested:** J414s (M2 Pro, 16 GB) at `<head SHA after rebase>`: stock command line, no userspace helper: 5/5 soak cycles x 45 s, one 20 min sleep (1192 s of 1204 s in S2R), Wi-Fi/Bluetooth/NVMe back each time, 0 failed units, 0 new kernel errors. A night on battery (7.1 h) averaged 0.375 W with 99.6 % of the time in S2R (one night, earlier head `7d3a1c`; to be repeated at the PR head). No other Mac.
**Risk:** two-way door (plain revert) for the code; the PSCI-via-EFI device tree is opt-in (`t6020-j414s-psci.dtb`), so no Mac changes behaviour until its boot loader selects it. Other Macs: the shared files are `pcie-apple.c`, `macsmc.c`, `rtkit.c`, `apple-dart.c`, `nvme/host/apple.c`, `pmgr-pwrstate.c`, `atc.c`; every new path is guarded by a hardware property or a hook that other boards do not set, but only the J414s was run.
**Not yet:** a cancelled sleep (`pm_test=devices`, a key during suspend) was not run on the J414s; another tester reports the display and GPU firmware stay down after one on an M2 Max. External display/dock, Bluetooth pairing, SD card insertion across a sleep, lid open/close and the speakers were not exercised at the PR head (speaker playback needs speakerguardd v2, which is not available for this Mac yet). Other chips (T6021 and later) not run.

<details><summary>Details</summary>

- The CPU path is Sven's PSCI EFI conduit (his 5 commits, unchanged) plus two small fixes for `SYSTEM_SUSPEND` and `CPU_OFF` through the conduit.
- PCIe (`pcie-apple`): the endpoints are unbound before the freeze and rescanned after the wake, the port setup is redone after the power cut and the PCIe domains stay up through the firmware commit.
- macsmc: the SMC wake policy, the PMGR AP wake mask and the T602x PMU alarm. The mask address and the sources the firmware keeps enabled come from `/chosen` (`aurora,ap-wake-mask-reg`, `aurora,ap-wake-sources`), which the boot loader fills from the ADT (companion PR in `aurora-silicon/aura`); without them the mask is left alone. The 22 sources it publishes are the ones the previous version of this series carried as a table.
- DCP: warm restart (display-0 cycle + RTKit warm restart); GPU: warm restart of the G14S firmware; ANS cold start with the ADT tunables; SEP DART save/restore, PMP SRAM backup; AIC2 firmware suspend save/restore.
- A DART tunable rewrite that an earlier version carried was removed: the registers read back their reset values before and after the sleep, and the sleep and wake work without it.
- Known hardcoded value: `WKTP = 2` at the sleep commit (SMC key value).
</details>

<details><summary>Evidence</summary>

- Soak (`s2r-soak.sh`, rtcwake 45 s, each cycle checks wall time, NVMe read, Wi-Fi link, Bluetooth, speaker daemon, CPUs 0-9, new kernel errors): 5/5 twice at the wake-source head, 20/20 and 10/10 earlier.
- 20 min sleep: wall 1204 s, `SLP_S2R` 1192 s.
- Overnight, lid closed, battery: 7.14 h, `SLP_S2R` 25616 s (99.6 %), AWAKE 80 s, 5 % of the battery, 0.375 W average.
- Full logs and the per-step history: github.com/JJRPF/Aurora-DeepIdle, issue #5, `docs/worklog.md`.
</details>
