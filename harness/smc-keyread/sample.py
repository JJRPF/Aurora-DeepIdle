#!/usr/bin/env python3
"""Sample smc_keyread's power keys: sudo python3 -I sample.py [SECONDS] -> mean/min/max W per key.

Needs smc-keyread.ko loaded. Keys that read 0 throughout are listed on one line at the end."""
import statistics, sys, time

F = "/sys/kernel/debug/smc_keyread/power"
n = int(sys.argv[1]) if len(sys.argv) > 1 else 60
vals = {}
for _ in range(n):
    t = time.monotonic()
    for line in open(F):
        f = line.split()  # "PSTR (0x50535452) 41140be9 9252" or "... err -5"
        k, raw, mw = f[0], f[-2], f[-1]
        if raw != "err":
            vals.setdefault(k, []).append(int(mw) / 1000)
    time.sleep(max(0, 1 - (time.monotonic() - t)))
zero = [k for k, v in vals.items() if not any(v)]
print(f"{n} samples at 1 Hz, {time.strftime('%F %T')}")
print(f"{'key':5} {'mean W':>8} {'min':>8} {'max':>8}")
for k, v in sorted(vals.items(), key=lambda kv: -statistics.mean(kv[1])):
    if any(v):
        print(f"{k:5} {statistics.mean(v):8.3f} {min(v):8.3f} {max(v):8.3f}")
print("always 0:", " ".join(sorted(zero)))
