#!/bin/bash
# Optional, after recover.sh: run the deep idle steps that never measured (the boots had no
# modules) again. Plan: 0 baseline (stock, fresh boot), 1 kernel (residency sweep, test kernel),
# 2 nodcpext, 3 pmp, 4 final stock. The runner now stops instead of moving on when a boot is
# unhealthy (/boot, module tree or SMC power sensor missing) or no ack comes within 30 min.
# Run as: sudo bash ~/Work/deepidle-harness/rearm.sh, then reboot.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
H=/home/jjr/Work/deepidle-harness
VAR=/var/lib/deepidle
REL=7.1.12-2-11.35-sep-ARCH-deepidle
[ -e /etc/systemd/system/linux-modules-cleanup.service.d/keep-pinned.conf ] || { echo "run recover.sh first"; exit 1; }
[ -e /usr/lib/modules/$REL/modules.dep ] || {
    cp -a /home/jjr/Work/deepidle-11.35/staging/lib/modules/$REL /usr/lib/modules/
    chown -R root:root /usr/lib/modules/$REL
    rm -f /usr/lib/modules/$REL/build
}
touch /usr/lib/modules/$REL/.keep
install -m755 $H/runner.sh /usr/local/lib/deepidle/runner.sh
stamp=$(date +%Y%m%d-%H%M)
mkdir -p $VAR/run1 && mv $VAR/results $VAR/runner.log $VAR/run1/ 2>/dev/null || true
mkdir -p $VAR/results
printf '%s\n' "baseline stock default default,pd-always" \
    "kernel stock deepidle-test-kernel default,res=2000,res=500,res=100,pd-always" \
    "nodcpext nodcpext-test deepidle-stock-panic default,pd-always" \
    "pmp pmp-test deepidle-stock-panic default,pd-always" \
    "final stock default default,pd-always" > $VAR/plan
echo 0 > $VAR/current
rm -f /home/jjr/.local/state/deepidle/ack-* /home/jjr/.local/state/deepidle/stop
sudo -u jjr touch /home/jjr/.local/state/deepidle/resume
grub-editenv /boot/grub/grubenv unset next_entry
echo "armed ($stamp). Step 0 runs on the next boot of the default entry; reboot when ready."
echo "Abort any time: touch ~/.local/state/deepidle/stop"
