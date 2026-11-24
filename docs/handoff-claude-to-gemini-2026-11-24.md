# Handoff: Claude Code to Gemini Neon, 2026-11-24 (GH-5, S2R on the M2 Pro)

Paste the prompt below into the new agent. Everything it refers to is in this repo.

---

You are taking over GH-5 in the Aurora-DeepIdle repo (github.com/JJRPF/Aurora-DeepIdle): suspend-to-RAM (S2R) on a 14-inch MacBook Pro M2 Pro (J414s, SoC T6020) running Linux (Omarchy, Asahi-based kernel 7.2.11). You work in the worktree `/home/jjr/dev/Aurora-DeepIdle/GH-5-S2R-DjNaeemPaths`, branch `GH-5-S2R-DjNaeemPaths`. Commit continuously and push straight to main with `git push -q origin HEAD:main` (no PRs). Git identity is the configured user; never change it.

## Read first

1. `docs/worklog.md`: the full history, appended in time order. Read the last ~150 lines ("R61O" to the end) in detail. The entries before that are reference: search them for a register or run name when you need it.
2. `docs/s2r-status.json`: the data behind the public status page https://jjrpf.com/S2R (phases with percentages, findings, unknowns, credits). `docs/status.md` is the older text summary.
3. `docs/s2r-repro.md`: how a test run works end to end, written for outsiders. Up to date with the R61P fix.
4. `docs/system-changes.md`: every change made outside the repo (UKIs on the ESP, boot.bin images, modules), one row per run.
5. GitHub issue #5 (`gh issue view 5 -R JJRPF/Aurora-DeepIdle --comments`): the thread with nekolyanich (native S2R on the M2 Pro J416s), the main outside collaborator.

## Where it stands

Works on the one-shot **test boot**, every run since R57AL. The test boot is a minimal Linux from a squashfs on /boot; the root and home filesystems are never mounted.
- A real S2R: PMGR `SLP_S2R`, DRAM in self-refresh, the RTC alarm wake through the RVBAR into Aura (our m1n1 fork at EL2), back to userspace with all 10 CPUs.
- NVMe (the ANS cold-started), USB, SMC, RTC, SEP, PMP and the keyboard come back.
- The internal display (R61M6/M7): the DCP firmware is cold-started from macOS's DCP.img4.
- **New on 2026-11-22: Wi-Fi/BT and the SD reader, 3 of 3 (R61P, R61Q, R61R).** In R61Q and R61R Wi-Fi scanned 51 networks and rejoined the home network.
  - The cause: Aura's `PSCI_S2R_PCIE` step (aura-ctl bit 20) powered off `apcie_gp_sys`, `apcie_gpshr_sys` and `apcie_gp` at the commit. The fix is to leave it off. The aura-ctl word is now `0xc16dcb3f 0 0 0 241` (was `0xc17dcb3f`).
  - The PCIe port teardown (`pcie_apple.test_s2r_l2`, patch 0010) turned out not to be needed (R61R).
  - The SMC's MEPS `000102010004` after `waka` is normal; macOS shows it too.

Site percentages: overall 83, phase 4 (devices) 92, phase 5 (full S2R) 90, phase 6 (normal install) 0.

## The test loop (one run is about 4 to 6 minutes)

1. Make a job. Copy the latest one (`harness/usbtest/jobs/r61r-nol2`) and edit `job.sh`. Each job's `apple/dcp-fw.macho` is Apple's DCP firmware: it is gitignored per job; **never commit it**.
2. Clear the PMU scratch (0x6004..0x601f except 0x6010, plus 0x6024..0x6027) with `\x00` via dd on `$(ls /sys/bus/spmi/devices/0-0b/spmi_nvmem*/nvmem | head -1)`. The exact loop is in the worklog.
3. Stage the test boot image: `sudo -n bash harness/usbtest/bootbin.sh test ~/Work/psci-test/boot-test.bin.127`.
4. Arm: `sudo -n bash harness/usbtest/arm.sh --chain --no-reboot --job harness/usbtest/jobs/<job> --label <L>`. Check that `sudo sha256sum /boot/efi/EFI/Linux/deeptest.efi` starts with `f49377c3` (UKI pmp30).
5. Log "R.. armed" in the worklog, commit, push, then `sudo -n systemctl reboot`. The Mac runs the job once and comes back to the normal install on its own.
6. After the reboot:
   - Read `/var/lib/deepidle/usbtest/last/summary` and `/boot/deeptest/postwake/*-<run>-*` (dmesg.txt, links.txt, cfg.txt, radio.txt, pmu.txt).
   - Check the PMU crumbs: `0x601f = aa` means a real sleep committed; `0x6023 = a4` means Aura's wake path ran.
   - Copy the folders to `docs/postwake` (`sudo -n cp -r`, then `chown -R jjr:`), then `rm -f` the `fd-*.txt` dumps.
   - **Scrub the home network name and the Wi-Fi MAC** from the copies before committing.
7. Log the result in `docs/worklog.md` (append) and `docs/s2r-status.json`:
   - Insert at the top of `findings` an entry with only `title` and `body`, in plain language.
   - Set `updated`.
   - Run `python3 tools/s2r-status-fmt.py docs/s2r-status.json`, then `python3 -m json.tool` on it.
   - Add a row to `docs/system-changes.md`.
   - Commit and push.
8. Post the site blurb (under about 240 characters): `curl -X PUT -H "Authorization: Bearer $S2R_STATUS_TOKEN" --data "<msg>" https://jjrpf.com/api/s2r-message`. The token is in the environment (`~/.bashrc`); never print it.

The kernel tree is `~/Work/src/linux-aurora-pstore` (toolchain env and the module/UKI build commands are in the worklog). Aura is `~/Work/src/aura-img99` (local branch, never push).

## Next steps, in order

1. **Owner checks** (ask; they need someone at the Mac): pair a Bluetooth device and insert an SD card after a test sleep. The BT chip loses its SRAM in the cut; the owner's merged PR aurora-silicon/linux#7 (hci_bcm4377 FLR recovery and post_init reload) is the relevant code if BT misbehaves.
2. **Clean up the fix.** Make bit 20 off the default in Aura (or drop the step), so the S2R recipe no longer depends on the job's aura-ctl word. Fold the DCP restart (patch 0009) and the relink (0001) into non-TEST code; keep `test_s2r_l2` off. Refresh `patches/s2r-repro/` so it includes the display changes.
3. **Drain over a night**: one long test sleep, battery charge read before and after (SMC keys in the post-wake dumps).
4. **Suspend from the full desktop** (GPU, display, all drivers). Untested so far; the test boot never mounts root or home.
5. **The normal install** (phase 6): Aura and U-Boot in the main boot chain, Omarchy's suspend using `deep`. **This needs the owner's explicit go-ahead first.**
6. Housekeeping when testing is done:
   - restore the pmp20 UKI and the original modules (`~/Work/modroot-backup-r61h/`);
   - delete the jobs' `apple/` firmware copies.
   - Then think about upstreaming the DCP restart and the bit-20 finding to aurora-silicon.

## Rules (keep them)

- Don't touch the normal install's partitions or boot chain without the owner's go-ahead. macOS volumes are read-only. Never edit files in a `main` folder. Reboots for tests are authorized.
- Owner's email is hey@jjrpf.com; send from ai@jjrpf.com. Never print the owner's email, the status token, passwords or the ntfy topic names.
- Don't post outside the repo's own issues without the owner seeing the text first. Replies on this repo's issues are fine.
- Shell gotchas:
  - no `rm` inside `sudo bash -c`;
  - a chained `sleep N` before a command is blocked;
  - `pkill -f` kills its own shell, so use pgrep and kill by PID.
- Notifications:
  - `tools/s2r-log-notify -m "..."` is for routine notes.
  - `agent-notify send --phone-only -m "..."` is only for when the owner must act, and for the pre-reboot note ("If the Mac is not back on main after 10 min, force a reboot.").
- **The Pi (core-node, 192.168.1.112) is unplugged** until the owner says otherwise. No macOS hypervisor runs. Test jobs still work: their Pi log pushes are short curl calls that fail quietly.
- A GPU session (repo Aurora-GPUParity) may be running on this Mac. Before a reboot, ask it to save and stop if it is running, and wait for its OK.

## Things outside the repo that the new agent should know

- After every reboot, the post-boot hook `~/.config/omarchy/hooks/post-boot.d/deepidle-resume` (repo copy `harness/usbtest/deepidle-resume`) opens a terminal running **Claude Code** (`claude --continue ...`) with `~/.local/state/deepidle/prompt.txt`, as long as `~/.local/state/deepidle/resume` exists. If Gemini Neon should be the one resumed, the owner has to change that hook, or delete the `resume` file to turn it off; otherwise Claude starts after each test reboot too. Log any change in `docs/system-changes.md`.
- No job is armed now. The ESP holds UKI pmp30 (`f49377c3`), and `boot-test.bin.127` is the staged test image. The last commit is `6998225`.
