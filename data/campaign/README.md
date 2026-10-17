# Unattended campaign, 2026-10-15/16

One step per boot, run as root by `harness/runner.sh`: `deep-idle-check.py` (`check.txt`),
`pm_genpd_summary` (`genpd.txt`), the command line, then `idle-ab.py` (15 rounds of 20 s,
`idle-ab.txt` and `.jsonl`) and `wakelat` per setting. `booted-sha.txt` names the m1n1 image
the boot came from. Kernel logs are left out.

* `run1/`: `0-stock` (run in place, no reboot) and `1-em` (E6 energy model) are valid.
  `2-kernel` to `5-final` measured nothing: booting the test kernel let kernel-modules-hook
  remove the hand-installed Aurora module tree (see `docs/deep-idle-research.md`).
* `run2/`: `0-baseline` (stock), `1-kernel` (E7 residency sweep), `2-nodcpext` (E4).
  E1 (PMP) stopped in m1n1 before GRUB, so it has no directory; `3-pmp-asahi-kernel` is the
  next boot, on the Asahi kernel with the stock image, a default against pd-always A/B.
* `run3/`: `0-calib` (Aurora kernel, stock image, `wakeload 10 650 15`, default against
  pd-always), `1-loadsweep` (test kernel, same load, the residency sweep) and `2-pmpdiag`
  (diagnostic m1n1 and the pmp-alias DTB; `pmp-dt.txt` has `/chosen/asahi,pmp-tunables-diag`:
  ret, count, flagged, max size, written, need, free before, free after, big-endian u32).
  `load.txt` names the load, if any. The owner used the machine during a few rounds; see the
  research doc for the quiet-round figures.
* `run4/`: the PMP, on the test kernel rebuilt with `CONFIG_APPLE_PMP=m`. Each step measures
  twice in one boot (`*-before`, `*-after`). `0-pmpctl` loads nothing in between (drift);
  `1-pmpload` boots `pmpfix-test` (m1n1 with 160 KiB DT headroom) and runs `modprobe pmp` in
  between (`modprobe.txt`, `dmesg-modprobe.txt`, `genpd-after.txt`). `2-pmpload2` repeats it
  (on AC), `3-pmpbusy` adds the wake load. `battery-2-pmpload2.log` is the battery gauge, unused
  (the machine was on AC, not charging).
