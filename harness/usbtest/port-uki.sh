#!/bin/bash
# GH-5: UKI of the sleep.c port kernel (~/Work/src/linux-port, release 7.3.0-port+). Never touches the S2R UKI or its modules.
#   sudo bash port-uki.sh        modules_install, initramfs (the system's mkinitcpio config), UKI on the ESP
# The cmdline is the S2R UKI's (stock Omarchy). The UKI is booted once through aura-main-try.sh armport.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
SRC=${SRC:-/home/jjr/Work/src/linux-port}
KREL=$(cat $SRC/include/config/kernel.release)
[ "$KREL" = 7.3.0-port+ ] || { echo "kernel.release is $KREL, not 7.3.0-port+ (would clash with the S2R modules)"; exit 1; }
OUT=/boot/efi/EFI/Linux/omarchy_linux-aurora-port.efi
CMD=$(objcopy -O binary --only-section=.cmdline /boot/efi/EFI/Linux/omarchy_linux-aurora-s2r.efi /dev/stdout | tr -d '\0')
T=$(mktemp -d)
make -C "$SRC" LLVM=1 -j10 modules_install INSTALL_MOD_STRIP=1 >/dev/null
depmod "$KREL"
touch /usr/lib/modules/$KREL/.keep
mkinitcpio -k "$KREL" -g "$T/initramfs.img" 2>&1 | grep -iE "error|warning: no|Image generation" || true
[ -s "$T/initramfs.img" ] || { echo "initramfs failed"; exit 1; }
ukify build --linux "$SRC/arch/arm64/boot/Image" --initrd "$T/initramfs.img" --cmdline "$CMD" --uname "$KREL" --output "$T/port.efi" 2>&1 | tail -1
OLD=$(stat -c %s "$OUT" 2>/dev/null || echo 0)
# the previous port UKI is replaced, so its space counts; it is only ever a one-shot test entry
[ $(stat -c %s "$T/port.efi") -lt $(( $(df --output=avail -B1 /boot/efi | tail -1) + OLD )) ] || { echo "UKI too big for the ESP"; exit 1; }
rm -f "$OUT"
cp "$T/port.efi" "$OUT" && sync -f "$OUT"
rm -rf "$T"
echo "port UKI $(b2sum $OUT | cut -c1-16), kernel $KREL"
