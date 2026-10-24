#!/bin/bash
# Build hv-testvol-recovery.sh: Aura as the custom boot object of the macOSTest volume (14.8.3),
# run by the owner in macOSTest's paired recoveryOS. Embeds aura.bin with its sha256.
#   make-recovery.sh <aura.bin> <out.sh>
set -eu
IMG=$1 OUT=$2
SHA=$(sha256sum "$IMG" | cut -d' ' -f1)
DESC=$(git -C "$(dirname "$IMG")/.." describe --always --dirty 2>/dev/null || echo unknown)
{
cat <<EOF
#!/bin/sh
# Aura as the custom boot object of the "macOSTest" volume, for the hypervisor sleep trace
# (Aurora-DeepIdle docs/s2r-plan.md Phase 3; the steps of Asahi's m1n1-hypervisor guide).
# Run in macOSTest's own (paired) recoveryOS. It only ever targets macOSTest with macOS 14.8.3;
# Macintosh HD and the Linux entry (omarchy) are never touched. Aura $DESC, sha256 $SHA.
set -e
NAME=macOSTest
WANT=14.8.3
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
grep -q ': Paired' /tmp/bp.txt || {
    echo "This is not \$NAME's own recoveryOS. Restart into \$NAME, set it as the startup disk"
    echo "(System Settings > General > Startup Disk), shut down, hold the power key, choose Options."
    echo "Stopping, nothing changed."; exit 1; }
T=/tmp/aura-hv
mkdir -p \$T
base64 -D -o \$T/aura.bin <<'EOF_AURA'
EOF
base64 -w 76 "$IMG"
cat <<EOF
EOF_AURA
got=\$( (shasum -a 256 \$T/aura.bin 2>/dev/null || openssl dgst -sha256 -r \$T/aura.bin) | cut -d' ' -f1)
[ "\$got" = "$SHA" ] || { echo "aura.bin checksum mismatch (\$got): stopping, nothing changed."; exit 1; }
echo
echo "Target: \$V (macOS \$ver, volume group \$VGID, paired recoveryOS)."
echo "Image: aura.bin \$(wc -c < \$T/aura.bin | tr -d ' ') bytes, checksum OK."
echo "Three steps, each asks for the \$NAME admin user and password:"
echo "  1. bputil -nkcas: reduced security for \$NAME only (custom kernel, kexts, no CTRR/SSV)"
echo "  2. csrutil disable: SIP off for \$NAME (bputil turns it back on)"
echo "  3. kmutil configure-boot: \$NAME boots Aura (proxy mode, waiting for the Pi) instead of macOS"
printf "Type yes to continue: "
read a < /dev/tty
[ "\$a" = yes ] || { echo "cancelled, nothing changed."; exit 1; }
until bputil -nkcas -v "\$VGID"; do
    printf "bputil failed (wrong password?). Enter to retry, q to stop: "; read a < /dev/tty
    [ "\$a" = q ] && exit 1
done
csrutil disable || echo "csrutil disable failed: note its message for Claude, continuing."
until kmutil configure-boot -c \$T/aura.bin --raw --entry-point 2048 --lowest-virtual-address 0 -v "\$V"; do
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
