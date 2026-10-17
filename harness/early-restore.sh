#!/bin/bash
# Deep idle campaign, early in every boot: note which m1n1 image this boot came from, then put the
# stock image back before anything else runs. A test DTB only has to boot once; if it freezes the
# machine later in this boot (the watchdog resets it) or the owner power-cycles it, the next boot
# is stock instead of the same test image again. Runs only while /var/lib/deepidle/plan exists.
VAR=/var/lib/deepidle
STOCK=$VAR/boot.bin.stock
STOCK_SHA=3630adc3b3be173c
sha=$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)
echo "$sha" > /run/deepidle-booted-sha
if [ "$sha" != "$STOCK_SHA" ] && [ "$(sha256sum $STOCK | cut -c1-16)" = "$STOCK_SHA" ]; then
    cp $STOCK /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync
    echo "$(date '+%F %T') early: booted $sha, restored stock ($(sha256sum /boot/m1n1/boot.bin | cut -c1-16))" >> $VAR/runner.log
fi
exit 0
