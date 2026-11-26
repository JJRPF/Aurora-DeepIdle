# Handoff: Gemini (`S2R-AGY`) → Claude (2026-11-25 21:08 EST)

## 1. Current State — Real Omarchy S2R Is Live & Verified!

The MacBook Pro 14" M2 Pro (`J414s` / `T6020`) is **currently booted into the real Omarchy desktop** on:
- **Kernel:** `7.3.0-s2r73+` (`51f46e71a30f`, branch `gh5/s2r-7.3` in `/home/jjr/Work/src/linux-aurora-73`, based on `omacom/linux-aurora` `integration/aurora-7.3` `8ca67c75ff52`)
- **Stage 2 / Aura:** `v0.1.0-77-g1b39fee5` (Aura image 128; `/home/jjr/Work/src/aura-img99` branch `gh5-img99-local`)
- **U-Boot:** `2026.07-g7a366a32dc83-dirty` (with `efi_platform_register()`)
- **OSFW:** standard macOS `13.5` (`iBoot-8422.141.2`); `asahi,iboot1-version: mBoot-20457.41.3`
- **Sleep mode:** `/sys/power/mem_sleep` = `s2idle [deep]`, `/etc/systemd/sleep.conf.d/10-deep-s2r.conf` (`MemorySleepMode=deep`), all 10 CPUs online (`0-9`).
- **Live Omarchy S2R ALREADY VERIFIED by owner:** A real `systemctl suspend` in Hyprland slept for **`SLP_S2R = 997.8 s` (16 min 38 s)** (`SYS_S2R_AOP = 997.8 s`) and woke cleanly with Hyprland, GPU rendering, display/backlight, Wi-Fi, BT, SD, NVMe, USB, PMP, and SEP all working and **zero errors**!

### Installed System Files for Real Omarchy S2R
- Kernel modules: `/usr/lib/modules/7.3.0-s2r73+` (stripped, `depmod` run)
- UKI: `/boot/efi/EFI/Linux/omarchy_linux-aurora-s2r.efi` (includes `cryptsetup-keys.d/root.key`, `aop.sleep_ap_idle=3 mem_sleep_default=deep`)
- Limine entry: `/OmarchyS2R` added to `/boot/efi/limine.conf` (stock `/+Omarchy -> //linux-aurora` `7.3.0-1-1-ARCH` untouched; backups at `/boot/efi/limine.conf.bak-r62y` and `/boot/efi/m1n1/boot-stock.bin.bak-r62y`)
- Prep service & sleep hook:
  - `/usr/local/sbin/s2r-t6020-prep.sh` (applies T6020 SIO `axi2af` `0x39a000000` tunables + disables USB-C `power/wakeup`, gated on `grep -qw deep /sys/power/mem_sleep`)
  - `/etc/systemd/system/s2r-t6020-prep.service` (enabled)
  - `/usr/lib/systemd/system-sleep/90-t6020-s2r` (re-runs prep on `pre` so multi-cycle S2R keeps SIO tunables & USB-C wakeup disabled)
  - `/usr/local/sbin/mmio-read`, `/usr/local/sbin/mmio-write`, `/usr/local/sbin/pmgrcnt`
- Overnight drain tool: `/usr/local/bin/s2r-overnight` (`sudo s2r-overnight start` before bed on battery, `sudo s2r-overnight report` in the morning)

---

## 2. Progress Since Previous Handoff (R62Q → Live Omarchy S2R)

All kernel commits are on `/home/jjr/Work/src/linux-aurora-73` branch `gh5/s2r-7.3` (diff already synced to `patches/s2r-repro/kernel-on-omacom-linux-aurora-7.3-8ca67c75ff52.diff`, pushed to `origin/main` at `eacbc56`, and reported on `JJRPF/Aurora-DeepIdle#5`):

1. **PMP, SEP, and Speaker Audio S2R (`dd487bc2eef1`, R62Q):**
   - `drivers/soc/apple/pmp.rs`: Added `HW_CFG_T6020` with `sram_backup: Some((0, 0x100000))`. `apple_pmp` wakes cleanly with zero `-62`.
   - `drivers/iommu/apple-dart.c`: `apple_dart_sleep_prepare()` saves DART state + `sleep_enable[]` even when `!dart->sleep_restore.count`. `apple_sep` wakes cleanly (`the enclave is back from its sleep request`), zero `NO TTBR FOR IOVA`.
   - `drivers/clk/clk-apple-nco.c`, `sound/soc/apple/mca.c`, `sound/soc/codecs/tas2764.c`: Ported `@nekolyanich`'s NCO/MCA/TAS2764 speaker S2R fixes (compiled & installed in `/usr/lib/modules/7.3.0-s2r73+`, ready to test once Aura 129 boots).
2. **SD Card & Bluetooth (`74f09d2d9e82`, R62S):**
   - `drivers/pci/controller/pcie-apple.c`: Added `apple_pcie_s2r_t602x_dart_tunables()` restoring the 6 T6020 DART tunables (`0x20c, 0x220, 0x224, 0x300, 0x308, 0x310`) on `dart-apcie0` and `dart-apcie1` before `pci_rescan_bus()`. SD card (`mmcblk0p1`, 58.6 GiB vfat) detects at `t=1s` and reads at `6.6–7.1 MB/s` direct.
   - Bluetooth (`hci0`): `btmgmt le on` + `power on` + `find` discovers 40 LE devices cleanly.
3. **Internal Display + Backlight Warm Restart (`511574238dd8`, `23f977b2100d`, `2674de3f362e`, R62W):**
   - Replaced cold restart (`dcp-fw.macho`) with **warm restart** in `drivers/gpu/drm/apple/dcp.c` (`A500` + `oslog_echo` + `apple_rtkit_idle` + `mailbox_off` + stop CPU on suspend; `disp0` power cycle with DART save/restore + `apple_rtkit_warm_restart` + `boot` on resume).
   - Warm restart takes **`0.9 ms`**, `dcp_poweron` takes **`27 ms`**, backlight (`apple-panel-bl`) ramps `20% → 100% → 60%` (visually confirmed by owner in R62Y-4). **No `dcp-fw.macho` needed anymore!**
4. **G14S GPU Warm Restart (`3492c1bb1298`, R62X):**
   - Pure-Rust `AscControl` + `Gpu::sleep_prepare()` (`rtk.idle()`) + `Gpu::sleep_complete()` (`rtk.warm_restart()` + `asc.start_cpu()` + `rtk.boot()` + `kick_firmware()`) in `drivers/gpu/drm/asahi/{regs,gpu,driver}.rs`.
   - `aurora 406400000.gpu` stays bound across S2R and warm-restarts in **`0.33 ms` (`kick Ok(())`)**; live Hyprland GPU rendering after S2R verified by owner.
5. **100% Zero-Unbind PCIe S2R (`51f46e71a30f`, R62Y-3 / R62Y-4):**
   - Added `apple_pcie_s2r_pre_freeze()` / `apple_pcie_s2r_post_thaw()` in `kernel/power/suspend.c` + `drivers/pci/controller/pcie-apple.c` so `pcie-apple` unbinds its 3 endpoints right after `PM_SUSPEND_PREPARE` (avoiding `hci_unregister_dev()`'s `pm_chain_head.rwsem` self-deadlock) and before `suspend_freeze_processes()`, with `apple_pcie_s2r_work()` rescanning them on wake.
   - Plain `echo mem > /sys/power/state` and `systemctl suspend` work with **zero** userspace unbinds.
6. **Aura 129 Built & Staged for Speakers (`1380c904` in `/home/jjr/Work/src/aura-img99`):**
   - On Aura 128, `snd-soc-macaudio` disabled internal speakers (`the boot loader passed no amp levels, disabling speakers`) because Aura 128 was based on an older `omacom/m1n1` (`bf6a6417`).
   - Strictly following **Aurora Speaker Safety rules** (never bypass/forge amp limits!), ported upstream `kboot_audio_amp_config()` from `origin/main` commit `9c083921` (`src/kboot_audio.{c,h}`, wired into `Makefile` and `src/kboot.c`) to pass the Mac's real ADT `bop-config`, `amp-dcblocker-config`, `speaker-config`, and `amp-tx-zd-config` byte-for-byte.
   - Built with `make -j8 -o build/librust.a` (existing `build/librust.a` reused because `rustup` isn't in PATH), assembled `/home/jjr/Work/psci-test/boot-test.bin.129-73`, and **already staged** to `/boot/efi/m1n1/boot-test.bin` (`eed3f571f38b6f84`). **Not yet booted!**

---

## 3. Lichen Multi-Agent Coordination

- **Agent:** `S2R-AGY` (`agt_r9tc7gmyiuuq`), token in `~/.lichen/token.json` (mode 600 — **never print!**).
- **Room:** `#Coordination` (`r_fmxa7rfvhpjy`), owner `github:jjrpf`.
- **Correct API endpoints (use `curl`, not Python `urllib` which hits Cloudflare 403):**
  - Read inbox: `GET https://lichen.jjrpf.com/api/inbox`
  - Ack inbox: `POST https://lichen.jjrpf.com/api/ack` with `{"cursor":"<cursor>"}`
  - Send message: `POST https://lichen.jjrpf.com/api/send` with `{"room":"r_fmxa7rfvhpjy","body":"...","reply_requested":false}` (NOTE: `/api/rooms/.../messages` returns `not_found`!)
  - React: `POST https://lichen.jjrpf.com/api/react` with `{"message_id":"...","emoji":"👍"}`
  - WebSocket listener: `node /home/jjr/.gemini/antigravity-cli/brain/eb6969fe-cb69-4970-b40a-c9b0fdc4d2a9/scratch/lichen-wait.mjs`
- **Important note:** Owner mentioned there may be a small issue with Lichen, so also send critical test/reboot instructions via `agent-notify send --phone-only -m "..."`.
- **Status blurb API:** `source ~/.bashrc 2>/dev/null; curl -sS -X PUT -H "Authorization: Bearer $S2R_STATUS_TOKEN" --data "<msg>" https://jjrpf.com/api/s2r-message` (raw `--data`, never print `$S2R_STATUS_TOKEN`).
- **Priority & etiquette:** `S2R-AGY` holds full priority (reboots allowed without waiting for `👍`). Move routine "back on main" notices to a new thread rather than spamming `#Coordination`. Message `@gpu-agy` in `#Coordination` when S2R work finishes or pauses.

---

## 4. Immediate Next Steps

1. **Boot Aura 129 & Verify Speakers Before + After S2R:**
   - `/boot/efi/m1n1/boot-test.bin` is **already staged** with Aura 129 (`eed3f571f38b6f84`).
   - **Gotcha:** Under patched U-Boot (`2026.07-g7a366a32dc83-dirty`), `efivarfs` is read-only (`bootctl set-oneshot` fails with `Read-only file system`). To boot `/OmarchyS2R` with Aura 129:
     - Move `/OmarchyS2R` to entry 1 in `/boot/efi/limine.conf` (`default_entry: 1`, `timeout: 3`, keeping `/+Omarchy -> //linux-aurora` right below it as fallback).
     - Run `sudo bash harness/usbtest/bootbin.sh flag set` (`PMU flag = a5`), send `agent-notify`, and `sudo systemctl reboot`.
   - After boot, verify `dmesg | grep -iE 'macaudio|tas2764|amp'` shows speakers enabled cleanly with real ADT `apple,speaker-config` levels (no `no amp level` error), `wpctl status` shows the MacBook speakers sink, and test audio playback **before and after** a live `systemctl suspend`!
   - If Aura 129 works cleanly, update `patches/s2r-repro/aura-on-omacom-m1n1-bf6a6417.diff` from `/home/jjr/Work/src/aura-img99` (`git diff bf6a6417..HEAD`) and push to `origin/main`.
2. **Overnight Battery Drain Test Inside Real Omarchy:**
   - Owner runs `sudo s2r-overnight start` on battery before bed, closes lid overnight, and runs `sudo s2r-overnight report` in the morning.
   - Record true mW/W S2R drain in `docs/worklog.md`, `docs/s2r-status.json`, and `JJRPF/Aurora-DeepIdle#5`.
3. **Make Persistent Default & Final Cleanup (when owner confirms):**
   - Once speakers + overnight drain are verified, confirm with owner whether to make Aura 129 persistent in `boot.bin` (keep `boot-stock.bin.bak-r62y` safe).
   - Clean up 4 minor compiler warnings in `linux-aurora-73`: missing prototypes for `apple_pcie_s2r_pre_freeze`/`apple_pcie_s2r_post_thaw`, unused `dcp_fw_s2r_afk_stop` in `dcp.c`, unused `Resources::start_cpu` in `regs.rs`.
   - Remove gitignored `apple/dcp-fw.macho` copies (no longer needed thanks to warm DCP restart), clean up old `deeptest.efi.*` backups if desired, and prepare upstream PRs (with owner review before posting outside `JJRPF/Aurora-DeepIdle`).
   - Remember: when unattended test work is over, remind owner to run `sudo bash harness/usbtest/luks-autounlock.sh remove` so the LUKS keyfile is removed from the ESP UKIs.
