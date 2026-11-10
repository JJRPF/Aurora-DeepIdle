#!/bin/bash
# GH-5: lets main's LUKS root unlock without the passphrase, so an unattended test cycle (or a crash
# reset) that lands back on main does not stop at the unlock prompt. The old install had the same
# thing (/crypto_keyfile.bin, worklog 2026-10-15); this install uses sd-encrypt, so the key goes to
# /etc/cryptsetup-keys.d/root.key, which systemd-cryptsetup tries first for the volume "root".
#   sudo bash luks-autounlock.sh add      random key in its own keyslot and in main's initramfs/UKI
#                                         (cryptsetup asks for the current passphrase once)
#   sudo bash luks-autounlock.sh remove   remove the keyslot, the key file and the initramfs entry
#   sudo bash luks-autounlock.sh status
# SECURITY: while added, the key sits inside the UKI on the unencrypted ESP. Anyone holding the Mac
# can read the disk. Run "remove" when the unattended work is over. The passphrase keyslot is never touched.
# It rebuilds main's UKI (limine-mkinitcpio), which is main's boot chain: run it only as the owner,
# and reboot main once while at the Mac afterwards.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
H=$(cd "$(dirname "$0")" && pwd)
UUID=$(awk '$1=="root"{sub("UUID=","",$2);print $2}' /etc/crypttab)
DEV=/dev/disk/by-uuid/$UUID
KEY=/etc/cryptsetup-keys.d/root.key
CONF=/etc/mkinitcpio.conf.d/zz-deepidle-keyfile.conf
UKI=/boot/efi/EFI/Linux/omarchy_linux-aurora.efi
[ -b "$DEV" ] || { echo "LUKS device for 'root' not found ($DEV)"; exit 1; }
inuki() { local t; t=$(mktemp); objcopy -O binary -j .initrd "$UKI" "$t" 2>/dev/null; lsinitcpio "$t" 2>/dev/null | grep -c 'cryptsetup-keys.d/root.key' || true; rm -f "$t"; }
rebuild() {
    echo "rebuilding main's UKI (limine-mkinitcpio) ..."
    limine-mkinitcpio > /var/lib/deepidle/limine-mkinitcpio.log 2>&1 || { echo "limine-mkinitcpio failed, see /var/lib/deepidle/limine-mkinitcpio.log"; exit 1; }
    # limine-entry-tool rewrites limine.conf: put the one-shot DeepTest entry back if its UKI is there
    [ -e /boot/efi/EFI/Linux/deeptest.efi ] && bash "$H/install-limine.sh" /boot/efi/EFI/Linux/deeptest.efi >/dev/null && echo "DeepTest entry re-added"
}
case "${1:-status}" in
add)
    mkdir -p /var/lib/deepidle; install -d -m 700 /etc/cryptsetup-keys.d
    if [ ! -s "$KEY" ]; then ( umask 077; dd if=/dev/urandom of="$KEY" bs=64 count=1 status=none ); fi
    chmod 400 "$KEY"
    if cryptsetup open --test-passphrase --key-file "$KEY" "$DEV" 2>/dev/null; then
        echo "the key already opens $DEV"
    else
        echo "Adding a keyslot to $DEV. Type the CURRENT disk passphrase when asked:"
        cryptsetup luksAddKey "$DEV" "$KEY"
        cryptsetup open --test-passphrase --key-file "$KEY" "$DEV" || { echo "the new key does not open the disk; nothing else changed"; exit 1; }
    fi
    printf '# GH-5 unattended test cycles: main unlocks its root by itself (luks-autounlock.sh)\nFILES+=(%s)\n' "$KEY" > "$CONF"
    rebuild
    [ "$(inuki)" -ge 1 ] || { echo "the key is NOT in the new UKI; main will still ask for the passphrase"; exit 1; }
    echo "done: the key opens $DEV and is in $UKI. Reboot main once while at the Mac to confirm."
    ;;
remove)
    [ -s "$KEY" ] && cryptsetup luksRemoveKey "$DEV" "$KEY" && echo "keyslot removed"
    rm -f "$KEY" "$CONF"
    rebuild
    [ "$(inuki)" = 0 ] && echo "done: the key is gone from the UKI"
    ;;
status)
    echo "device: $DEV"
    cryptsetup luksDump "$DEV" | awk '/^Keyslots:/{k=1} /^Tokens:/{k=0} k&&/^  [0-9]+: /{n++} END{print "keyslots in use: " n}'
    [ -s "$KEY" ] && { cryptsetup open --test-passphrase --key-file "$KEY" "$DEV" 2>/dev/null && echo "key file: opens the disk" || echo "key file: present, does NOT open the disk"; } || echo "key file: none"
    [ -e "$CONF" ] && echo "mkinitcpio drop-in: present" || echo "mkinitcpio drop-in: none"
    echo "key in the installed UKI: $(inuki)"
    ;;
*) echo "usage: $0 add|remove|status"; exit 1 ;;
esac
