#!/bin/bash
# GH-5: builds the DeepTest UKI (kernel + the usbtest initramfs + cmdline).
#   sudo bash build-uki.sh [<kernel image> [<kernel release> [<out.efi> [extra cmdline...]]]]
# Defaults: main's stock linux-aurora kernel. The UKI needs nothing from the USB drive.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
H=$(cd "$(dirname "$0")" && pwd)
KIMG=${1:-/boot/vmlinuz-linux-aurora}
KREL=${2:-$(strings "$KIMG" | grep -m1 -oE '^[0-9]+\.[0-9]+\.[0-9]+[^ ]*')}
OUT=${3:-/home/jjr/Work/deepidle-usbtest/deeptest.efi}
shift $(( $# > 3 ? 3 : $# ))
EXTRA="$*"
[ -d "/usr/lib/modules/$KREL" ] || { echo "no modules for $KREL"; exit 1; }
install -Dm644 "$H/initcpio/install/usbtest" /etc/initcpio/install/usbtest
install -Dm644 "$H/initcpio/hooks/usbtest" /etc/initcpio/hooks/usbtest
T=$(mktemp -d)
cat > "$T/mkinitcpio.conf" <<EOF
MODULES=(nvme-apple apple-sart apple-dart dwc3-apple dwc3 phy-apple-atc tps6598x typec uas usb-storage xhci-plat-hcd)
BINARIES=()
FILES=()
HOOKS=(base udev asahi modconf block usbtest)
COMPRESSION="zstd"
EOF
mkinitcpio -c "$T/mkinitcpio.conf" -k "$KREL" -g "$T/initramfs.img" 2>&1 | grep -iE "error|usbtest|successful" || true
[ -s "$T/initramfs.img" ] || { echo "initramfs build failed"; exit 1; }
CMD="root=LABEL=OMARCHY_BOOT usbtest=1 rootdelay=20 loglevel=6 panic=10 net.ifnames=0 zswap.enabled=0 user4k=on $EXTRA"
mkdir -p "$(dirname "$OUT")"
ukify build --linux "$KIMG" --initrd "$T/initramfs.img" --cmdline "$CMD" --uname "$KREL" --output "$OUT" 2>&1 | tail -1
rm -rf "$T"
echo "UKI $OUT: kernel $KREL, $(stat -c %s "$OUT") bytes, sha256 $(sha256sum "$OUT" | cut -c1-16)"
echo "cmdline: $CMD"
