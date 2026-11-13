# SPDX-License-Identifier: MIT
# GH-5, 2026-11-12: after the guest's first write to mcc_0 0x11080 (the first memory write of macOS's sleep entry, just after
# MBSE=slpa), write-trace every other /arm-io device range (SYNC, writes only) except the known hot ones (storage, DART, UART,
# USB, GPU, display), so everything else macOS pokes between there and the sleep is listed in order. Run beside trace_mem_w.py.
from m1n1.hv import TraceMode
from m1n1.utils import irange

_state = {"on": False}
_skip = ("nvme", "ans", "dart", "uart", "usb", "atc", "gfx", "gpu", "disp", "dcp", "mcc", "amcc", "pmgr", "aic", "sio", "spmi", "pmp")

def _arm(evt):
    if _state["on"]:
        return
    _state["on"] = True
    n = 0
    for node in hv.adt["/arm-io"]:
        name = node.name
        if any(s in name for s in _skip):
            continue
        try:
            regs = node.reg
        except Exception:
            continue
        for i in range(len(regs)):
            try:
                addr, size = node.get_reg(i)
            except Exception:
                continue
            if size > 0x1000000:
                continue
            try:
                hv.trace_range(irange(addr, size), TraceMode.SYNC, read=False, name="late_%s_%d" % (name, i))
                n += 1
            except Exception as e:
                pass
    print("trace_late_w: armed %d device ranges for write tracing" % n)

hv.add_tracer(irange(0x28e3d1080, 8), "late_w_trigger", TraceMode.SYNC, write=_arm)
print("trace_late_w: waiting for the first sleep-entry memory write")
