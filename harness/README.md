# Unattended test harness (as run on 2026-10-15/16)

Machine-specific: paths, UUIDs and the user name are this machine's. Kept as a record and a
starting point, not as an installer.

| File | Role |
|---|---|
| `runner.sh`, `deepidle-runner.service` | Root runner: one plan step per boot (check, settle 180 s, `idle-ab`, `wakelat`), arms the next step (m1n1 image, GRUB `next_entry`), waits for the session's `ack-<n>`, reboots. Stops on an unhealthy boot or a missing ack. |
| `early-restore.sh`, `deepidle-early-restore.service` | Right after `/boot` mounts: records the booted `boot.bin`, puts the stock one back |
| `90-deepidle-watchdog.conf` | systemd hardware watchdog (60 s) for hangs after userspace starts |
| `43_deepidle` | GRUB entries for the test kernel and the stock kernel with `panic=10` |
| `deepidle-resume`, `prompt.txt` | Hyprland autostart hook that reopens the Claude Code session after each reboot |
| `keep-pinned.conf` | `linux-modules-cleanup.service` drop-in: skip module trees marked `.keep` |
| `recover.sh`, `rearm.sh`, `rearm3.sh`, `rearm4.sh`, `teardown.sh` | Restore the Aurora module tree; re-arm the plan; remove the harness |
| `batlog.sh` | Battery gauge log every 10 s (power, current, voltage, energy) |
| `wakeload.c` | Synthetic busy-desktop wake load: `wakeload THREADS MEAN_US WORK_US` (threads sleep an exponential time, then spin); a plan line's optional 5th field, e.g. `10:650:15` |

What went wrong, so it does not again:

* `kernel-modules-hook` deletes every module tree pacman does not own, other than the
  running kernel's, at the next boot. Booting a second hand-installed kernel removed the
  first one's modules. Install `keep-pinned.conf` and mark such trees `.keep` first.
* A `boot.bin` that stops in m1n1 hangs before any watchdog; only recoveryOS gets out. Put
  the stock `boot.bin` copy on the ESP before the test, where recoveryOS can reach it.
* A session that cannot come back (no network) must stop the plan, not let it continue.
