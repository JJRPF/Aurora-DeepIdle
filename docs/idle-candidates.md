# Awake-idle candidates (GH-10)

Step 1 of issue #10: what is on at an idle desktop, ranked by what it could
save. This is a first, unprivileged pass (2026-11-02, kernel
`7.1.12-2-11.35-sep-ARCH+`, on AC, load average 0.3). Nothing was changed.
Watts are guesses until the privileged dumps below exist; no A/B has run yet.

## Not yet inventoried (needs root, ask the owner)

* `/sys/kernel/debug/pm_genpd/pm_genpd_summary` (debugfs is root-only here):
  which PMGR domains are on, with their device lists.
* PMGR registers of every domain, DCS/fabric state, CLPC/PMP votes
  (harness tools, mmio, root).
* A blanked-screen pass, and a battery pass (this one ran on AC).
* Macos comparison per domain (`data/` from issue #3).

## What sysfs shows without root

Runtime-PM status over `/sys/devices`: 42 devices active, 30 suspended,
1056 `unsupported` (mostly no runtime PM at all).

Already suspended at idle: the ISP (`384000000.isp`, all 7 genpd links), AVD,
mca/audio, spi, serial, several mailboxes and IOMMUs. So #522 is already
done on T6020.

Runtime PM `unsupported` (the driver never lets the device sleep), which is
where the candidates are:

| Device | Driver | Candidate | Source PR |
|---|---|---|---|
| `406400000.gpu` | asahi | GPU idle state / DCS and fabric floor held only while it has work | #455, #582 |
| `289c00000.dcp`, `315c00000.dcp`, `389c00000.dcp` | apple-dcp | blanked and static display power; external DCPs (campaign E4 already tried) | #830, #501, #503 |
| `702280000.usb`, `b02280000.usb`, `f02280000.usb` (+ `*03000000.phy`) | dwc3-apple, atc PHY | idle ATCn_USB/ATCn_COMMON power-down | #528 |
| `0-0038`, `0-003a`, `0-003b`, `0-003f` | cd321x (tipd) | controller runtime PM, 1 s after last access | #833, #637 |
| `284000000.ane` | none bound | ANE domain: check it is off | none |
| `1-*`, `3-*` sn012776, `2-004b` cs42l84 | audio | amps and codec at idle | none |

SMC (`hwmon1`): Total System Power, AC Input Power, 3.8 V rail (reads 0),
Heatpipe Power (SoC package). The battery power node reads 0 on AC.
`tools/idle-ab.py` logs all SMC sensors, so it will measure each change.

## Ranking (guesses, to be replaced by measurements)

1. Memory/fabric floor held by the GPU (#582): 0.2 to 0.4 W on J713; unknown here.
2. USB-C ATC domains with nothing plugged in (#528): three ports, each with a
   USB and a common domain; status above is `unsupported`, so they are probably on.
3. cd321x runtime PM (#833): up to ~0.2 W per controller on J713's SN201202x; check
   the 3.3 V rail here, four controllers.
4. GPU idle state (#455).
5. Display pipe while blanked (#830): large but needs DCP resume, tied to GH-8.
6. ANE, ISP: ISP already suspended; ANE unknown.

## Next

Root dump of genpd and PMGR state at idle (screen on, then blanked), then
rank by measured watts and port one change at a time with `tools/idle-ab.py`.
