# SPDX-License-Identifier: MIT
# Hypervisor tracer for the T6020 sleep engine's registers (GH-5, 2026-11-12): every guest access, in order (SYNC),
# to the always-on PMGR block MPMGR_AON pages 0-7 (0x29e5c0000..0x29e5c7fff: the five words the S2R commit changes, +0x14,
# +0x100, +0x4000 (the S2R timer), +0x4008, +0x400c) and to the AP wake-source mask/status block (0x404ea8000 and the
# first 0x100 bytes; macOS's setAPWakeupSources writes the nine mask words at +0x0c, getAPWakeupSources reads the
# status words at +0x30). Pages 8 and up of MPMGR_AON are not mapped (they fault from any core).
# Run beside trace_pmp.py / trace_smc.py:  run_guest.py -m hv/trace_pmgr.py ... -m hv/trace_mpmgr.py ...
from m1n1.hv import TraceMode
from m1n1.utils import irange

hv.trace_range(irange(0x29e5c0000, 0x4000), TraceMode.SYNC, name="mpmgr_aon_lo")
hv.trace_range(irange(0x29e5c4004, 0x3ffc), TraceMode.SYNC, name="mpmgr_aon_hi")
hv.trace_range(irange(0x404ea8000, 0x100), TraceMode.SYNC, name="ap_wake")
print("trace_mpmgr: tracing MPMGR_AON 0x29e5c0000..0x29e5c7fff and the AP wake block 0x404ea8000")

# 2026-11-12: at the guest's first write to the S2R timer, read macOS's own register state through the proxy (the guest is trapped
# on that write): every PMGR PS word of every ADT device (addr = pmgr reg + ps-reg offset + psidx * 8) and every non-zero word of
# MPMGR_AON pages 0 to 7. Written to ~/deepidle/hv/psdump-<time>.txt on the Pi. To be compared with Aura's view at our commit.
import time as _time
_dump = {"done": False}
_pmgr = hv.adt["/arm-io/pmgr"]

def _rd(a):
    try:
        return hv.p.read32(a)
    except Exception as e:
        return None

def _dump_at_timer(evt):
    print("trace_mpmgr: guest write to the S2R timer, value 0x%x" % evt.data)
    if _dump["done"] or evt.addr != 0x29e5c4000:
        return
    _dump["done"] = True
    path = "/home/jjrpfister/deepidle/hv/psdump-%d.txt" % int(_time.time())
    f = open(path, "w")
    n = 0
    for dev in _pmgr.devices:
        ps = _pmgr.ps_regs[dev.psreg]
        a = _pmgr.get_reg(ps.reg)[0] + ps.offset + dev.psidx * 8
        v = _rd(a)
        f.write("PS 0x%x %s %s\n" % (a, dev.name, "None" if v is None else "0x%08x" % v))
        n += 1
    for off in range(0, 0x8000, 4):
        v = _rd(0x29e5c0000 + off)
        if v:
            f.write("AON 0x%x 0x%08x\n" % (off, v))
    f.close()
    print("trace_mpmgr: dumped %d ps words and the AON pages to %s" % (n, path))

hv.add_tracer(irange(0x29e5c4000, 4), "mpmgr_dump", TraceMode.SYNC, write=_dump_at_timer)
