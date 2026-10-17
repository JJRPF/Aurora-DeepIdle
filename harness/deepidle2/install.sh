#!/bin/bash
# deepidle2: test kernel with the PMP s2idle hook (pmp-sleep.c), plus a one-boot smoke test.
# Run once as root:  sudo bash ~/Work/deepidle-harness/deepidle2/install.sh
#
# Installs, next to the existing kernels (none of them is touched):
#   /boot/vmlinuz-deepidle2-test, /boot/initramfs-deepidle2-test.img,
#   /usr/lib/modules/7.1.12-2-11.35-sep-ARCH-deepidle2 (with .keep), /etc/grub.d/44_deepidle2
#   two one-shot units that run only while /var/lib/deepidle/deepidle2-armed exists:
#     deepidle2-early  puts the stock m1n1 image back at the very start of the test boot
#     deepidle2-smoke  loads pmp, runs 3 s2idle cycles with pm_test=platform, logs results
# Then arms ONE boot: the PMP m1n1 image (boot.bin.pmpfix-test) and GRUB next_entry.
# The default GRUB entry is unchanged; any later boot is the normal one.
# Remove: sudo bash ~/Work/deepidle-harness/deepidle2/install.sh remove
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
REL=7.1.12-2-11.35-sep-ARCH-deepidle2
SRC=/home/jjr/Work/deepidle-11.35/staging-deepidle2
H=/home/jjr/Work/deepidle-harness/deepidle2
PMPBIN=/home/jjr/Work/deep-idle-build/boot.bin.pmpfix-test
PMPSHA=db84dd49f4095e96
STOCK=/var/lib/deepidle/boot.bin.stock
STOCKSHA=3630adc3b3be173c

if [ "${1:-}" = remove ]; then
    rm -f /var/lib/deepidle/deepidle2-armed
    systemctl disable deepidle2-early.service deepidle2-smoke.service 2>/dev/null || true
    rm -f /etc/systemd/system/deepidle2-early.service /etc/systemd/system/deepidle2-smoke.service
    rm -f /usr/local/lib/deepidle/deepidle2-early.sh /usr/local/lib/deepidle/deepidle2-smoke.sh
    rm -f /etc/grub.d/44_deepidle2 /boot/vmlinuz-deepidle2-test /boot/initramfs-deepidle2-test.img
    rm -rf /usr/lib/modules/$REL
    grub-editenv /boot/grub/grubenv unset next_entry
    [ "$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)" = $STOCKSHA ] || {
        cp $STOCK /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync; }
    grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
    systemctl daemon-reload
    echo "deepidle2 removed; boot.bin $(sha256sum /boot/m1n1/boot.bin | cut -c1-16)"
    exit 0
fi

# Preconditions
[ -d $SRC/lib/modules/$REL ] && [ -f $SRC/boot/vmlinuz-deepidle2-test ] || { echo "staging missing"; exit 1; }
[ "$(sha256sum $STOCK | cut -c1-16)" = $STOCKSHA ] || { echo "stock boot.bin copy missing or wrong"; exit 1; }
[ "$(sha256sum $PMPBIN | cut -c1-16)" = $PMPSHA ] || { echo "PMP boot.bin wrong"; exit 1; }
[ "$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)" = $STOCKSHA ] || { echo "ESP boot.bin is not stock; stopping"; exit 1; }
systemctl cat linux-modules-cleanup.service | grep -q keep-pinned || { echo "keep-pinned drop-in missing"; exit 1; }
for d in /usr/lib/modules/*/; do
    [ -e "$d/.keep" ] || pacman -Qoq "$d" >/dev/null 2>&1 || { echo "unprotected module tree $d"; exit 1; }
done

# Kernel, modules, initramfs
cp -a $SRC/lib/modules/$REL /usr/lib/modules/
rm -f /usr/lib/modules/$REL/build
chown -R root:root /usr/lib/modules/$REL
touch /usr/lib/modules/$REL/.keep
depmod $REL
install -m 644 $SRC/boot/vmlinuz-deepidle2-test /boot/vmlinuz-deepidle2-test
mkinitcpio -k $REL -g /boot/initramfs-deepidle2-test.img > /var/lib/deepidle/mkinitcpio-deepidle2.log 2>&1
[ -s /boot/initramfs-deepidle2-test.img ] || { echo "initramfs failed, see /var/lib/deepidle/mkinitcpio-deepidle2.log"; exit 1; }

# GRUB entry: copy of the deepidle test entry with the new files (never the default)
sed -e "s/Deep idle test kernel (7.1.12-2-11.35-sep-ARCH-deepidle)/Deep idle 2: PMP s2idle hook ($REL)/" \
    -e 's/--id deepidle-test-kernel/--id deepidle2-test-kernel/' \
    -e 's/vmlinuz-deepidle-test/vmlinuz-deepidle2-test/' -e 's/initramfs-deepidle-test.img/initramfs-deepidle2-test.img/' \
    /etc/grub.d/43_deepidle | awk '/^menuentry .Deep idle DTB test/{exit} {print}' > /etc/grub.d/44_deepidle2
echo "MENU" >> /etc/grub.d/44_deepidle2
chmod 755 /etc/grub.d/44_deepidle2
grub-mkconfig -o /boot/grub/grub.cfg > /var/lib/deepidle/grub-mkconfig-deepidle2.log 2>&1
grep -q "id deepidle2-test-kernel" /boot/grub/grub.cfg || { echo "GRUB entry missing, see log"; exit 1; }

# One-shot units
mkdir -p /usr/local/lib/deepidle
install -m 755 $H/early.sh /usr/local/lib/deepidle/deepidle2-early.sh
install -m 755 $H/smoke.sh /usr/local/lib/deepidle/deepidle2-smoke.sh
install -m 644 $H/deepidle2-early.service $H/deepidle2-smoke.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable deepidle2-early.service deepidle2-smoke.service

# Arm one boot
touch /var/lib/deepidle/deepidle2-armed
cp $PMPBIN /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync
grub-editenv /boot/grub/grubenv set next_entry=deepidle2-test-kernel
echo "armed: boot.bin $(sha256sum /boot/m1n1/boot.bin | cut -c1-16), next_entry deepidle2-test-kernel."
echo "Reboot when ready (Claude may reboot it). Results: /var/lib/deepidle/results-deepidle2/"
