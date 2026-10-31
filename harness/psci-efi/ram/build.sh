#!/bin/bash
# Build the RAM-only test initramfs: static init + the stock boot.bin to put back. Output: $1 (default /tmp/psci-ram.img)
set -eu
H=$(cd "$(dirname "$0")" && pwd); OUT=${1:-/tmp/psci-ram.img}; W=$(mktemp -d)
gcc -O2 -static -o $W/init $H/init.c
cp /var/lib/deepidle/boot.bin.stock $W/boot.bin.stock
(cd $W && printf 'init\nboot.bin.stock\n' | cpio -o -H newc --quiet | gzip -1 > $OUT)
rm -rf $W; ls -la $OUT
