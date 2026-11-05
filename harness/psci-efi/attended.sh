#!/bin/bash
# Owner-attended slpa runs (worklog 2026-11-05 10:02): arm one, tell the owner, reboot into it.
#   bash harness/psci-efi/attended.sh A|B|C [--dry]
# A: slpa (deep_steps 6), 30 s alarm. B: A + PMU boot stage 0x50 (deep_steps 14). C: B + the PMP steps (pmp-sleep).
# Every run: image 51 (install.sh BIN2), 1 deep cycle, root read-only, the PMGR state counters on, dead-man switch.
# Run only when the owner has said they are at the Mac and ready to reset by hand.
set -eu
RUN=${1:?A, B or C}; DRY=${2:-}
H=$(cd "$(dirname "$0")" && pwd)
L=/var/lib/deepidle
case $RUN in
    A) DS=6;  PMP=0 ;;
    B) DS=14; PMP=0 ;;
    C) DS=14; PMP=1 ;;
    *) echo "run A, B or C"; exit 2 ;;
esac
findmnt /boot >/dev/null || { echo "/boot is not mounted"; exit 1; }
[ "$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)" = 76f850895fed53d1 ] || { echo "ESP boot.bin is not the default"; exit 1; }
echo "run $RUN: deep_steps=$DS pmp-sleep=$PMP, 1 deep cycle, 30 s alarm, counters on"
[ "$DRY" = --dry ] && exit 0
echo $DS | sudo tee $L/deep-steps >/dev/null
echo 1 | sudo tee $L/suspend-cycles >/dev/null
echo 30 | sudo tee $L/suspend-alarm >/dev/null
echo deep | sudo tee $L/sleep-modes >/dev/null
sudo touch $L/pmgr-counters $L/force-ro
if [ $PMP = 1 ]; then sudo touch $L/pmp-sleep; else sudo rm -f $L/pmp-sleep; fi
sudo rm -f $L/discharge $L/poke-wakemask
sudo bash $H/install.sh suspendall | tail -1
agent-notify send --title "S2R run $RUN: starting now" --priority high --tags "robot,warning" --message \
"Mac reboots in ~30 s; screen stays dark. ~2 min: it suspends with slpa; 30 s later the alarm. Don't touch keys, trackpad or lid.
1) Works or resumes: result in the chat within ~6 min.
2) Disk dead: a high-priority 'Mac dead-man switch' push; the Mac resets itself. Nothing to do.
3) No chat message and no push within 10 min: hold power ~10 s until off, wait 5 s, press once. Then tell me 'reset by hand' and when." | tail -1
P=$(mktemp)
cat > $P <<E
First remove ~/.local/state/deepidle/resume. This boot is OWNER-ATTENDED slpa run $RUN (worklog 2026-11-05 10:02): image 51, deep_steps=$DS, pmp-sleep=$PMP, 1 deep cycle, 30 s alarm, PMGR counters on, root ro, dead-man switch. FIRST read the ntfy "Mac dead-man switch" pushes (worklog 2026-11-05 15:57: they hold the resume, the counters, aura dbg and SART lines; never print the topic). Then work out what happened from uptime vs resume.log, the Pi watcher kmsg and the newest results-psci-efi-suspendall-*/run.log: a resume (read 'pmgr counters after deep 1': SLP_S2R / SYS_S2R_AOP above 0 = the SoC went down; psci_dbg[13] 3 = it came back through RVBAR with no wake line; apple-sart lines; nvme errors; the dead-man regs), or a reset (time from echo mem to the next kernel start: about 204 s = Linux resumed through RVBAR then hung; 94 s cold boot; 124 s SMC timeout; ask the owner if they reset by hand). Read-only btrfs scrub if any btrfs error appeared. Then remove deep-steps, pmp-sleep, pmgr-counters, force-ro; check boot.bin 76f850895fed53d1 and next_entry unset. Record in the worklog, s2r-status.json, status.md and the board; push GH-8 and main; tell the owner the result right away.
E
sed -n '/^UPDATE FROM GH-10/,$p' ~/.local/state/deepidle/prompt.txt >> $P
bash ~/Work/deepidle-harness/reboot.sh $P 30
