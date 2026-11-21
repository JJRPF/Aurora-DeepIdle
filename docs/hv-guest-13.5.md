# macOS 13.5 hypervisor guest (macOS135): the owner's checklist

Why: DJ's advice (2026-11-21) is to trace what macOS does on the M2 Pro under the m1n1 hypervisor with macOS 13.5, the guest Asahi's m1n1-hypervisor guide pins for M1/M2. Our 14.8.9 guest (macOSTest) only boots with PCIe turned off, so we have never seen macOS power the Wi-Fi and SD slots. With 13.5 and PCIe on, the trace should show it.

macOSTest (14.8.9) stays as it is. 13.5 goes on a new volume, **macOS135**, in the same APFS container (about 30 GB of free space used). Macintosh HD and Linux are never touched.

## The installer

- macOS 13.5 (22G74) `InstallAssistant.pkg`, 11,934,300,398 bytes, SHA-1 `9ceeac3a75aaf3d6e477990caaf2c695f31624e2`.
- Apple took 13.5 off its CDN (the old swcdn links return 403), so it comes from archive.org (`install-assistant_20240930`). On Linux I checked the size and SHA-1 against archive.org's metadata, and that the package is signed by Apple (the xar signature chains to Apple Root CA). The script below checks the size, SHA-1 and Apple signature again on the Mac before installing.
- Linux copy: `~/Work/macos-installers/13.5-22G74/InstallAssistant.pkg` (downloaded and fully checked 2026-11-21: SHA-1, Apple signature, every stored file against the signed TOC).
- Fallback: macOS 13.7.8 (22H730), straight from Apple, in `~/Work/macos-installers/13.7.8-22H730/`. nekolyanich runs 13.7.8 under their hypervisor and it sleeps and wakes there.

## Steps

| # | Where | What | Time |
|---|---|---|---|
| 1 | Linux | Plug in a USB drive (16 GB or more) formatted exFAT and copy the pkg onto it, or tell me the drive is in and I copy it. | 10 min |
| 2 | everyday macOS | Plug the drive in. Terminal: `curl -fsSL https://raw.githubusercontent.com/JJRPF/Aurora-DeepIdle/main/tools/macos-hv-testvol.sh \| HV_GUEST=13.5 HV_PKG=/Volumes/<drive>/InstallAssistant.pkg bash`. It checks the pkg (size, SHA-1, Apple signature), installs "Install macOS Ventura.app", adds the empty **macOS135** volume (asks `yes`), opens the installer. | 10 to 15 min |
| 3 | installer | Continue, agree, choose **macOS135** (Show All Disks). Never Macintosh HD or macOSTest. It restarts and installs. | ~30 min |
| 4 | Setup Assistant | Local admin account (any name), no Apple Account, **FileVault off**, skip Location, Analytics, Screen Time, Siri. | 5 min |
| 5 | new macOS 13.5 | Terminal: `curl -fsSL .../tools/macos-hv-testvol.sh \| HV_GUEST=13.5 bash -s -- setup`. Turns off automatic updates (the guest must stay 13.5), installs the sleep job, copies its data to the Pi. | 5 min |
| 6 | startup disk | Keep macOS135 as the startup disk. Shut down, hold the power key, choose Options (macOS135's own recoveryOS). | 2 min |
| 7 | recoveryOS | Terminal: `curl -fsSL http://<pi>:8000/hv-135-recovery.sh \| sh -s -- http://<pi>:8000/aura.bin` (I start the Pi's file server and give you the exact address). It checks the volume is macOS135 with 13.5 and paired, then `bputil -nkcas`, `csrutil disable`, `kmutil configure-boot` with Aura (the same aura.bin as macOSTest, sha256 c7509ccf...). Each step asks for the macOS135 admin password. | 5 to 10 min |
| 8 | recoveryOS | Startup Disk: set Linux (omarchy) back as the default. Reboot into Linux. | 2 min |

**If the Ventura installer won't open in the everyday macOS** (newer macOS sometimes refuses older installers): make a bootable USB instead. Use a second drive, or erase this one after step 2 has installed the app:
`sudo /Applications/Install\ macOS\ Ventura.app/Contents/Resources/createinstallmedia --volume /Volumes/<drive>`. Then shut down, hold the power key, choose the installer drive, and install to macOS135. Create the volume first in Disk Utility, or step 2 has already added it.

## Then (my part)

- Read the 13.5 kernelcache from macOS135's Preboot on Linux (read-only, `tools/macos-preboot-read.sh`) and copy it to the Pi.
- Each run: `harness/hv/bless.sh next macOS135`, reboot, `hv-run.sh <kernelcache-13.5>` on the Pi with PCIe on (no `apcie=` mask), SMC and PMGR tracers. It needs your go and the Pi's cable in the DFU port, as before.
- First: does 13.5 boot under the hypervisor with PCIe on, and what does it write (SMC keys, PMU, PCIe) to bring the Wi-Fi and SD slots up? Then its sleep entry, and the wake if the sleep completes.

Undo: delete the macOS135 volume in Disk Utility from the everyday macOS.
