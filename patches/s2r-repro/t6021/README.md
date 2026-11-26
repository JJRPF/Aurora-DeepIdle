# M2 Max (J414c, T6021) on top of the M2 Pro S2R patches

Two small diffs that go on top of the M2 Pro diffs in the parent folder. With them, the R62Y-4 recipe gives a real suspend-to-RAM and wake on a 14-inch M2 Max (J414c, T6021, 12 CPUs).

| File | Apply after | What it does |
|---|---|---|
| `kernel-t6021-j414c.diff` | `../kernel-on-omacom-linux-aurora-7.3-8ca67c75ff52.diff` | Adds `t6021-j414c-psci-pmp.dts` (PSCI through EFI, PMP booted, modelled on `t6020-j414s-psci-pmp.dts`). Lets `macsmc` set WKTP and the wake mask on `apple,t6021` as it does on `apple,t6020`. |
| `aura-t6021.diff` | `../aura-on-omacom-m1n1-bf6a6417.diff` | Lets T6021 use the T6020 suspend path, and adds what the Max has on top: a sixth soc-cluster (DISPLAY2), the dispext2/3 power words, five gate words macOS 13.5 zeroes at sleep entry, two more IOA error enables, memory-cache controllers 4-7, and room for their runtime MMIO ranges. |

No change to the R62Q-R62Y kernel code was needed. The `apple,t6020-pmp-v2` and `apple,t6020-pcie` matches and the disp0 power cycle apply to the Max as they are.

The device tree is left out of the Makefile because it has the same compatible as `t6021-j414c.dtb`; build it by name (`make apple/t6021-j414c-psci-pmp.dtb`).

## What was tested

Tested on one J414c, 2026-11-25, from a RAM root (initramfs only, root and home never mounted), nothing plugged in, on battery. Kernel: this repo's 7.3 diff at `eacbc56` plus `kernel-t6021-j414c.diff`. Aura: image 128 from the Aura diff at `eacbc56` plus `aura-t6021.diff`.

Nothing unbound, `pm_async=0`, 10 s RTC alarm, two sleeps in one boot. Both woke, `echo mem` returned 0:

- Real S2R: `SLP_S2R` advanced on both sleeps; CPUs 0-11 back.
- Internal display: `internal DCP A500: 0`, `disp0 cycle complete: cpu0 0x1f0403ff fe 0x3ff sys 0x3ff (0 0 0 0 0 0)`, `internal DCP warm restart complete (0)`; eDP-1 connected and enabled, backlight back, panel on.
- GPU (`aurora 406400000.gpu`): kept bound, `GPU firmware idled for sleep`, `GPU firmware restarted warm (kick Ok(()))`.
- SEP: `the enclave is back from its sleep request`; the second sleep was accepted.
- PMP: restarts after the wake, no ack timeouts.
- PCIe: `unbound 3 endpoint(s) before freeze`, both dart-apcie tunables restored, rescan finds the devices; a Wi-Fi scan saw networks after the first wake. NVMe live.

The same kernel with the GPU and PCIe endpoints unbound by hand before the sleep gave the same result.

## Caveats

- **The Max needs `echo 0 > /sys/power/pm_async` before sleeping.** With the default (parallel device suspend) it hangs during device suspend. The cause is not known yet.
- Both diffs also apply on the parent diffs at `c2b1eac` (Aura 129), and Aura builds there, but that combination has not been booted.
- `aura-t6021.diff` still carries a WFI-only retention path for T6021 (`psci_j414c_retention`). It runs only when the Aura control word has no entry steps, which is not the default, so the default path is the real sleep.
- Not tested: the full desktop, lid, audio, external displays or a dock, SD card, Bluetooth pairing, overnight drain.
