# Changes made to the owner's system for the S2R work (GH-5), and how to reverse them

Kept current as each change is made. Append-only: a reversed item stays listed, with the date it was undone.
Entries marked (earlier) come from the session history and `docs/worklog.md`; the log starts complete only from 2026-11-17.

## In place now

| Since | What | Where | Reverse with |
|---|---|---|---|
| earlier | One-shot loader installed as the Mac's `boot.bin` (the DeepTest chain; it chainloads `m1n1/boot-test.bin` once, then the Mac returns to main). A test image is staged as `boot-test.bin`. | the ESP's m1n1 dir (`bootbin.sh status` shows the digests) | `sudo bash harness/usbtest/bootbin.sh restore` (puts `boot-stock.bin` back). `update-m1n1` can silently replace `boot.bin`; re-run `tools/rebuild-loader.py` plus `bootbin.sh install` if so. |
| earlier | Post-boot hook that reopens a Claude session after a test reboot | `~/.config/omarchy/hooks/post-boot.d/deepidle-resume` (copy in `harness/usbtest/deepidle-resume`); armed by `~/.local/state/deepidle/resume` | delete `~/.local/state/deepidle/resume` to disarm, or delete the hook file to remove it |
| 2026-11-17 | The same hook now starts Claude with `--remote-control` | the same file, line 10 | remove ` --remote-control` from that line |
| earlier | Test kernel module `macsmc-reboot.ko` rebuilt with a TEST patch (`deep_steps` bit 128) and installed | `/usr/lib/modules/7.2.11-psci-efi+/` | the old module is `~/Work/psci-test/macsmc-reboot.ko.before-pmvc`; copy it back |
| earlier | Pi (core-node): hand-started upload server, `hv-run.sh` edits (backups `hv-run.sh.bak-before-*`), run dirs under `~/deepidle/hv/` | Pi `~jjrpfister/deepidle` | kill the server; restore the backups; `rm` the run dirs when no longer wanted |
| 2026-11-17 | `mmio-write` allow-list gained the SIO axi2af window `0x39a000000` (+0xc00) | `harness/mmio/mmio-write.c`, a copy inside a job dir | repo only; revert the commit |
| 2026-11-18 | (undone 2026-11-19) Post-boot resume hook was switched from Claude to Antigravity (`agy`); it is Claude Code again, `agy-conversation` removed | `~/.config/omarchy/hooks/post-boot.d/deepidle-resume` | n/a |

## Temporary, undone already

| Date | What | Undone |
|---|---|---|
| 2026-11-16 | battery charge thresholds 25/30 plus auto-discharge, for the long-sleep test | 2026-11-16: back to 75/80, `charge_behaviour` auto |

## This run (hypervisor route, 2026-11-17)

Filled in below as it happens.

- 2026-11-17: `asahi-bless --next --set-boot macOSTest` (one-shot NVRAM boot target; the default stays Omarchy). Consumed by the first boot; if a run is aborted and it is still set: `sudo bash harness/hv/bless.sh clear-next` (check with `bless.sh list`).
- 2026-11-17: Pi started `hv-run.sh` (tag `clusterpower0`, run dir `~/deepidle/hv/<date>-clusterpower0`). It makes the Mac boot macOSTest through Aura's hypervisor, then reboots the Mac into Omarchy by itself. Nothing is installed; delete the run dir when no longer wanted.
- macOS is only booted from macOSTest (a disposable volume); the main install and Macintosh HD are untouched.

- 2026-11-17 18:58 correction: the first hv run (R53, 15:32) failed to connect: the Pi's `hv-run.sh` waited only 300 s for the proxy, started 2 min before the Mac reboot, so it gave up ("no /dev/m1n1 after 300 s") and the Mac sat in the m1n1 proxy until the owner restarted it. No test ran. The one-shot next-boot target was consumed (`bless.sh list`: default and next both Omarchy).
- 2026-11-17: Pi `~/deepidle/hv-run.sh` now reads the proxy wait from `WAITSECS` (default 300). Backup: `hv-run.sh.bak-before-waitsecs`; reverse with `cp ~/deepidle/hv-run.sh.bak-before-waitsecs ~/deepidle/hv-run.sh`.
- 2026-11-17 19:00: retry R53b: Pi hv-run (tag clusterpower0b, WAITSECS=900) started, then `bless.sh next macOSTest` set again (one-shot, same reversal).
- 2026-11-17 21:25: R53b also failed to connect (no USB link from the Mac to the Pi). Nothing further armed; default and next boot targets are both Omarchy. Still in place from this run: the Pi's `hv-run.sh` WAITSECS edit (above).
- 2026-11-17 21:40: pacman hook that warns when `update-m1n1` replaces the one-shot loader. **Warning only, it never writes the boot chain.** Files: `/usr/local/sbin/deepidle-loader-check` and `/etc/pacman.d/hooks/96-deepidle-loader-check.hook` (copies in `harness/usbtest/`); it writes `/var/lib/deepidle/bootbin/NEEDS_REBUILD`, shown by `bootbin.sh status`. Reverse: `sudo rm /usr/local/sbin/deepidle-loader-check /etc/pacman.d/hooks/96-deepidle-loader-check.hook /var/lib/deepidle/bootbin/NEEDS_REBUILD`.
- 2026-11-17 21:45: Pi: the stage 1 upload server is now a user service, `~/.config/systemd/user/deepidle-upload.service` (enabled, linger on), so it survives a Pi reboot (it replaced the hand-started process on port 8099). Reverse on the Pi: `systemctl --user disable --now deepidle-upload.service; rm ~/.config/systemd/user/deepidle-upload.service`.
- 2026-11-17 21:50: local git commits (never pushed) in `~/Work/src/aura-img99` (branch gh5-img99-local) and `~/Work/src/aura-pr268` (branch pr268), so the images can be rebuilt. Reverse: `git reset --hard HEAD~1` there (or delete the branch).
- 2026-11-18: owner replugged the Pi to Mac USB. R53c: Pi hv-run (tag clusterpower0c, WAITSECS=600) started and `bless.sh next macOSTest` set again (one-shot; same reversal as before).
- 2026-11-18: local commit `6b8002e7` (image 101, never pushed) in `~/Work/src/aura-img99` (`gh5-img99-local`) and `~/Work/psci-test/boot-test.bin.101` (`e6b4a319d4109d79`) staged as `boot-test.bin`. Reverse: `git reset --hard ce98322f` (or delete the branch) in `~/Work/src/aura-img99`, and `sudo bash harness/usbtest/bootbin.sh test ~/Work/psci-test/boot-test.bin.100` (or `bootbin.sh restore`).
- 2026-11-18: local commit `5700a13b` (image 102, never pushed) in `~/Work/src/aura-img99` (`gh5-img99-local`) and `~/Work/psci-test/boot-test.bin.102` (`3fa056ac204b5c80`) staged as `boot-test.bin`. Reverse: `git reset --hard 6b8002e7` (or `ce98322f` / delete the branch) in `~/Work/src/aura-img99`, and `sudo bash harness/usbtest/bootbin.sh test ~/Work/psci-test/boot-test.bin.101` (or `bootbin.sh restore`).
- 2026-11-18: local commit `206fad03` (image 103, never pushed) in `~/Work/src/aura-img99` (`gh5-img99-local`) and `~/Work/psci-test/boot-test.bin.103` (`bfc63d18c573481b`) staged as `boot-test.bin`. Reverse: `git reset --hard 5700a13b` in `~/Work/src/aura-img99`, and `sudo bash harness/usbtest/bootbin.sh test ~/Work/psci-test/boot-test.bin.102` (or `bootbin.sh restore`).
- 2026-11-18: local commit `4e5f33cc` (image 104, never pushed) in `~/Work/src/aura-img99` (`gh5-img99-local`) and `~/Work/psci-test/boot-test.bin.104` (`6736a9461a95fe27`) staged as `boot-test.bin`. Reverse: `git reset --hard 206fad03` in `~/Work/src/aura-img99`, and `sudo bash harness/usbtest/bootbin.sh test ~/Work/psci-test/boot-test.bin.103` (or `bootbin.sh restore`).
- 2026-11-18: local commit `86776585` (image 105, never pushed) in `~/Work/src/aura-img99` (`gh5-img99-local`) and `~/Work/psci-test/boot-test.bin.105` (`39980e97b1c1bb80`) staged as `boot-test.bin`. Reverse: `git reset --hard 4e5f33cc` in `~/Work/src/aura-img99`, and `sudo bash harness/usbtest/bootbin.sh test ~/Work/psci-test/boot-test.bin.104` (or `bootbin.sh restore`).
| 2026-11-19 | `~/.local/state/deepidle/pi-ssh` points at the Pi's dd-wrt address 192.168.5.111 (the Pi left 192.168.1.112) | `~/.local/state/deepidle/pi-ssh` | change the address back to 192.168.1.112 once the Pi is on LiveFreeOrDie again |
| 2026-11-19 | DeepTest UKI rebuilt with extra cmdline `mem=30G panic_on_oops=1 hung_task_panic=1 hung_task_timeout_secs=10 softlockup_panic=1` (for R57E, ramoops above the memory limit). Only DeepTest boots use it | `/home/jjr/Work/deepidle-usbtest/deeptest.efi`, `/boot/efi/EFI/Linux/deeptest.efi` | `sudo bash harness/usbtest/build-uki.sh` (no extras); the next `arm.sh` reinstalls it |
