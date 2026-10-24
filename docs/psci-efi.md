# PSCI CPU_ON and CPU_OFF through EFI on T6020 (S2R plan, Phase 1)

Status, 2026-10-24: all three parts are built and compile-clean. None has
been booted. Patches are in `patches/psci-efi/`.

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
| Kernel | local branch `psci-efi-test` (worktree `~/Work/linux-psci-efi`, on GH-1-DeepIdle 1ac4376) | the RFC's six patches, applied clean to 7.1.12; plus `t6020-j414s-psci.dts`, an opt-in DTB with a `psci { method = "efi"; }` node and `enable-method = "psci"` on all 12 CPU nodes, idle states left to the Apple cpuidle driver |
| Aura | branch `psci-efi` (`aura-psci` worktree), `patches/psci-efi/aura` | `src/psci.c` plus `smp_psci_*` in `smp.c`: CPU_ON, CPU_OFF, AFFINITY_INFO; `dt_set_psci()` in kboot publishes the table |
| U-Boot | `asahi-v2026.07-2` + 1 commit (`~/Work/u-boot-asahi`), `patches/psci-efi/u-boot` | `efi_platform_register()`: installs the table and adds Aura's image and MMIO to the EFI memory map |

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
* **CPU_OFF**, on the dying CPU:
  1. posts the PMGR stop request, as `smp_stop_cpu()` does;
  2. marks itself OFF;
  3. cleans and invalidates its L1 by set/way;
  4. calls `cpu_sleep(true)`, which powers the core down without
     retention.
* **AFFINITY_INFO** reports what the dying CPU wrote. It never reads a core's
  power status: `smp_stop_cpu()` notes that register access dies with the
  last core of a cluster.
* **CPU_ON of a core that is off:**
  1. waits 1 ms;
  2. restarts the core through the PMGR start registers (`+0x4`, then
     `+0x8 + 4 * cluster`);
  3. the core re-enters through RVBAR (`_cpu_reset_c`, `init_cpu()`) into
     the park loop;
  4. CPU_ON waits up to 100 ms for the park loop's flag, then dispatches.
     That flag is the same one `smp_start_cpu()` waits for.
* **Cache maintenance.** The parked CPUs run with the MMU off, so every
  spin-table access from the kernel's side is cleaned or invalidated
  (`dc civac`).

Checked statically: the call graph from `psci_efi_handler` reaches only the
`smp_psci_*` helpers, `dc_civac_range`, the L1 set/way loop, `udelay`,
`memset`, `smp_send_ipi` and `cpu_sleep`. No printf, no FP, and the build
uses `-mgeneral-regs-only`.

## Not covered yet

* **CPU_SUSPEND and SYSTEM_SUSPEND.** They are the next phase. The boot CPU's
  RVBAR entry still goes to `m1n1_main()`; Phase 2 needs a resume branch
  there.
* **A known race.** A CPU_ON that lands in the few instructions between a
  dying CPU's OFF and its power-down finds the core still up. The restart
  then does nothing, and CPU_ON returns INTERNAL_FAILURE: the kernel reports
  the CPU as failing to come online. The 1 ms wait makes this unlikely.
* **The RFC's open review points.**
  * The `preempt_count` and TTBR0 state are not restored when the handler
    does not return (CPU_SUSPEND). That does not apply to CPU_OFF, where the
    idle thread is re-initialised.
  * SET_SUSPEND_MODE before runtime services are up.
* **Watchdog.** Aura still disables the watchdog. A hang before systemd
  arms it needs the owner.

## First boot test (needs the owner's go)

One boot, armed the way the PMP test was (a one-boot `boot.bin` plus an
early unit that restores stock):

* **`boot.bin`:** the `aura-psci` build, the stock DTB set with #31 replaced
  by `t6020-j414s-psci.dtb`, and the patched U-Boot.
* **Kernel:** the `psci-efi-test` build (`-psci-efi`, `APPLE_PMP=y` for the
  link) with its modules, booted once via GRUB `next_entry`.

Expected outcomes:

* **The table is missing:** the kernel boots on one CPU and says so ("failed
  to come online" for each secondary). Linux still comes up, and the early
  unit puts stock back.
* **The table is found:** the boot log shows `psci: PSCIv1.0 detected` with
  the EFI conduit and all 10 CPUs online.
* **Then the test proper:** each secondary offline and online 100 times,
  then the idle and wake-latency checks against stock.
* **Risk:** the handler faults in the kernel's context (an unmapped
  address). That is an early panic, and the watchdog may not be armed yet.
