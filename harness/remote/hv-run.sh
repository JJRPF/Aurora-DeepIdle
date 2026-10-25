#!/bin/bash
# Pi side of the hypervisor sleep trace: run macOSTest's kernel (14.8.9) under Aura's hypervisor
# with the PMP and SMC tracers, unattended. The Mac must be booting Aura on macOSTest (Linux:
# hv/bless.sh next macOSTest, then reboot) with the Pi's USB-A port cabled to the Mac's DFU port.
#   hv-run.sh <kernelcache.macho> [tag] [aura.bin (raw) or aura.macho to chainload first; use the raw build]
# Output: ~/deepidle/hv/<date>-<tag>/ (console.txt, hv.log). Not to be started without the owner's go.
set -eu
KC=$(readlink -f "$1"); TAG=${2:-sleep}; CHAIN=${3:+$(readlink -f "$3")}
AURA=$HOME/deepidle/aura
OUT=$HOME/deepidle/hv/$(date +%Y%m%d-%H%M%S)-$TAG
DEV=${M1N1DEVICE:-/dev/m1n1}
mkdir -p "$OUT"
echo "$(date '+%F %T') waiting for $DEV (Aura proxy)" | tee "$OUT/run.txt"
for _ in $(seq 300); do [ -e "$DEV" ] && break; sleep 1; done
[ -e "$DEV" ] || { echo "no $DEV after 300 s: Aura did not come up on USB" | tee -a "$OUT/run.txt"; exit 1; }
cd "$AURA/proxyclient"
if [ -n "$CHAIN" ]; then
    echo "$(date '+%F %T') chainloading $(basename "$CHAIN") $(sha256sum "$CHAIN" | cut -c1-16)" | tee -a "$OUT/run.txt"
    # A *.bin is the raw build (what the volume's boot object is): its vectors sit at the image base,
    # where the first stage's locked RVBAR points. The Mach-O build has them 0x10000 higher, and the
    # second stage then refuses to start any secondary CPU ("RVBAR differs from vector").
    RAW=; case "$CHAIN" in *.bin) RAW="-r -E 2048" ;; esac
    timeout 120 python3 tools/chainload.py $RAW "$CHAIN" < /dev/null >> "$OUT/run.txt" 2>&1 || { echo "chainload failed" | tee -a "$OUT/run.txt"; exit 1; }
    sleep 3
    for _ in $(seq 60); do [ -e "$DEV" ] && break; sleep 1; done
fi
echo "$(date '+%F %T') starting the guest: $(basename "$KC")" | tee -a "$OUT/run.txt"
# stdin from /dev/null: the shells run_guest opens on errors and on exit read EOF and move on.
timeout 3600 python3 tools/run_guest.py -l "$OUT/hv.log" \
    -m hv/trace_pmp.py -m hv/trace_smc.py "$KC" -- \
    "debug=0x14e serial=3 apcie=0xfffffffe -enable-kprintf-spam wdt=-1 clpc=0 hvsleep=1" \
    < /dev/null > "$OUT/console.txt" 2>&1 || echo "run_guest exit $?" | tee -a "$OUT/run.txt"
# Leave the Mac rebooting into its default (Linux), not stopped in the proxy: a guest left
# without its host, or Aura idling after the run, would otherwise wait for the owner.
sleep 2
if [ -e "$DEV" ]; then
    timeout 60 python3 tools/reboot.py >> "$OUT/run.txt" 2>&1 && echo "rebooted the Mac" | tee -a "$OUT/run.txt" \
        || echo "reboot via proxy failed: the Mac needs the power key" | tee -a "$OUT/run.txt"
fi
echo "$(date '+%F %T') done" | tee -a "$OUT/run.txt"
