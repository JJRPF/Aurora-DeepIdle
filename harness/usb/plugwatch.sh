#!/bin/bash
# plugwatch.sh: log USB-C plug handling while someone plugs and unplugs devices.
# Read only. Every 0.5 s, on change: cd321x IRQ count (Apple-GPIO 44), each cd321x STATUS
# register (0x1a; byte 1 bit 0 = plug present), Type-C partners, USB devices. Plus the
# kernel log lines about USB/Type-C. Output: /var/lib/deepidle/plugwatch/
#   sudo systemd-run --unit=di-plugwatch ~/Work/deepidle-harness/usb/plugwatch.sh [seconds]
set -u
OUT=/var/lib/deepidle/plugwatch; mkdir -p $OUT; chmod 755 $OUT
END=$(( $(date +%s) + ${1:-1800} ))
journalctl -k -f -n0 -o short-precise | grep --line-buffered -iE 'usb|xhci|dwc3|cd321|tps|typec|thunderbolt|acio|atc' > $OUT/kernel.log &
JP=$!
trap 'kill $JP 2>/dev/null' EXIT
prev=""
while [ $(date +%s) -lt $END ]; do
    irq=$(awk '/Apple-GPIO +44 /{s=0; for(i=2;i<=11;i++) s+=$i; print s}' /proc/interrupts)
    st=""
    for a in 0x38 0x3f 0x3b; do
        st="$st $a=$(i2ctransfer -f -y 0 w1@$a 0x1a r5@$a 2>&1 | cut -d' ' -f2-5 | tr -d ' ')"
    done
    par=$(ls -d /sys/class/typec/port*-partner 2>/dev/null | sed 's|.*/||' | tr '\n' ' ')
    dev=$(lsusb | grep -v 'root hub' | cut -d' ' -f2,4,6- | tr '\n' ';')
    cur="irq=$irq |$st | partners: $par| usb: $dev"
    [ "$cur" != "$prev" ] && echo "$(date '+%T.%N' | cut -c1-12) $cur" | tee -a $OUT/state.log
    prev=$cur
    sleep 0.5
done
chmod -R a+r $OUT
