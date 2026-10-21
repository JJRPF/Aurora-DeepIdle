#!/bin/bash
# deepidle3 + USB: the same deepidle3 kernel rebuilt with CONFIG_USB4_APPLE_SOC=m.
# Why: the T6020 DT links each cd321x (USB-C port controller) to its USB4 host router
# (cio@...), and the 11.35 config leaves that driver out. With no driver on cio, fw_devlink
# defers the cd321x forever, dwc3 never gets a role and no xHCI bus appears: no USB at all,
# on the stock 11.35/11.32 kernels too. Only change: one config line; the built-in code is
# identical (Image differs only in the embedded config and timestamp), plus
# thunderbolt_apple.ko. Same release name, so it replaces the deepidle3 files in place
# (/boot has no room for a second test kernel). The old Image and initramfs are kept in
# /var/lib/deepidle/deepidle3-nousb4/ for rollback; the old modules stay in staging-deepidle3.
# Then arms ONE boot exactly as install.sh does (rtcalarm2 DTB, next_entry, smoke test).
#   sudo bash ~/Work/deepidle-harness/deepidle3/usb4.sh            install and arm
#   sudo bash ~/Work/deepidle-harness/deepidle3/usb4.sh rollback   put the old files back
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
REL=7.1.12-2-11.35-sep-ARCH-deepidle3
B=/home/jjr/Work/deepidle-11.35
NEW=$B/staging-deepidle3-usb4
OLD=$B/staging-deepidle3
KEEP=/var/lib/deepidle/deepidle3-nousb4
TESTBIN=/home/jjr/Work/deep-idle-build/boot.bin.rtcalarm2-test
TESTSHA=28fed82d8ec731d1
STOCK=/var/lib/deepidle/boot.bin.stock
STOCKSHA=3630adc3b3be173c

put_modules() {  # $1 = staging root
    rm -rf /usr/lib/modules/$REL
    cp -a $1/lib/modules/$REL /usr/lib/modules/
    rm -f /usr/lib/modules/$REL/build
    chown -R root:root /usr/lib/modules/$REL
    touch /usr/lib/modules/$REL/.keep
    depmod $REL
}

if [ "${1:-}" = rollback ]; then
    [ -f $KEEP/vmlinuz-deepidle3-test ] && [ -f $KEEP/initramfs-deepidle3-test.img ] || { echo "no saved files"; exit 1; }
    put_modules $OLD
    cp $KEEP/vmlinuz-deepidle3-test /boot/vmlinuz-deepidle3-test
    cp $KEEP/initramfs-deepidle3-test.img /boot/initramfs-deepidle3-test.img
    sync
    echo "rolled back: vmlinuz $(sha256sum /boot/vmlinuz-deepidle3-test | cut -c1-16)"
    exit 0
fi

# Preconditions
[ -f $NEW/boot/vmlinuz-deepidle3-test ] && [ -f $NEW/lib/modules/$REL/kernel/drivers/thunderbolt/thunderbolt_apple.ko ] \
    || { echo "staging-deepidle3-usb4 missing"; exit 1; }
[ -e /etc/grub.d/44_deepidle3 ] && grep -q "id deepidle3-test-kernel" /boot/grub/grub.cfg || { echo "deepidle3 not installed"; exit 1; }
[ "$(sha256sum $STOCK | cut -c1-16)" = $STOCKSHA ] || { echo "stock boot.bin copy missing or wrong"; exit 1; }
[ "$(sha256sum $TESTBIN | cut -c1-16)" = $TESTSHA ] || { echo "test boot.bin wrong"; exit 1; }
[ "$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)" = $STOCKSHA ] || { echo "ESP boot.bin is not stock; stopping"; exit 1; }

# Keep the current files once (not overwritten by a second run)
if [ ! -f $KEEP/vmlinuz-deepidle3-test ]; then
    mkdir -p $KEEP
    cp /boot/vmlinuz-deepidle3-test /boot/initramfs-deepidle3-test.img $KEEP/
fi

# Modules, initramfs (built off /boot first: it is nearly full), kernel
put_modules $NEW
mkinitcpio -k $REL -g $KEEP/initramfs-usb4.img.new > /var/lib/deepidle/mkinitcpio-deepidle3-usb4.log 2>&1 || true
[ -s $KEEP/initramfs-usb4.img.new ] || { echo "initramfs failed, see /var/lib/deepidle/mkinitcpio-deepidle3-usb4.log"; exit 1; }
cp $KEEP/initramfs-usb4.img.new /boot/initramfs-deepidle3-test.img
rm -f $KEEP/initramfs-usb4.img.new
install -m 644 $NEW/boot/vmlinuz-deepidle3-test /boot/vmlinuz-deepidle3-test
sync
cmp -s $NEW/boot/vmlinuz-deepidle3-test /boot/vmlinuz-deepidle3-test || { echo "vmlinuz copy differs"; exit 1; }

# Previous smoke results moved aside, then arm one boot (same as install.sh)
R=/var/lib/deepidle/results-deepidle3
[ -d $R ] && mv $R $R-before-usb4-$(date +%Y%m%d-%H%M)
touch /var/lib/deepidle/deepidle3-armed
cp $TESTBIN /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync
grub-editenv /boot/grub/grubenv set next_entry=deepidle3-test-kernel
echo "installed: vmlinuz $(sha256sum /boot/vmlinuz-deepidle3-test | cut -c1-16), thunderbolt_apple $(modinfo -k $REL -F vermagic thunderbolt_apple | cut -d' ' -f1)"
echo "armed: boot.bin $(sha256sum /boot/m1n1/boot.bin | cut -c1-16), next_entry deepidle3-test-kernel."
