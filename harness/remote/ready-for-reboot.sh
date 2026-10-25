#!/bin/bash
# Mac side: run before EVERY test reboot. Refuses (exit 1) unless the Pi has the agy helper ready in
# remote-control mode, the mac-guard running and the kernel-log watcher running.
#   ready-for-reboot.sh <tag>
set -u
PI=${PI_HOST:-core-node-ts}; TAG=${1:-test}
r() { timeout 60 ssh -o BatchMode=yes -o ConnectTimeout=8 "$PI" "$@" 2>&1 | grep -v 'Pseudo-terminal'; }
bad=0
out=$(r "~/deepidle/agy-ready.sh $TAG"); echo "agy: $out"; echo "$out" | grep -qi "daemon status: active" || { echo "NOT READY: agy RC daemon"; bad=1; }
g=$(r '~/deepidle/mac-guard.sh start >/dev/null; ~/deepidle/mac-guard.sh status | head -1'); echo "guard: $g"; echo "$g" | grep -q "^running" || { echo "NOT READY: mac-guard"; bad=1; }
w=$(r '~/deepidle/pi-watch.sh status | head -1' | sed 's#/home/[^ ]*#<watch>#'); echo "watch: $w"
echo "$w" | grep -q "^running" || { echo "NOT READY: pi-watch"; bad=1; }
[ -e "$HOME/.local/state/deepidle/resume-always" ] || { echo "NOT READY: resume-always missing"; bad=1; }
date '+%F %T' > "$HOME/.local/state/deepidle/last-ready"
[ $bad = 0 ] && echo "READY (tag $TAG)"; exit $bad
