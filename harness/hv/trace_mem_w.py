# SPDX-License-Identifier: MIT
# GH-5, 2026-11-12: every WRITE the guest makes to the memory controller blocks (/arm-io/mcc, /arm-io/amcc), in order (SYNC):
# does macOS prepare the memory system (cache flush, DRAM self-refresh, retention) on its way to sleep? Run beside trace_mpmgr.py.
from m1n1.hv import TraceMode
from m1n1.utils import irange

done = 0
try:
    for path in ("/arm-io/mcc", "/arm-io/amcc"):
        try:
            node = hv.adt[path]
        except Exception as e:
            print("trace_mem_w: no", path, repr(e))
            continue
        for i in range(len(node.reg)):
            try:
                addr, size = node.get_reg(i)
            except Exception:
                continue
            hv.trace_range(irange(addr, size), TraceMode.SYNC, read=False, name="%s_%d" % (path.split("/")[-1], i))
            print("trace_mem_w:", path, i, hex(addr), hex(size))
            done += 1
except Exception as e:
    print("trace_mem_w: stopped:", repr(e))
print("trace_mem_w: write-tracing", done, "memory controller ranges")
