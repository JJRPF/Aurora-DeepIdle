#!/bin/bash
# Reboot for a test and come back: run as jjr (not root).
#   bash ~/Work/deepidle-harness/reboot.sh PROMPT_FILE [DELAY_SECONDS]
# 1) The Claude session reopens after the boot: PROMPT_FILE becomes
#    ~/.local/state/deepidle/prompt.txt and ~/.local/state/deepidle/resume arms
#    ~/.local/bin/deepidle-resume (Hyprland autostart). The prompt must say to remove the resume file.
# 2) The screens stay dark: refuses unless the after-boot headless hook is in place and enabled
#    (the owner asked for headless after every reboot, 2026-10-22).
# 3) Reboots after DELAY_SECONDS (default 30) through a transient unit, via the harness sudo rule,
#    else systemctl reboot (logind/polkit).
set -eu
[ "$(id -u)" != 0 ] || { echo "run as jjr, not root"; exit 1; }
P=${1:?prompt file}; D=${2:-30}
[ -s "$P" ] || { echo "empty prompt file"; exit 1; }
CTL=$HOME/.local/state/deepidle
[ -e $CTL/headless-on-boot ] && [ -x $HOME/.local/bin/deepidle-headless-boot ] \
    && grep -q deepidle-headless-boot $HOME/.config/hypr/autostart.lua \
    || { echo "headless-after-boot hook not in place: not rebooting"; exit 1; }
grep -q deepidle-resume $HOME/.config/hypr/autostart.lua || { echo "resume hook missing from autostart"; exit 1; }
mkdir -p $CTL
cp "$P" $CTL/prompt.txt
touch $CTL/resume
sync
echo "$(date '+%F %T') reboot.sh: armed resume, rebooting in $D s" >> $CTL/resume.log
if sudo -n /usr/bin/systemd-run --unit=di-reboot-$(date +%H%M%S) --on-active=$D /usr/bin/systemctl reboot 2>/dev/null; then
    echo "reboot in $D s (harness sudo rule)"
else
    setsid -f sh -c "sleep $D; systemctl reboot" >/dev/null 2>&1
    echo "reboot in $D s (systemctl reboot, no sudo rule)"
fi
