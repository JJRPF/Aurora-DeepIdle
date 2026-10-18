# S2R research on macOS for Aurora deep sleep (agent prompt)

You are an agent on a MacBook Pro 14" M2 Pro (J414s, SoC T6020) booted into
macOS. The owner works on Aurora Silicon's Linux for this machine. Your job
is to collect what macOS does to put the SoC into S2R (suspend to RAM, the
state macOS calls "Deep Idle" in `pmset -g log`) and bring it back, so that
Linux can do the same. Report everything in one new issue in
`JJRPF/Aurora-DeepIdle`.

## Where the work stands

Repository: https://github.com/JJRPF/Aurora-DeepIdle. The write-up is
`docs/deep-idle-research.md`
(https://github.com/JJRPF/Aurora-DeepIdle/blob/main/docs/deep-idle-research.md).
Read these sections before you start: "What macOS 13.5 does to sleep the SoC
(static analysis)", "macOS 15.7.1 live on this machine (issue #3)", "s2idle
suspects one at a time" and "Unblocking deep sleep". History: PR #1 and #2
(CPU idle, the PMP, the s2idle measurements), issue #3 (the previous macOS
agent's findings: https://github.com/JJRPF/Aurora-DeepIdle/issues/3) and PR #4
(sleep tooling and the HDMI rails).

The numbers:

- macOS sleeps this machine at **0.24 W** (5.9 h lid closed, 98.7% in S2R,
  issue #3). Linux s2idle draws **1.4 W** on unplugged nights and **2.0-2.2 W**
  on the charger. Awake, the two match (about 5.4-5.6 W on a quiet desktop,
  with Linux's PMP running).
- What s2idle tuning can still do is small: the HDMI rails are 0.13 W (asleep
  and awake), the AOP's wake rate and sensor drivers cost nothing measurable,
  and the SD link's L1 substates save nothing. The rest of the gap is what
  S2R powers down: the CPUs, DRAM into self-refresh, the SoC clocks and PLLs.

What is already known about macOS's path (from the macOS 13.5 J414s
kernelcache, the release whose coprocessor firmware Linux runs, and from
issue #3's kernel log of 15.7.1):

- `IOCPUSleepKernel` runs the platform **sleep** actions (lowest priority
  first): Dialog SPMI PMU RTC, CLPC, `AppleT6020PMGR`, `ApplePMPv2` (62 ms,
  the longest), `AppleSMCPMU`, `AppleSMCKeysEndpoint` (writes SMC `MBSE` =
  `slpa`), DART (x31), Thunderbolt HAL. Then the boot CPU's **quiesce** actions:
  `AppleT6020PCIe`, `AppleT6000PCIeC` (x3), `AppleT6020SOCTuner`,
  `AppleT6020MemCacheController`, `AppleSEPManager`, `AppleT6020PMGR`
  ("Starting S2R timer"), `AppleInterruptControllerV2`, `AppleDialogSPMIPMU`
  (x2). Wake runs **active** then **wake** actions in reverse.
- SMC: `MBSE` = `slpw` on the way to sleep, `WKTP` = 2 (1 byte) in
  `AppleSMC::setPowerState(0)`, `MBSE` = `slpa` in the sleep action; on wake
  `MBSE`/`MBSW` are read (`MBSW` read `0001000000000000` after a lid wake),
  `MBSE` = `waka`, `WKTP` = 0.
- PMGR (13.5): `quiesceHW` quiesces the GPU's PMGR (`AGX_PMGR` + 0x100),
  gates clocks in `PMGR_SOC_EAST` and the SoC clock generator, sets PLL-off
  modes, and ends with `startS2RTimer`: one write of 1 to `MPMGR_AON` + 0x4000
  (`MPMGR_AON` = PMGR `reg` index 38, 0x29e5c0000). The PMGR `events` include
  `SLP_DDR`, `AWAKE`, `SLP_S2R`, `DEEP_WAIT`, `SYS_AWAKE`, `SYS_S2R_AOP`,
  `SYS_SLP_DDR`, `DDR_WK_TIME`, `S2R_WK_TIME`.
- PMP: the T6020 PMP runs under `AppleASCWrapV4` -> `iop-pmp-nub` ->
  `RTBuddy(PMP)` -> `PMPEndpoint1` (endpoint 33) -> `ApplePMPv2`
  (`no-shutdown`, `pre-loaded`). `AppleA7IOPV4PMP` is the A11's class and is
  not used. What `ApplePMPv2`'s 62 ms sleep action sends is not known.
- Dark wakes come from the Dialog PMU's RTC (`NUB.SPMI0Sw3IRQ`). The static
  13.5 device tree's `spmi-mpmu` node has the RTC alarm layout: `info-rtc`
  0x1406, `info-rtc_alarm_offset` 0x140C, `info-rtc_alarm_ctrl` 0x1401 (enable
  mask 0x40), `info-rtc_alarm_event` 0x14C0, `info-rtc_irq_mask_offset` 0x14C2,
  `info-rtc_alarm_mask` 1, `info-pm_setting` 0x1405, `info-clock_offset`
  [0x1411, 6], `info-scrpad` [0x8000, 0x1000], `info-leg_scrpad` 0x6000,
  `info-has_slpsmc` 1. Linux has no RTC alarm on this machine, which is also
  what S2R needs for timed wakes.
- On the Linux side, the CPU deep-idle state (deep WFI with retention) already
  works. In raw boot mode m1n1 is the image iBoot boots, so a wake from S2R
  would restart the boot CPU in m1n1, which would have to hand it back to
  Linux.

## Rules

- **Read only.** Do not change the system. Never write SMC keys, run `nvram`,
  `csrutil`, `bputil`, `kmutil`, `systemextensionsctl`, load kexts, change
  `pmset` settings, or `defaults write` outside your own files. Install only
  what the owner approves; expected: Xcode Command Line Tools (`otool`,
  `objdump`), and `ipsw` (https://github.com/blacktop/ipsw, Homebrew
  `blacktop/tap/ipsw`) for reading the kext collection.
- **Ask before every `sudo` command**, showing the exact command and why.
- **Aurora Silicon policy** (https://aurorasilicon.org/project/policies-and-guidelines/).
  Reading and disassembling the public macOS on this machine is allowed. Never
  post or commit Apple binaries, firmware, kernel collections, or large
  disassembly or decompiled listings. Post findings: function names, call
  order, register addresses and values, property values, short pseudocode
  (at most about 30 lines per function) and short log excerpts. Never contact
  or post to upstream projects (Asahi Linux, m1n1, kernel lists). The only
  thing you post is one new issue in `JJRPF/Aurora-DeepIdle`; do not comment
  on existing issues or PRs.
- **Privacy.** The repo is public. No full `ioreg` dumps. Remove serial
  numbers (`IOPlatformSerialNumber`, `serial-number`, `mlb-serial-number`),
  UUIDs, MAC addresses, Wi-Fi network names, user and host names, Apple IDs.
  Grep your draft for them before posting.
- Keep raw output in `~/Library/Logs/AuroraDeepIdle/s2r/` (create it), and
  write findings to `~/Library/Logs/AuroraDeepIdle/s2r/findings.md` as you
  go, so nothing is lost if the session ends.
- If something is not available on this macOS version, say so and move on.
  Mark every finding as **read** (seen in code or a property), **inferred**,
  or **unknown**.

## Phase 1: live facts (about 30 minutes, awake)

Record `sw_vers`, `sysctl -n hw.model`, `uname -a`.

1. **Device tree, sleep-related nodes**, from `ioreg -l -w0 -p IODeviceTree`
   (save it raw, post only these properties):
   - `pmgr`: `events` (all names and values), `ap-wake-sources`, the number
     of `reg` entries and the address and length of index 38 (`MPMGR_AON`),
     every `function-*` property, anything with `s2r`, `sleep`, `wake`,
     `aon` or `ddr` in its name.
   - Every `spmi*` node and its children (`spmi-mpmu` and any other PMU): all
     `info-*` properties, `reg`, `compatible`, interrupts. Compare with the
     13.5 values above and list the differences.
   - `aic`, `mcc` / `amcc`, `aop`, `smc`, `pmp`, `sep`, `cpu0`..`cpu11`
     (`cpu-impl-reg`, `reg-private`, `cpu-uttdbg-reg`, `state`), the PCIe
     nodes' `manual-enable-s2r`, and `chosen` / `arm-io` properties whose names
     mention sleep, wake, s2r, resume, rvbar or reset.
2. **IOPMrootDomain**: `ioreg -l -w0 -r -c IOPMrootDomain`: properties about
   the last sleep and wake (sleep phases, wake reason, wake type, failure
   codes, timings), redacted.
3. `pmset -g stats`, `pmset -g log | tail -100` (the Sleep / DarkWake / Wake
   lines and their reasons), and `sysctl -a | grep -iE
   'sleep|wake|s2r|hibern'`.

## Phase 2: one short sleep, with timings (about 10 minutes)

1. Note the time, then ask the owner to close the lid on battery for 3
   minutes and open it again.
2. `log show --style compact --info --debug --start "<time>" --predicate
   'process == "kernel"'` (ask for `sudo` only if it is needed). From it,
   build a timeline with timestamps and durations: every
   `IOPlatformSleepAction`, `IOPlatformQuiesceAction`, `IOPlatformActiveAction`
   and `IOPlatformWakeAction` line, "Starting S2R timer", `IOCPUSleepKernel`
   enter and exit, the SMC lines, and anything from PMGR, PMP, AOP, SEP, AIC,
   the PMU and the memory cache controller. The quiesce and active lines carry
   their own `[seconds]` timestamps; use them for the time spent in S2R and
   for how long each action took.
3. Repeat the Phase 1 IOPMrootDomain read after the wake.

## Phase 3: what the drivers do (the main part, 2-3 hours)

The kexts are in `/System/Library/KernelCollections/BootKernelExtensions.kc`
(a Mach-O fileset; `ipsw macho info --fileset-entry <bundle id>` and `ipsw
disass` read it). Check first whether the kexts keep their symbols; on 13.5
they did. Work through these in order and stop each one when the question is
answered. For each, give the function names, the order of calls, and a table
of register writes (block or base, offset, value or how it is computed) or
messages (endpoint, type, payload), plus what is waited for and with what
timeout.

1. **The PMU RTC alarm** (`AppleDialogSPMIPMURTC`, `AppleDialogSPMIPMU`): how
   a wake time is programmed: which `info-*` offsets are used, byte order,
   units (the RTC's tick and its relation to `info-rtc` and
   `info-clock_offset`), enabling the alarm, and acknowledging its interrupt
   (`info-rtc_alarm_event`, `info-rtc_irq_mask_offset`). Also which SPMI
   controller and slave ID the PMU is. Linux needs exactly this for an RTC
   alarm.
2. **`ApplePMPv2`'s sleep and wake actions**: what it sends to the PMP over
   endpoint 33 (message words), what it waits for, and why it takes 62 ms. Also
   whether RTBuddy changes the PMP's power state across S2R (`no-shutdown`).
3. **`AppleT6020PMGR`**: the sleep, quiesce (`quiesceHW`), active and wake
   actions on 15.7.1. Confirm or correct the 13.5 description above, and list
   what the active action restores. In particular: everything written to
   `MPMGR_AON` (index 38), PS (power state) register writes, PLL and clock
   generator writes, and any `events` used.
4. **`AppleDialogSPMIPMU` quiesce and active actions** (priority 98000, the
   last quiesce): the SPMI commands and register writes that take the
   system down and what changes on wake.
5. **`AppleT6020MemCacheController` and `AppleT6020SOCTuner`** quiesce and
   active: what is saved and re-applied on wake (tunables), and anything that
   puts DRAM into self-refresh, or confirms that PMGR does it.
6. **`AppleInterruptControllerV2`** quiesce and active: what is saved and
   restored.
7. **`AppleSEPManager`** quiesce: what it tells the SEP.
8. **`AppleT6020PCIe` / `AppleT6000PCIeC`** quiesce and active, and what
   `manual-enable-s2r` changes.
9. **The CPU side**, mostly from XNU's open source (the release matching
   15.7.1, `xnu-11417`, at https://github.com/apple-oss-distributions/xnu):
   `ml_arm_sleep`, `arm64_prepare_for_sleep`, the per-CPU and per-cluster
   registers written before the last CPU powers off, and where the boot CPU
   restarts on wake (the reset vector, RVBAR, `LowResetVectorBase`), plus how
   the secondaries are brought back. Cross-check against the T6020 kexts
   (`AppleARMPlatform`, CPU and CLPC drivers) for anything SoC-specific.
10. **AOP and SMC**: what `AppleAOP2` does across S2R (it is in
    `ap-wake-sources` and stays running), and whether any SMC key besides
    `MBSE` / `WKTP` / `MBSW` is written in the sleep or wake path.

## Phase 4: the issue

Write the body to a file and open the issue:
`gh issue create -R JJRPF/Aurora-DeepIdle --title "macOS S2R path on T6020: <one-line headline> (<date>)" --body-file <file>`,
then give the owner the URL. Structure:

- **Summary**: 5-10 bullets, the answers first, in the order Linux needs them:
  the RTC alarm, the PMP's sleep message, PMGR's S2R entry and exit, the PMU's
  quiesce, memory, CPU power-off and the wake vector.
- **Phase 1** tables (device tree properties, differences from 13.5).
- **Sleep and wake timeline** (Phase 2), in `<details>`.
- **Per question** (Phase 3): findings with read / inferred / unknown, the
  register and message tables, short pseudocode.
- **What Linux needs to implement, in order**, as you would propose it from
  what you found, and what is still unknown.
- **Not available / could not check**.
- A last line: `Posted by an AI agent (tools/macos-s2r-prompt.md).`

If you cannot finish, still open the issue with what you have and say what
is missing.
