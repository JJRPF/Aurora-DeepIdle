#!/bin/bash
# GH-5: arms ONE DeepTest boot (Limine one-shot) and reboots into it. Main stays the default entry, so
# the reboot at the end of the job, a crash, a watchdog or a hand reset all land back on main.
#   sudo bash arm.sh [--no-reboot] [--job <dir>] [--label <text>] [--allow-prompt]
# --job <dir>     job directory copied to the drive (job.sh, deadline, topic, keep); none = the hello job
# --allow-prompt  arm even though main would stop at the LUKS passphrase prompt on the way back
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
H=$(cd "$(dirname "$0")" && pwd)
W=${W:-/home/jjr/Work/deepidle-usbtest}; S=/var/lib/deepidle/usbtest
ESPUKI=/boot/efi/EFI/Linux/deeptest.efi; CONF=/boot/efi/limine.conf
VAR=/sys/firmware/efi/efivars/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
REBOOT=1; JOB=; LABEL=hello; PROMPT_OK=0
while [ $# -gt 0 ]; do case "$1" in
    --no-reboot) REBOOT=0 ;; --job) JOB=$2; shift ;; --label) LABEL=$2; shift ;; --allow-prompt) PROMPT_OK=1 ;;
    *) echo "unknown option $1"; exit 1 ;; esac; shift; done
LABEL=${LABEL// /_}
die() { echo "arm: $*" >&2; exit 1; }
mkdir -p $S
# 1. can main come back by itself?
if ! bash "$H/luks-autounlock.sh" status | grep -q 'key in the installed UKI: [1-9]'; then
    [ $PROMPT_OK = 1 ] || die "main has no auto-unlock key in its UKI: it would wait at the passphrase prompt (use --allow-prompt when someone is at the Mac)"
    echo "arm: note: main will ask for the LUKS passphrase on the way back"
fi
# 2. the image in /boot: present and intact, job in place
[ -s "$W/root.sfs" ] && [ -s "$W/deeptest.efi" ] || die "build the image and the UKI first (build-root.sh, build-uki.sh)"
if [ -n "$JOB" ]; then [ -f "$JOB/job.sh" ] || die "no job.sh in $JOB"; chmod +x "$JOB/job.sh"; bash "$H/write-image.sh" job "$JOB"; else bash "$H/write-image.sh" nojob; fi
# 3. the UKI on the ESP and its Limine entry
ok_entry() { [ -e $ESPUKI ] && [ "$(sha256sum $ESPUKI | cut -c1-64)" = "$(sha256sum "$W/deeptest.efi" | cut -c1-64)" ] \
    && grep -q '^/DeepTest$' $CONF && grep -q "deeptest.efi#$(b2sum $ESPUKI | cut -d' ' -f1)" $CONF; }
ok_entry || bash "$H/install-limine.sh" "$W/deeptest.efi" >/dev/null
ok_entry || die "the DeepTest entry is not in place"
# 4. main is still the default: default_entry 2 = Omarchy/linux-aurora, and DeepTest comes after it
grep -q '^default_entry: 2$' $CONF || die "default_entry is not 2: check $CONF"
[ "$(grep -n '^/DeepTest$' $CONF | cut -d: -f1)" -gt "$(grep -n '^  //linux-aurora' $CONF | head -1 | cut -d: -f1)" ] || die "DeepTest is not after the main entry"
# 5. nothing pending
[ ! -e $VAR ] || die "a one-shot request is already set"
# 6. arm
echo "armed=$(date -Is) epoch=$(date +%s) label=$LABEL job=${JOB:-none} image=$(cut -c1-16 "$W/root.sfs.sha256") uki=$(sha256sum $ESPUKI | cut -c1-16)" > $S/armed
bootctl set-oneshot DeepTest
[ "$(tail -c +5 $VAR | tr -d '\0')" = DeepTest ] || { rm -f $S/armed; die "the one-shot variable did not take"; }
sync
echo "arm: DeepTest armed ($LABEL)"
[ $REBOOT = 1 ] || { echo "arm: not rebooting (--no-reboot); the next reboot goes to DeepTest"; exit 0; }
systemctl reboot
