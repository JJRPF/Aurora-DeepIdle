#!/bin/bash
# Reboot if the network dies during a risky test, and reopen the Claude session after it.
#   sudo systemd-run --unit=deepidle-netguard /bin/bash ~/Work/deepidle-harness/net-guard.sh SECONDS "what is being tested"
# Pings 1.1.1.1 and 8.8.8.8 every 15 s; 4 failed checks in a row (about a minute) -> arm
# ~/.local/state/deepidle/resume with a prompt, then reboot. Stop early: systemctl stop deepidle-netguard
set -u
DUR=${1:-1800}; WHAT=${2:-a test}
LOG=/home/jjr/Work/deep-idle-build/netguard.log
ST=/home/jjr/.local/state/deepidle
end=$(( $(date +%s) + DUR )); fails=0
echo "$(date '+%F %T') guard on for ${DUR}s: $WHAT" >> "$LOG"
while [ "$(date +%s)" -lt "$end" ]; do
    sleep 15
    if ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; then
        fails=0
    else
        fails=$((fails + 1))
        echo "$(date '+%F %T') ping failed ($fails)" >> "$LOG"
    fi
    if [ "$fails" -ge 4 ]; then
        echo "$(date '+%F %T') network down during: $WHAT; rebooting" >> "$LOG"
        dmesg | tail -40 >> "$LOG"
        cat > "$ST/prompt.txt" <<P
net-guard rebooted the machine at $(date '+%F %T'): the network died during: $WHAT. Read ~/Work/deep-idle-build/netguard.log (dmesg tail included). Record it in ~/Work/deep-idle-build/WORKLOG.md and the research doc, commit and push to Aurora-DeepIdle PR #4, and never repeat that test. Remove ~/.local/state/deepidle/resume first. Then continue the deep idle research (s2idle 1.4 W vs macOS 0.24 W); keep committing findings. Reboots allowed. Do nothing that could break Wi-Fi (no PCI remove/rescan, no rfkill, nothing on the Wi-Fi link). Omarchy stay-awake: off only around a self-suspend. Aurora Silicon policies.
P
        chown jjr:jjr "$ST/prompt.txt"; sudo -u jjr touch "$ST/resume"
        sync; systemctl reboot; exit 0
    fi
done
echo "$(date '+%F %T') guard off, network fine" >> "$LOG"
