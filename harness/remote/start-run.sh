#!/bin/bash
# Pi side: start a guest run and, if asked, its phone notification, with absolute paths (a `cd x && cmd &`
# in an ssh one-liner only changes directory in the background subshell: the notify script was never found).
#   [HVSLEEP=0] [RUNTIME=s] ~/deepidle/start-run.sh <tag> [--notify <delay s> <title> <message>]
D=$HOME/deepidle; TAG=${1:?tag}; shift
cd "$D" || exit 1
setsid nohup "$D/hv-run.sh" "$D/hv/kernelcache-14.8.9-23J631.macho" "$TAG" "$D/hv/aura-hvsleep.bin" > /dev/null 2>&1 < /dev/null &
if [ "${1:-}" = "--notify" ]; then
    setsid nohup "$D/notify-when-guest.sh" "$2" "$3" "$4" > /dev/null 2>&1 < /dev/null &
fi
sleep 3
d=$(ls -dt "$D"/hv/*/ | head -1); echo "run dir: $(basename "$d")"; cat "${d}run.txt"
tail -2 "$D/guard.log" | sed 's#/home/[^ ]*#<path>#'
