# SPDX-License-Identifier: MIT
# GH-5, 2026-11-12: every WRITE the guest makes to any of the PMGR's register ranges (/arm-io/pmgr regs), in order (SYNC), so
# a macOSTest sleep shows the full list of power-state words macOS changes on its way down, with values, on THIS Mac.
# (MPMGR_AON, reg 38, is covered by trace_mpmgr.py with reads.) Run beside trace_pmp.py / trace_smc.py / trace_mpmgr.py.
from m1n1.hv import TraceMode
from m1n1.utils import irange

node = hv.adt["/arm-io/pmgr"]
n = len(node.reg)
for i in range(n):
    try:
        addr, size = node.get_reg(i)
    except Exception as e:
        print("trace_pmgrw: reg", i, "skipped:", e)
        continue
    if addr == 0x29e5c0000:
        continue
    hv.trace_range(irange(addr, size), TraceMode.SYNC, read=False, name="pmgrw%d" % i)
print("trace_pmgrw: writes to", n, "pmgr ranges traced")
