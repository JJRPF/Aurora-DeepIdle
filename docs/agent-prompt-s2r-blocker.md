# Prompt for an agent: why S2R never completes on the M2 Pro (T6020, J414s)

Self-contained. Paste it to an agent that can read `aurora-silicon/linux` and `aurora-silicon/aura`.

```
Task: find why suspend-to-RAM never completes on the MacBook Pro 14" M2 Pro
(T6020, J414s), by comparing it with the SoCs where it already works. This is
analysis first; propose a concrete fix only if the evidence supports one.

Symptom
- Linux runs at EL2 under Aura. We replay macOS's whole sleep entry, then write
  the PMGR S2R timer (the commit). The cores go into deep sleep.
- Nothing wakes the SoC. About 60 s after the commit it resets and cold-boots.
  The reset follows the commit, not the wake alarm (alarm at +40 s and +70 s:
  same reset time) and not any watchdog (all AON watchdogs were disarmed;
  without the commit the 120 s suspend watchdog fires instead).
- The PMU register space holds no reset-cause flag (full dumps compared across
  commit, no-commit and watchdog resets).
- macOS 14.8.9's own deep sleep, run as a guest under our m1n1 hypervisor with
  the cores' ACC_OVRD/CYC_OVRD writes passed to hardware, also resets ~60 s
  after the last core write. So either something in that setup blocks the
  sleep, or the missing condition is invisible to our traces.

Already done on T6020 (do not redo)
- SMC slpw/slpa, PMU boot stage 0x50, PMP handshake and request words to 0,
  SetAPPower/SetIOPPower 0x201, coprocessor halts (GFX, ANS, SIO, PMP),
  59 PMGR power words forced to macOS's state, 484 memory-controller and device
  writes replayed from a macOS hypervisor trace, SEP told to sleep, clusters and
  APSC off, AIC masked, S2R timer last.
- Evidence and a full log: https://github.com/JJRPF/Aurora-DeepIdle
  (docs/worklog.md, docs/s2r-status.json, docs/hv-*.txt, data/pmu-dumps/),
  public summary at https://jjrpf.com/S2R .

What to do
1. Read drivers/soc/apple/sleep.c in aurora-silicon/linux (integration/aurora),
   the T8140, T8132 and T6050 sleep paths, and the M4 Max series (#1664).
   List every step or precondition before or at the commit that those paths do
   and that the T6020 path above does not. Look especially at: what has to be
   idle or off before the commit is accepted, any handshake with the SMC/PMU/AOP
   after the timer write, and anything that makes a commit "stick" rather than
   time out (e.g. the "BUSY latched" power words, DART/SIO/ANS/ISP stop order,
   SPMI interrupt acknowledgement).
2. Check Aura's S2R mailbox path (aurora-silicon/aura, src/psci.c and the
   T6050/T8132 sleep code) for the same questions.
3. For each candidate difference, say how it could produce "the SoC resets
   about 60 s after the commit with no wake" and how we could test it on T6020
   with one armed run.

Constraints
- Do not touch a main install's partitions or boot chain. Test only through our
  DeepTest harness (a disposable boot that returns to the normal OS by itself).
- Report: ranked candidate causes, evidence for each (file and line), and the
  smallest change to try first. Say clearly what you could not verify.
```
