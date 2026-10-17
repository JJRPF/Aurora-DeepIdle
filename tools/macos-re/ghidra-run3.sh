#!/bin/bash
# ghidra-run.sh <list> <out>: decompile the functions in <list> from the kc135 project
cd ~/Work/macos-re
export JAVA_HOME=$PWD/jdk-21.0.12.1+1 PATH=$PWD/jdk-21.0.12.1+1/bin:$PATH
export GHIDRA_HEADLESS_MAXMEM=12G
ghidra_12.1.4_PUBLIC/support/analyzeHeadless gproj3 kc135 -process kc.fixed.bin -noanalysis \
  -scriptPath ghidra-scripts -postScript DecompFns.java "$(realpath $1)" "$(realpath -m $2)" > gproj3/last-run.log 2>&1
grep -E "ERROR|Exception" gproj3/last-run.log | head -5
