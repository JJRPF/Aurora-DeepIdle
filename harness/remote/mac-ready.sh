#!/bin/bash
# mac-ready.sh: run on the controller (the Pi) to check the Mac can be driven
# over SSH. Read only: it changes nothing on either machine.
#   mac-ready.sh [ssh-host]     default host: mac (an ~/.ssh/config alias)
set -u
H=${1:-mac}
ok=0; bad=0
pass() { echo "ok    $*"; ok=$((ok + 1)); }
fail() { echo "FAIL  $*"; bad=$((bad + 1)); }
r() { ssh -o BatchMode=yes -o ConnectTimeout=5 "$H" "$@" 2>&1; }

out=$(r hostname) && pass "ssh $H (key login): $out" || { fail "ssh $H: $out"; exit 1; }
r sudo -n true >/dev/null && pass "sudo without a password" || fail "sudo -n (harness needs root)"
pass "kernel: $(r uname -r)"
pass "mem_sleep: $(r cat /sys/power/mem_sleep)"
r test -d Work/deepidle-harness && pass "harness at ~/Work/deepidle-harness" \
    || fail "no ~/Work/deepidle-harness on the Mac"
rtc=$(r sudo -n python3 Work/deepidle-harness/mmio/pmu-rtc.py show) \
    && pass "PMU RTC readable: $(echo "$rtc" | sed -n 2p)" || fail "pmu-rtc.py show: $rtc"
r 'grep -l macsmc /sys/class/rtc/rtc*/name' >/dev/null \
    && pass "macsmc RTC present (alarm kernel)" || fail "no macsmc RTC"
r 'test -e ~/.local/state/omarchy/indicators/stay-awake' \
    && pass "stay-awake on" || echo "note  stay-awake off (turn it back on unless a test is running)"
r 'systemctl is-active deepidle-runner.service' | grep -qx active \
    && echo "note  deepidle-runner.service active: a campaign is running" || true
echo "$ok ok, $bad failed"
[ "$bad" = 0 ]
