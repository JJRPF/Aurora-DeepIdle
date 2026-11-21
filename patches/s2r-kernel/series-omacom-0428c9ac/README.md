# GH-5 S2R kernel series on current linux-aurora

Base: `omacom/linux-aurora` `integration/aurora` at `0428c9ac66e1` (2026-11-19, "Merge pull request #487"),
the tree the Omarchy `linux-aurora` package is built from.

87 patches: our 86 commits from the old base (`49a8c150d6be`, 2026-11-08), rebased without conflicts and
unchanged (`git range-diff` all equal), plus one commit with the S2R working set
(`../0001`-`../0007`, including the TEST knobs: REG_ON, bnap, pmVC, SMC key dump).

    git checkout -b gh5/s2r 0428c9ac66e1 && git am patches/s2r-kernel/series-omacom-0428c9ac/*.patch

Built 2026-11-20 with the old toolchain (clang/rustc of `~/Work/toolchain-old`, as before), config unchanged
(`olddefconfig`: no change), `make LLVM=1 Image modules`: exit 0, warnings only in upstream drm/asahi Rust.
Image sha256 c6afdac501bfff27, UKI `deeptest.efi.s2r1` sha aae19bcd454a4fc0, modules in `~/Work/modroot-s2r`.

Upstream notes for the next step (not in this series):
- `aurora-silicon/linux` `integration/aurora` (a separate, faster fork) has runtime PM in i2c-pasemi that
  covers our 0006, and a T6050 deep sleep whose SMC policy sends `pmVC` around `slpa` / after `waka` (R60G).
