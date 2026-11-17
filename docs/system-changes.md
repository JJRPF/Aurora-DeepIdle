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

## Temporary, undone already

| Date | What | Undone |
|---|---|---|
| 2026-11-16 | battery charge thresholds 25/30 plus auto-discharge, for the long-sleep test | 2026-11-16: back to 75/80, `charge_behaviour` auto |

## This run (hypervisor route, 2026-11-17)

Filled in below as it happens.
