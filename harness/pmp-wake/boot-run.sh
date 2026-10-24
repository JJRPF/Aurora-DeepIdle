#!/bin/bash
# Run by di-pmpwake-run.service (pmp-wake/arm.sh) in the armed boot: once, unattended.
FLAG=/var/lib/deepidle/pmpwake-armed
TESTSHA=2c710fe4e8d91600
rm -f $FLAG
s=$(cat /run/deepidle3-booted-sha 2>/dev/null)
[ "$s" = $TESTSHA ] || { echo "booted m1n1 '$s', not the PMP image: not testing"; exit 0; }
exec /usr/bin/bash /home/jjr/Work/deepidle-harness/pmp-wake/run.sh 3
