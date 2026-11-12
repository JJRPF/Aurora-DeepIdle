#!/bin/bash
# P12H: the fit-fail path of the Aura PMP port (issue #12 step 4). Stage 2 = the port (6fb6a87e) with a LOCAL test line that
# adds 1 MB to the need in pmp_tunables_fit() (headroom unchanged), so the tunables "do not fit": expected = Aura prints why,
# leaves the PMP node disabled (no tunables copied) and still boots the kernel. Kernel = linux PR 933, DTB as P12C.
J=/run/usbtest/job; C=/proc/device-tree/chosen; PUSH_TRIES=8
V=$(tr -d '\0' < $C/asahi,m1n1-stage2-version 2>/dev/null)
log "P12H kernel $(uname -r); stage2 $V"
case "$V" in *g6fb6a87e*) ;; *) log "stage 2 is not the Aura port build: stopping"; push "P12H wrong stage 2" "$V"; return 0 ;; esac
P=$(ls -d /proc/device-tree/soc/pmp@* 2>/dev/null | head -1)
ST=$(tr -d '\0' < $P/status 2>/dev/null || echo "(no status property = okay)")
NT=$(ls $P 2>/dev/null | grep -c '^apple,tunable'); BI=$(ls $P 2>/dev/null | grep -c '^apple,board-id')
log "pmp node $P status=$ST tunables=$NT board-id props=$BI"
dmesg | grep -iE 'pmp|pmgr-misc' | cut -c1-150 > /run/usbtest/pmp.txt
D=/sys/kernel/debug; mountpoint -q $D || mount -t debugfs none $D 2>/dev/null
push "P12H fit-fail" "pmp node status=$ST, tunables=$NT, board-id props=$BI; online cpus $(cat /sys/devices/system/cpu/online); pmp dmesg: $(cat /run/usbtest/pmp.txt | cut -c1-110 | tr '\n' '|'); pmp domains: $(grep -iE 'pmp' $D/pm_genpd/pm_genpd_summary | awk '{print $1"="$2}' | tr '\n' ' '); errors: $(dmesg -l err,crit | wc -l)"
