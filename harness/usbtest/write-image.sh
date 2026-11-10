#!/bin/bash
# GH-5: puts the root image (and optionally a job) in main's /boot partition (LABEL=OMARCHY_BOOT,
# ext4), where the DeepTest boot reads it: read-only, copied to RAM, then unmounted.
#   sudo bash write-image.sh            copy $W/root.sfs if it differs
#   sudo bash write-image.sh job <dir>  replace /boot/deeptest/job with <dir> (job.sh, topic, deadline, keep)
#   sudo bash write-image.sh nojob      remove the job (the boot then runs the hello job)
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
W=${W:-/home/jjr/Work/deepidle-usbtest}; D=/boot/deeptest
[ "$(findmnt -no LABEL /boot)" = OMARCHY_BOOT ] || { echo "/boot is not LABEL=OMARCHY_BOOT"; exit 2; }
mkdir -p $D
case "${1:-}" in
job) rm -rf $D/job; cp -r "${2:?job dir}" $D/job; echo "job: $(ls $D/job | tr '\n' ' ')" ;;
nojob) rm -rf $D/job; echo "job removed" ;;
esac
if [ "$(cat $D/root.sfs.sha256 2>/dev/null)" != "$(cat "$W/root.sfs.sha256")" ]; then
    cp "$W/root.sfs" $D/root.sfs.tmp && sync && mv $D/root.sfs.tmp $D/root.sfs
    cp "$W/root.sfs.sha256" $D/root.sfs.sha256
fi
sync; echo 3 > /proc/sys/vm/drop_caches   # read back from the disk, not the page cache
[ "$(sha256sum $D/root.sfs | cut -c1-64)" = "$(cat "$W/root.sfs.sha256")" ] || { echo "image in /boot does not match"; exit 4; }
echo "image ok: $(cut -c1-16 $D/root.sfs.sha256) in $D, job: $([ -d $D/job ] && ls $D/job | tr '\n' ' ' || echo none), /boot free $(df -h --output=avail /boot | tail -1 | tr -d ' ')"
