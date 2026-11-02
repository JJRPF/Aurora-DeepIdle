#!/bin/bash
# GH-10: arm one boot with a test m1n1 image.   sudo arm.sh /path/to/boot.bin.test
# Keeps the current boot.bin as stock (once), installs the test image; early.sh restores stock
# on the next boot. Does not reboot.
set -e
V=/var/lib/gh10; IMG=$1
[ "$(id -u)" = 0 ] && [ -s "$IMG" ] || { echo "usage: sudo $0 IMAGE"; exit 1; }
mkdir -p $V
[ -s $V/boot.bin.stock ] || cp /boot/m1n1/boot.bin $V/boot.bin.stock
stock=$(sha256sum $V/boot.bin.stock | cut -c1-16)
[ "$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)" = "$stock" ] || { echo "boot.bin is not the stock image ($stock): fix first"; exit 1; }
[ -s /boot/grub/grubenv ] && [ ! -e $V/armed ] || { echo "already armed"; exit 1; }
cp "$IMG" /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync
rm -f $V/armed.done; touch $V/armed
echo "armed: $(sha256sum "$IMG" | cut -c1-16) (stock $stock); reboot to test"
