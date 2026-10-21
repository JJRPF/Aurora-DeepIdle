#!/usr/bin/env python3
"""Apply one idle-ab setting (default, pd-always, res=US, ...) and leave it in place, for wakelat.

'default' also puts pd_residency_us back to the driver's 10000 when the kernel has it.
"""
import importlib.util
import sys

spec = importlib.util.spec_from_file_location('idle_ab', '/usr/local/lib/deepidle/idle-ab.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
machine = m.Machine()
d0, d1, residency, only, eas = m.parse_setting(sys.argv[1])
if residency is None and machine.residency.exists():
    residency = 10000
machine.apply((d0, d1, residency, only, eas))
