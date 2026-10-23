#!/bin/bash
# Read-only disk check after a test that hit storage errors (SMC step 7, 2026-10-22: NVMe writes
# failed after resume, root went read-only, the next boot replayed the btrfs tree log).
# Changes nothing: btrfs scrub in read-only mode (-r, reports checksum errors, repairs nothing),
# the btrfs device error counters, and a no-write fsck of the ESP (FAT, "not properly unmounted").
#   sudo bash /home/jjr/Work/deepidle-harness/tools/fs-check.sh
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
echo "== btrfs device stats /"; btrfs device stats /
echo "== btrfs scrub (read-only) /"; btrfs scrub start -B -r /
echo "== ESP $(findmnt -no SOURCE /boot) fsck -n"; fsck.vfat -n "$(findmnt -no SOURCE /boot)"
