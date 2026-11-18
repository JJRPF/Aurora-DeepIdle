Thank you, that clears up two things: `cluster_power=0` is a macOS boot-arg (I found it in the kernelcache's machine_routines, next to enable_skstb), so it is not a gap in our setup, and the old ~1/4 wake rate was your own diagnostic, not the hardware. Good to know both.

Two questions, only if you have a moment:
1. "The hypervisor holds the real power-down until cpu0 reaches the edge": what is the edge, concretely (cpu0's write of the S2R timer, or a later write), and does anything release the held secondaries other than cpu0's own final WFI? Ours release the parked cores into deep WFI after the timer write (CPUSTART stop request before it), and the SoC still resets about 86 s after the commit.
2. Is your wake working with the PMP and SEP both still running at the commit, or did you stop them first?

For the resume side, I would like the exact register sequences when you have them, starting with ANS (the two tunable properties plus keeping the RTKit buffers) and the PCIe re-init at the wake, since neither is testable here until we get a wake.
