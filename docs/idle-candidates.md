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

## Results on 7.2.11 (2026-11-02)

Kernel: the packaged `linux-aurora 7.2.11.aurora14`, now the default. The
stock 7.2.11 boot has none of the three proven changes (PMP disabled, CPU PD
residency 10 ms, no CPU energy model), so the "5.38 W" baseline of the issue
is not what a plain boot gives. Each test image was one boot, headless (screen
off, power-saver, as every boot here is), 180 s settle, then 16 windows of 30 s
(`harness/gh10/measure.sh`, `data/idle_erikwb/boot-*`). Means with standard
error over the windows; the difference is against `stock2`, a plain-stock boot
in the same state. An image differs from stock only by the m1n1 DT-headroom fix
plus the DTB named.

| Boot | Total | SoC (Heatpipe) | Total vs stock2 | SoC vs stock2 |
|---|---|---|---|---|
| stock2 (plain stock) | 3.485 +- 0.012 | 1.990 +- 0.020 | | |
| em (energy model) | 3.307 +- 0.006 | 1.953 +- 0.022 | -0.178 +- 0.013 W | -0.037 +- 0.030 W (not significant) |
| pmp | 2.566 +- 0.007 | 1.341 +- 0.014 | **-0.919 +- 0.014 W** | -0.649 +- 0.024 W |
| pmp + em | 2.378 +- 0.004 | 1.159 +- 0.007 | **-1.107 +- 0.013 W** | -0.831 +- 0.021 W |

* `stock1` (7.35 W / 2.37 W) was taken with the screen on and is not
  comparable; it is kept only as a record.
* These are across-boot comparisons, one boot per image, so they carry
  boot-to-boot drift the standard errors do not show. The PMP result matches
  the earlier campaign (0.9 to 1.15 W). EM saves 0.18 W of system power here
  but the SoC sensor shows nothing significant, against 61 mW measured paired
  earlier: treat EM as 0.06 to 0.18 W.
* CPU PD "always" (runtime, no reboot): **-0.54 W of system power, lower in 10
  of 10 paired rounds** (`ab-7.2.11-pd.txt`, screen on, 20 s windows). Installed
  now through `/etc/tmpfiles.d/cpuidle-pd-always.conf`. It was not re-measured
  on top of the PMP.
* With the PMP running, genpd shows `pmp-disp0`, `pmp-dispext0/1`,
  `pmp-isp-sys` and `isp_sys` on; the rest is unchanged. The PMP drives the
  memory/fabric/DCS floor itself, which is the #582 technique's target on the
  J713, so on T6020 that candidate is covered by booting the PMP.

Sum against a plain stock 7.2.11 boot, headless: **PMP + EM -1.1 W, plus PD
always about -0.5 W**, about 1.6 W of about 3.5 W, or of the 7.35 W screen-on
desktop about 22%. The PMP and EM are staged, not adopted (below).

## What is not done, and why

* **Idle USB-C ports (#528).** 7.2.11's `dwc3-apple` has runtime PM, but the
  ATC PHY (`phy-apple-atc`) does not, so `atc*_usb` stays on. #528's PHY change
  is for PHYs without DisplayPort (`idle_power_off`); the J414s ports carry
  DisplayPort and Thunderbolt, which I cannot test here (no dock or display),
  and the estimate is 90 to 130 mW. Not ported.
* **GPU/DCS floor (#582, #455).** The PMP boot covers the floor; the GPU still
  has no runtime PM. Needs a code change in the asahi driver, not measured.
* **cd321x runtime PM (#833).** The 3.8 V rail reads 0 on the SMC, so the
  saving cannot be measured here. Not started.
* **HDMI rails.** 0.13 W measured earlier, but lowering them while awake would
  break HDMI hot-plug unless HPD works with the converter off; untestable here.
* **Display pipe while blanked (#830).** Blocked on DCP resume (GH-8).
* **Hot-plug after a domain was off:** banned (FS damage); nothing adopted turns a domain off at runtime.

## Installed and tested (2026-11-02/03)

PMP + energy model are the default boot now (owner order, 2026-11-02): `/etc/default/update-m1n1`
sources `harness/gh10/update-m1n1.pmp-em.sh`, which uses `/usr/local/lib/gh10/m1n1-pmpfix.bin` and
`t6020-j414s-pmp-em.dtb` while `linux-aurora` is still 7.2.11.aurora14-1 (`/usr/local/lib/gh10/PKGVER`).
After a kernel update the stock DTBs go in instead and a line lands in `/var/log/gh10-pmp-em.log`;
the DTB must then be rebuilt from the new source (`patches/upstream/0001`, `0002`) and PKGVER bumped.
Backups: `/var/lib/gh10/boot.bin.stock*`, original config `/var/lib/gh10/update-m1n1.default.orig`.

| Check (installed default, headless) | Result |
|---|---|
| Boot | PMP firmware ready, `pmp-*` domains, energy model on 3 clusters, state0 disabled on 10 CPUs |
| Idle power, 16 x 30 s | 2.39 W total, 1.16 W SoC (stock2 control 3.485 / 1.99) |
| 1 h soak, 120 x 30 s | 2.36 W / 1.13 W, 0 of 3695 pings lost, no new dmesg errors, genpd unchanged |
| Regression | Wi-Fi, Bluetooth, audio sinks, backlight, battery, NVMe, USB, typec, Hyprland: ok |
| dmesg vs stock | only `pmp-isp-sys will not be powered off` and transient deferred-probe lines at 13.8 s (all devices probe; `devices_deferred` empty) |
| Wake latency p50 | PD-always timer 25/20 us, ipi 18/22 us; default 7.7/7.5, 8.3/14.2 (same as before the PMP) |
| Paired on PMP+EM, 12 x 20 s | pd-always -0.015 W (n.s.); wfi-only +0.862 W; no-eas +0.230 W |

Consequences: PD-always no longer matters with the PMP (default is already 79% PD); I left it
installed because it is worth 0.54 W if the stock DTB fallback ever applies, at +17 us wake latency.
The energy model is worth 0.23 W at idle (EAS off costs it back). Total gain against a plain 7.2.11
boot, headless: about 1.1 W (PMP 0.92 + EM 0.19) = 3.485 -> 2.39 W; PD-always is the 0.54 W of that
only on a boot without the PMP. Against the issue's 5.38 W baseline the comparison is not like for
like (that figure was a screen-on battery desktop), so the target is met in the sense that all three
proven changes are on and measured, not as a number.

Found on the way: `aurora-fand.service` (not package-owned) crash-loops every 5 s since boot
(status 226/NAMESPACE, `/run/aurora-fand` missing, restart counter 863 after 72 min). It costs no
power (2.36 W with it stopped vs 2.36 W looping) but the fan daemon is not running. Not changed.

## Staged, needs the owner

* `patches/upstream/` (README.md has the PR texts and numbers): energy model dtsi, PMP J414s dts,
  m1n1 fit check, PD-always tmpfiles. Nothing opened, pushed or commented upstream; posting needs
  the owner's OK.
* Not attempted (need driver work or hardware I cannot test): ATC PHY runtime PM (#528), GPU
  runtime PM (asahi driver reports runtime_status unsupported), ANE (no firmware, no driver bound),
  cd321x (#833), HDMI rails, blanked display (#830).
