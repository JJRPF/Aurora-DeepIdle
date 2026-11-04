# Upstream changes from GH-10 (posted 2026-11-04, with the owner's OK)

* aurora-silicon/m1n1#63 (base aurora-wip): give the PMP tunables room, leave the PMP off if they do not
  fit. Patch: `0003-m1n1-pmp-tunables-fit-check.patch`. Booted on the J414s as the PR build.
* aurora-silicon/linux#932 (base integration/aurora): T602x CPU energy model (`opp-microwatt`), derived
  from T8112, paired +0.230 W with EAS off on a PMP boot. Patch: `0001-...energy-model.patch`.
* aurora-silicon/linux#933 (DRAFT): `t6020-j414s: enable PMP`, after m1n1#63 and once S2R with the PMP is
  qualified (GH-8). Patch: `0002-t6020-j414s-enable-pmp.patch`. The opt-in `t6020-j414s-pmp.dts` variant
  that was staged before is dropped: `t6000-j314s` sets `APPLE_USE_PMP` in the board file directly.
* Not posted: PD-always (`0004-cpuidle-pd-always.tmpfiles.conf`), a userspace opt-in that adds nothing on
  top of the PMP.

Branches live in JJRPF/m1n1 (`pmp-tunables-fit`) and JJRPF/linux-aurora-silicon (a fork of aurora-silicon/linux
made for these PRs; JJRPF/linux is in omacom/linux-aurora's fork network and cannot target it).
