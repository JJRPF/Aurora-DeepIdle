# PSCI through EFI on T6020: CPU_ON, CPU_OFF, SYSTEM_SUSPEND (S2R plan, Phases 1 and 2)

Status, 2026-11-05: booted and working. CPU_ON, CPU_OFF and SYSTEM_SUSPEND
run through this handler on the test boots: CPU_ON since 2026-10-25,
SYSTEM_SUSPEND on the boot CPU since 2026-10-31, and CPU_OFF inside every
suspend since 2026-11-04. Linux offers `deep` in
`/sys/power/mem_sleep`, and suspend to RAM passes 20 of 20 cycles with all
10 CPUs and the PMP on (Phase 2 of `s2r-plan.md`). The SoC itself stays up
in that suspend; powering it down is Phase 5. Patches are in
`patches/psci-efi/`; the run-by-run history is in `worklog.md`
(2026-10-25 21:32 onwards).

## Why EFI

Apple silicon has no EL3. Linux and the bootloader share EL2, so `smc` and
`hvc` have nothing to call. Sven Peter's RFC ("PSCI-via-EFI to support
firmware and kernel sharing EL2 for Apple Silicon", linux-arm-kernel,
2026-07-08, message-id `20260708-efi-psci-v1-0-9efb3abf0e4c@kernel.org`) gives
the kernel a function pointer instead:

* A `LINUX_EFI_ARM_PSCI_HANDLER_TABLE` configuration table holds the PSCI
  version, a features array and the handler.
* The kernel calls the handler as a plain function, under its EFI runtime
  map, with interrupts masked. Unlike runtime services there is no lock, so
  it works in atomic context: CPU bring-up and idle.
* The handler must not touch FP/SIMD and must be reentrant.

Where the review stood when last read:

* Ard Biesheuvel took the two EFI memory-attribute patches (3 and 4).
* Mark Rutland objects to calling it PSCI.
* Will Deacon and Ard discussed an EFI-callable interface, modelled on ACPI
  PRM, as the compromise.

The interface may change, so these patches are a test vehicle, not
something to ship.

## The three parts

| Part | Where | What |
|---|---|---|
| Kernel | local branch `psci-efi-test-72` (on 7.2.11), `patches/psci-efi/linux` | the RFC's six patches; `t6020-j414s-psci.dts`, an opt-in DTB with a `psci { method = "efi"; }` node and `enable-method = "psci"` on all CPU nodes, idle states left to the Apple cpuidle driver; two fixes for EFI calls that never return (below); the PMU RTC alarm; and the `TEST:` patches of the S2R runs (SMC sleep handshake, PMP IDLE, SART save/restore, PMU boot stage, PMGR wake mask), all off by default |
| Aura | branch `psci-efi` (`aura-psci` worktree), `patches/psci-efi/aura` (`wip-system-suspend.diff` is image 51) | `src/psci.c` plus `smp_psci_*` in `smp.c`: CPU_ON, CPU_OFF, AFFINITY_INFO, SYSTEM_SUSPEND; `dt_set_psci()` in kboot publishes the table |
| U-Boot | `asahi-v2026.07-2` + 2 commits (`~/Work/u-boot-asahi`), `patches/psci-efi/u-boot` | `efi_platform_register()`: installs the table and adds Aura's image and MMIO to the EFI memory map; a second commit re-applies those runtime ranges after U-Boot carves out the DT's reserved ranges (without it the first CPU_ON faulted, 2026-10-25 22:01) |

The m1n1 reference (`AsahiLinux/m1n1` branch `psci-via-efi`) builds its own
EFI tables in Rust and only works when m1n1 loads the kernel directly. This
Mac boots m1n1, then Aura, then U-Boot, then GRUB, then Linux, so here U-Boot
publishes the table instead. That matches the RFC's plan to take this to
U-Boot later.

## How it works

Boot:

1. Aura finds `psci { method = "efi"; }` in the payload DT.
2. It writes three properties to `/chosen`:
   * `aura,psci-table`: the physical address of `psci_efi_table`;
   * `aura,psci-runtime-code`: Aura's whole image, aligned to 16K;
   * `aura,psci-runtime-mmio`: the PMGR CPU start/stop block of each die, plus
     the AIC on chips without fast IPIs.
3. U-Boot reads those properties. It adds the image as
   `EFI_RUNTIME_SERVICES_CODE` and the MMIO as `EFI_MMAP_IO`. The MMIO gets
   the UEFI 2.10 ISA bits for Device-nGnRnE (RFC patch 4 honours them;
   without them the kernel maps nGnRE). Then U-Boot installs the table. A DT
   without the `psci` node changes nothing at either stage.
4. The table holds physical addresses, so the kernel's runtime map must be
   1:1. The arm64 EFI stub already does that on this config: with 48-bit VAs
   it skips SetVirtualAddressMap (`check_platform_features()`). On other
   configs, `efi=novamap` forces it.

CPU operations (all in the kernel's context: its stack, its page tables,
no printf):

* **The parked state.** Aura parks every secondary in
  `smp_secondary_entry()`, as it does for spin-table. The kernel's first
  CPU_ON hands that CPU the entry point the way `smp_call4()` does, without
  waiting, and wakes it with SEV, since kboot switches the parked CPUs to WFE
  before the handoff.
* **CPU_OFF**, on the dying CPU: it marks itself OFF, clears the stale
  spin-table target and parks in Aura, on its own Aura stack, in deep WFI
  (`CYC_OVRD` WFI_MODE 3) **with** state retention. The first design powered
  the core down without retention (`cpu_sleep(true)`); such a core never
  came back properly (image 43). The very first version, `cpu_sleep(true)`,
  also wrote the per-cluster `ACC_OVRD` deep-sleep bits under the running
  cores and took the whole SoC down (2026-10-25 22:11).
* **AFFINITY_INFO** reports what the dying CPU wrote. It never reads a core's
  power status: `smp_stop_cpu()` notes that register access dies with the
  last core of a cluster.
* **CPU_ON of a parked core** writes the entry point into the spin table and
  wakes the core with SEV and an IPI. The park loop restores the core's `CYC_OVRD`
  before it enters the kernel: a re-onlined core used to inherit WFI_MODE 3
  from the park and hang (image 47). A core that really lost power (not
  seen so far) would come back through RVBAR (`_cpu_reset_c`, `init_cpu()`)
  into the same park loop.
* **Cache maintenance.** The parked CPUs run with the MMU off, so every
  spin-table access from the kernel's side is cleaned or invalidated
  (`dc civac`).

The handler never prints once the kernel has made its first call (the UART
may be powered down, and its TX-empty wait would spin forever); it reaches
only the `smp_psci_*` helpers, cache maintenance, the AIC and watchdog
registers, `smp_send_ipi` and the deep-WFI helper. No FP, and the build
uses `-mgeneral-regs-only`.

## SYSTEM_SUSPEND

Linux calls it on the boot CPU last, with the nine secondaries already
parked through CPU_OFF, every device suspended and the AIC masked by its
syscore hook. Aura (`psci_system_suspend()`):

1. arms the SoC watchdog (WD1, 120 s), so a firmware hang resets the Mac;
2. records the kernel's resume entry and context, and ignores wake lines for
   the first 500 ms;
3. unmasks two wake lines at the AIC: 724, the PMU over SPMI (the RTC alarm),
   and 865, the SMC mailbox (power key, lid). It watches their raw
   `HW_STATE` bits, since every line is masked and the AP's event register
   stays empty;
4. puts the boot core in deep WFI with retention. The EL2 physical timer
   wakes it every 60 s to re-arm the watchdog (it cannot count past about
   178 s), so a sleep can last hours;
5. on a wake line, masks the two lines again, disarms the watchdog and enters
   the kernel's resume entry with the MMU and caches off, as a PSCI resume.

If the boot core loses power (a real SoC sleep), it restarts through its
locked RVBAR into Aura's reset path. That path finds the resume record,
arms 10 s and then 150 s watchdog stages (so the reset time names how far it
got), and resumes the kernel even with no wake line showing, since an S2R
wake would have reset the AIC (image 51). It has not been reached yet: in
every `slpa` run so far the SoC stayed up (`worklog.md`, 2026-11-05 16:03).

Kernel side, two fixes for an EFI call that never returns:

* SYSTEM_SUSPEND: the resume comes back through `cpu_resume`, not out of the
  EFI call, so the EFI runtime state the call entered is unwound there;
* CPU_OFF: the dying CPU never leaves the call, so the virtmap preempt count
  is dropped before it ("scheduling while atomic" ×45 is gone).

Aura's debug words (`psci_dbg`, found by the magic `0xA0AA0001` with
`harness/mmio/scan-magic.c`) record each suspend: the wake line, the time
asleep, the number of WFI exits and heartbeats, and whether the core came
back through RVBAR.

## Results

| Test | Image | Result |
|---|---|---|
| CPU_ON of all nine secondaries at boot | 2026-10-25 | 10 of 10 CPUs online, 0.25 s |
| SYSTEM_SUSPEND, boot CPU only (`maxcpus=1`) | 41 | 20 of 20 cycles |
| SYSTEM_SUSPEND, all 10 CPUs (180 CPU_OFF/CPU_ON pairs per gate) | 47, 48 | 20 of 20 each, 0 device errors |
| `systemctl suspend -i` with the sleep hooks, all CPUs | 47 | 20 of 20 |
| Wake on the PMU alarm | 26 onwards | every alarm cycle since |
| Wake on the power key (SMC mailbox line 865) | 29 | 1 of 1, owner at the Mac |
| Deliberate hang inside SYSTEM_SUSPEND | 27-hang | the watchdog reset the Mac by itself |
| Long sleeps on battery (watchdog heartbeat) | 50, 51 | 1 h 46 min and 90 min, clean, 1.44 and 1.49 W |

Image 48 is the clean reference build; image 51 adds the RVBAR resume.

## Not covered yet

* **Runtime hotplug** (offline and online outside suspend) has not been
  rerun since the park fixes. Inside suspend it works every cycle.
* **A core that really loses power.** The parked cores and the boot core all
  keep their state today. The RVBAR paths exist but have not run in anger.
* **CPU_SUSPEND** is not offered: cpuidle stays with the Apple driver.
* **The RFC's open review points** (the PSCI name, an ACPI-PRM-like
  interface instead). The interface may change, so this stays a test
  vehicle.
