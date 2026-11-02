#!/bin/bash
# GH-10: early in every boot while /var/lib/gh10/armed exists, note which m1n1 image this boot
# came from and put the stock one back, so a test image boots at most once.
V=/var/lib/gh10
sha() { sha256sum "$1" | cut -c1-16; }
echo "$(date '+%F %T') booted $(sha /boot/m1n1/boot.bin) kernel $(uname -r)" >> $V/log
cp /boot/m1n1/boot.bin $V/booted.bin 2>/dev/null
if [ -s $V/boot.bin.stock ] && [ "$(sha /boot/m1n1/boot.bin)" != "$(sha $V/boot.bin.stock)" ]; then
    cp $V/boot.bin.stock /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync
    echo "$(date '+%F %T') restored stock $(sha /boot/m1n1/boot.bin)" >> $V/log
fi
mv $V/armed $V/armed.done
exit 0
