Thanks all, a few updates from the J414s (M2 Pro, 14").

**Clean install, no helper.** The S2R boot now runs on the stock Omarchy command line with no userspace helper and no sleep config: deep sleep is the kernel default once PSCI suspend is available. Soak 5/5, a 20 min sleep with 99.0 % of it in S2R (`SLP_S2R` counter), Wi-Fi/BT/NVMe back after each wake.

**`apple,t6020` gate and the hardcoded wake table are gone.** The PMGR AP wake mask address and the 22 wake sources come from the ADT (`pmgr` `ap-wake-sources`; the 22 numbers are exactly the ones my table carried), published by the boot loader in `/chosen`, so macsmc has no machine check or table any more.

**@muness:** the SIO tunables and USB-C wake-source settings I applied by script were not needed here: with the script off (tunables unwritten, USB-C wakeup left enabled) the J414s soaks 5/5 and does the 20 min sleep. They may still matter on the M2 Max, I only know the J414s. Likewise the T6020 DART tunable rewrite: the registers read back the same reset value (`0x1e000048` at 0x20c) before and after a sleep and sleeps work without writing them, so I dropped it.

**Cancelled sleeps.** Thanks for the report. I have not run `pm_test=devices` or a key during suspend on the J414s yet, so I can't say whether it shares your failure; it is on my list of untested cases.

**@nekolyanich:** thanks for the second-sleep write-up. Still not reproduced on the J414s; my soak is an idle desktop, not a drawing client.

Next: a 4 h battery sleep on this exact configuration, then draft PRs.
