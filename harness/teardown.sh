#!/bin/bash
# Remove the deep idle test harness. Keeps: the 11.35 modules (.keep) and the cleanup drop-in that protects
# them, the results (/var/lib/deepidle/results, run1), and every boot.bin on the ESP.
# Run as: pkexec bash ~/Work/deepidle-harness/teardown.sh   (or sudo in a terminal)
set -u
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
systemctl disable --now deepidle-runner.service deepidle-early-restore.service 2>/dev/null
rm -f /etc/systemd/system/deepidle-runner.service /etc/systemd/system/deepidle-early-restore.service
rm -f /etc/systemd/system.conf.d/90-deepidle-watchdog.conf
rm -f /etc/modprobe.d/deepidle-no-pmp.conf
rm -f /var/lib/deepidle/plan /var/lib/deepidle/boot.bin.stock
rm -rf /usr/local/lib/deepidle
rm -f /etc/sudoers.d/90-deepidle-harness   # the harness-only passwordless sudo rule
# The test kernel: GRUB entries, image, initramfs, modules.
rm -f /etc/grub.d/43_deepidle /boot/vmlinuz-deepidle-test /boot/initramfs-deepidle-test.img
rm -rf /usr/lib/modules/7.1.12-2-11.35-sep-ARCH-deepidle
grub-editenv /boot/grub/grubenv unset next_entry
grub-mkconfig -o /boot/grub/grub.cfg
systemctl daemon-reload
# The user-side resume hook.
sed -i -e '\|deepidle-resume|d' -e '/^-- Deep idle testing: reopen the Claude session/d' /home/jjr/.config/hypr/autostart.lua
rm -f /home/jjr/.local/bin/deepidle-resume /home/jjr/.local/state/deepidle/resume
# The after-boot headless hook (agent headless mode back on after every boot).
sed -i -e '\|deepidle-headless-boot|d' -e '/^-- Deep idle testing: agent headless mode back on/d' -e '/^-- ~\/.local\/state\/deepidle\/headless-on-boot exists/d' /home/jjr/.config/hypr/autostart.lua
rm -f /home/jjr/.local/bin/deepidle-headless-boot /home/jjr/.local/state/deepidle/headless-on-boot
echo "Harness removed. Still to do, when you want: remove the LUKS keyfile slot:"
echo "  cryptsetup luksRemoveKey /dev/nvme0n1p5 /crypto_keyfile.bin"
echo "  rm /crypto_keyfile.bin /etc/mkinitcpio.conf.d/deepidle-keyfile.conf && mkinitcpio -P"
