#!/bin/bash
# Pi side: make sure the agy rescue helper is ready, in remote-control (RC) mode, before the Mac is
# rebooted for a test. Logs to ~/deepidle/rescue/agy-ready.log. Exit 0 only when the RC daemon is active.
#   ~/deepidle/agy-ready.sh [tag]
D=$HOME/deepidle; mkdir -p "$D/rescue"; L=$D/rescue/agy-ready.log
AGY=$HOME/.local/bin/agy
st() { "$AGY" remote-control status 2>&1 | head -4 | tr '\n' ' '; }
echo "$(date '+%F %T') [${1:-}] before: $(st)" >> "$L"
if ! "$AGY" remote-control status 2>&1 | grep -qi "daemon status: active"; then
    "$AGY" remote-control start >> "$L" 2>&1; sleep 5
fi
s=$(st); echo "$(date '+%F %T') [${1:-}] after: $s" >> "$L"
echo "$s"
echo "$s" | grep -qi "daemon status: active"
