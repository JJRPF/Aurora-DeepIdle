#!/bin/bash
# Build recovery.sh from recovery.sh.in with the digests of the two images.
#   make-recovery.sh <thin.bin> <restore.bin> <out.sh>
set -eu
THIN=$1 REST=$2 OUT=$3; D=$(dirname "$0")
sed -e "s|@THIN_SZ@|$(wc -c < "$THIN" | tr -d ' ')|g" -e "s|@THIN_SHA@|$(sha256sum "$THIN" | cut -d' ' -f1)|g" \
    -e "s|@THIN_MD5@|$(md5sum "$THIN" | cut -d' ' -f1)|g" -e "s|@THIN_CK@|$(cksum "$THIN" | cut -d' ' -f1)|g" \
    -e "s|@REST_SZ@|$(wc -c < "$REST" | tr -d ' ')|g" -e "s|@REST_SHA@|$(sha256sum "$REST" | cut -d' ' -f1)|g" \
    -e "s|@REST_MD5@|$(md5sum "$REST" | cut -d' ' -f1)|g" -e "s|@REST_CK@|$(cksum "$REST" | cut -d' ' -f1)|g" "$D/recovery.sh.in" > "$OUT"
sh -n "$OUT" && echo "$OUT: $(wc -c < "$OUT") bytes, syntax ok"
