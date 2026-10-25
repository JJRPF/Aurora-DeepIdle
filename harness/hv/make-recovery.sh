#!/bin/bash
# Build hv-testvol-recovery.sh: Aura as the custom boot object of the macOSTest volume (14.8.9),
# run by the owner in macOSTest's paired recoveryOS. Embeds aura.bin with its sha256.
#   make-recovery.sh <aura.bin> <out.sh>
# recoveryOS has no base64, so the script downloads aura.bin (checked by size and the best digest recoveryOS has)
# from the URL given as its argument or $AURA_URL: serve <aura.bin> next to the script, then in
# recoveryOS: curl -fsSL http://<host>/hv-testvol-recovery.sh | sh -s -- http://<host>/aura.bin
set -eu
IMG=$1 OUT=$2
SHA=$(sha256sum "$IMG" | cut -d' ' -f1)
MD5=$(md5sum "$IMG" | cut -d' ' -f1)
CK=$(cksum "$IMG" | cut -d' ' -f1)
SZ=$(wc -c < "$IMG" | tr -d ' ')
DESC=$(git -C "$(dirname "$IMG")/.." describe --always --dirty 2>/dev/null || echo unknown)
{
cat <<EOF
#!/bin/sh
# Aura as the custom boot object of the "macOSTest" volume, for the hypervisor sleep trace
# (Aurora-DeepIdle docs/s2r-plan.md Phase 3; the steps of Asahi's m1n1-hypervisor guide).
# Run in macOSTest's own (paired) recoveryOS. It only ever targets macOSTest with macOS 14.8.9;
# Macintosh HD and the Linux entry (omarchy) are never touched. Aura $DESC, sha256 $SHA.
set -e
# recoveryOS ships a small toolset (no base64, no shasum or openssl): report the state of every tool
# first, before any check or change. Only the tools the steps cannot do without are fatal.
miss=
for t in plutil diskutil bputil csrutil kmutil curl grep cut tr wc mkdir; do
    if command -v \$t > /dev/null 2>&1; then echo "  ok       \$t"; else echo "  MISSING  \$t"; miss="\$miss \$t"; fi
done
SUM=size
for t in shasum openssl md5 cksum; do
    if command -v \$t > /dev/null 2>&1; then echo "  ok       \$t (image check)"; [ \$SUM = size ] && SUM=\$t
    else echo "  absent   \$t (image check)"; fi
done
echo "image check: \$SUM"
[ -z "\$miss" ] || { echo "recoveryOS lacks:\$miss"; echo "Stopping, nothing changed. Send these lines back."; exit 1; }
NAME=macOSTest
WANT=14.8.9
V="/Volumes/\$NAME"
P="\$V/System/Library/CoreServices/SystemVersion.plist"
[ -f "\$P" ] || { echo "\$NAME is not mounted. Open Disk Utility, mount \$NAME, then run this again."; exit 1; }
ver=\$(plutil -extract ProductVersion raw "\$P")
[ "\$ver" = "\$WANT" ] || { echo "\$NAME has macOS \$ver, not \$WANT: stopping, nothing changed."; exit 1; }
diskutil info -plist "\$V" > /tmp/vi.plist
VGID=\$(plutil -extract APFSVolumeGroupID raw /tmp/vi.plist)
case "\$VGID" in
63C812F7-0F7D-4358-903C-D2257F942E56|"") echo "unexpected volume group '\$VGID': stopping, nothing changed."; exit 1 ;;
esac
bputil -d -v "\$VGID" > /tmp/bp.txt
if ! grep -q ': Paired' /tmp/bp.txt; then
    echo
    echo "This may not be \$NAME's own recoveryOS (no ': Paired' line in bputil -d). bputil said:"
    sed -n 1,25p /tmp/bp.txt
    echo "--- the recoveryOS you are in was started from:"
    diskutil list | grep -i "recovery\\|\$NAME" || true
    echo "If it is not \$NAME's: set \$NAME as the startup disk (System Settings > General > Startup Disk),"
    echo "shut down, hold the power key, choose Options. If you are sure it is, say yes to go on;"
    echo "bputil itself refuses to change a volume it is not paired with."
    printf "Type yes to go on anyway: "; read a < /dev/tty
    [ "\$a" = yes ] || { echo "Stopping, nothing changed."; exit 1; }
fi
T=/tmp/aura-hv
mkdir -p \$T
URL=\${1:-\${AURA_URL:-}}
[ -n "\$URL" ] || { echo "usage: sh -s -- <url of aura.bin>"; exit 1; }
curl -fsS "\$URL" -o \$T/aura.bin || { echo "cannot download \$URL: stopping, nothing changed."; exit 1; }
case "\$SUM" in
shasum) got=\$(shasum -a 256 \$T/aura.bin | cut -d' ' -f1); want=$SHA ;;
openssl) got=\$(openssl dgst -sha256 -r \$T/aura.bin | cut -d' ' -f1); want=$SHA ;;
md5) got=\$(md5 -q \$T/aura.bin); want=$MD5 ;;
cksum) got=\$(cksum \$T/aura.bin | cut -d' ' -f1); want=$CK ;;
*) got=; want= ;;
esac
size=\$(wc -c < \$T/aura.bin | tr -d ' ')
[ "\$size" = "$SZ" ] || { echo "aura.bin is \$size bytes, not $SZ: stopping, nothing changed."; exit 1; }
[ "\$got" = "\$want" ] || { echo "aura.bin \$SUM mismatch (\$got): stopping, nothing changed."; exit 1; }
echo
echo "Target: \$V (macOS \$ver, volume group \$VGID, paired recoveryOS)."
echo "Image: aura.bin \$(wc -c < \$T/aura.bin | tr -d ' ') bytes, size and \$SUM check OK."
echo "Three steps, each asks for the \$NAME admin user and password:"
echo "  1. bputil -nkcas: reduced security for \$NAME only (custom kernel, kexts, no CTRR/SSV)"
echo "  2. csrutil disable: SIP off for \$NAME (bputil turns it back on)"
echo "  3. kmutil configure-boot: \$NAME boots Aura (proxy mode, waiting for the Pi) instead of macOS"
printf "Type yes to continue: "
read a < /dev/tty
[ "\$a" = yes ] || { echo "cancelled, nothing changed."; exit 1; }
until bputil -nkcas -v "\$VGID" < /dev/tty; do
    printf "bputil failed (wrong password?). Enter to retry, q to stop: "; read a < /dev/tty
    [ "\$a" = q ] && exit 1
done
echo "csrutil will ask which installation: choose the number of \$NAME."
csrutil disable < /dev/tty || echo "csrutil disable failed: note its message for Claude, continuing."
until kmutil configure-boot -c \$T/aura.bin --raw --entry-point 2048 --lowest-virtual-address 0 -v "\$V" < /dev/tty; do
    printf "kmutil failed (wrong password?). Enter to retry, q to stop: "; read a < /dev/tty
    [ "\$a" = q ] && exit 1
done
bputil -d -v "\$VGID" > /tmp/bp-after.txt 2>&1 || true
grep -i "custom\|kernel\|ctrr\|sip\|ssv" /tmp/bp-after.txt || true
echo
echo "Done. Set the startup disk back to Linux: Apple menu > Startup Disk, choose omarchy, Restart."
echo "Claude boots macOSTest once from Linux for each hypervisor run (asahi-bless --next)."
EOF
} > "$OUT"
echo "$OUT: $(wc -c < "$OUT") bytes, sha256 $(sha256sum "$OUT" | cut -c1-16), aura $SHA"
