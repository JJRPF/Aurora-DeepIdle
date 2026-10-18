#!/usr/bin/env python3
"""Rates of the SMC watch keys against PSTR/PDTR/PHPC: sudo python3 -I acc-rates.py [SECONDS]"""
import sys, time
W = "/sys/kernel/debug/smc_keyread/watch"
P = "/sys/kernel/debug/smc_keyread/power"
def watch():
    d = {}
    for line in open(W):
        f = line.split()
        if f[0] == "t_ns":
            d["t"] = int(f[1]) / 1e9
        elif f[-1] != "err":
            d[f[0]] = int.from_bytes(bytes.fromhex(f[-1]), "little")
    return d
def power():
    return {l.split()[0]: int(l.split()[-1]) / 1000 for l in open(P) if l.split()[-2] != "err"}
n = int(sys.argv[1]) if len(sys.argv) > 1 else 60
w0 = watch(); ps = []
end = time.time() + n
while time.time() < end:
    ps.append(power()); time.sleep(1)
w1 = watch()
dt = w1["t"] - w0["t"]
mean = {k: sum(p[k] for p in ps) / len(ps) for k in ("PSTR", "PDTR", "PHPC", "PMVC", "PPBR", "Pb0f") if k in ps[0]}
print(f"{dt:.1f} s; means: " + ", ".join(f"{k} {v:.3f} W" for k, v in mean.items()))
for k in w0:
    if k == "t":
        continue
    r = (w1[k] - w0[k]) / dt
    line = f"{k}  {w0[k]:>16} -> {w1[k]:>16}  {r:12.3f}/s"
    if r:
        line += "   " + "  ".join(f"/{m}={r / v:9.2f}" for m, v in mean.items() if v)
    print(line)
