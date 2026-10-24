#!/bin/bash
# Arm ONE boot for the PMP wake test, then reboot (harness/reboot.sh) to run it unattended.
# The PMP node is disabled in the DTB deepidle3 boots with (rtcalarm2); the PMP needs the pmpfix
# m1n1 (copies the PMP tunables into the DT, sets the node okay; it ran the PMP fine in run 4)
# and the "pmp" alias. boot.bin.pmpwake-test = m1n1-pmpfix.bin + the rtcalarm2 boot.bin's 113
# DTBs with #31 (J414s) = the deepidle3 build's t6020-j414s.dtb plus only `aliases { pmp = &pmp; }`
# (decompiled diff: that one line) + the same U-Boot tail.
# The boot it arms:
#   di-pmpwake-early (before sysinit): deepidle3-early.sh: notes the booted m1n1 image, puts the
#     stock boot.bin back on the ESP, unsets next_entry, so any later boot is the normal one.
#   di-pmpwake-run (multi-user, +120 s): pmp-wake/boot-run.sh: removes the arm flag, checks the
#     booted image, runs pmp-wake/run.sh 3 (pmp stays blacklisted; the test insmods the new pmp.ko).
#   sudo bash /home/jjr/Work/deepidle-harness/pmp-wake/arm.sh          arm
#   sudo bash /home/jjr/Work/deepidle-harness/pmp-wake/arm.sh remove   disarm, remove the units
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
H=/home/jjr/Work/deepidle-harness
FLAG=/var/lib/deepidle/pmpwake-armed
TESTBIN=/home/jjr/Work/deep-idle-build/boot.bin.pmpwake-test
TESTSHA=2c710fe4e8d91600
STOCK=/var/lib/deepidle/boot.bin.stock
STOCKSHA=3630adc3b3be173c
U=/etc/systemd/system

if [ "${1:-}" = remove ]; then
    rm -f $FLAG
    systemctl disable di-pmpwake-early.service di-pmpwake-run.service 2>/dev/null || true
    rm -f $U/di-pmpwake-early.service $U/di-pmpwake-run.service
    systemctl daemon-reload
    [ "$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)" = $STOCKSHA ] \
        || { cp $STOCK /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync; }
    grub-editenv /boot/grub/grubenv unset next_entry
    echo "disarmed: ESP boot.bin $(sha256sum /boot/m1n1/boot.bin | cut -c1-16), next_entry unset"
    exit 0
fi

[ "$(sha256sum $TESTBIN | cut -c1-16)" = $TESTSHA ] || { echo "test boot.bin missing or changed"; exit 1; }
[ "$(sha256sum $STOCK | cut -c1-16)" = $STOCKSHA ] || { echo "stock boot.bin copy missing or wrong"; exit 1; }
[ "$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)" = $STOCKSHA ] || { echo "ESP boot.bin is not stock; stopping"; exit 1; }
[ -x /usr/local/lib/deepidle/deepidle3-early.sh ] || { echo "deepidle3-early.sh missing"; exit 1; }
grep -q "id deepidle3-test-kernel" /boot/grub/grub.cfg || { echo "deepidle3 GRUB entry missing"; exit 1; }
[ -e /var/lib/deepidle/deepidle3-armed ] && { echo "deepidle3 smoke is armed too; remove /var/lib/deepidle/deepidle3-armed first"; exit 1; }

cat > $U/di-pmpwake-early.service <<EOF
[Unit]
Description=PMP wake test boot: restore the stock m1n1 image early
DefaultDependencies=no
RequiresMountsFor=/boot /var/lib/deepidle
ConditionPathExists=$FLAG
Before=sysinit.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/deepidle/deepidle3-early.sh

[Install]
WantedBy=sysinit.target
EOF
cat > $U/di-pmpwake-run.service <<EOF
[Unit]
Description=PMP wake test boot: run pmp-wake/run.sh once
ConditionPathExists=$FLAG
After=multi-user.target di-pmpwake-early.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 120
ExecStart=/usr/bin/bash $H/pmp-wake/boot-run.sh
TimeoutStartSec=1800

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable di-pmpwake-early.service di-pmpwake-run.service
touch $FLAG
cp $TESTBIN /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync
grub-editenv /boot/grub/grubenv set next_entry=deepidle3-test-kernel
echo "armed: ESP boot.bin $(sha256sum /boot/m1n1/boot.bin | cut -c1-16), next_entry deepidle3-test-kernel, flag $FLAG"
echo "now reboot with: bash $H/reboot.sh <prompt file>"
