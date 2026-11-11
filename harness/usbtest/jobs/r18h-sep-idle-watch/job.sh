#!/bin/bash
# R18H: R17D's entry (aura-ctl 0x7dcb1f, image 65 or 66) + macOS's SEP hand-off before the commit: wait for the enclave's
# idle word, SLEEP (type 2) in a freezer-only pass, then OUTBOX_CTRL enable cleared (sep-outbox-off) and ps_sep := 0x1000030f
# (ps-sep-write) from user space, as macOS does
# after the SLEEP ack. R18D showed the enclave holds its floor at f after the SLEEP, so the host has to lower it.
# R18E showed the ps_sep write alone does not lower the floor. The SEP hwrng is taken out of use first.
# The driver is loaded with xart_writes=0 provision_keybag=0. WD1 stays armed (0x1000 left out).
# No commit and no suspend in this run: after the SEP steps it only watches (see the end).
J=/run/usbtest/job; C=/proc/device-tree/chosen; R=/sys/class/rtc/rtc0; M=/sys/module
PUSH_TRIES=8
set1() { [ -e "$1" ] && echo "$2" > "$1"; printf '%s=%s ' "$(basename $1)" "$(cat $1 2>/dev/null || echo MISSING)"; }
w() { $J/mmio-read $1 1 2>/dev/null | awk '{print $2}'; }
atc() { for a in 278 288 298 2a8 228 230 238 240; do printf '%s ' "$(w 0x28e080$a)"; done; }
V=$(tr -d '\0' < $C/asahi,m1n1-stage2-version)
log "R18H kernel $(uname -r); stage2 $V; cmdline aop: $(grep -o 'aop.sleep_ap_idle=[0-9]*' /proc/cmdline || echo none)"
case "$V" in *b22c3766*|*7f8a122e*) ;; *) log "stage 2 is not image 65 or 66: stopping"; return 0 ;; esac
[ -e $R/wakealarm ] && grep -q deep /sys/power/mem_sleep || { log "no wakealarm or no deep, stopping"; return 0; }
grep -q 'aop.sleep_ap_idle=3' /proc/cmdline || { log "aop.sleep_ap_idle=3 not on the cmdline: stopping"; return 0; }
[ -e $M/appledrm/parameters/test_sleep_off ] || { log "appledrm has no test_sleep_off: stopping"; return 0; }
# --- the SEP: load read-only, send SLEEP alone in a freezer-only pass, report, then go on
# R18B (SLEEP + OUTBOX_CTRL clear + ps_sep write) reset the Mac about 9 s after this pass began, kernel.panic=10: most
# likely a panic on a mailbox access after the enclave slept. S3: in this root ps_sep already reads 0x1000030f with the
# driver bound, so the write is not needed. Here: SLEEP only, nothing touches the mailbox afterwards, pushes before and after.
SP=$M/apple_sep/parameters; SB=/sys/bus/platform/drivers/apple_sep/396400000.sep
P0=$(w 0x290280c00)
[ -d $M/apple_sep ] || modprobe apple_sep xart_writes=0 provision_keybag=0 2>&1 | tail -1
[ -e $SP/test_sleep_msg ] || { log "apple_sep has no test_sleep_msg: stopping"; return 0; }
for i in $(seq 1 30); do [ -e $SB ] && break; sleep 1; done
[ -e $SB ] || { log "apple_sep did not bind: stopping"; return 0; }
# Main, 2026-11-10 21:25: the enclave sets its own PS_AUTO. Idle it reads 0x1000030f (auto-enable, floor 0, gated);
# serving a request it raises the floor (0x1400034f) and drops back within 0.1 s; a periodic wake about every 60 s
# (0x1f0003ff). R18C sent SLEEP 9 s after the bind while the word still read 0x1f0002ff (busy since boot).
# So: wait for the idle word first (up to 90 s), then SLEEP, then check it is idle again before the commit.
SI=0; for i in $(seq 1 90); do case "$(w 0x290280c00)" in 0x100003?f) SI=$i; break ;; esac; sleep 1; done
RC=/sys/class/misc/hw_random/rng_current
RNG0=$(cat $RC 2>/dev/null); echo none > $RC 2>/dev/null; RNG1=$(cat $RC 2>/dev/null)
B="ps_sep before the driver $P0, idle after ${SI} s (0 = never): $(w 0x290280c00); rng_current $RNG0 -> $RNG1; panic=$(cat /proc/sys/kernel/panic); the SLEEP pass is next"
log "sep: $B"; push "R18H sep bound" "$B"
echo 2 > $SP/test_sleep_msg; echo N > $SP/test_sleep_psoff
echo freezer > /sys/power/pm_test
echo mem > /sys/power/state; frc=$?
PA=$(w 0x290280c00)
echo none > /sys/power/pm_test
echo 0 > $SP/test_sleep_msg
sleep 2
SEPL="freezer pass rc=$frc; ps_sep right after $PA, 2 s later $(w 0x290280c00); $(dmesg | grep -E 'TEST SLEEP|apple_sep.*(fail|error|timeout|warn)' | tail -4 | cut -c1-140 | tr '\n' '|'); the ps_sep write is next"
log "sep: $SEPL"
push "R18H sep asleep" "$SEPL"
case "$SEPL" in *"TEST SLEEP type 2: reply"*) ;; *) log "the SLEEP got no reply: stopping"; return 0 ;; esac
# R18D: after the SLEEP the enclave holds its floor at f (0x1f0003ff). R18E: the host's write of 0x1000030f alone does not
# lower it (read back 0x1f0000ff: only the two W1C flags cleared). macOS's order after the SLEEP ack is: clear the
# mailbox's OUTBOX_CTRL enable, then write 0x1000030f. So here: the OUTBOX_CTRL bit first, watch the word, then the write.
sync
OB=$($J/sep-outbox-off 2>&1 | tail -1)
PW="outbox ctrl $OB;"; for i in 1 2 3 4 5; do PW="$PW +$((i*200)) ms $(w 0x290280c00)"; sleep 0.2; done
log "sep: $PW"; push "R18H sep outbox off" "$PW; the ps_sep write is next"
WR=$($J/ps-sep-write 0x1000030f 2>&1 | tail -1)
PW="write $WR;"; for i in 1 2 3 4 5; do PW="$PW +$((i*200)) ms $(w 0x290280c00)"; sleep 0.2; done
sleep 3; PL=$(w 0x290280c00); PW="$PW; +4 s $PL"
log "sep: $PW"
push "R18H sep word written" "$PW"
case "$PL" in 0x10*) ;; *) log "ps_sep did not reach floor 0: stopping"; return 0 ;; esac
# R18F and R18G both reset 74 to 75 s after the outbox went off (69 to 71 s after the suspend began), and R18G's first
# pm_test level never reported. Is that the suspend, or the SEP state by itself? This run does not suspend at all: with
# the outbox off and the word at 0x1000030f it only watches, a push every 10 s for 150 s with the word and the SEP lines.
T0=$(date +%s)
for i in $(seq 1 15); do
    sleep 10
    RES="+$(( $(date +%s) - T0 )) s after the word write: ps_sep $(w 0x290280c00), outbox ctrl $(w 0x396408114); $(dmesg | grep -E 'apple_sep|mbox|rtkit|SError|Oops|panic' | tail -3 | cut -c1-120 | tr '\n' '|')"
    log "watch: $RES"
    push "R18H watch $i" "$RES"
done
log "R18H: still up 150 s after the SEP steps, no suspend was tried"
