#!/bin/bash
# GH-5: read files from macOS's Preboot volume (kernelcaches, DeviceTree.*.im4p) without macOS, read-only.
# Builds apfs-fuse (github.com/sgan81/apfs-fuse) in a work dir with two local fixes: <cstdint> in PList.h, and a
# container whose key manager does not parse (FileVault on the Data volume) is still opened for unencrypted volumes.
#   bash macos-preboot-read.sh <workdir> build
#   sudo bash macos-preboot-read.sh <workdir> mount [volume-index, default 3 = Preboot on this Mac] ; ... ; sudo bash ... umount
# The FUSE driver is read-only; nothing is written to the APFS container. cmake comes from a venv (pip) if missing.
set -eu
W=${1:?workdir}; A=${2:?build|mount|umount}; V=${3:-3}; DEV=${DEV:-/dev/nvme0n1p2}
B=$W/apfs-fuse/build
case $A in
build)
    mkdir -p "$W"; cd "$W"
    command -v cmake >/dev/null && CM=cmake || { [ -x cmv/bin/cmake ] || { python3 -m venv cmv && cmv/bin/pip -q install cmake; }; CM=$W/cmv/bin/cmake; }
    [ -d apfs-fuse ] || git clone -q --recursive https://github.com/sgan81/apfs-fuse.git
    cd apfs-fuse
    grep -q '<cstdint>' ApfsLib/PList.h || sed -i '0,/#include/s//#include <cstdint>\n#include/' ApfsLib/PList.h
    python3 - <<'PY'
p='ApfsLib/ApfsContainer.cpp'; s=open(p).read()
s=s.replace('std::cerr << "Initialization of KeyManager failed." << std::endl;\n\t\t\treturn false;',
            'std::cerr << "Initialization of KeyManager failed (continuing; unencrypted volumes only)." << std::endl;')
open(p,'w').write(s)
PY
    mkdir -p build && cd build && "$CM" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 .. >/dev/null && make -j"$(nproc)" >/dev/null
    echo "built: $B/apfs-fuse, $B/apfsutil" ;;
mount)  mkdir -p "$W/mnt"; "$B/apfs-fuse" -o ro,allow_other -v "$V" "$DEV" "$W/mnt"; echo "mounted volume $V at $W/mnt" ;;
umount) fusermount3 -u "$W/mnt" ;;
esac
