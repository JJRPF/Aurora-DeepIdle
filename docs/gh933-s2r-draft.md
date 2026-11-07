# Draft comment for aurora-silicon/linux#933 (NOT posted; needs the owner's OK)

S2R status with the PMP enabled on J414s (M2 Pro), from GH-8 testing on 2026-11-04:

- With this PR's PMP node active, a PSCI `SYSTEM_SUSPEND` (implemented in the Aura/m1n1 stage and called
  through an EFI runtime PSCI handler) suspends and resumes cleanly: 20 of 20 cycles on the boot CPU alone
  and 20 of 20 with all 10 CPUs (the nine secondaries go through PSCI CPU_OFF/CPU_ON each cycle), woken by
  the PMU RTC alarm, 0 device errors after resume. The SMC power-key line also wakes it.
- That is suspend with the CPUs in deep WFI and the devices suspended; the SoC and DRAM stay powered.
  The real SoC sleep steps (what macOS does after `slpa`) are not implemented yet, so S2R with the PMP is
  qualified only at this level. Nothing seen so far points at the PMP being a problem for it.

Update, 2026-11-06 (GH-8 runs since; still NOT posted, for the owner to approve or cut):

- The PMP takes part in the sleep handshake as in macOS: `SetAPPower`/`SetIOPPower` 0x201 (IDLE) for sleep are
  acked, and it answers again after the wake. Sending `SetAPPower` twice crashes its firmware ("Invalid AP power");
  that was a bug in our test kernel, not in the PMP or this PR.
- Order matters: once the PMP is IDLE it refuses to drop device requests (`-EALREADY`). genpd releases the display
  and ISP requests only in the noirq phase, after a driver has sent IDLE in `suspend_late`, so the PMP went to sleep
  still holding them (0xf000). Releasing them before IDLE takes the request word to 0 as macOS does; after the wake
  all four are asserted again. Normal suspends with that release came back on the alarm in every run today except one
  whose own test register dump hung it.
- The SoC's own S2R entry still does not complete with every macOS sleep step we know of, the PMP's included (the
  PMGR's S2R timer resets the SoC about 86 s in). Nothing points at the PMP; the open difference is the devices Linux
  keeps powered at sleep (the display coprocessors, the USB-C controllers).

Update, 2026-11-06 evening (still NOT posted):

- The devices are not what the S2R entry waits for: with test switches that stop the USB-C controllers and shut the
  display coprocessors' firmware down for the sleep, genpd powers every device-held domain off (83 of 200 on at the
  last moment, the rest the DT's always-on ones), and the full macOS sequence still ends in the timer's reset at 86 s.
- The PMP also takes CPU-complex requests from the AP (PCPM0/1, `0xf300` acked) and their release; macOS releases
  them after `slpa`. Whether that release is the missing step is the next (attended) test.
- One PMP-adjacent finding: when the display chain goes off, its fabric parent `afr` goes off too, and the GPU's
  `gfx` domain (also under `afr`) then fails to power up after the wake (`Failed to reach power state 0xf`). Keeping
  `afr` on through the sleep avoids it. Not a PMP issue as far as we can tell, but it touches the display/GPU power
  tree this PR enables.
