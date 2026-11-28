#!/bin/bash
# GH-5 desktop bisect: stop groups of userspace, run the staged dry run at one level, start them again if it returns.
#   sudo bash bisect-userspace.sh "<groups>" [level]      groups: wm audio bt wifi misc (space separated)
# A hang is logged by staged-dryrun.sh (BEGIN with no END); the dog / owner resets it.
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
U="sudo -u jjr XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus systemctl --user"
G=" $1 "; LEVEL=${2:-platform}
H=$(cd "$(dirname "$0")" && pwd)
LOG=/home/jjr/dev/Aurora-DeepIdle/GH-5-S2R-DjNaeemPaths/docs/postwake/staged-$(date +%Y%m%d-%H%M%S).log
export LOG
echo "$(date +%T) bisect groups:$G level $LEVEL" >> "$LOG"; sync -f "$LOG"
[[ $G == *" misc "* ]]  && $U stop owed.service mac-autobrightness.service superwhisper.service power-log.service omarchy-audio-watchdog.service omarchy-asahi-mic.service 2>/dev/null
[[ $G == *" audio "* ]] && { $U stop omarchy-audio-watchdog.service pipewire-pulse.service wireplumber.service pipewire.service pipewire.socket pipewire-pulse.socket 2>/dev/null; systemctl stop speakersafetyd.service; }
[[ $G == *" bt "* ]]    && systemctl stop bluetooth.service
[[ $G == *" wifi "* ]]  && systemctl stop NetworkManager.service iwd.service
[[ $G == *" wm "* ]]    && $U stop wayland-wm@hyprland.desktop.service
echo "$(date +%T) stopped, running" >> "$LOG"; sync -f "$LOG"
sleep 3
KEEPALIVE=1 SKIP=1 DEADMAN=60 bash $H/staged-dryrun.sh "$LEVEL"
echo "$(date +%T) returned, restarting services" >> "$LOG"
[[ $G == *" wifi "* ]]  && systemctl start iwd.service NetworkManager.service
[[ $G == *" bt "* ]]    && systemctl start bluetooth.service
[[ $G == *" audio "* ]] && { systemctl start speakersafetyd.service; $U start pipewire.socket pipewire-pulse.socket pipewire.service wireplumber.service pipewire-pulse.service; }
[[ $G == *" wm "* ]]    && $U start wayland-wm@hyprland.desktop.service
