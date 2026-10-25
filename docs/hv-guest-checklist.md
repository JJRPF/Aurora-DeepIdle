# macOSTest (macOS 14.8.9) hypervisor guest: the owner's checklist

Everything that can be done from Linux was done (worklog 2026-10-24, GH-8). What is left needs macOS or recoveryOS. Times are estimates; a download depends on the line.

**Version change:** Apple's catalog no longer offers 14.8.3 (checked 2026-10-24: Sonoma is 14.8.7, 14.8.8 and 14.8.9 only; no Sonoma IPSW is on Apple's feed). The guest is **14.8.9** (build 23J631, same XNU line, no SPTM). It has never run under m1n1's hypervisor; if the guest misbehaves, the version is the first suspect.

| # | Where | What | Time |
|---|---|---|---|
| 0 | Linux (me) | `asahi-bless --next --set-boot <macOS volume>` and reboot, if you want to skip the boot picker. Your go first. | 2 min |
| 1 | everyday macOS | Terminal: `curl -fsSL https://raw.githubusercontent.com/JJRPF/Aurora-DeepIdle/main/tools/macos-hv-testvol.sh \| bash` (needs the PR branch pushed). It downloads the 13.7 GB `InstallAssistant.pkg` from Apple's catalog (size and SHA-1 checked), installs "Install macOS Sonoma.app", adds the empty `macOSTest` volume (asks `yes`), opens the installer. | 20 to 60 min, mostly download |
| 2 | installer | Continue, agree, choose **macOSTest** (Show All Disks). Never Macintosh HD. It restarts itself and installs. | ~30 min |
| 3 | Setup Assistant | Local admin account (any name), no Apple Account, **FileVault off**, skip Location, Analytics, Screen Time, Siri. | 5 min |
| 4 | new macOS 14.8.9 | Terminal: `curl -fsSL .../tools/macos-hv-testvol.sh \| bash -s -- setup`. Turns off automatic updates, installs the sleep job, collects data, copies it to the Pi (asks for the Pi's ssh login). | 5 min |
| 5 | startup disk | Keep macOSTest as the startup disk. Shut down, hold the power key, choose Options (macOSTest's own recoveryOS). | 2 min |
| 6 | recoveryOS | Terminal: run the recovery script from the Pi (`hv-testvol-recovery.sh`, served on the LAN; the Pi gives the URL). It checks the volume is macOSTest 14.8.9 and paired, then does `bputil -nkcas`, `csrutil disable`, `kmutil configure-boot` with Aura. Authentication prompts for the admin password. | 5 to 10 min |
| 7 | recoveryOS | Startup Disk: set the Linux volume (omarchy) back as default. Reboot into Linux. | 2 min |
| 8 | cable | USB-A from the Pi to the Mac's DFU port (the port in `docs/pi-handoff.md`). | 1 min |

Then the guest run (my part): `harness/hv/bless.sh next macOSTest` and a reboot, `harness/remote/hv-run.sh` on the Pi. That boots the Mac into Aura and needs your explicit go and the Pi watcher on.

Undo: `macos-hv-prep.sh remove` removes the sleep job. The volume can be deleted in Disk Utility from the everyday macOS.
