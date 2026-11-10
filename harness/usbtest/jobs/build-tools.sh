#!/bin/bash
# GH-5: build the static /dev/mem tools (harness/mmio) into a job directory: build-tools.sh <job dir>
set -eu
H=$(cd "$(dirname "$0")" && pwd); D=${1:?job dir}
for t in aura-ctl mmio-read mmio-write pmgrcnt scan-magic wakemask; do gcc -O2 -static -o "$D/$t" "$H/../../mmio/$t.c"; done
echo "tools built in $D"
