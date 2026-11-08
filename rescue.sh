#!/bin/sh
# rescue.sh — run in the initramfs emergency shell (busybox sh).
# READ-ONLY: nothing here writes to /dev/mapper/root or the ESP.
#   sh /esp/btrfs-kit/rescue.sh            superblock + find-root candidates
#   sh /esp/btrfs-kit/rescue.sh check N    read-only 'btrfs check --tree-root N'
DEV=/dev/mapper/root
SRC=$(cd "$(dirname "$0")" && pwd)
B=/tmp/b
OUT=/tmp/rescue
WANT_SB=88553

mkdir -p "$B" "$OUT"
[ -x "$B/btrfs" ] || cp "$SRC"/* "$B"/ && chmod +x "$B"/btrfs* "$B"/ld-musl-aarch64.so.1

run() { prog=$1; shift; "$B/ld-musl-aarch64.so.1" --library-path "$B" "$B/$prog" "$@"; }

if [ ! -b "$DEV" ]; then
  echo "$DEV is missing. Unlock first:  cryptsetup open /dev/nvme0n1p5 root"
  exit 1
fi

echo "== kit: $(run btrfs --version 2>&1)"
run btrfs --version >/dev/null 2>&1 || { echo "Kit does not run here; photo this screen."; exit 1; }

case "${1:-scan}" in
scan)
  echo "== superblock (full copy in $OUT/super.txt)"
  run btrfs inspect-internal dump-super -fa "$DEV" > "$OUT/super.txt" 2>&1
  grep -E '^(superblock:|generation|root[[:space:]]|root_level|chunk_root[[:space:]])' "$OUT/super.txt" | head -n 20

  echo "== find-root (full output in $OUT/find-root.txt, may take a minute)"
  if [ -x "$B/btrfs-find-root" ]; then
    run btrfs-find-root -a "$DEV" > "$OUT/find-root.txt" 2>&1
  else
    echo "btrfs-find-root not in kit"; exit 1
  fi
  echo "-- candidates newer than the superblock ($WANT_SB):"
  grep -E 'gen: ?885(5[4-9]|[6-9][0-9])' "$OUT/find-root.txt" | sort -u | head -n 25
  echo "-- summary lines:"
  grep -iE 'superblock thinks|found tree root' "$OUT/find-root.txt" | head -n 5
  echo
  echo "Photo this screen. Next (read-only): sh $SRC/rescue.sh check <bytenr>"
  ;;
check)
  [ -n "${2:-}" ] || { echo "usage: rescue.sh check <bytenr>"; exit 1; }
  echo "== btrfs check --readonly --tree-root $2 (full output in $OUT/check-$2.txt)"
  run btrfs check --readonly --tree-root "$2" "$DEV" > "$OUT/check-$2.txt" 2>&1
  echo "exit code: $?"
  tail -n 25 "$OUT/check-$2.txt"
  ;;
*)
  echo "usage: rescue.sh [scan | check <bytenr>]"; exit 1 ;;
esac
