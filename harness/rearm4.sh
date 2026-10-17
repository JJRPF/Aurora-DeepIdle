#!/bin/bash
# Run 4: the PMP, loaded as a module mid-boot so a boot can only lose it.
# Test kernel rebuilt with CONFIG_APPLE_PMP=m (pmp.ko), autoload blacklisted; the runner measures,
# runs `modprobe pmp`, waits 60 s and measures again in the same boot. boot.bin.pmpfix-test is
# m1n1 with 160K DT headroom and a PMP tunable copy that cannot fail the boot (it enables the PMP
# node only when every tunable fits), plus the J414s DTB with only the pmp alias added.
# Plan: 0 pmpctl (stock image, control: no modprobe), 1 pmpload, 2 pmpload2 (repeat), 3 pmpbusy
# (same under the wake load). A step that hangs after its modprobe stops the campaign.
# Run as: pkexec bash ~/Work/deepidle-harness/rearm4.sh, then reboot.
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
H=/home/jjr/Work/deepidle-harness
W=/home/jjr/Work/deep-idle-build
S=/home/jjr/Work/deepidle-11.35/staging-pmpm
VAR=/var/lib/deepidle
R=7.1.12-2-11.35-sep-ARCH-deepidle
[ "$(sha256sum $W/boot.bin.before-pmp-test | cut -c1-16)" = 3630adc3b3be173c ]
[ "$(sha256sum $W/boot.bin.pmpfix-test | cut -c1-16)" = db84dd49f4095e96 ]
[ "$(sha256sum /boot/m1n1/boot.bin.before-pmp-test | cut -c1-16)" = 3630adc3b3be173c ]
[ -e $S/lib/modules/$R/kernel/drivers/soc/apple/pmp.ko ]
[ "$(uname -r)" != $R ] || { echo "boot the Aurora kernel first: this replaces the test kernel"; exit 1; }
# The test kernel, PMP as a module.
# /boot has ~17M free: overwrite the (non-default) test kernel in place.
cp $S/boot/vmlinuz-deepidle-test /boot/vmlinuz-deepidle-test
cmp $S/boot/vmlinuz-deepidle-test /boot/vmlinuz-deepidle-test
rm -rf /usr/lib/modules/$R
cp -a $S/lib/modules/$R /usr/lib/modules/
chown -R root:root /usr/lib/modules/$R
rm -f /usr/lib/modules/$R/build /usr/lib/modules/$R/source
touch /usr/lib/modules/$R/.keep
depmod $R
echo "blacklist pmp" > /etc/modprobe.d/deepidle-no-pmp.conf
mkinitcpio -k $R -g /boot/initramfs-deepidle-test.img > /home/jjr/Work/deepidle-11.35/mkinitcpio-pmpm.log 2>&1
sync
# The runner (modprobe/control hook) and the plan.
install -m755 $H/runner.sh $H/wakeload /usr/local/lib/deepidle/
mkdir -p $VAR/run3 && mv $VAR/results $VAR/runner.log $VAR/run3/ 2>/dev/null || true
mkdir -p $VAR/results
printf '%s\n' "pmpctl stock deepidle-test-kernel default,pd-always - control" \
    "pmpload pmpfix-test deepidle-test-kernel default,pd-always - modprobe:pmp" \
    "pmpload2 pmpfix-test deepidle-test-kernel default,pd-always - modprobe:pmp" \
    "pmpbusy pmpfix-test deepidle-test-kernel default,pd-always 10:650:15 modprobe:pmp" > $VAR/plan
echo 0 > $VAR/current
rm -f /home/jjr/.local/state/deepidle/ack-* /home/jjr/.local/state/deepidle/stop
sudo -u jjr touch /home/jjr/.local/state/deepidle/resume
grub-editenv /boot/grub/grubenv set next_entry=deepidle-test-kernel
grub-editenv /boot/grub/grubenv list
df -h /boot | tail -1
echo "armed run 4. Reboot; step 0 runs on the test kernel."
