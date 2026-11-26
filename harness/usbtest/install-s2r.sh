#!/bin/bash
# GH-5: makes the S2R kernel the default Limine entry, and keeps it so. Idempotent.
# limine-entry-tool regenerates limine.conf on kernel/bootloader package updates and drops this entry and
# default_entry; the pacman hook 99-deepidle-s2r-default.hook reruns this script afterwards.
#   sudo bash install-s2r.sh            (re)install the /OmarchyS2R entry and default_entry
#   sudo bash install-s2r.sh status
# The entry's UKI is /boot/efi/EFI/Linux/omarchy_linux-aurora-s2r.efi (kernel 7.3.0-s2r73+, aop.sleep_ap_idle=3
# mem_sleep_default=deep). Stock Omarchy stays below it as the fallback. This script never touches boot.bin.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
ESP=/boot/efi; CONF=$ESP/limine.conf; UKI=$ESP/EFI/Linux/omarchy_linux-aurora-s2r.efi; BAK=/var/lib/deepidle/limine-backup
KVER=7.3.0-s2r73+
mkdir -p "$BAK"
[ -e "$UKI" ] || { echo "no S2R UKI at $UKI"; exit 1; }
H=$(b2sum "$UKI" | cut -d' ' -f1)
if [ "${1:-}" = status ]; then
    grep -n 'default_entry\|OmarchyS2R' "$CONF"; echo "UKI b2sum ${H:0:16}"; grep -c "#$H" "$CONF" | sed 's/^/entries with the current hash: /'; exit 0
fi
[ -d /usr/lib/modules/$KVER ] || { echo "modules for $KVER missing"; exit 1; }
touch /usr/lib/modules/$KVER/.keep     # linux-modules-cleanup must never move these aside
cp -a "$CONF" "$BAK/limine.conf.before-s2r-$(date +%Y%m%d-%H%M%S)"
python3 - "$CONF" "$H" <<'PY'
import sys, re
p, h = sys.argv[1], sys.argv[2]
L = open(p).read().split('\n')
out = []; i = 0
while i < len(L):                               # drop any existing S2R entry
    if L[i].strip() == '/OmarchyS2R':
        i += 1
        while i < len(L) and (L[i].startswith(' ') or L[i].startswith('# --- OmarchyS2R')):
            i += 1
        continue
    if L[i].startswith('# --- OmarchyS2R'):
        i += 1; continue
    out.append(L[i]); i += 1
first = next(k for k, l in enumerate(out) if l.startswith('/'))
block = ['/OmarchyS2R', '  comment: Omarchy 7.3.0-s2r73+ (GH-5 S2R)', '  protocol: efi',
         f'  path: boot():/EFI/Linux/omarchy_linux-aurora-s2r.efi#{h}', '# --- OmarchyS2R end', '']
out[first:first] = block
txt = '\n'.join(out)
txt = re.sub(r'(?m)^default_entry:.*\n', '', txt)
txt = re.sub(r'(?m)^(timeout:.*\n)', r'\1default_entry: 1\n', txt, count=1) if re.search(r'(?m)^timeout:', txt) else 'default_entry: 1\n' + txt
open(p, 'w').write(re.sub(r'\n{3,}', '\n\n', txt).rstrip('\n') + '\n')
PY
limine-enroll-config >/dev/null
grep -q "#$H" "$CONF" && grep -q '^default_entry: 1' "$CONF" || { echo "install failed, restoring"; cp -a "$(ls -t $BAK/limine.conf.before-s2r-* | head -1)" "$CONF"; limine-enroll-config >/dev/null; exit 1; }
echo "S2R default entry installed (UKI ${H:0:16})"
