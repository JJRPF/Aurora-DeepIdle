Thanks all, a few updates from the J414s (M2 Pro, 14").

**Clean install, no helper.** The S2R boot now runs on the stock Omarchy command line with no userspace helper and no sleep config: deep sleep is the kernel default once PSCI suspend is available. Soak 5/5, a 20 min sleep with 99.0 % of it in S2R (`SLP_S2R` counter), Wi-Fi/BT/NVMe back after each wake.

**`apple,t6020` gate and the hardcoded wake table are gone.** The PMGR AP wake mask address and the 22 wake sources come from the ADT (`pmgr` `ap-wake-sources`; the 22 numbers are exactly the ones my table carried), published by the boot loader in `/chosen`, so macsmc has no machine check or table any more.

**@muness:** the SIO tunables and USB-C wake-source settings I applied by script were not needed here: with the script off (tunables unwritten, USB-C wakeup left enabled) the J414s soaks 5/5 and does the 20 min sleep. They may still matter on the M2 Max, I only know the J414s. Likewise the T6020 DART tunable rewrite: the registers read back the same reset value (`0x1e000048` at 0x20c) before and after a sleep and sleeps work without writing them, so I dropped it.

**Cancelled sleeps.** Thanks for the report. I have not run `pm_test=devices` or a key during suspend on the J414s yet, so I can't say whether it shares your failure; it is on my list of untested cases.

**@nekolyanich:** thanks for the second-sleep write-up. Still not reproduced on the J414s; my soak is an idle desktop, not a drawing client.

Update: a 4 h sleep (14404 s) on this exact configuration woke on the RTC alarm with 99.9% of it in S2R (`SLP_S2R`), 0 failed units, Wi-Fi back. Its battery reading is not usable (the charger was connected at some point), so the 0.375 W figure is still the one night.

I merged #13 and #14, thank you @muness. The macsmc hunk of the T6021 kernel diff is obsolete after the wake-source change; there is a DTS-only diff next to it. #14's `kernel-commit-late.diff` changes the core PM code for every firmware suspend and adds module parameters, so I am keeping the diffs in the repo and not proposing them upstream; the `hci_bcm4377` probe fix stands on its own and is a candidate for its own PR.

The Aura half is filed as a draft: https://github.com/aurora-silicon/aura/pull/539 . The kernel series is written on the omacom 7.3 integration branch; 4 of its 10 squashed commits conflict with the S2R work already on aurora-silicon/linux main, so it needs a port and a test run before it is filed.
