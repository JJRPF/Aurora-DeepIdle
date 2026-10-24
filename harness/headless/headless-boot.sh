#!/bin/bash
# After every boot, while ~/.local/state/deepidle/headless-on-boot exists: turn the owner's agent
# headless mode (jjr.headless, omarchy-headless) back on, so the screens stay dark through test
# reboots at night. Started by Hyprland autostart (~/.config/hypr/autostart.lua).
# A reboot keeps headless's "active" flag but kills its keeper and inhibitor, and
# `omarchy-headless on` then only says "already on"; so stale state is cleared first.
# Exit blind: SUPER+SHIFT+H. Stop doing this: rm ~/.local/state/deepidle/headless-on-boot
export PATH=/home/jjr/.local/bin:/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:$PATH
CTL=$HOME/.local/state/deepidle
HS=$HOME/.local/state/omarchy/headless
[ -e $CTL/headless-on-boot ] || exit 0
log() { echo "$(date '+%F %T') $*" >> $CTL/headless-boot.log; }
for i in $(seq 30); do hyprctl monitors >/dev/null 2>&1 && break; sleep 1; done
alive() { [ -f "$1" ] && kill -0 "$(cat "$1" 2>/dev/null)" 2>/dev/null; }
if [ -f $HS/active ] && ! alive $HS/keeper.pid; then
    rm -f $HS/active $HS/keeper.pid $HS/inhibitor.pid
    log "cleared stale headless state from before the boot"
fi
omarchy-headless on --quiet >/dev/null 2>&1
log "boot $(uname -r): omarchy-headless on, $(omarchy-headless status | head -1)"
