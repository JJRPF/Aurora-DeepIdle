# Question for Naeem Malik: S2R on T6020 (M2 Pro, J414s)

Hi Naeem. I'm following your S2R path (Aura, `SYSTEM_SUSPEND`, the commit, then deep WFI) on a MacBook Pro M2 Pro (T6020, J414s), and I'm stuck at the point where your M1 goes down and mine does not. I would value anything you can tell me about what the sleep engine needs at that point.

**What we do.** The same order as yours: everything macOS does before the commit (domains, clusters, SEP asleep and gated, SMC `slpw` / `slpa` / `WKTP`, PMP release, wake mask, AIC masked, APSC off, EDPRCR cleared), the secondaries released into a deep WFI (CYC_OVRD WFI_MODE 3, retention), then three writes of 1 to `MPMGR_AON_S2R_TIMER` (`0x29e5c4000`), then only the cache flush and the boot core's deep WFI. Nothing after the commit.

**What happens.**
- The commit is taken: the PMGR system state moves `SYS_AWAKE` to `SYS_SLP_DDR`, and WD2 is reloaded from 90 s to 60 s. The SoC-level state stays `AWAKE`, and DEEP_WAIT / SLP_S2R / SLP_DDR never start counting.
- Exactly five words of `MPMGR_AON` (pages 0 to 7 readable; none change without the commit) change, all within 4 ms of the first write, and then nothing moves for the next ~58 s:

  | word | at rest | after the commit |
  |---|---|---|
  | `+0x14` | 0x3 | 0x1 |
  | `+0x100` | 0x8 | 0xa |
  | `+0x4000` (timer) | 0x1 | 0x0 |
  | `+0x4008` | 0x00010000 | 0x00000001 |
  | `+0x400c` | 0 | 1 |

- Then WD2 resets the Mac 61 s after the commit. An RTC alarm set inside that window does not wake anything.
- Pages 8, 9 and 10 of the block (`0x29e5c8000` and up) hang the reader (an access from an awake core never returns), so I cannot see more of the engine.
- The same happens with no extra core awake (all ten cores in deep sleep, no observer), so a core held awake is not the cause.

**Questions.**
1. On M1 after the commit, do you see the same words move and then something further? Do you know what `+0x14`, `+0x100`, `+0x4008` and `+0x400c` are (the one-hot move of `+0x4008` from bit 16 to bit 0 looks like a state step)?
2. Is there an input the engine takes after the timer write that you have to provide on M1 (a core's deep-sleep state, an SMC or PMP acknowledgement, a PCPM or CLPC line, the AOP) and that could be different or missing on T6020?
3. Does anything need to happen to pages 8 to 10 (a clock, a power gate, a different access type) before they can be read, and do they hold the sleep state?
4. Did you have to disarm anything besides WD1 and WD2 (you stop WD2 last in the wake path)? On T6020 WD2 is reloaded to 60 s by the commit itself.

Everything above is in the open at https://jjrpf.com/S2R and in `docs/worklog.md` of JJRPF/Aurora-DeepIdle (runs R34 to R36A).

Thank you.
