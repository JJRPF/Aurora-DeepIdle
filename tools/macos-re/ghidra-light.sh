#!/bin/bash
# Light project gproj3: symbols + functions, no auto analysis; decompile on demand with ghidra-run3.sh
cd ~/Work/macos-re
export JAVA_HOME=$PWD/jdk-21.0.12.1+1 PATH=$PWD/jdk-21.0.12.1+1/bin:$PATH GHIDRA_HEADLESS_MAXMEM=8G KC_KERNEL_FNS=1
rm -rf gproj3; mkdir gproj3
exec ghidra_12.1.4_PUBLIC/support/analyzeHeadless gproj3 kc135 -import 13.5-22G74/kc.fixed.bin -loader BinaryLoader \
  -loader-baseAddr 0xfffffe0007004000 -processor "AARCH64:LE:64:AppleSilicon" -scriptPath ghidra-scripts \
  -preScript SetupKC.java $PWD/ghidra-scripts/syms.txt $PWD/ghidra-scripts/kexts.lst -noanalysis > gproj3/import.log 2>&1
