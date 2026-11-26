# Draft PR: aurora-silicon/aura

**Title:** `kboot: publish the PMGR AP wake mask address and the ADT wake sources`
**Branch:** `feat/ap-wake-sources` (one commit, `Signed-off-by`, from `gh5-upstream-wakesrc` on `bf6a6417`)

---

**What:** Publish `aurora,ap-wake-mask-reg` (address of the PMGR AP wake mask, register block 7 + 0xc) and `aurora,ap-wake-sources` (the source numbers of the ADT `pmgr` `ap-wake-sources` property) in `/chosen`, so the kernel's macsmc driver can mask every other wake source for suspend-to-RAM instead of carrying a table. Companion of the linux PR "suspend-to-RAM on the T6020".
**Tested:** J414s (M2 Pro) at `7443df8f` plus the rest of the local Aura tree (the commit does not link on a plain checkout of this host only because of a missing `__popcountdi2`, unrelated): `/chosen` carries 22 source words and the mask address `0x29e00400c`; the kernel masks the other sources and wakes on the RTC alarm 25/25 cycles. No other Mac.
**Risk:** two-way door (revert); a new `/chosen` property pair, nothing reads it but the new macsmc code. Any Mac whose ADT has the property gets it published; only the J414s was run.
**Not yet:** other Macs' ADTs were not dumped; the number of mask words is found by the kernel by readback, not published.

<details><summary>Details</summary>
The 22 numbers in the J414s ADT are the sources the firmware keeps enabled across a sleep. The property is the machine's own list, not a per-model table.
</details>

# Not a PR yet: the rest of the local Aura tree
The remaining Aura work (about 75 commits) is not upstreamable as it stands and is not being proposed: `psci_ctl` bit switches for experiments, tables of addresses and values recorded from macOS runs (`qs_macos_*.h`), and a local `__popcountdi2` stub. It needs to be redesigned around ADT properties before a PR.
