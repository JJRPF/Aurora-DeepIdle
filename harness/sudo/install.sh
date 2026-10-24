#!/bin/bash
# Install (or remove) the harness-only passwordless sudo rule for jjr: 90-deepidle-harness next to
# this script -> /etc/sudoers.d/90-deepidle-harness. No expiry. The file name differs from Omarchy's
# 99-omarchy-nopasswd-jjr, so omarchy-sudo-passwordless and its expiry timer never touch it.
#   sudo bash ~/Work/deepidle-harness/sudo/install.sh           install, then self-test
#   sudo bash ~/Work/deepidle-harness/sudo/install.sh remove    remove
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
DST=/etc/sudoers.d/90-deepidle-harness
if [ "${1:-}" = remove ]; then
    rm -f $DST
    echo "removed $DST"
    exit 0
fi
SRC=$(dirname "$(readlink -f "$0")")/90-deepidle-harness
visudo -c -q -f "$SRC" || { echo "$SRC fails visudo; nothing installed"; exit 1; }
TMP=$(mktemp /etc/sudoers.d/.90-deepidle-harness.XXXXXX)
install -o root -g root -m 0440 "$SRC" "$TMP"
mv -f "$TMP" $DST
visudo -c -q || { rm -f $DST; echo "full sudoers check failed; removed $DST again"; exit 1; }
echo "installed $DST"

# Self-test as jjr. sudo -l cannot tell "allowed without a password" from "allowed with one" (jjr
# may run anything with the password), so each case really runs, with sudo -n: "deny" means sudo
# answered "a password is required". -k ignores the password just typed to run this script. Every command here is harmless if it does run; nothing that
# could power off or change the system is tried.
H=/home/jjr/Work/deepidle-harness
fail=0
t() {  # want(allow|deny) cmd...
    local want=$1; shift
    local err; err=$(sudo -u jjr sudo -n -k "$@" 2>&1 >/dev/null)
    case $err in *"password is required"*) got=deny;; *) got=allow;; esac
    [ $got = $want ] && r=ok || { r=BAD; fail=1; }
    printf '%-4s %-5s %s\n' $r $got "$*"
}
t allow /usr/bin/bash $H/sudo/selftest.sh
t allow /usr/bin/bash $H/sudo/selftest.sh with args
t allow /usr/bin/python3 -I $H/sudo/selftest.py
t allow /usr/bin/systemd-run --unit=di-selftest --collect /usr/bin/bash $H/sudo/selftest.sh
t allow /usr/bin/dmesg
t allow /usr/bin/dmesg -T
t allow /usr/bin/journalctl --no-pager -n 1
t deny  /usr/bin/bash $H/../../../tmp/no-such.sh
t deny  /usr/bin/bash $H/.no-such.sh
t deny  /usr/bin/bash -c true
t deny  /usr/bin/python3 -c pass
t deny  /usr/bin/python3 $H/sudo/selftest.py
t deny  /usr/bin/systemd-run --unit=di-selftest2 --collect /usr/bin/bash -c true
t deny  /usr/bin/systemd-run --unit=selftest3 --collect /usr/bin/bash $H/sudo/selftest.sh
t deny  /usr/bin/dmesg -H
t deny  /usr/bin/journalctl -n 1
t deny  /usr/bin/id
[ $fail = 0 ] && echo "self-test passed" || echo "SELF-TEST FAILED: check the BAD lines (the rule stays installed; remove it with: sudo bash $0 remove)"
