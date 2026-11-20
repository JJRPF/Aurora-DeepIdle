#!/bin/bash
# R57AB: no sleep. Does the test boot run the patched U-Boot, and does the kernel see EFI ResetSystem as supported?
# Pushes the kernel's EFI lines (RTPROP=...), the SMBIOS firmware version, the stage 2 tag; then the normal reboot,
# which (boot-test 109) should leave Aura's header at PMU 0x6040 (50 00 cpu 00).
J=/run/usbtest/job; C=/proc/device-tree/chosen
PUSH_TRIES=8
V=$(tr -d '\0' < $C/asahi,m1n1-stage2-version)
E=$(dmesg | grep -i -E "efi:|psci" | head -12 | cut -c1-160 | tr '\n' '|')
B=$(cat /sys/class/dmi/id/bios_version /sys/class/dmi/id/bios_vendor /sys/class/dmi/id/bios_date 2>/dev/null | tr '\n' ' ')
RT=$(ls /sys/firmware/efi/ 2>/dev/null | tr '\n' ' ')
log "R57AB stage2 $V; bios $B; efi dir: $RT; $E"
push "R57AB efi" "stage2 $V | bios $B | /sys/firmware/efi: $RT | $E"
