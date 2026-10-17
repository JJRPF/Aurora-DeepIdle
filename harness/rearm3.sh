#!/bin/bash
# Run 3: 0 calib (Aurora, stock, wake load: default vs pd-always), 1 loadsweep (test kernel, wake
# load: residency sweep), 2 pmpdiag (diagnostic m1n1 + J414s DTB with only the pmp alias: records
# why the PMP tunable copy fails; the PMP stays disabled). Puts the stock boot.bin on the ESP as
# m1n1/boot.bin.before-pmp-test first, for recoveryOS.
# Run as: pkexec bash ~/Work/deepidle-harness/rearm3.sh, then reboot into the default entry.
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
H=/home/jjr/Work/deepidle-harness
W=/home/jjr/Work/deep-idle-build
VAR=/var/lib/deepidle
STOCK_SHA=3630adc3b3be173c
[ "$(sha256sum $W/boot.bin.before-pmp-test | cut -c1-16)" = $STOCK_SHA ]
[ "$(sha256sum $W/boot.bin.pmpdiag-test | cut -c1-16)" = 225043d007b0cbc2 ]
cp $W/boot.bin.before-pmp-test /boot/m1n1/boot.bin.before-pmp-test && sync
[ "$(sha256sum /boot/m1n1/boot.bin.before-pmp-test | cut -c1-16)" = $STOCK_SHA ]
install -m755 $H/runner.sh $H/wakeload /usr/local/lib/deepidle/
mkdir -p $VAR/run2 && mv $VAR/results $VAR/runner.log $VAR/run2/ 2>/dev/null || true
mkdir -p $VAR/results
printf '%s\n' "calib stock default default,pd-always 10:650:15" \
    "loadsweep stock deepidle-test-kernel default,res=2000,res=500,res=200,res=100,pd-always 10:650:15" \
    "pmpdiag pmpdiag-test deepidle-stock-panic default,pd-always" > $VAR/plan
echo 0 > $VAR/current
rm -f /home/jjr/.local/state/deepidle/ack-* /home/jjr/.local/state/deepidle/stop
sudo -u jjr touch /home/jjr/.local/state/deepidle/resume
grub-editenv /boot/grub/grubenv unset next_entry
df -h /boot | tail -1
echo "armed run 3. Reboot into the default entry; step 0 runs on that boot."
