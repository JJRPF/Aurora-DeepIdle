# Driving the Mac from a Raspberry Pi 5

The deep idle work moves its agent session to a Raspberry Pi 5, so that reboots, hangs and suspends of the Mac (J414s, M2 Pro, T6020) no longer end the session. The Pi controls the Mac in two ways:

- **SSH**, while Linux runs on the Mac and its network is up.
- **USB**, while the Mac waits in Aura (Aurora Silicon's m1n1 fork) proxy mode. That gives the proxy client, chainloading and the hypervisor with its trace scripts.

Neither link reaches a Mac that has hung: then the owner presses the power button. A serial console and remote reboot need `tuxvdmtool` (aurora-silicon) on a second Apple Silicon machine running Linux; a Pi cannot do it.

Builds stay on the Mac (much faster than the Pi). The Pi runs them over SSH.

## Read first

The Pi session starts fresh: this session's transcript is not carried over. Read these first:

1. `docs/deep-idle-research.md`. Begin with "S2R: what is missing, piece by piece".
2. `docs/worklog.md`, and the Mac's live copy `~/Work/deep-idle-build/WORKLOG.md`.
3. This file.

## What lives where (on the Mac, user `jjr`)

| Path | What |
|---|---|
| `~/dev/linux-aurora/GH-1-DeepIdle` | Kernel worktree, branch GH-1-DeepIdle. Commit there, **never push it** |
| `~/Work/deepidle-11.35` | Out-of-tree build: `src/`, `build/` (`O=build`, `LOCALVERSION=-deepidle3`), `staging-deepidle3/` |
| `~/Work/deepidle-harness` | The harness as it runs. Its scripts use these paths; run them there, over SSH |
| `~/Work/deep-idle-build/WORKLOG.md` | Running log |
| `~/Work/m1n1` | m1n1 tree the installed stage 2 is built from (v1.6.1-29-gc6498e6e) |
| `~/Work/aurora-src/aura` | Aura, read-only clone. Base new m1n1 work on this |
| `~/dev/Aurora-DeepIdle/quick-Campaign` | This repo, branch quick-Campaign (PR #6) |

`harness/` here mirrors `~/Work/deepidle-harness` (sources only).

## Connecting

The Mac runs sshd with key logins only (no passwords). User `jjr` has passwordless `sudo` (`/etc/sudoers.d/99-omarchy-nopasswd-jjr`). **The Pi's key therefore gives root on the Mac.** So:

- Give the Pi its own key (`ssh-keygen -t ed25519`), used for nothing else.
- On the Mac, put a `from=` restriction on that key in `~/.ssh/authorized_keys`, naming the Pi's address. Keep it off the internet-facing side.

Pi `~/.ssh/config`:

```
Host mac
    HostName omarchy-mac        # or its LAN or Tailscale address
    User jjr
    ServerAliveInterval 15
    ServerAliveCountMax 4
```

Then run `harness/remote/mac-ready.sh` on the Pi. It reads only, and checks:

- the key login;
- `sudo -n`;
- the kernel;
- `mem_sleep`;
- the harness;
- the PMU RTC;
- the macsmc RTC;
- stay-awake;
- whether a campaign runner is active.

### Long jobs and suspends

An SSH session dies when the Mac suspends or Wi-Fi drops. So start anything that suspends, reboots or runs long as a transient unit on the Mac, then reconnect and read the results:

```
ssh mac sudo systemd-run --unit=di-<name> --collect <script> <args>
ssh mac systemctl status di-<name>; ssh mac journalctl -u di-<name>
```

The harness scripts write their own logs under `~/Work/deepidle-harness/*/logs` and `/var/lib/deepidle`. To time a suspend from outside, ping the Mac from the Pi. The time it stops answering and the time it answers again are an independent check of the Mac's own log.

## USB: Aura proxy mode

- **Cable:** a USB-A (Pi host port) to USB-C data cable. Check in the Aura/m1n1 docs which J414s port m1n1's USB device works on before relying on one.
- **Pi setup:** Aura's `proxyclient` needs Python with `pyserial` and `construct`. Install its `udev/` rules; the Mac then shows up as `/dev/aura` (old names kept), with a second port for the hypervisor's virtual UART. Set `M1N1DEVICE` to the first port.
- **Loading Aura:** **chainload it, never install it** as the Mac's stage 2. Aura 0.1.0 does not claim J414s testing.
- **Normal boot stays as it is:** the installed `boot.bin` on the ESP stays the owner's stock image.
- **Hypervisor trace scripts:** `proxyclient/hv/trace_pmgr.py`, `trace_smc.py`, `trace_spmi.py`, `trace_pmp.py`, `trace_aop.py`.
- **Known blocker:** the hypervisor refuses the guest's CYC_OVRD DISABLE_WFI_RET write (`src/hv/hv_exc.c`, both Aura and m1n1). So macOS cannot reach system sleep under it until that is changed.

## Standing rules (from the owner)

- **Aurora Silicon's policies, not Asahi's.**
  - Decompiling public macOS is fine.
  - Never contact upstream.
  - AI disclosure goes in commits.
  - Prefer Aurora tools (Aura) over Asahi's.
- **Before any hardware register write, say exactly what and why.** Proxy mode can reach any register, so this matters more there.
- **Never PCI remove/rescan or rfkill.** It kills Wi-Fi until a reboot.
- **Never remove the owner's fallback kernels.**
- **Build out of tree.**
- **Reboots:** check the latest word. As of 2026-10-20 they are allowed without asking.
- **Omarchy stay-awake** stays on. Turn it off (`omarchy-toggle-idle allow-idle`) only right around a self-suspend test, and back on (`omarchy-toggle-idle stay-awake`) right after. Trap it in scripts.
- **Repositories:**
  - Commit findings to this repo and to the kernel worktree.
  - Push only this repo's PR branch; never GH-1-DeepIdle.
  - Never edit `main` folders.
- **Non-interactive commands only.** No markdown blockquotes in reports.
- **Notifications:** send a short `agent-notify` on significant results.
- **Cleanup when testing ends:** remind the owner to:
  - run `teardown.sh`;
  - remove the LUKS keyfile slot;
  - run `deepidle3/install.sh remove`.

## Next work

In order, from "S2R: what is missing, piece by piece":

1. **PMP `_runCPU` wake fix and the SMC slpw/slpa/waka handshake.** Both are tested in s2idle with the PMU alarm (`rtcwake -m freeze`, deepidle3 kernel and its DTB), with no one at the machine.
2. **AIC save/restore** across suspend.
3. **PSCI `SYSTEM_SUSPEND` and `CPU_OFF`, built on Aura.** Use the psci-via-efi branch as a reference only.
4. **PMGR sleep steps.** These need the hypervisor trace of macOS (above), once the CYC_OVRD block is dealt with.

Open items that need the owner:

- the HDMI rails patch boot and its hot-plug test;
- s2idle on battery against on the charger.
