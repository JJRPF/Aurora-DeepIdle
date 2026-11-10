#!/bin/bash
# GH-5: the boot.bin side of a DeepTest run. A test boot.bin (Aura, device tree, U-Boot) must never stay in
# place: it runs before any watchdog, on every boot. So the ESP's m1n1/boot.bin is a one-shot loader instead:
# the stock stage 2 source plus one patch (patches/psci-efi/selector). With PMU scratch byte 0x6010 = 0xa5 it
# clears the byte, starts the watchdog (120 s) and chainloads m1n1/boot-test.bin; without it, it boots as the
# stock image does. A test chain that hangs is reset by the watchdog and the next boot is the normal one.
#   sudo bash bootbin.sh status
#   sudo bash bootbin.sh install <loader boot.bin>   keeps the stock file as m1n1/boot-stock.bin
#   sudo bash bootbin.sh restore                      stock boot.bin back
#   sudo bash bootbin.sh test <boot-test.bin>         stage a test image (not used until the flag is set)
#   sudo bash bootbin.sh flag get|set|clear
# update-m1n1 (kernel or bootloader package updates) rewrites boot.bin with the stock image: run install again.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
E=/boot/efi/m1n1; S=/var/lib/deepidle/bootbin; NV=/sys/bus/nvmem/devices/spmi_nvmem2/nvmem; REG=$((0x6010))
mkdir -p $S
sha() { sha256sum "$1" | cut -c1-64; }
die() { echo "bootbin: $*" >&2; exit 1; }
put() { # put <src> <dst>: copy, flush, compare, then rename over the target
    cp "$1" "$2.new"; sync -f "$2.new"; [ "$(sha "$1")" = "$(sha "$2.new")" ] || { rm -f "$2.new"; die "copy of $1 does not match"; }
    mv -f "$2.new" "$2"; sync -f "$2"; [ "$(sha "$1")" = "$(sha "$2")" ] || die "$2 does not match after the rename"; }
flag_get() { dd if=$NV bs=1 skip=$REG count=1 2>/dev/null | xxd -p; }
flag_put() { printf "\\x$1" | dd of=$NV bs=1 seek=$REG count=1 conv=notrunc 2>/dev/null; [ "$(flag_get)" = "$1" ] || die "PMU flag did not take"; }
is_loader() { [ -s $S/loader.sha256 ] && [ "$(sha $E/boot.bin)" = "$(cat $S/loader.sha256)" ]; }
case "${1:-status}" in
status)
    echo "boot.bin        $(sha $E/boot.bin | cut -c1-16) $(is_loader && echo '(one-shot loader)' || echo '(not the loader)')"
    [ -e $E/boot-stock.bin ] && echo "boot-stock.bin  $(sha $E/boot-stock.bin | cut -c1-16)"
    [ -e $E/boot-test.bin ] && echo "boot-test.bin   $(sha $E/boot-test.bin | cut -c1-16)"
    echo "PMU flag        $(flag_get) (a5 = the next boot is a test boot)"
    echo "booted with     stage 2 $(tr -d '\0' < /proc/device-tree/chosen/asahi,m1n1-stage2-version 2>/dev/null), u-boot $(tr -d '\0' < /proc/device-tree/chosen/u-boot,version 2>/dev/null | cut -c1-40)" ;;
install)
    [ -s "${2:-}" ] || die "install <loader boot.bin>"
    strings "$2" | grep -q 'oneshot: flag was set' || die "$2 is not a one-shot loader image"
    [ "$(flag_get)" = 00 ] || die "the PMU flag is set: clear it first"
    is_loader || put $E/boot.bin $E/boot-stock.bin
    sha "$2" > $S/loader.sha256
    put "$2" $E/boot.bin
    echo "bootbin: loader installed ($(sha $E/boot.bin | cut -c1-16)), stock kept as boot-stock.bin ($(sha $E/boot-stock.bin | cut -c1-16))" ;;
restore)
    [ -s $E/boot-stock.bin ] || die "no boot-stock.bin"
    flag_put 00; put $E/boot-stock.bin $E/boot.bin; rm -f $S/loader.sha256
    echo "bootbin: stock boot.bin restored" ;;
test)
    [ -s "${2:-}" ] || die "test <boot-test.bin>"
    put "$2" $E/boot-test.bin; echo "bootbin: test image staged ($(sha $E/boot-test.bin | cut -c1-16))" ;;
flag)
    case "${2:-get}" in get) flag_get ;; clear) flag_put 00; echo "bootbin: flag clear" ;;
    set) is_loader || die "boot.bin is not the loader: the flag would do nothing"; [ -s $E/boot-test.bin ] || die "no boot-test.bin staged"; flag_put a5; echo "bootbin: flag set" ;;
    *) die "flag get|set|clear" ;; esac ;;
*) die "status | install <file> | restore | test <file> | flag get|set|clear" ;;
esac
