# Awake-idle candidates (GH-10)

Step 1 of issue #10: what is on at an idle desktop, ranked by what it could
save. This is a first, unprivileged pass (2026-11-02, kernel
`7.1.12-2-11.35-sep-ARCH+`, on AC, load average 0.3). Nothing was changed.
Watts are guesses until the privileged dumps below exist; no A/B has run yet.

## genpd at idle (root, 2026-11-02)

`data/idle_erikwb/genpd-idle-screenon.txt` and `genpd-idle-blanked.txt`:
`pm_genpd_summary` with the screen on, then DPMS-off for 25 s. **The two are
identical: blanking the screen powers no domain down.** 116 domains are on,
84 off. Only `port0` has a partner (the charger); the other ports are empty.

Off already: all of `ispsens*`/`isp_*`, `venc_*`, `prores`, `jpg`, `avd_sys`,
`ane_set1..4`/`ane_base`/`ane_td`/`ane_sys_mpm`, `atc*_cio*`, `mca0/1/3`,
`uart*`, `spi0-5`, `i2c4-8`, `dpa*`, `pmp-*`.

On, with devices that cannot runtime-suspend (`unsupported`), grouped:

| Domains (on) | Held on by | Candidate |
|---|---|---|
| `gfx`, `gpx` (+ `afr`) | `406400000.gpu` (asahi), no runtime PM | GPU idle (#455, #582) |
| `atc0..2_usb` (+ `atc3_usb`), `atc0..3_common`, `*_usb_aon` | per port: PHY, mux, tunables `unsupported`; DARTs active | idle USB-C ports (#528) |
| `disp0_*`, `dispext0/1_*` | DCP `unsupported`, one device each | static display (#830); E4 found no gain from the externals |
| `ane_cpu`, `ane_sys` | two IOMMUs active (no ANE driver) | ANE: check |
| `apcie_*`, `ans2` | Wi-Fi, SD, NVMe in use | stay (PCIe is banned to touch) |
| `dcs_00..15`, `amcc0..3`, `afnc*`, `soc_dpe`, `pms*` | no devices: PMGR-owned fabric/DRAM | memory floor (#582): needs PMP/CLPC votes, not genpd |
| `i2c0..3`, `fpwm0`, `gpio`, `sep`, `nub_*` | one `unsupported` device each | small, probably not worth it |

## Measured earlier (no new work)

From `status.md`/`deep-idle-research.md`: HDMI and DP-to-HDMI rails off
saves **0.13 W** awake (12 of 12 rounds; SMC GPIOs `gP17`/`gP06`; patch
`patches/hdmi-rails-off-in-sleep.patch`, built, not booted). SD link L1
substates and the external DCPs: nothing. Removing the SD reader costs 0.37 W
and killed Wi-Fi (banned).

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

## Ranking

| # | Candidate | Estimate | Cost to port | Status |
|---|---|---|---|---|
| 1 | HDMI/DP-to-HDMI rails off while no cable | **0.13 W measured** | small (a GPIO policy); patch exists | needs the soak and a hot-plug check, then a patch |
| 2 | Idle USB-C ATC domains (#528) | 90 to 130 mW on J713 | large: our base has no runtime PM in `dwc3-apple` or the ATC PHY, so #528 needs the T8132 series' preconditions rebased | not started |
| 3 | GPU/DCS floor held only while busy (#582) | 0.2 to 0.4 W on J713 | large: the T6020 GPU has no runtime PM; needs CLPC/PMP votes read first | needs PMP register reads (root) |
| 4 | cd321x runtime PM (#833) | up to 0.2 W per controller on J713 | medium; the 3.3 V rail is not on the SMC list (reads 0) | measure first |
| 5 | Blanked display (#830) | unknown | blocked on DCP resume (GH-8) | defer |
| 6 | ANE `ane_cpu`/`ane_sys` | unknown | needs a driver or a PMGR hold | measure first |

Everything below #1 is a kernel change that needs a build of the base
(`~/Work/deepidle-11.35`) and a boot of it; each boot step needs the owner's
reboot, which was given on 2026-11-02.
