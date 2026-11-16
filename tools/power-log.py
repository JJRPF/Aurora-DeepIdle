#!/usr/bin/env python3
"""Power log: every INTERVAL seconds one JSON line with the system power (macsmc_hwmon: Total System and
Heatpipe), the battery, the backlight, the open windows (Hyprland clients) and the processes using the most CPU.
Log: ~/.local/share/power-log/power.jsonl. Summary: power-log.py report [hours]."""
import glob, json, os, subprocess, sys, time
from collections import defaultdict
from pathlib import Path

INTERVAL = int(os.environ.get("POWER_LOG_INTERVAL", "30"))
LOG = Path.home() / ".local/share/power-log/power.jsonl"
HZ = os.sysconf("SC_CLK_TCK")

def rd(p):
    try:
        return Path(p).read_text().strip()
    except Exception:
        return None

def hwmon():
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        if rd(h + "/name") == "macsmc_hwmon":
            return h

def power(h):
    out = {}
    for f in glob.glob(h + "/power*_label"):
        v = rd(f[:-6] + "_input")
        if v is not None:
            out[rd(f)] = int(v) / 1e6
    return out

def cpu_times():
    t = {}
    for d in glob.glob("/proc/[0-9]*"):
        try:
            s = Path(d + "/stat").read_text()
            r = s.rsplit(")", 1)
            name = r[0].split("(", 1)[1]
            f = r[1].split()
            t[int(d[6:])] = (name, int(f[11]) + int(f[12]))
        except Exception:
            pass
    return t

def windows():
    try:
        sigs = sorted(glob.glob(f"/run/user/{os.getuid()}/hypr/*/"), key=os.path.getmtime)
        env = dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE=os.path.basename(sigs[-1].rstrip("/")),
                   XDG_RUNTIME_DIR=f"/run/user/{os.getuid()}")
        c = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, env=env, timeout=3).stdout)
        return sorted({x["class"] for x in c if x.get("mapped")})
    except Exception:
        return None

def sample(prev, dt):
    h = hwmon()
    p = power(h) if h else {}
    b = "/sys/class/power_supply/macsmc-battery/"
    cur = cpu_times()
    top = defaultdict(float)
    for pid, (name, t) in cur.items():
        if pid in prev and prev[pid][0] == name:
            top[name] += (t - prev[pid][1]) / HZ / dt * 100
    top = sorted(top.items(), key=lambda x: -x[1])[:6]
    bl = rd("/sys/class/backlight/apple-panel-bl/brightness"); bm = rd("/sys/class/backlight/apple-panel-bl/max_brightness")
    return cur, {
        "t": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "total_w": p.get("Total System Power"), "heatpipe_w": p.get("Heatpipe Power"),
        "batt_w": (int(rd(b + "power_now") or 0) / 1e6), "batt_pct": rd(b + "capacity"), "batt_status": rd(b + "status"),
        "ac": rd("/sys/class/power_supply/macsmc-ac/online"),
        "backlight_pct": round(100 * int(bl) / int(bm)) if bl and bm else None,
        "load1": os.getloadavg()[0], "windows": windows(),
        "top_cpu": [[n, round(v, 1)] for n, v in top if v >= 1.0],
    }

def run():
    LOG.parent.mkdir(parents=True, exist_ok=True)
    prev, last = cpu_times(), time.time()
    while True:
        time.sleep(INTERVAL)
        now = time.time()
        prev, rec = sample(prev, now - last); last = now
        with LOG.open("a") as f:
            f.write(json.dumps(rec) + "\n")

def report(hours):
    cutoff = time.time() - hours * 3600
    rows = []
    for l in LOG.read_text().splitlines():
        r = json.loads(l)
        if time.mktime(time.strptime(r["t"][:19], "%Y-%m-%dT%H:%M:%S")) >= cutoff and r.get("total_w") is not None:
            rows.append(r)
    if not rows:
        print("no samples"); return
    print(f"{len(rows)} samples, mean total {sum(r['total_w'] for r in rows)/len(rows):.2f} W, "
          f"heatpipe {sum(r['heatpipe_w'] for r in rows)/len(rows):.2f} W")
    by = defaultdict(list)
    for r in rows:
        for w in (r["windows"] or ["(none)"]):
            by[w].append(r["total_w"])
    print("mean total W while a window class is open:")
    for w, v in sorted(by.items(), key=lambda x: -sum(x[1]) / len(x[1])):
        print(f"  {sum(v)/len(v):6.2f} W  {w}  ({len(v)} samples)")
    cpu = defaultdict(list)
    for r in rows:
        for n, v in r["top_cpu"]:
            cpu[n].append(v)
    print("busiest processes (mean %CPU over the samples they topped):")
    for n, v in sorted(cpu.items(), key=lambda x: -sum(x[1]))[:8]:
        print(f"  {sum(v)/len(v):6.1f} %  {n}  ({len(v)} samples)")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "report":
        report(float(sys.argv[2]) if len(sys.argv) > 2 else 24)
    else:
        run()
