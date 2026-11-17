Thanks, this is very useful. We went through each point against our J414s (Linux at EL2 under Aura, no hypervisor):

- SMC AP deadline (0x29e2a002c): reads 0 here, nothing arms it, so zeroing it is a no-op for us.
- PCIe: our entry already takes apcie_gp_sys, apcie_gpshr_sys and apcie_gp to target 0 and reads all three at actual state 0 at the commit; we did not need the port interrupt ack to get there. Still happy to look at it as a PR against Aura if useful.
- SIO axi2af tunables: not in the ADT; I decoded the 22-entry T6020 `_af_sioaxi2af_figs_1` table from the macOS 15 kernelcache (reg = (reg & ~clear) | set at 0x39a000000: 0x0 (3,1), 0xc (0xfffff,0xd), 0x10 (0xfffff,0xc), 0x14/0x18 (0xfff,1), 0x1c-0x2c (0xfff,3), the same again at 0x108-0x12c, 0x400 (0xc00103ff,0xc0010010), 0xa00 (0x1ffffff,0x1ffffff)). Applied all of them before the SEP sleep, read back OK, then the usual commit: still no wake, reset ~86 s later.
- cluster_power=0 / parked cores powered off: on our side the secondaries go into non-retention deep WFI (WFI_MODE 3 + DISABLE_WFI_RET) right at the commit, with the cluster power-off step and a quiet commit. No change. What does cluster_power=0 do in your tree (which register or m1n1 knob)? We could not find it in the public m1n1.

Where we are different from both of you: Andreas's thin stage 1 (cores never started by smp_init), which we are about to try as a stage 1 install. If your woken runs share anything like that (cores started late or never), that would be worth knowing.
