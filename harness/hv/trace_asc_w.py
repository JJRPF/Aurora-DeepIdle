# SPDX-License-Identifier: MIT
# GH-5, 2026-11-12: which coprocessors does macOS put to idle on its way to sleep? Every WRITE the guest makes to the register ranges of
# each /arm-io node that has an "iop-*" child (an RTKit coprocessor: ans, sio, isp, ane, ave, gfx, dcp, aop, smc, pmp, ...), SYNC.
# A SetAPPower / SetIOPPower message shows as a 64-bit write of 0x00b0000000000201 / 0x0060000000000201 to the mailbox inbox.
from m1n1.hv import TraceMode
from m1n1.utils import irange

done = 0
try:
    done = 0
    for path in ["/arm-io"]:
        top = hv.adt[path]
        for node in top:
            try:
                kids = [c.name for c in node]
            except Exception:
                continue
            if not any(k.startswith("iop-") for k in kids):
                continue
            try:
                n = len(node.reg)
            except Exception:
                continue
            for i in range(n):
                try:
                    addr, size = node.get_reg(i)
                except Exception:
                    continue
                if size > 0x400000:
                    continue
                if node.name == "ans" and i == 3:
                    continue  # the NVMe queues: 1.2 million writes in the first run; the guest never reached its sleep
                hv.trace_range(irange(addr, size), TraceMode.SYNC, read=False, name="asc_%s_%d" % (node.name, i))
                done += 1
except Exception as e:
    print("trace_asc_w: stopped:", repr(e))
print("trace_asc_w: write-tracing", done, "coprocessor register ranges")
