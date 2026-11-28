#!/bin/bash
# Staged suspend on the sleep.c port kernel: GPU unbound (main refuses G14S GPU sleep), then
# pm_test levels from the shallowest, then the real (dry-run) entry. A line is flushed to disk
# before each step, so after a hang's reset the last line says which step it was.
# usage: sudo bash staged-dryrun.sh [first-level]   levels: devices platform processors core none
LOG=${LOG:-/home/jjr/dev/Aurora-DeepIdle/GH-5-S2R-DjNaeemPaths/docs/postwake/staged-$(date +%Y%m%d-%H%M%S).log}
mkdir -p "$(dirname "$LOG")"
say() { echo "$(date +%T) $*" >> "$LOG"; sync -f "$LOG"; }
P=/sys/module/apple_sleep/parameters
say "start $(uname -r) deep=$(cat $P/deep) untested_commit=$(cat $P/untested_commit)"
[ -n "$NONOTES" ] && echo 0 > $P/pmu_notes
[ -n "$SKIP" ] && echo $SKIP > $P/dbg_skip
[ -n "$KEEPALIVE" ] && { echo 1 > /sys/module/apple_wdt/parameters/suspend_keepalive; say "wdt keepalive $(cat /sys/module/apple_wdt/parameters/suspend_keepalive)"; }
[ -e $P/deadman_s ] && echo ${DEADMAN:-60} > $P/deadman_s && say "dead-man $(cat $P/deadman_s) s"
say "dbg_skip=$(cat $P/dbg_skip 2>/dev/null)"
say "pmu_notes=$(cat $P/pmu_notes)"
# Unbinding the GPU takes Hyprland down (its GL framebuffer alloc asserts, and the session with it).
# The kernel now lets a dry run past the GPU's sleep refusal, so leave it bound unless UNBIND_GPU=1.
if [ -n "$UNBIND_GPU" ]; then
  echo 406400000.gpu > /sys/bus/platform/drivers/aurora/unbind 2>>"$LOG"; say "gpu unbound"
else
  say "gpu left bound"
fi
echo 1 > /sys/power/pm_print_times; echo 1 > /sys/power/pm_debug_messages
echo deep > /sys/power/mem_sleep; say "mem_sleep $(cat /sys/power/mem_sleep)"
levels="devices platform processors core none"
[ -n "$1" ] && levels=$(echo $levels | sed "s/.*\b$1\b/$1/;")
for l in $levels; do
  echo $l > /sys/power/pm_test
  say "BEGIN level=$l"
  echo mem > /sys/power/state 2>>"$LOG"; rc=$?
  say "END level=$l rc=$rc"
  dmesg | sed -n '/PM: suspend entry (deep)/,$p' | grep -vE "UFW|RTKit" | tail -25 >> "$LOG"; sync -f "$LOG"
  sleep 3
done
say "done"
