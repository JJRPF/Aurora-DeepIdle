# Plan: S2R (suspend to RAM) on the M2 Pro (T6020, J414s)

Written 2026-10-23, after the SMC handshake and PMP wake tests. The research
behind each step is in `deep-idle-research.md` ("S2R: what is missing, piece
by piece" and the sections after it).

**Goal.** `/sys/power/mem_sleep` offers `deep`. A lid close powers the SoC
down with DRAM in self-refresh, wakes on the lid, the power key, the keyboard
or the PMU alarm, and comes back into Linux with every device working. Sleep
draws near macOS's 0.24 W (s2idle today: 1.4 to 2 W).

**The shape of it.** Aura (m1n1) becomes a PSCI provider with `CPU_OFF` and
`SYSTEM_SUSPEND`. Linux's PSCI driver then offers `deep` with no new core
code. The SoC steps that macOS runs after the drivers (PMGR quiesce, the S2R
timer, the PMU SPMI quiesce, the final SMC `slpa`) live behind
`SYSTEM_SUSPEND` in Aura. Driver steps (PMP, NVMe, PCIe L2, DCP, the early
SMC keys) stay in the Linux drivers' suspend callbacks.

**Two risks decide whether this works at all**, and the plan reaches them as
early as it can:

1. **Raw boot mode.** Linux boots as a raw image. Nobody knows whether iBoot
   programs the PMGR reconfig engine's wake script for a raw image as it
   does for a macOS kernelcache. If it does not, S2R needs the Mach-O boot
   path (Aurora's bootloader rework), not this plan. Phase 3 answers it.
2. **DCP.** The display coprocessor driver cannot resume from power loss
   ("we do not support full shutdown properly yet"). This is likely the
   longest single piece of driver work.

## Why some steps need someone at the Mac, and how to remove that

When Linux runs, a hang is recoverable from here. systemd arms the hardware
watchdog (1 min timeout), every test image boots only once, and the Pi keeps
the kernel log. Three cases are not recoverable remotely:

* **The Mac is not running Linux.** This covers m1n1 proxy mode, a sleep that
  never wakes, and a hang in m1n1 or in the wake path. Nothing answers the
  network, the watchdog may be off, and only a long press of the power key
  brings the Mac back. The Pi cannot press it.
* **A test boot image that does not reach Linux** boots again on every reboot.
  The step that restores the stock `boot.bin` runs in Linux.
* **A state that outlasts a warm reboot.** After `slpa` only a full power off
  cleared the storage loss.

An unattended run that hits one of these leaves the Mac down until the owner
is back, which also stops all other work. Some steps also need hands once:
the USB-C cable from the Pi to the Mac, the charger unplugged for a battery
measurement, and a macOS login for the hypervisor setup.

**Phase 0 would have removed most of this** (dropped, see below). Give the Pi a USB-PD board that speaks
Apple's vendor messages: Marc Zyngier's Central Scrutinizer (a Raspberry Pi
Pico with an FUSB302), or a similar board. Wired to the Mac's DFU port, it
gives the Pi:

* a hard reboot of the Mac. It goes through the Mac's own PD controller, so it
  should work when the SoC is hung or asleep (not yet tried on this machine);
* the Mac's debug serial console. That is the only log that works while USB
  and the network are down, which is during sleep and the first moments of a
  wake.

Add a smart plug on the charger that the Pi can switch, and battery-drain
measurements need no hands either. Whether a PD reboot also clears an
`slpa`-type state is unknown; check it once with the owner present.

## Phases

Each phase ends with a gate: what has to work before the next phase starts.

### Phase 0: remote hands (dropped: no extra hardware)

The owner cannot add the PD board or the smart plug (2026-10-23), so recovery
has to come from software:

* a test Aura build that leaves the SoC watchdog armed instead of disabling
  it (`wdt_disable()` in `main.c`), so a hang in Aura or in a wake reboots
  the Mac;
* Aura's early proxy wait, so the Pi can chainload the stock chain from a
  test boot that did not reach Linux;
* for the hypervisor runs, `asahi-bless --next` from Linux boots the test
  volume once, and the Pi's run script ends by rebooting the Mac through the
  proxy, back into Linux.

What this cannot cover: a sleep that never wakes, and an `slpa`-type state
that only a full power off clears. Runs that can end there still need the
owner within reach.

### Phase 1: CPU_OFF and CPU_ON in Aura (unattended where the watchdog covers it)

* Aura: a resident PSCI provider for T6020. Use the `psci-via-efi` branch as a
  reference only. Add `CPU_ON` and `CPU_OFF`; `CPU_OFF` is the ACC power-down,
  `0xc5acce55` at 0xfb0 and 0 at 0x310. Change the CPUs' `enable-method` to
  `psci` in the DT it passes on.
* Kernel: apply the PSCI-via-EFI RFC's six patches to a test branch.
* Boot: route A, a one-boot test `boot.bin` with `psci=direct`. If the
  payload fails, m1n1 drops into proxy mode, and the Pi can chainload the
  stock chain from there.
* Test: CPU hotplug, each secondary offline and online 100 times, then the
  idle and wake-latency checks against stock.
* **Gate:** hotplug is clean, deep idle is not worse, and the RVBAR re-entry
  of a secondary works.

### Phase 2: SYSTEM_SUSPEND with the SoC still on (unattended where the watchdog covers it)

* Aura `SYSTEM_SUSPEND`: the boot CPU powers down like a secondary. Its locked
  RVBAR lands in resident Aura, which restores the CPU state (chicken bits,
  EL2) and jumps to the resume address Linux passed in. The SoC, DRAM and
  devices keep power.
* Linux: `mem_sleep` now shows `deep`. The kernel takes the secondaries
  offline, suspends the devices and makes the last call. The AIC
  save/restore (kernel commit 1ac4376) runs here for the first time.
* Wake: the PMU alarm through the AIC (SPMI irq, AIC 724), then the lid and
  the power key.
* **Gate:** 20 of 20 cycles back in Linux, with no device errors. This proves
  the hand-back, the hardest firmware piece, without any SoC power-down.
  Power saved is small, since only the CPUs are off.

### Phase 3: trace macOS sleeping under the Aura hypervisor (owner once for macOS setup, then unattended)

This answers risk 1. The hypervisor boots macOS through the same raw chain
(iBoot, then m1n1, then the kernelcache as a guest). If macOS sleeps and
wakes there, iBoot's raw-mode setup is enough for S2R.

* Aura hypervisor changes:
  - Log the CYC_OVRD write it refuses today, and let the core power off.
  - Catch the boot CPU's RVBAR entry on wake and restart the guest at its
    own reset vector.
  - Bring the USB proxy link back after the wake, or log over serial
    while it is down (there is no serial without Phase 0).
* The guest is macOS 14.8.3 on its own volume, `macOSTest`, beside the
  everyday macOS. 14.8.3 is the pinned hypervisor guest for the M1 to M3
  series in Asahi's m1n1-hypervisor guide. Newer XNU needs SPTM, which Aura
  does not load (m1n1 PR #698 adds it; not merged). The everyday macOS
  (15.7.4) cannot be the guest.
* Set up once by the owner (`tools/macos-hv-testvol.sh`): the installer and
  an empty volume from the everyday macOS, then Setup Assistant without
  FileVault, then `setup` mode in the new system. That mode turns off
  automatic updates and runs `tools/macos-hv-prep.sh`. The prep script
  installs a launch daemon that, only when the boot-args carry `hvsleep=1`,
  schedules a wake (`pmset schedule wake`) and sleeps 5 minutes after boot.
  Then, in macOSTest's own recoveryOS, the Asahi guide's `bputil -nkcas`,
  `csrutil disable` and `kmutil configure-boot` with Aura. No hands are
  needed after that.
* The kernel: `tools/im4p-extract.py` turns the Preboot kernelcache into
  the Mach-O that `run_guest.py` loads (checked on 15.7.1: a 115 MB fileset).
* Trace (`proxyclient/hv/trace_*`):
  - PMGR: PS writes, `MPMGR_AON`, the CPU-start block, reconfig-looking
    writes;
  - SMC keys in the last seconds before sleep and the first after wake;
  - PMP messages;
  - ACC_OVRD and ACC_CFG per CPU;
  - the AOP and RVBAR writes.
* The old E3 check (from the proxy, stop the secondaries and deep-sleep the
  boot CPU) fits in the same session. It tests only the core-level RVBAR
  path, which Phase 2 already covers. It is cheap but does not decide risk
  1.
* **Gate:** an ordered list of every write macOS makes for sleep and for
  wake on T6020, and a macOS wake under the hypervisor. If macOS never wakes
  under the hypervisor, find out whether the hypervisor or raw mode is the
  cause. If it is raw mode, stop this plan and wait for the Mach-O boot path.

The fallback, if the hypervisor sleep cannot be made to work, is static
reverse engineering of the ApplePMGR and AppleT6020PMGR kexts, already
partly done. It is slower and less certain.

### Phase 4: devices that survive power loss (mostly unattended, in s2idle or Phase 2 mode)

Each device on its own, in the order the trace gives:

| Device | Today | Work |
|---|---|---|
| PMP | IDLE works; the wake fails. Gating `ps_pms_sram` alone does not restart the CPU, and a PMGR reset of `ps_pmp` killed the SoC (2026-10-23) | `ps_pmp` is pinned on (PS_MIN 0xf), so macOS probably never really power-cycles it either. Next: macOS's DART off/on and outbox steps around RUN, no reset |
| NVMe (ANS) | suspend shuts down RTKit and resets on resume | check it in Phase 2 and 5; little work expected |
| PCIe: Wi-Fi, SD reader, HDMI | ASPM only | L2 entry per `manual-enable-s2r`, D3cold resume through the PCI core (no remove/rescan) |
| SMC | `WKTP` and `slpw` harmless | keep those in prepare; `slpa` goes last, in Aura or a syscore step, in the traced order |
| DCP | no resume from power loss | the long pole: full shutdown and restart of the DCP firmware, or keep it powered if macOS does |
| GPU, USB/ATC and cio, keyboard and trackpad (MTP), AOP, audio | not checked | read each driver's suspend path; fix what loses state |

* **Gate:** each device passes 20 cycles of its own suspend path, with its
  power actually removed where the trace says macOS removes it.

### Phase 5: full S2R (owner present for the first cycle, then unattended)

* Aura `SYSTEM_SUSPEND` gains the SoC steps from Phase 3, in macOS's order.
  - Sleep: PMGR `quiesceHW` (GPU PMGR, SoC clock gates, PLL-off modes),
    which ends with the S2R timer (`MPMGR_AON` + 0x4000), the PMU SPMI
    quiesce and `slpa`. Where `slpa` falls against the PMGR steps is not
    known yet; the trace decides.
  - Wake: `restoreHW`, meaning the PLL relock and 0xc000 bit 31, then the
    hand-back from Phase 2.
* The first cycle uses the PMU alarm as the only wake source and has the
  owner at the power key. The first `slpa` on a sleep path that really
  powers down is still the most uncertain step.
* **Gate:**
  - 20 of 20 cycles;
  - wakes from the lid, the power key, the keyboard and the alarm;
  - `fs-check.sh` clean;
  - one hour on battery measured with the fuel gauge (`charge_now`) at or
    near 0.3 W (about 25 mAh an hour, against about 120 mAh at s2idle's
    1.4 W).

### Phase 6: daily use

* Route B: U-Boot passes Aura's PSCI table on as an EFI configuration table.
  That keeps the GRUB menu and the fallback kernels.
* Omarchy's suspend uses `deep`; s2idle stays available.
* The patches go to Aurora's trees under the Aurora policies.

## What can start now

No owner and no reboot needed:

* **Phase 1 code:** Aura `CPU_ON` and `CPU_OFF` for T6020, and the RFC on a
  kernel test branch. Built, not booted.
* **Phase 3 code:** the hypervisor CYC_OVRD and RVBAR-wake changes, and the
  trace scripts.
* **Phase 4 PMP:** the read-only answers the design still needs. Who pins
  `ps_pmp`'s minimum power state, and whether PMS_SRAM holds the PMP
  firmware.

Owner decisions (2026-10-23):

* no Phase 0 hardware; recovery comes from software (Phase 0 above);
* the PMP power-cycle test may run unattended;
* the Phase 3 guest is a separate macOS 14.8.3 volume (the everyday macOS
  auto-updated to 15.7.4, which the hypervisor cannot run).
