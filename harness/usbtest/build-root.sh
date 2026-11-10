#!/bin/bash
# GH-5: builds the lean DeepTest root in a staging directory on main and packs it as the squashfs image
# that the DeepTest boot copies to RAM (initcpio/hooks/usbtest).
#   sudo bash build-root.sh            pacstrap (first time), configure, pack
#   sudo bash build-root.sh pack       configure and pack only (after changing files under root/)
# Extra kernel module trees: MODS="7.2.11-15-1-ARCH 7.2.11-psci-efi+" (default: the installed linux-aurora).
# Output: $W/root.sfs and root.sfs.sha256. write-usb.sh puts them on the drive.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
H=$(cd "$(dirname "$0")" && pwd)
W=${W:-/home/jjr/Work/deepidle-usbtest}; R=$W/root
MODS=${MODS:-$(strings /boot/vmlinuz-linux-aurora | grep -m1 -oE '^[0-9]+\.[0-9]+\.[0-9]+[^ ]*')}
PKGS="base iwd openssh curl python tinyxxd dtc usbutils pciutils rsync jq nano less strace wireless-regdb"
mkdir -p "$R"
if [ "${1:-}" != pack ] && [ ! -x "$R/usr/bin/bash" ]; then
    pacstrap -c -K "$R" $PKGS
fi
[ -x "$R/usr/bin/bash" ] || { echo "no root in $R"; exit 1; }
# identity, no first-boot prompts
echo deeptest > "$R/etc/hostname"
: > "$R/etc/fstab"
[ -s "$R/etc/machine-id" ] || systemd-machine-id-setup --root="$R" >/dev/null
echo "LANG=C.UTF-8" > "$R/etc/locale.conf"
ln -sf /usr/share/zoneinfo/UTC "$R/etc/localtime"
echo "KEYMAP=us" > "$R/etc/vconsole.conf"
echo 'root:deeptest' | chpasswd -R "$R"
# network: iwd with its own DHCP, the main install's Wi-Fi profiles (owner OK'd 2026-11-09)
mkdir -p "$R/etc/iwd" "$R/var/lib/iwd"
printf '[General]\nEnableNetworkConfiguration=true\n[Network]\nNameResolvingService=systemd\n' > "$R/etc/iwd/main.conf"
cp -a /var/lib/iwd/*.psk "$R/var/lib/iwd/" 2>/dev/null || echo "warning: no iwd profiles copied"
chmod 600 "$R"/var/lib/iwd/*.psk 2>/dev/null || true
ln -sf /run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"
# firmware: this Mac's Wi-Fi/BT and vendor firmware, as main has it
mkdir -p "$R/usr/lib/firmware/vendor"
cp -a /usr/lib/firmware/brcm /usr/lib/firmware/apple "$R/usr/lib/firmware/" 2>/dev/null || true
cp -aL /usr/lib/firmware/vendor/. "$R/usr/lib/firmware/vendor/"
# kernel modules
mkdir -p "$R/usr/lib/modules"
for m in $MODS; do
    [ -d "/usr/lib/modules/$m" ] || { echo "no module tree $m"; exit 1; }
    rsync -a --delete "/usr/lib/modules/$m/" "$R/usr/lib/modules/$m/"
done
# ssh: key logins only, the keys main accepts
mkdir -p "$R/root/.ssh"; chmod 700 "$R/root/.ssh"
cp /home/jjr/.ssh/authorized_keys "$R/root/.ssh/authorized_keys" 2>/dev/null && chmod 600 "$R/root/.ssh/authorized_keys" || true
mkdir -p "$R/etc/ssh/sshd_config.d"
printf 'PasswordAuthentication no\nPermitRootLogin prohibit-password\n' > "$R/etc/ssh/sshd_config.d/10-deeptest.conf"
# watchdog: a userspace hang resets the Mac (as main's 90-deepidle-watchdog.conf did)
mkdir -p "$R/etc/systemd/system.conf.d"
printf '[Manager]\nRuntimeWatchdogSec=60\nRebootWatchdogSec=60\n' > "$R/etc/systemd/system.conf.d/90-deeptest-watchdog.conf"
# the runner
install -Dm755 "$H/root/usbtest-run.sh" "$R/usr/local/lib/deepidle/usbtest-run.sh"
install -Dm644 "$H/root/usbtest-run.service" "$R/etc/systemd/system/usbtest-run.service"
install -Dm644 "$H/root/usbtest-deadline.service" "$R/etc/systemd/system/usbtest-deadline.service"
[ -d "$H/root/tools" ] && { mkdir -p "$R/usr/local/lib/deepidle"; cp -a "$H/root/tools/." "$R/usr/local/lib/deepidle/"; }
systemctl --root="$R" enable iwd systemd-resolved sshd systemd-timesyncd usbtest-run.service usbtest-deadline.service >/dev/null 2>&1
systemctl --root="$R" mask systemd-firstboot.service systemd-homed.service >/dev/null 2>&1 || true
# pack
rm -f "$W/root.sfs" "$W/root.sfs.sha256"
mksquashfs "$R" "$W/root.sfs" -comp zstd -Xcompression-level 12 -noappend -quiet -no-progress \
    -e var/cache/pacman/pkg -e var/lib/pacman/sync
( cd "$W" && sha256sum root.sfs | cut -c1-64 > root.sfs.sha256 )
echo "image $W/root.sfs: $(du -h "$W/root.sfs" | cut -f1), sha256 $(cut -c1-16 "$W/root.sfs.sha256"), modules: $MODS"
