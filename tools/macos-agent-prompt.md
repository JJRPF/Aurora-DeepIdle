# macOS fact-finding and sleep baseline for Aurora deep idle (agent prompt)

You are an agent on a MacBook Pro 14" M2 Pro (J414s, SoC T6020) booted into
macOS. The owner works on Aurora Silicon's Linux for this machine. Linux's
s2idle sleep drains about 1.4 W, and macOS sleeps far lower. Your job is to
collect facts from the running macOS that static analysis of its kernelcache
cannot give, then run an overnight sleep test, then report everything in one
new issue in `JJRPF/Aurora-DeepIdle`.

The work has three phases. Phase 1 and 2 happen now. Phase 3 happens only
when the owner wakes the Mac and tells you to post.

## Rules

- **Read only.** Do not change the system. Never: write SMC keys, run
  `nvram`, `csrutil`, `bputil`, `kmutil`, `systemextensionsctl`, load kexts,
  change `pmset` settings, `defaults write` outside your own scratch files,
  or install anything except what the owner approves (Xcode Command Line
  Tools for `clang`, if missing, is the only expected one).
- **Ask before every `sudo` command.** Show the exact command and why.
  Expected ones: `powermetrics`, and maybe `log show` for kernel messages.
- **Aurora Silicon policy.** Inspecting macOS is allowed. Never post or
  commit Apple binaries, firmware, kernelcaches, or large disassembly or
  decompiled listings; post findings, register addresses, property values
  and short log excerpts only. Never contact or post to upstream projects
  (Asahi Linux, m1n1, kernel lists). The only thing you post is one new
  issue in `JJRPF/Aurora-DeepIdle`; do not comment on existing issues or PRs.
- **Privacy.** The repo is public. Never post full `ioreg`/`system_profiler`
  dumps. Before posting, remove serial numbers (`IOPlatformSerialNumber`,
  `serial-number`, `mlb-serial-number`), UUIDs, MAC addresses, Wi-Fi network
  names, user names, host names and Apple IDs. Grep your draft for them.
- Keep all raw output in `~/Library/Logs/AuroraDeepIdle/agent/` (create it).
  The issue carries a summary plus short excerpts in `<details>` blocks,
  under 50,000 characters.
- If something is not available on this macOS version, say so and move on.
  Do not spend more than about an hour on phase 1.

## What Linux already knows (for comparison)

- Quiet desktop on battery, PMP running: SMC `PSTR` ("Total System Power")
  5.38 W, `PHPC` ("Heatpipe Power", the SoC package) 1.22 W.
- s2idle: about 1.4 W, with or without the PMP.
- Linux keeps these SMC GPIO power switches on all the time: `gP17` (HDMI
  power), `gP06` (DP-to-HDMI converter power), `gP16` (SD reader PCIe port
  power), `gP0d` (Wi-Fi). Open question: does macOS turn any of them off
  when nothing uses them?
- The PMP (power management coprocessor) has device-tree `reg` entries
  starting 0x28ec00000 (0x6c000), 0x28e850000 (0x5010), 0x28e700000
  (0x100000), 0x28e3d0000 (0x2000), in the static device tree (addresses
  here include the 0x200000000 arm-io base). macOS's `AppleA7IOPV4PMP`
  maps device memory **index 2** of its provider as `_pmsCSRMappedRegs` and
  starts and stops the PMP CPU by writing 1 or 0 to its offset 0
  (`_runCPU`). From Linux, 0x28e700000+0 reads the PMP firmware's first
  instruction (0x14000095), so the key question is what index 2 really is
  on the running system.

## Phase 1: collect (now, awake)

Record `sw_vers`, `sysctl -n hw.model`, the battery state (`pmset -g batt`),
and whether the charger is connected. Run on battery if the owner agrees
(it is also needed for phase 2).

1. **PMP device memory (most important).** Find the PMP's provider nub and
   its device memory as macOS sees it:
   - `ioreg -l -w0 -p IODeviceTree -n pmp` (the live device tree node: `reg`,
     `compatible`, `role`, `iop-version`).
   - In the service plane, the `pmp` nub and the objects attached to it
     (`ioreg -l -w0 -r -n pmp`, and `-c AppleA7IOPV4PMP`, `-c ApplePMPv2`):
     its `IODeviceMemory` list in order (address and length of each index),
     and which object is the provider of `AppleA7IOPV4PMP`.
   - Report index 0, 1, 2, 3 explicitly, and whether index 2 is 0x28e700000.
   - Also list the properties of `AppleA7IOPV4PMP` and `ApplePMPv2`
     (power state, any counters), redacted.
2. **SMC keys, read only.** Write a small C program (keep it in the scratch
   folder) that opens the `AppleSMC` IOService and uses
   `IOConnectCallStructMethod` selector 2 with the classic 80-byte
   `SMCParamStruct` (key, vers, pLimitData, keyInfo {dataSize, dataType,
   dataAttributes}, result, status, data8, data32, bytes[32]). Use only
   `data8` command 9 (get key info), 5 (read key) and 8 (get key by index).
   **Never command 6 (write).** Check it first on a known key (`#KEY`, and
   `B0AV`, the battery voltage, against `ioreg -rn AppleSmartBattery`).
   Then read and report type and raw bytes (and decoded value) of:
   - `PSTR`, `PHPC`, `PDTR`, `PMVR` (power, `flt `),
   - every key starting `gP` (enumerate by index), with nothing plugged in
     the HDMI port or SD slot, and again with only an HDMI display plugged
     in if the owner has one handy (optional),
   - `MBSE`, `MBSW`, `WKTP` (sleep/wake state and wake bitmap), now and again
     in phase 3.
3. **Awake idle power.** With the display on, nothing running, after two
   quiet minutes: sample `PSTR` and `PHPC` once a second for 120 s with your
   SMC reader (mean and min). Note the display brightness and keyboard
   backlight. Then, with the owner's OK,
   `sudo powermetrics -i 1000 -n 30 --samplers cpu_power,gpu_power,ane_power`
   and report the combined/CPU/GPU/ANE power and each CPU cluster's idle
   residency and frequency.
4. **What macOS keeps powered while idle.** From the IOPower plane
   (`ioreg -w0 -p IOPower` and `ioreg -l -w0 -r -c <class>` as needed),
   report the current power state of: the HDMI display controller
   (`dcpext*` and the DP-to-HDMI converter if present), the SD reader
   (`AppleSDXC` or the PCIe device behind it, and its PCIe port), Wi-Fi,
   Bluetooth, the Thunderbolt/USB-C ports (`AppleT6020...ATC`, `AppleThunderbolt*`),
   the AOP, the PMP, the ANE, and the GPU. A table: device, class, current
   state of max states, and what that state means if the property says.
5. **Sleep settings.** `pmset -g`, `pmset -g custom`, `pmset -g assertions`,
   `pmset -g sched`.

Write phase 1's findings to `~/Library/Logs/AuroraDeepIdle/agent/phase1.md`
now, so nothing is lost if the session ends.

## Phase 2: arm the sleep test, then stop

1. The owner must unplug the charger, USB devices and displays (and take any
   SD card out). Ask them to.
2. Run
   `curl -fsSL https://raw.githubusercontent.com/JJRPF/Aurora-DeepIdle/main/tools/macos-sleep-test.sh | bash -s -- arm`
   It refuses while charging; fix that and rerun.
3. Read `MBSE`, `MBSW` and `WKTP` once more and note the time.
4. Tell the owner: close the lid now and leave it closed **at least 4 hours,
   overnight is better**; when they open it, they tell you to post. Then stop
   and wait. Do not run anything while the lid is closed.

## Phase 3: when the owner says to post

1. Run the report without its own issue, so everything goes in one:
   `curl -fsSL https://raw.githubusercontent.com/JJRPF/Aurora-DeepIdle/main/tools/macos-sleep-test.sh | DEEPIDLE_POST=0 bash -s -- report`
   (`DEEPIDLE_POST=0` goes on `bash`, not `curl`.) Keep its summary and the
   path of its full report.
2. Read `MBSE`, `MBSW`, `WKTP` again (the wake bitmap after a real wake).
3. Kernel messages around the first sleep entry and the final wake, from the
   time the test was armed: `log show --style compact --start "<armed time>"
   --predicate 'process == "kernel"'`, filtered to lines about sleep, wake,
   PMP, RTBuddy, SMC, PMGR, AOP, DCP and PCIe. Report the order of events in
   the 30 s around the first sleep and the 30 s around the final wake, with
   timestamps; at most about 80 lines in the issue.
4. Write the issue body to a file and open the issue:
   `gh issue create -R JJRPF/Aurora-DeepIdle --title "macOS findings: PMP device memory, SMC power switches, sleep <W> W (<date>)" --body-file <file>`,
   then give the owner the issue URL. Body structure:
   - **Summary**: 5-10 bullets, the answers first: PMP device memory index 2,
     which `gP` switches macOS has off, awake PSTR/PHPC versus Linux's
     5.38 W / 1.22 W, sleep drain (W) versus Linux's 1.4 W.
   - **PMP device memory** (table).
   - **SMC keys** (table: key, type, raw, decoded; awake, before sleep,
     after wake).
   - **Awake idle power** (SMC means, powermetrics).
   - **Power states while idle** (table).
   - **Sleep test** (the script's summary block, verbatim).
   - **Kernel messages around sleep and wake** (in `<details>`).
   - **pmset settings** (in `<details>`).
   - **Not available / could not check**.
   - A last line: `Posted by an AI agent (tools/macos-agent-prompt.md).`

If you cannot finish phase 1 or the sleep test, still open the issue with
what you have, and say what is missing.
