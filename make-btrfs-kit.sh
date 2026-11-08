#!/bin/sh
# make-btrfs-kit.sh — run on macOS (same Mac).
# Builds a self-contained btrfs-progs kit (Alpine arm64 binaries + their libs
# + the musl loader) and copies it, with rescue.sh, to the Asahi ESP.
# Writes only to the ESP. Override the ESP with: ESP_DEV=disk0s4 ./make-btrfs-kit.sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d /tmp/btrfs-kit.XXXXXX)
KIT="$WORK/btrfs-kit"
mkdir -p "$KIT"

# --- 1. Build inside an arm64 Alpine container -------------------------------
cat > "$KIT/.build.sh" <<'EOF'
set -e
apk add -q btrfs-progs
apk add -q btrfs-progs-extra 2>/dev/null || true   # btrfs-find-root etc., if split out
for b in /usr/bin/btrfs* /usr/sbin/btrfs* /sbin/btrfs* /bin/btrfs*; do
  [ -f "$b" ] && cp "$b" /out/
done
for b in /out/btrfs*; do ldd "$b" 2>/dev/null | awk '/=>/{print $3}'; done \
  | sort -u | while read -r l; do [ -n "$l" ] && cp -L "$l" /out/; done
cp -L /lib/ld-musl-aarch64.so.1 /out/
/out/btrfs --version > /out/VERSION
EOF

if command -v docker >/dev/null 2>&1; then
  docker run --rm --platform linux/arm64 -v "$KIT:/out" alpine sh /out/.build.sh
elif command -v podman >/dev/null 2>&1; then
  podman run --rm --arch arm64 -v "$KIT:/out" alpine sh /out/.build.sh
elif command -v container >/dev/null 2>&1; then
  container run --rm --volume "$KIT:/out" alpine sh /out/.build.sh
else
  echo "No docker, podman or Apple 'container' found. Install one (OrbStack is quickest)." >&2
  exit 1
fi
rm -f "$KIT/.build.sh"

[ -x "$KIT/btrfs" ] || { echo "Build failed: no btrfs binary in kit" >&2; exit 1; }
echo "Kit built: $(cat "$KIT/VERSION")"
ls "$KIT"

cp "$HERE/rescue.sh" "$KIT/rescue.sh"

# --- 2. Find and mount the Asahi ESP ----------------------------------------
if [ -z "${ESP_DEV:-}" ]; then
  ESP_DEV=$(diskutil list | awk '/EFI - OMARC/ {print $NF}' | head -n1)
fi
if [ -z "$ESP_DEV" ]; then
  echo "Could not find the 'EFI - OMARC' partition. Run 'diskutil list' and rerun with ESP_DEV=diskXsY." >&2
  exit 1
fi
echo "Using ESP: $ESP_DEV"

diskutil mount "$ESP_DEV" >/dev/null
MP=$(diskutil info "$ESP_DEV" | sed -n 's/^ *Mount Point: *//p')
[ -n "$MP" ] && [ -d "$MP" ] || { echo "ESP did not mount" >&2; exit 1; }

# --- 3. Copy -----------------------------------------------------------------
SUDO=""
[ -w "$MP" ] || SUDO="sudo"
$SUDO rm -rf "$MP/btrfs-kit"
$SUDO cp -R "$KIT" "$MP/btrfs-kit"
sync
echo "Copied to $MP/btrfs-kit ($(du -sh "$MP/btrfs-kit" | cut -f1))"
diskutil unmount "$ESP_DEV" >/dev/null
rm -rf "$WORK"

cat <<EOF

Done. Reboot into Linux. In the emergency shell:

  mkdir -p /esp && mount -o ro /dev/nvme0n1p4 /esp
  sh /esp/btrfs-kit/rescue.sh

EOF
