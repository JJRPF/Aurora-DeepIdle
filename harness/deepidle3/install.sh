#!/bin/bash
# deepidle3: test kernel + DTB with the PMU RTC alarm (macsmc-rtc alarm on the PMU's alarm
# registers, SPMI peripheral interrupt 2 wired to AIC 724, wakeup source), plus a one-boot
# smoke test (an awake alarm, three rtcwake s2idle cycles).
# Run once as root:  sudo bash ~/Work/deepidle-harness/deepidle3/install.sh
#
# First removes the deepidle2 test kernel (a test artifact; /boot has no room for both).
# Installs, next to the existing kernels (none of the owner's kernels is touched):
#   /boot/vmlinuz-deepidle3-test, /boot/initramfs-deepidle3-test.img,
#   /usr/lib/modules/7.1.12-2-11.35-sep-ARCH-deepidle3 (with .keep), /etc/grub.d/44_deepidle3
#   two one-shot units that run only while /var/lib/deepidle/deepidle3-armed exists:
#     deepidle3-early  puts the stock m1n1 image back at the very start of the test boot
#     deepidle3-smoke  the alarm tests, results in /var/lib/deepidle/results-deepidle3/
# Then arms ONE boot: the m1n1 image with the new J414s DTB and GRUB next_entry.
# The default GRUB entry is unchanged; any later boot is the normal one.
# Remove: sudo bash ~/Work/deepidle-harness/deepidle3/install.sh remove
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
REL=7.1.12-2-11.35-sep-ARCH-deepidle3
SRC=/home/jjr/Work/deepidle-11.35/staging-deepidle3
H=/home/jjr/Work/deepidle-harness/deepidle3
TESTBIN=/home/jjr/Work/deep-idle-build/boot.bin.rtcalarm2-test
TESTSHA=28fed82d8ec731d1
STOCK=/var/lib/deepidle/boot.bin.stock
STOCKSHA=3630adc3b3be173c

restore_stock() {
    [ "$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)" = $STOCKSHA ] || {
        cp $STOCK /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync; }
}

if [ "${1:-}" = remove ]; then
    rm -f /var/lib/deepidle/deepidle3-armed
    systemctl disable deepidle3-early.service deepidle3-smoke.service 2>/dev/null || true
    rm -f /etc/systemd/system/deepidle3-early.service /etc/systemd/system/deepidle3-smoke.service
    rm -f /usr/local/lib/deepidle/deepidle3-early.sh /usr/local/lib/deepidle/deepidle3-smoke.sh
    rm -f /etc/grub.d/44_deepidle3 /boot/vmlinuz-deepidle3-test /boot/initramfs-deepidle3-test.img
    rm -rf /usr/lib/modules/$REL
    grub-editenv /boot/grub/grubenv unset next_entry
    restore_stock
    grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
    systemctl daemon-reload
    echo "deepidle3 removed; boot.bin $(sha256sum /boot/m1n1/boot.bin | cut -c1-16)"
    exit 0
fi

# Preconditions
[ "$(uname -r)" != 7.1.12-2-11.35-sep-ARCH-deepidle2 ] || { echo "running deepidle2; boot the default first"; exit 1; }
[ -d $SRC/lib/modules/$REL ] && [ -f $SRC/boot/vmlinuz-deepidle3-test ] || { echo "staging missing"; exit 1; }
[ "$(sha256sum $STOCK | cut -c1-16)" = $STOCKSHA ] || { echo "stock boot.bin copy missing or wrong"; exit 1; }
[ "$(sha256sum $TESTBIN | cut -c1-16)" = $TESTSHA ] || { echo "test boot.bin wrong"; exit 1; }
[ "$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)" = $STOCKSHA ] || { echo "ESP boot.bin is not stock; stopping"; exit 1; }
systemctl cat linux-modules-cleanup.service | grep -q keep-pinned || { echo "keep-pinned drop-in missing"; exit 1; }
for d in /usr/lib/modules/*/; do
    [ -e "$d/.keep" ] || pacman -Qoq "$d" >/dev/null 2>&1 || { echo "unprotected module tree $d"; exit 1; }
done

# deepidle2 out (its own remove path; it puts nothing back that deepidle3 needs)
if [ -e /etc/grub.d/44_deepidle2 ] || [ -e /boot/vmlinuz-deepidle2-test ]; then
    bash /home/jjr/Work/deepidle-harness/deepidle2/install.sh remove
fi

# Kernel, modules, initramfs
cp -a $SRC/lib/modules/$REL /usr/lib/modules/
rm -f /usr/lib/modules/$REL/build
chown -R root:root /usr/lib/modules/$REL
touch /usr/lib/modules/$REL/.keep
depmod $REL
install -m 644 $SRC/boot/vmlinuz-deepidle3-test /boot/vmlinuz-deepidle3-test
mkinitcpio -k $REL -g /boot/initramfs-deepidle3-test.img > /var/lib/deepidle/mkinitcpio-deepidle3.log 2>&1 || true
[ -s /boot/initramfs-deepidle3-test.img ] || { echo "initramfs failed, see /var/lib/deepidle/mkinitcpio-deepidle3.log"; exit 1; }

# GRUB entry: copy of the deepidle test entry with the new files (never the default)
sed -e "s/Deep idle test kernel (7.1.12-2-11.35-sep-ARCH-deepidle)/Deep idle 3: PMU RTC alarm ($REL)/" \
    -e 's/--id deepidle-test-kernel/--id deepidle3-test-kernel/' \
    -e 's/vmlinuz-deepidle-test/vmlinuz-deepidle3-test/' -e 's/initramfs-deepidle-test.img/initramfs-deepidle3-test.img/' \
    /etc/grub.d/43_deepidle | awk '/^menuentry .Deep idle DTB test/{exit} {print}' > /etc/grub.d/44_deepidle3
echo "MENU" >> /etc/grub.d/44_deepidle3
chmod 755 /etc/grub.d/44_deepidle3
grub-mkconfig -o /boot/grub/grub.cfg > /var/lib/deepidle/grub-mkconfig-deepidle3.log 2>&1
grep -q "id deepidle3-test-kernel" /boot/grub/grub.cfg || { echo "GRUB entry missing, see log"; exit 1; }

# One-shot units
mkdir -p /usr/local/lib/deepidle
install -m 755 $H/early.sh /usr/local/lib/deepidle/deepidle3-early.sh
install -m 755 $H/smoke.sh /usr/local/lib/deepidle/deepidle3-smoke.sh
install -m 644 $H/deepidle3-early.service $H/deepidle3-smoke.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable deepidle3-early.service deepidle3-smoke.service

# Arm one boot
touch /var/lib/deepidle/deepidle3-armed
cp $TESTBIN /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync
grub-editenv /boot/grub/grubenv set next_entry=deepidle3-test-kernel
echo "armed: boot.bin $(sha256sum /boot/m1n1/boot.bin | cut -c1-16), next_entry deepidle3-test-kernel."
echo "Reboot when ready. Results: /var/lib/deepidle/results-deepidle3/"
