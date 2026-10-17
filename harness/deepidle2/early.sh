#!/bin/bash
# deepidle2 test boot, very early: note the m1n1 image, then put the stock one back so any
# later boot (watchdog reset, power cycle) is the normal one. Runs only while armed.
STOCK=/var/lib/deepidle/boot.bin.stock
STOCK_SHA=3630adc3b3be173c
sha=$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)
echo "$sha" > /run/deepidle2-booted-sha
if [ "$sha" != "$STOCK_SHA" ] && [ "$(sha256sum $STOCK | cut -c1-16)" = "$STOCK_SHA" ]; then
    cp $STOCK /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync
fi
grub-editenv /boot/grub/grubenv unset next_entry
exit 0
