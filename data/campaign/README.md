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
