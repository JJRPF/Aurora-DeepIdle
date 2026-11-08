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
#!/bin/sh
# rescue.sh — run in the initramfs emergency shell (busybox sh).
#   scan                     superblock + find-root candidates            (read-only)
#   check <bytenr>           btrfs check --readonly --tree-root <bytenr>  (read-only)
#   owner <bytenr>           which tree a block belongs to                (read-only)
#   save                     copy the 3 superblocks + logs to the ESP     (writes ESP only)
#   fix <root> <gen> <level> point the PRIMARY superblock at another tree root (asks YES)
#   undo                     put the saved primary superblock back        (asks YES)
#   mount                    mount -o ro,rescue=all on /new_root          (read-only)
DEV=/dev/mapper/root
SRC=$(cd "$(dirname "$0")" && pwd)
ESP=$(dirname "$SRC")
BK="$ESP/sb-backup"
B=/tmp/b
OUT=/tmp/rescue
WANT_SB=88553

mkdir -p "$B" "$OUT"
[ -x "$B/btrfs-sb-mod" ] || { cp "$SRC"/* "$B"/ && chmod +x "$B"/btrfs* "$B"/ld-musl-aarch64.so.1; }

run() { prog=$1; shift; "$B/ld-musl-aarch64.so.1" --library-path "$B" "$B/$prog" "$@"; }
confirm() { printf '%s\nType YES to continue: ' "$1"; read -r ans; [ "$ans" = "YES" ] || { echo "Stopped, nothing written."; exit 1; }; }
esp_rw() { mount -o remount,rw "$ESP" || { echo "Cannot remount $ESP rw"; exit 1; }; }
esp_ro() { sync; mount -o remount,ro "$ESP"; }
sbsum() { run btrfs inspect-internal dump-super "$DEV" 2>&1 | grep -E '^(generation|root[[:space:]]|root_level)'; }

if [ ! -b "$DEV" ]; then
  echo "$DEV is missing. Unlock first:  cryptsetup open /dev/nvme0n1p5 root"
  exit 1
fi
run btrfs --version >/dev/null 2>&1 || { echo "Kit does not run here; photo this screen."; exit 1; }
echo "== kit: $(run btrfs --version 2>&1 | head -n1)"

case "${1:-scan}" in
scan)
  echo "== superblock (full copy in $OUT/super.txt)"
  run btrfs inspect-internal dump-super -fa "$DEV" > "$OUT/super.txt" 2>&1
  grep -E '^(superblock:|generation|root[[:space:]]|root_level|chunk_root[[:space:]])' "$OUT/super.txt" | head -n 20
  echo "== find-root (full output in $OUT/find-root.txt, may take a minute)"
  run btrfs-find-root -a "$DEV" > "$OUT/find-root.txt" 2>&1
  echo "-- candidates newer than the superblock ($WANT_SB):"
  grep -E 'gen: ?885(5[4-9]|[6-9][0-9])' "$OUT/find-root.txt" | sort -u | head -n 25
  ;;
check)
  [ -n "${2:-}" ] || { echo "usage: rescue.sh check <bytenr>"; exit 1; }
  F="$OUT/check-$2.txt"
  echo "== btrfs check --readonly --tree-root $2 (full output in $F)"
  run btrfs check --readonly --tree-root "$2" "$DEV" > "$F" 2>&1
  echo "exit code: $?"
  echo "-- steps:"; grep -nE '^\[[0-9]/8\]' "$F"
  echo "-- transid by block (block wanted found):"
  grep 'parent transid' "$F" | awk '{print $6,$8,$10}' | sort | uniq -c
  echo "-- other messages by type:"
  grep -vE 'transid|^\[[0-9]/8\]' "$F" | sed 's/[0-9]\{3,\}/N/g' | sort | uniq -c | sort -rn | head -n 15
  ;;
owner)
  [ -n "${2:-}" ] || { echo "usage: rescue.sh owner <bytenr>"; exit 1; }
  run btrfs inspect-internal dump-tree -b "$2" "$DEV" 2>/dev/null | grep -E '^(leaf|node) ' | head -n 1
  ;;
save)
  esp_rw
  mkdir -p "$BK"
  dd if="$DEV" of="$BK/sb-primary.bin"   bs=4096 skip=16       count=1 2>/dev/null
  dd if="$DEV" of="$BK/sb-mirror1.bin"   bs=4096 skip=16384    count=1 2>/dev/null
  dd if="$DEV" of="$BK/sb-mirror2.bin"   bs=4096 skip=67108864 count=1 2>/dev/null
  cp "$OUT"/*.txt "$BK"/ 2>/dev/null
  esp_ro
  ls -la "$BK"
  echo "Saved. Primary superblock gen: $(xxd "$BK/sb-primary.bin" | sed -n 5p | cut -c30-39)"
  ;;
fix)
  [ $# -eq 4 ] || { echo "usage: rescue.sh fix <root bytenr> <generation> <root_level>"; exit 1; }
  [ -s "$BK/sb-primary.bin" ] || { echo "No backup in $BK. Run: rescue.sh save"; exit 1; }
  grep -q " $DEV " /proc/mounts && { echo "$DEV is mounted; unmount it first"; exit 1; }
  echo "== now:"; sbsum
  confirm "This rewrites the PRIMARY superblock: root=$2 generation=$3 root_level=$4 (mirrors untouched, undo: rescue.sh undo)."
  run btrfs-sb-mod "$DEV" root "=$2" generation "=$3" root_level "=$4"
  sync
  echo "== after:"; sbsum
  echo "Next (read-only): sh $SRC/rescue.sh mount"
  ;;
undo)
  [ -s "$BK/sb-primary.bin" ] || { echo "No backup in $BK"; exit 1; }
  grep -q " $DEV " /proc/mounts && { echo "$DEV is mounted; unmount it first"; exit 1; }
  confirm "This writes the saved primary superblock back to $DEV."
  dd if="$BK/sb-primary.bin" of="$DEV" bs=4096 seek=16 count=1 2>/dev/null && sync
  sbsum
  ;;
mount)
  mkdir -p /new_root
  if mount -t btrfs -o ro,rescue=all "$DEV" /new_root; then
    echo "== mounted read-only at /new_root"; ls /new_root; df -h /new_root 2>/dev/null
  else
    echo "== mount failed; kernel says:"; dmesg | grep -i btrfs | tail -n 15
  fi
  ;;
*)
  sed -n 2,10p "$0"; exit 1 ;;
esac

3. Copy -----------------------------------------------------------------
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
