# Reproducing our S2R on the M2 Pro (J414s, T6020)

This is how we get a real suspend-to-RAM (SLP_S2R power cut, RTC alarm wake through RVBAR) back to userspace on a 14-inch M2 Pro. It is written for anyone who wants to try it on their own machine.

**Read this first**

- It has only ever run on one J414s (T6020). Many register addresses in the Aura and kernel changes are T6020-specific. On another SoC (M1 or M2, T8103/T8112/T600x) most of them will be wrong. Treat those parts as a map of *what* has to happen, not *where*.
- Everything here is test code with test parameters, not something to run as a daily kernel.
- **Our tests never run the full desktop install.** Each test boots a minimal Linux: the test kernel plus a small initramfs that runs the job, from a squashfs image kept on the normal install's /boot. That /boot partition is only read, with the block device set read-only as a guard; it is made writable only briefly after the wake, to save the logs, then unmounted. The root and home filesystems are never mounted. This is for filesystem safety: a failed wake or a reset mid-sleep can't leave a mounted root or home filesystem half-written. So "back to userspace" here means the initramfs userspace, not a full desktop session, and suspend with a full desktop (GPU, display, all drivers loaded) is untested.
- We keep the normal boot untouched. The test chain is only used for one boot, through a one-shot flag; any crash, watchdog or reset lands back on the normal install.

## What works and what doesn't

Works, in every run since R57AL (2026-11-20):
- The real S2R sleep and the RTC alarm wake, back to userspace with all 10 CPUs online. `echo mem` returns 0.
- NVMe, USB, the SMC, RTC, SEP and PMP come back.

Works since 2026-11-25 (`7.3.0-s2r73+` + Aura 128, R62Q–R62Y-4, **zero userspace unbinds**):
- **Plain `echo mem > /sys/power/state`**: `pcie-apple` unbinds its 3 endpoints pre-freeze and rescans them on wake (`apple_pcie_s2r_pre_freeze` + `apple_pcie_s2r_work`).
- **Internal display + backlight** (R62W–R62Y-4, visually confirmed): warm DCP restart (`A500` + `rtkit_idle` + `disp0` power cycle with DART save/restore + `rtkit_warm_restart` + `boot`) in 0.9 ms — **no `dcp-fw.macho` needed**. Backlight (`apple-panel-bl`) ramps cleanly (`20% -> 100% -> 60%`).
- **G14S GPU (`aurora 406400000.gpu`)** (R62X–R62Y-4): kept bound across sleep, idled on suspend, warm-restarted on wake (`kick Ok(())`).
- **SD card (`mmcblk0p1`)**: T6020 `dart-apcie0/1` tunables restored; detects at `t=1s` and reads at `6.6–7.1 MB/s` direct.
- **Bluetooth (`hci0`)**: `btmgmt le on` + `power on` + `find` discovers 40 LE devices cleanly.
- **PMP & SEP**: T6020 PMP 1 MiB SRAM backup + SEP DART save/restore; both wake cleanly with zero errors.
- **Speaker audio (`clk-apple-nco`, `mca`, `tas2764`)**: S2R fixes ported and compiled (pending live desktop playback test).

Not tested yet: live desktop GPU rendering & speaker playback, external displays (`dcpext`), and overnight battery drain inside real Omarchy.

## The pieces

| Piece | Source | Our change |
|---|---|---|
| Kernel (7.3.0 clean non-TEST, R62P) | `omacom/linux-aurora` `integration/aurora-7.3` at `8ca67c75ff52` | `patches/s2r-repro/kernel-on-omacom-linux-aurora-7.3-8ca67c75ff52.diff`, config `patches/s2r-repro/kernel-7.3.config` |
| Kernel (7.2.11 historical, R61P–R61R) | `omacom/linux-aurora` at `49a8c150d6be` | `patches/s2r-repro/kernel-on-omacom-linux-aurora-49a8c150d6be.diff` (51 files), config `patches/s2r-repro/kernel.config` |
| Aura (image 128: bit 20 dropped, default `0xc16dcb3f` / `241`, no `aura-ctl` needed) | `omacom/m1n1` at `bf6a6417` | `patches/s2r-repro/aura-on-omacom-m1n1-bf6a6417.diff` (`src/psci.c`, `src/smp.c`, `src/qs_macos_*.h`) |
| Test boot harness | this repo, `harness/usbtest/` | `bootbin.sh`, `arm.sh`, `build-uki.sh`, the jobs |
| A test job | `harness/usbtest/jobs/r62p-s2r73/job.sh` | clean 7.3.0 S2R run (no `aura-ctl` or `TEST` switches), logging and post-wake checks |

The boot chain on a test boot: m1n1 stage 1 → Aura (image 124/125) → U-Boot → a UKI with the test kernel and a small initramfs that runs the job.

## Build

Kernel (we build with an older LLVM toolchain; a current one should work too):

```
git clone https://github.com/omacom/linux-aurora && cd linux-aurora
git checkout 49a8c150d6be
git apply /path/to/kernel-on-omacom-linux-aurora-49a8c150d6be.diff
cp /path/to/kernel.config .config
make LLVM=1 -j8 Image modules
make LLVM=1 INSTALL_MOD_PATH=<modroot> modules_install
```

Aura:

```
git clone https://github.com/omacom/m1n1 aura && cd aura
git checkout bf6a6417
git apply /path/to/aura-on-omacom-m1n1-bf6a6417.diff
RUSTC_BOOTSTRAP=1 make BUILDSTD=1 RELEASE=1 LD=ld.lld
```

Then put the new `build/aura.bin` into a copy of your boot image (`tools/swapimg.py <old boot.bin> build/aura.bin <new boot.bin>`), and the UKI:

```
sudo EXTRA_MODULES="apple-pmp macsmc macsmc-reboot i2c-pasemi-platform" MODROOT=<modroot> \
  bash harness/usbtest/build-uki.sh arch/arm64/boot/Image <kernel release> deeptest.efi \
  aop.sleep_ap_idle=3 reserve_mem=1M:2M:oops nvme_apple.iorvbar_phys=0x347050000 pcie_apple.s2r_pwren_off_ms=0
```

## One test run

```
sudo bash harness/usbtest/bootbin.sh test <new boot.bin>      # stage the test chain (used only when the flag is set)
sudo bash harness/usbtest/arm.sh --chain --job harness/usbtest/jobs/r60j-nostage --label TEST
```

`arm.sh` sets the one-shot flag (PMU scratch `0x6010` = `0xa5`) and reboots. The job then, in order:

1. Sets the sleep parameters:
   - `macsmc_reboot.deep_steps=183`, `macsmc_reboot.s2r_pmvc=0x100`;
   - `macsmc.pmp_sleep=1`, `macsmc.pmp_cycle=1`;
   - `apple_wdt.suspend_timeout=120`;
   - `pmp_report.test_release_aon=1`, `test_release_ids=0x1000`, `test_pcpm=0x300`;
   - `pmgr_pwrstate.test_sleep_keep=afr,gpio`;
   - `dwc3_apple.test_deep_teardown=1`, `appledrm.test_sleep_off=1`.
2. Puts the SEP to sleep (a freezer pass, then the SLEEP message).
3. Tells Aura which entry steps to use: `aura-ctl 0xc16dcb3f 0 0 0 241` (bit 20 off; see above).
4. Sets an RTC alarm 30 s ahead (`/sys/class/rtc/rtc0/wakealarm`), then `echo mem > /sys/power/state`.
5. After the wake, logs `dmesg`, `lspci -vv`, the PCIe registers, the SMC keys and the PMU registers. It writes them to `/boot/deeptest/postwake/<date>-<run>/` on the normal install's /boot, then reboots back to it.

A run takes about 8 to 10 minutes from arm to being back on the normal install.

## What to look for after the wake

- `PM: suspend exit` in `dmesg` and `echo mem` rc 0: the wake worked.
- `pcie-apple ... lost its link in suspend (... link 0xab000200)` followed by `link up after resume` and `rescanning after the S2R power cut: 2 devices`: Wi-Fi/BT and the SD reader are back. `link 0xa9000200` and `link still down after resume` mean the PCIe domains were powered off at the commit.
- `TEST s2r: ... MEPS` lines from `macsmc-reboot`: the SMC's power state at `waka` and after.

If you try this on your machine, we would like to hear how it went (SoC, firmware, kernel, which steps you used). Issue: https://github.com/JJRPF/Aurora-DeepIdle/issues/5

## Credits

This builds on work by Andreas Fernandez (Ante042), DJ (DjDeveloperr), Naeem Malik (malik-na), nekolyanich, František Balázsy, muness, the aurora-silicon authors and Asahi Linux. The full list, with what each contributed, is in the README.
