# SPDX-License-Identifier: MIT
# Hypervisor tracer for the T6020 sleep engine's registers (GH-5, 2026-11-12): every guest access, in order (SYNC),
# to the always-on PMGR block MPMGR_AON pages 0-7 (0x29e5c0000..0x29e5c7fff: the five words the S2R commit changes, +0x14,
# +0x100, +0x4000 (the S2R timer), +0x4008, +0x400c) and to the AP wake-source mask/status block (0x404ea8000 and the
# first 0x100 bytes; macOS's setAPWakeupSources writes the nine mask words at +0x0c, getAPWakeupSources reads the
# status words at +0x30). Pages 8 and up of MPMGR_AON are not mapped (they fault from any core).
# Run beside trace_pmp.py / trace_smc.py:  run_guest.py -m hv/trace_pmgr.py ... -m hv/trace_mpmgr.py ...
from m1n1.hv import TraceMode
from m1n1.utils import irange

hv.trace_range(irange(0x29e5c0000, 0x8000), TraceMode.SYNC, name="mpmgr_aon")
hv.trace_range(irange(0x404ea8000, 0x100), TraceMode.SYNC, name="ap_wake")
print("trace_mpmgr: tracing MPMGR_AON 0x29e5c0000..0x29e5c7fff and the AP wake block 0x404ea8000")
