# SPDX-License-Identifier: MIT
# GH-5 (2026-11-21): the two PMU SPMI buses of T6020 (nub-spmi0 = spmi-mpmu, nub-spmi1 = spmi-spmu), so a macOS
# sleep and wake show its PMU register writes (rails such as VR3l, and 0x2505/0x2705). The stock trace_spmi.py
# also traces nub-spmi-a0, which this ADT does not have.
from m1n1.trace.spmi import SPMITracer, SPMIDevTracer

for dname in ["/arm-io/nub-spmi0", "/arm-io/nub-spmi1"]:
    t = SPMITracer(hv, dname, verbose=0)
    for dev in t.dev:
        if hasattr(dev, "reg"):
            t.add_device(dev.reg[0], SPMIDevTracer(dev.reg[0], dev.name))
    t.start()
    print("trace_spmi_pmu: tracing", dname)
