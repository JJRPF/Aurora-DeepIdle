#!/bin/bash
# Pi side: power-cycle the Mac's USB port (VBUS) with uhubctl, to try to wake a Mac hung in sleep.
#   ~/deepidle/vbus.sh learn    while the Mac's Aura is on USB: remember which hub port it is on
#   ~/deepidle/vbus.sh cycle    cut VBUS for OFF s (default 8) and restore it
#   ~/deepidle/vbus.sh status
# Untested whether a hung M2 wakes on attach; the guard uses it before bothering the owner.
set -u
D=$HOME/deepidle; F=$D/mac-usb-port; OFF=${OFF:-8}
case "${1:-status}" in
learn)
    for d in /sys/bus/usb/devices/*; do
        [ -e "$d/idVendor" ] && [ "$(cat "$d/idVendor")" = 1209 ] || continue
        n=$(basename "$d")                      # e.g. 3-1 or 1-1.2: bus-port.port...
        hubbus=${n%%-*}; path=${n#*-}; port=${path##*.}
        [ "$path" = "$port" ] && hub=$hubbus || hub="$hubbus-${path%.*}"
        echo "$hub $port" > "$F"; echo "Aura at $n -> hub $hub port $port"; exit 0
    done
    echo "no Aura (1209:*) on USB"; exit 1 ;;
cycle)
    [ -s "$F" ] || { echo "port unknown: run learn while Aura is attached"; exit 1; }
    read -r hub port < "$F"
    sudo -n uhubctl -l "$hub" -p "$port" -a cycle -d "$OFF" ;;
status) [ -s "$F" ] && echo "Mac port: $(cat "$F")" || echo "port not learned"; sudo -n uhubctl 2>&1 | head -20 ;;
esac
