#!/bin/bash
# Retired 2026-10-18. Its restore step (PCI rescan for the SD reader) killed the Wi-Fi chip's
# firmware until a reboot, and a dead chip then makes every later suspend fail
# (brcmf_pcie_pm_enter_D3 returns -5), so the machine stays awake with the lid shut. Blocking
# the radios across s2idle is out for the same reason. The old script is
# s2idle-alloff.sh.retired. Use s2idle-ab.sh (self-waking suspends, Wi-Fi and SD reader left alone).
echo "s2idle-alloff.sh is retired (it breaks Wi-Fi); use: sudo bash ~/Work/deepidle-harness/s2idle-ab.sh"
exit 1
