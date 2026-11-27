#!/bin/bash
# GH-5: one test boot of an Aura image on the STOCK kernel entry, then back to the S2R default.
#   sudo bash aura-main-try.sh arm <boot-test.bin>   one-shot loader + test image + PMU flag a5 + stock entry default
#   sudo bash aura-main-try.sh restore               persistent Aura 130 boot.bin + the S2R default entry again
# A test chain that hangs is reset by the 120 s watchdog and the next boot is the normal one (bootbin.sh).
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
H=$(cd "$(dirname "$0")" && pwd); BB=$H/bootbin.sh
CONF=/boot/efi/limine.conf; BAK=/var/lib/deepidle/limine-backup; GOOD=~jjr/Work/psci-test/boot-test.bin.130
E=/boot/efi/m1n1; LOADER=$E/boot-loader-oneshot.bin.bak-129
case "${1:-}" in
arm)
    [ -s "${2:-}" ] || { echo "arm <boot-test.bin>"; exit 1; }
    mkdir -p $BAK; cp -a $CONF $BAK/limine.conf.before-try-$(date +%Y%m%d-%H%M%S)
    bash $BB install $LOADER
    # install copies the old boot.bin over boot-stock.bin; the loader falls back to boot-stock.bin, so put the true stock back
    cp $E/boot-stock.bin.bak-r62y $E/boot-stock.bin.new && sync -f $E/boot-stock.bin.new && mv -f $E/boot-stock.bin.new $E/boot-stock.bin
    [ "$(sha256sum $E/boot-stock.bin | cut -c1-16)" = 8166bf503562e46c ] || { echo 'boot-stock.bin is not the true stock'; exit 1; }
    bash $BB test "$2"
    sed -i 's/^default_entry:.*/default_entry: 3/' $CONF
    limine-enroll-config >/dev/null
    grep -n '^default_entry' $CONF
    bash $BB flag set
    bash $BB status ;;
restore)
    bash $BB flag clear || true
    bash $BB persist $GOOD
    bash $H/install-s2r.sh
    bash $BB status ;;
*) echo "usage: $0 arm <boot-test.bin> | restore"; exit 1 ;;
esac
