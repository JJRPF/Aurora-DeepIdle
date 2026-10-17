#!/bin/bash
# Put back the modules of the Aurora 11.35-sep kernel (7.1.12-2-11.35-sep-ARCH+), which
# kernel-modules-hook's linux-modules-cleanup.service moved aside when the deep idle test kernel
# booted (and its tmpfiles rule then deleted), and stop that from happening again.
# Run as: sudo bash ~/Work/deepidle-harness/recover.sh
set -eu
REL=7.1.12-2-11.35-sep-ARCH+
SRC=/home/jjr/Work/aurora-modules-restore/lib/modules/$REL
DST=/usr/lib/modules/$REL
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
[ -e $DST/modules.dep ] && { echo "$DST already exists, leaving it"; } || {
    cp -a $SRC $DST
    chown -R root:root $DST
    chown -h jjr:jjr $DST/build
}
touch $DST/.keep
install -d /etc/systemd/system/linux-modules-cleanup.service.d
install -m644 /home/jjr/Work/deepidle-harness/keep-pinned.conf /etc/systemd/system/linux-modules-cleanup.service.d/keep-pinned.conf
systemctl daemon-reload
# Checks
systemctl cat linux-modules-cleanup.service | grep -q '.keep' && echo "cleanup drop-in: active"
for m in brcmfmac hci_bcm4377 macsmc-hwmon apple-sep zram nls_cp437; do
    printf '%-14s %s\n' $m "$(modinfo -k $REL -F filename $m 2>&1 | head -1)"
done
echo "modules: $(find $DST -name '*.ko' | wc -l) (expect 1871)"
echo "Done. Reboot into the default entry (Omarchy Linux, the Aurora 11.35 kernel)."
