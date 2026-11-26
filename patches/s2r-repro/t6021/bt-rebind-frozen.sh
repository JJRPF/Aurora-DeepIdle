#!/bin/sh
# Repro for the hci_bcm4377 probe bug: the Bluetooth daemons cannot run between the unbind and the rebind, as
# during a suspend cancelled at the freeze stage, so the old hci0 is still held and the new device gets hci1.
D=0000:01:00.1
P="$(pgrep -x bluetoothd) $(pgrep -x obexd)"
echo "before: $(ls /sys/class/bluetooth | tr '\n' ' '); pausing $P"
kill -STOP $P
echo $D > /sys/bus/pci/drivers/hci_bcm4377/unbind
echo "after unbind: $(ls /sys/class/bluetooth | tr '\n' ' ')"
echo $D > /sys/bus/pci/drivers/hci_bcm4377/bind
echo "bind rc=$?"
kill -CONT $P
sleep 3
echo "after bind: $(ls /sys/class/bluetooth | tr '\n' ' '); driver: $(basename $(readlink /sys/bus/pci/devices/$D/driver 2>/dev/null) 2>/dev/null)"
