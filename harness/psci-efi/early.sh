#!/bin/bash
# PSCI-via-EFI test boot, very early: note which m1n1/Aura image booted, then put the stock one back
# so any later boot (watchdog reset, power cycle) is the normal one. Runs only while armed.
STOCK=/var/lib/deepidle/boot.bin.default
STOCK_SHA=76f850895fed53d1
# The test kernel finds the NVMe late; fstab's 5 s device timeout then gives up on /boot (nofail). Wait for it here.
if ! findmnt -n /boot >/dev/null; then
    for i in $(seq 90); do [ -e /dev/disk/by-uuid/6407-ED7C ] && break; sleep 1; done
    mount /boot || { echo "no /boot after ${i}s"; exit 0; }
    echo "mounted /boot after ${i}s"
fi
# Once per boot: a second run would read the image restored by the first and record that instead
[ -e /run/psci-efi-booted-sha ] && { echo "already ran this boot ($(cat /run/psci-efi-booted-sha))"; exit 0; }
sha=$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)
echo "$sha" > /run/psci-efi-booted-sha
if [ "$sha" != "$STOCK_SHA" ] && [ "$(sha256sum $STOCK | cut -c1-16)" = "$STOCK_SHA" ]; then
    cp $STOCK /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync
fi
grub-editenv /boot/grub/grubenv unset next_entry
exit 0
