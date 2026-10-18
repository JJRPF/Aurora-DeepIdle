#!/usr/bin/env python3
"""Mean SMC Total System Power between two snapshots of zSPa (sum of PSTR in mW per SMC sample) and
zSPc (sample count), so sleep can be measured on the charger.
  sudo python3 -I smc-acc.py snap FILE         save a snapshot
  sudo python3 -I smc-acc.py diff FILE0 FILE1  mean power and sample period between them"""
import json, sys
W = "/sys/kernel/debug/smc_keyread/watch"
def watch():
    d = {}
    for line in open(W):
        f = line.split()
        if f[0] == "t_ns":
            d["t"] = int(f[1]) / 1e9
        elif f[-1] != "err":
            d[f[0]] = int.from_bytes(bytes.fromhex(f[-1]), "little")
    return d
if sys.argv[1] == "snap":
    json.dump(watch(), open(sys.argv[2], "w"))
else:
    a, b = (json.load(open(f)) for f in sys.argv[2:4])
    dt, n = b["t"] - a["t"], (b["zSPc"] - a["zSPc"]) % 2**32
    if not n:
        sys.exit("no SMC samples between the snapshots")
    mw = ((b["zSPa"] - a["zSPa"]) % 2**64) / n
    print(f"{dt:.1f} s, {n} SMC samples ({dt / n:.4f} s each): mean Total System Power {mw / 1000:.3f} W")
