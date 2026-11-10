#!/bin/bash
# GH-5: undo arm.sh without rebooting: remove the Limine one-shot request and the armed flag.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
VAR=/sys/firmware/efi/efivars/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
if [ -e "$VAR" ]; then chattr -i "$VAR" 2>/dev/null || true; rm -f "$VAR"; fi
rm -f /var/lib/deepidle/usbtest/armed
[ -e "$VAR" ] && { echo "disarm: the one-shot is still set"; exit 1; }
echo "disarm: nothing armed"
