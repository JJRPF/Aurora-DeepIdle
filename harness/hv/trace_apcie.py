# SPDX-License-Identifier: MIT
# GH-5 (2026-11-21): every guest WRITE to the T6020 apcie block, in order (SYNC), so a macOS sleep and wake
# show what it does to bring the Wi-Fi/BT (port 0) and SD reader (port 1) links back. Reads are not logged
# (LINKSTS polling would flood the log). Covers config space (ECAM, 0x580000000..), the RC (0x591000000..),
# the port blocks (0x594000000, 0x595000000, ...), and the PHYs (0x59e000000..). BAR windows are elsewhere.
#   run_guest.py ... -m hv/trace_apcie.py
from m1n1.hv import TraceMode
from m1n1.utils import irange

hv.trace_range(irange(0x580000000, 0x20000000), TraceMode.SYNC, read=False, write=True, name="apcie")
print("trace_apcie: tracing writes to 0x580000000..0x59fffffff")
