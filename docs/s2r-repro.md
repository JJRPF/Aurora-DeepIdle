# Reproducing our S2R on the M2 Pro (J414s, T6020)

This is how we get a real suspend-to-RAM (SLP_S2R power cut, RTC alarm wake through RVBAR) back to userspace on a 14-inch M2 Pro. It is written for anyone who wants to try it on their own machine.

**Read this first**

- It has only ever run on one J414s (T6020). Many register addresses in the Aura and kernel changes are T6020-specific. On another SoC (M1 or M2, T8103/T8112/T600x) most of them will be wrong. Treat those parts as a map of *what* has to happen, not *where*.
- Everything here is test code with test parameters, not something to run as a daily kernel.
- We keep the normal boot untouched. The test chain is only used for one boot, through a one-shot flag; any crash, watchdog or reset lands back on the normal install.

## What works and what doesn't

Works, in every run since R57AL (2026-11-20):
- The real S2R sleep and the RTC alarm wake, back to userspace with all 10 CPUs online. `echo mem` returns 0.
- NVMe, USB, the SMC, RTC, SEP and PMP come back.

Does not work:
- **Wi-Fi/BT (PCIe port 0) and the SD reader (port 1).** After the wake both links stay in Detect (LINKSTS `0xa9000200`/`0xa8000200`), and `lspci` shows "Unknown header type 7f". The root complex, ports and PHYs restore word for word. The SMC stays at MEPS `000102010004` (awake: `000400040001`), and a few PMU registers keep their sleep values (`0x2505` 0x20 → 0, `0x2705` 0x80 → 0). Everything we tried against this is in `docs/worklog.md` (R58 to R60L).

## The pieces

| Piece | Source | Our change |
|---|---|---|
| Kernel | `omacom/linux-aurora` at `49a8c150d6be` | `patches/s2r-repro/kernel-on-omacom-linux-aurora-49a8c150d6be.diff` (51 files), config `patches/s2r-repro/kernel.config` |
| Aura (m1n1 fork; the S2R entry and the RVBAR wake live in its PSCI code) | `omacom/m1n1` at `bf6a6417` | `patches/s2r-repro/aura-on-omacom-m1n1-bf6a6417.diff` (27 files; `src/psci.c`, `src/smp.c`, `src/qs_macos_*.h`) |
| Test boot harness | this repo, `harness/usbtest/` | `bootbin.sh`, `arm.sh`, `build-uki.sh`, the jobs |
| A test job | `harness/usbtest/jobs/r60j-nostage/job.sh` | the sleep, the logging and the post-wake checks |

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
3. Tells Aura which entry steps to use: `aura-ctl 0xc17dcb3f 0 0 0 241`.
4. Sets an RTC alarm 30 s ahead (`/sys/class/rtc/rtc0/wakealarm`), then `echo mem > /sys/power/state`.
5. After the wake, logs `dmesg`, `lspci -vv`, the PCIe registers, the SMC keys and the PMU registers. It writes them to `/boot/deeptest/postwake/<date>-<run>/` on the normal install's /boot, then reboots back to it.

A run takes about 8 to 10 minutes from arm to being back on the normal install.

## What to look for after the wake

- `PM: suspend exit` in `dmesg` and `echo mem` rc 0: the wake worked.
- `pcie-apple ... lost its link in suspend` and `link still down after resume`: the Wi-Fi/SD failure we are stuck on.
- `TEST s2r: ... MEPS` lines from `macsmc-reboot`: the SMC's power state at `waka` and after.

If Wi-Fi or the SD reader comes back on your machine, we would very much like to know what is different (SoC, firmware, kernel, which steps you used). Issue: https://github.com/JJRPF/Aurora-DeepIdle/issues/5

## Credits

This builds on work by Andreas Fernandez (Ante042), DJ (DjDeveloperr), Naeem Malik (malik-na), nekolyanich, František Balázsy, muness, the aurora-silicon authors and Asahi Linux. The full list, with what each contributed, is in the README.
