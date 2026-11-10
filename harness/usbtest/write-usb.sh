#!/bin/bash
# GH-5: puts the root image (and optionally a job) on the USB test drive, checks it, unmounts.
#   sudo bash write-usb.sh            copy $W/root.sfs if it differs
#   sudo bash write-usb.sh job <dir>  replace /deeptest/job with <dir> (job.sh, topic, deadline, keep)
#   sudo bash write-usb.sh nojob      remove the job (the boot then runs the hello job)
# The drive is identified by the label DEEPTEST_ROOT; it is mounted only for the copy.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
W=${W:-/home/jjr/Work/deepidle-usbtest}
DEV=$(blkid -L DEEPTEST_ROOT) || { echo "no DEEPTEST_ROOT partition: is the drive plugged in?"; exit 2; }
M=$(mktemp -d)
udisksctl unmount -b "$DEV" >/dev/null 2>&1 || true
fsck.ext4 -p "$DEV" >/dev/null 2>&1 || { rc=$?; [ $rc -le 1 ] || { echo "fsck of $DEV failed ($rc)"; exit 3; }; }
mount -t ext4 "$DEV" "$M"
trap 'umount "$M" 2>/dev/null; rmdir "$M" 2>/dev/null' EXIT
mkdir -p "$M/deeptest"
case "${1:-}" in
job) rm -rf "$M/deeptest/job"; cp -r "${2:?job dir}" "$M/deeptest/job"; echo "job: $(ls "$M/deeptest/job" | tr '\n' ' ')" ;;
nojob) rm -rf "$M/deeptest/job"; echo "job removed" ;;
esac
if [ "$(cat "$M/deeptest/root.sfs.sha256" 2>/dev/null)" != "$(cat "$W/root.sfs.sha256")" ]; then
    cp "$W/root.sfs" "$M/deeptest/root.sfs.tmp" && sync && mv "$M/deeptest/root.sfs.tmp" "$M/deeptest/root.sfs"
    cp "$W/root.sfs.sha256" "$M/deeptest/root.sfs.sha256"
    sync
fi
umount "$M"; mount -t ext4 -o ro "$DEV" "$M"   # read back from the device, not the page cache
echo 3 > /proc/sys/vm/drop_caches
[ "$(sha256sum "$M/deeptest/root.sfs" | cut -c1-64)" = "$(cat "$W/root.sfs.sha256")" ] || { echo "image on the drive does not match"; exit 4; }
echo "drive ok: image $(cut -c1-16 "$M/deeptest/root.sfs.sha256"), job: $([ -d "$M/deeptest/job" ] && ls "$M/deeptest/job" | tr '\n' ' ' || echo none)"
