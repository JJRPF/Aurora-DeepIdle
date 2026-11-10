#!/bin/bash
# GH-5: adds a one-shot-only Limine entry "DeepTest" that boots a UKI built from the USB test drive's
# kernel and initramfs (root LABEL=DEEPTEST_ROOT, read-only, tmpfs overlay). default_entry is not touched.
# Usage: sudo bash install-limine.sh <uki.efi> | remove
# The entry is only ever selected with: bootctl set-oneshot DeepTest   (Limine consumes the variable).
# limine-entry-tool regenerates limine.conf on kernel updates and drops this entry; rerun this script.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
ESP=/boot/efi; CONF=$ESP/limine.conf; BAK=/var/lib/deepidle/limine-backup
mkdir -p "$BAK"
strip() { sed -i '/^# --- DeepTest begin/,/^# --- DeepTest end/d' "$CONF"; }
[ -e "$BAK/limine.conf.orig" ] || { cp -a "$CONF" "$BAK/limine.conf.orig"; cp -a $ESP/EFI/limine/limine_aa64.efi "$BAK/limine_aa64.efi.orig"; }
if [ "${1:-}" = remove ]; then
    strip; rm -f $ESP/EFI/Linux/deeptest.efi; limine-enroll-config; echo removed; exit 0
fi
UKI=${1:?uki.efi}
cp "$UKI" $ESP/EFI/Linux/deeptest.efi.tmp && sync && mv $ESP/EFI/Linux/deeptest.efi.tmp $ESP/EFI/Linux/deeptest.efi
H=$(b2sum $ESP/EFI/Linux/deeptest.efi | cut -d' ' -f1)
strip
cat >> "$CONF" <<EOF
# --- DeepTest begin (GH-5, one-shot only)
/DeepTest
  comment: GH-5 USB test root, RAM overlay
  protocol: efi
  path: boot():/EFI/Linux/deeptest.efi#$H
# --- DeepTest end
EOF
limine-enroll-config
echo installed; grep -n "DeepTest" "$CONF"
