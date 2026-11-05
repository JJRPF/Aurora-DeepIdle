#!/bin/bash
# Dead-man switch for one suspend cycle (run.sh starts it just before `echo mem`).
#
# Why: after `slpa` (2026-10-22 in s2idle, 2026-11-04 in a real suspend) the kernel comes back with NVMe
# gone. The kernel is alive, so systemd keeps feeding the hardware watchdog and nothing resets the Mac;
# the owner had to. This script runs from RAM (/run), waits for run.sh's resume marker, then reads one
# block of the NVMe directly. If that read does not succeed, it pushes the key kernel lines to the owner
# (ntfy, plain HTTP through bash's /dev/tcp, nothing from the disk needed), prints them on the console,
# and resets the Mac (sysrq s, u, b). If the restart handler itself hangs, the hardware watchdog that
# systemd armed (RuntimeWatchdogSec, 1 min) is no longer fed and resets it.
#
#   deadman.sh <marker> <timeout-s> [dry]
#     marker     file run.sh creates right after `echo mem` returns
#     timeout-s  no marker after this long: treat as a failed resume
#     dry        do everything but the reset (for testing)
# Needs, prepared by run.sh in /run/psci-deadman: dd (copied), fifo, optional topic, ntfy-ip and mmio-read (static).
set -u
D=/run/psci-deadman
M=$1; T=$2; DRY=${3:-}
export LC_ALL=C
exec 3<>$D/fifo
pause() { read -r -t "$1" -u 3 _ 2>/dev/null; true; }
say() {
    echo "psci-deadman: $*" > /dev/kmsg 2>/dev/null
    echo "psci-deadman: $*" > /dev/console 2>/dev/null
    echo "$(printf '%(%T)T' -1) $*" >> $D/log
}
# the kernel lines worth having: the SMC sleep handshake, PM, NVMe/ANS, the first btrfs errors
evidence() {
    local l n=0 out='' nb=0
    exec 5</dev/kmsg
    while IFS= read -r -t 0.2 -u 5 l; do
        case $l in " "*) continue ;; esac   # the record's dictionary lines (DEVICE=...)
        l=${l#*;}
        case $l in
            *sleep:*|*SetAPPower*|*MBSE*|*MBSW*|*waka*|*"PM: "*|*nvme*|*apple-ans*|*psci*) ;;
            *BTRFS*) nb=$((nb + 1)); [ $nb -le 3 ] || continue ;;
            *) continue ;;
        esac
        out+="$l"$'\n'; n=$((n + 1))
    done
    exec 5<&-
    # keep the last 40 lines
    printf '%s' "$out" | { mapfile -t a; s=$(( ${#a[@]} > 40 ? ${#a[@]} - 40 : 0 )); printf '%s\n' "${a[@]:s}"; }
}
# Read-only snapshot of the storage controller (static mmio-read in RAM): the PMGR domain ps_ans2 (die 0,
# 0x28e080000 + 0x1a8), and only while that reports on (actual state, bits 7:4, 0xf; a read of a block
# without power can stop the bus): the ANS CPU_CONTROL/STATUS, its mailbox A2I/I2A_CONTROL and the SART's
# 16 config and 16 address words. Normal wakes give the baseline; after slpa it shows what was lost.
regs() {
    local r=$D/mmio-read ps out
    [ -x $r ] || return 0
    words() { local a v w=''; while read -r a v; do w+="${v#0x} "; done < <($r "$@"); printf '%s' "${w% }"; }
    ps=$(words 0x28e0801a8)
    out="ps_ans2 $ps"
    if [ -n "$ps" ] && [ $(( (0x$ps >> 4) & 0xf )) = 15 ]; then
        out+="; ANS cpu $(words 0x347400044 2); mbox $(words 0x347408110 2); SART cfg $(words 0x34bc50000 16); SART pa $(words 0x34bc50040 16)"
    else
        out+=" (domain not on: ANS and SART not read)"
    fi
    printf '%s' "$out"
}
push() {
    local body=$1 topic ip line try
    topic=$(< $D/topic) 2>/dev/null || return 0
    ip=$(< $D/ntfy-ip) 2>/dev/null || ip=ntfy.sh
    [ -n "$topic" ] || return 0
    for try in 1 2 3 4 5 6; do
        if exec 4<>/dev/tcp/$ip/80 2>/dev/null; then
            printf 'POST /%s HTTP/1.1\r\nHost: ntfy.sh\r\nTitle: Mac dead-man switch\r\nPriority: high\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
                "$topic" "${#body}" "$body" >&4
            read -r -t 10 -u 4 line; exec 4<&-
            say "ntfy push: ${line%$'\r'}"
            case $line in *" 200"*) return 0 ;; esac
        fi
        pause 10   # Wi-Fi may still be reconnecting after the resume
    done
    say "ntfy push failed"
}
fail() {
    local ev
    say "FAIL: $1"
    ev=$(evidence)
    printf '%s\n' "$ev" > /dev/console 2>/dev/null
    printf '%s\n' "$ev" > $D/evidence
    push "${DRY:+TEST, dry run: }$1 ($(printf '%(%F %T)T' -1)). Resetting the Mac. Kernel lines:"$'\n'"$ev"
    ev=$(regs); say "regs: $ev"
    [ -n "$ev" ] && push "${DRY:+TEST, dry run: }storage controller registers: $ev"
    if [ -n "$DRY" ]; then say "dry run: not resetting"; exit 1; fi
    echo s > /proc/sysrq-trigger; pause 3
    echo u > /proc/sysrq-trigger; pause 3
    echo b > /proc/sysrq-trigger
    pause 120; say "still alive after sysrq b; the watchdog should follow"
    exit 1
}

say "armed: marker $M, timeout ${T}s${DRY:+, dry run}"
t0=$(printf '%(%s)T' -1)
while [ ! -e "$M" ]; do
    [ $(( $(printf '%(%s)T' -1) - t0 )) -ge "$T" ] && fail "no resume marker after ${T} s"
    pause 1
done
# The cycle is back. One direct (uncached) read from a spread of offsets, by a dd that lives in RAM.
for try in 1 2 3; do
    # only bash builtins and the copied dd from here on (rm, sleep etc. would have to come from the disk)
    : > $D/ok
    ( $D/dd if=${PROBE_DEV:-/dev/nvme0n1} of=/dev/null bs=4096 count=1 skip=$(( (RANDOM << 8) + try )) iflag=direct 2>/dev/null && echo $try > $D/ok ) &
    for s in 1 2 3 4 5 6 7 8 9 10; do [ "$(< $D/ok)" = $try ] 2>/dev/null && break; pause 1; done
    [ "$(< $D/ok)" = $try ] 2>/dev/null && { say "disk ok after resume (try $try)"; say "regs: $(regs)"; exit 0; }
done
fail "the disk does not answer after the resume"
