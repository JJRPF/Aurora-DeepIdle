#!/bin/bash
# GH-5: one RAM-root test boot of the sleep.c port (no desktop, no disk mounted): the DeepTest UKI (port kernel, build-uki.sh)
# plus the test boot.bin chain (Aura + sleeptest DTB), as a Limine ONE-SHOT. Main's default entry is never touched, so a hang that the
# 120 s watchdog (bootbin loader) or the job's deadline (sysrq b) resets lands on the normal S2R entry.
#   sudo bash ramtest.sh <boot-test.bin> <job dir>     arm and reboot
#   sudo bash ramtest.sh restore                       after the boot: persistent Aura boot.bin + S2R default again (aura-main-try.sh restore)
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
H=$(cd "$(dirname "$0")" && pwd); BB=$H/bootbin.sh
W=${W:-/home/jjr/Work/deepidle-usbtest}; S=/var/lib/deepidle/usbtest
E=/boot/efi/m1n1; LOADER=$E/boot-loader-oneshot.bin.bak-129
VAR=/sys/firmware/efi/efivars/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
[ "${1:-}" = restore ] && exec bash $H/aura-main-try.sh restore
BIN=${1:?boot-test.bin}; JOB=${2:?job dir}
[ -s "$BIN" ] && [ -f "$JOB/job.sh" ] && [ -s $W/root.sfs ] && [ -s $W/deeptest.efi ] || { echo "missing boot.bin, job.sh, root.sfs or deeptest.efi"; exit 1; }
[ ! -e $VAR ] || { echo "a one-shot request is already set"; exit 1; }
PS=/sys/class/power_supply; [ "$(cat $PS/macsmc-ac/online)" = 1 ] && [ "$(cat $PS/macsmc-battery/capacity)" -ge 50 ] || { echo "AC is not online or the battery is under 50%"; exit 1; }   # the charge cap (80%) reads "Not charging"
mkdir -p $S
chmod +x $JOB/job.sh
bash $H/write-image.sh
bash $H/write-image.sh job "$JOB"
LOGT=/home/jjr/.config/deepidle/ntfy-log-topic
[ -s $LOGT ] && install -m 644 $LOGT /boot/deeptest/job/topic
rm -f /boot/deeptest/failtest; sync
bash $H/install-limine.sh $W/deeptest.efi >/dev/null
sudo grep -q '^/DeepTest$' /boot/efi/limine.conf || { echo "no DeepTest entry"; exit 1; }
bash $BB install $LOADER
cp $E/boot-stock.bin.bak-r62y $E/boot-stock.bin.new && sync -f $E/boot-stock.bin.new && mv -f $E/boot-stock.bin.new $E/boot-stock.bin
[ "$(sha256sum $E/boot-stock.bin | cut -c1-16)" = 8166bf503562e46c ] || { echo 'boot-stock.bin is not the true stock'; exit 1; }
bash $BB test "$BIN"
echo "armed=$(date -Is) epoch=$(date +%s) label=ramtest job=$(basename $JOB) image=$(cut -c1-16 $W/root.sfs.sha256) uki=$(sha256sum /boot/efi/EFI/Linux/deeptest.efi | cut -c1-16) chain=1" > $S/armed
bootctl set-oneshot DeepTest
[ "$(tail -c +5 $VAR | tr -d '\0')" = DeepTest ] || { rm -f $S/armed; echo "the one-shot variable did not take"; exit 1; }
bash $BB flag set
sync
echo "ramtest: armed; rebooting"
systemctl reboot
