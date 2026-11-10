#!/bin/bash
# GH-5, runs inside the DeepTest RAM root (usbtest-run.service). One job per boot, then back to main.
#   /run/usbtest/job/job.sh    the job (copied from the drive's /deeptest/job by the initramfs); none = "hello"
#   /run/usbtest/job/topic     ntfy topic (default agent-notify)
#   /run/usbtest/job/keep      if present, do not reboot at the end (the deadline service still does)
# Every line also goes to the kernel log, so the Pi's kmsg stream has it if the Mac dies.
J=/run/usbtest/job
TOPIC=$(cat $J/topic 2>/dev/null || echo agent-notify)
LOG=/run/usbtest/run.log
log() { echo "$(date '+%F %T') $*" | tee -a $LOG; echo "usbtest-run: $*" > /dev/kmsg; }
push() {  # push <title> <body>; retries while the network comes up
    local i
    for i in $(seq 1 ${PUSH_TRIES:-45}); do
        curl -fsS -m 10 -H "Title: $1" -H "Tags: test_tube" -d "$2" "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 && return 0
        sleep 2
    done
    log "push failed: $1"; return 1
}
facts() {
    echo "kernel $(uname -r), cpus $(cat /sys/devices/system/cpu/online), mem $(free -m | awk '/Mem/{print $2}') MB"
    echo "root: $(findmnt -no FSTYPE,OPTIONS / | cut -c1-80)"
    echo "disk mounts: $(findmnt -rno SOURCE,TARGET -t ext4,btrfs,vfat,apfs | tr '\n' ' ' | sed 's/^$/none/')"
    echo "nvme opened: $(grep -c nvme /proc/mounts) mounts; usb drive present: $([ -e /dev/disk/by-label/DEEPTEST_ROOT ] && echo yes || echo no)"
    echo "mem_sleep: $(cat /sys/power/mem_sleep 2>/dev/null); wdt: $(cat /sys/class/watchdog/watchdog0/identity 2>/dev/null) $(cat /sys/class/watchdog/watchdog0/state 2>/dev/null)"
    echo "wifi: $(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2, $4}' | tr '\n' ' ')"
    echo "cmdline: $(cut -c1-160 /proc/cmdline)"
}
log "start; $(facts | head -1)"
if [ -x $J/job.sh ]; then
    log "job: $(head -2 $J/job.sh | tail -1)"
    ( . $J/job.sh ) 2>&1 | tee -a $LOG
    log "job ended rc=${PIPESTATUS[0]}"
    push "DeepTest job ended" "$(tail -25 $LOG)"
else
    F=$(facts); log "hello job"; echo "$F" | tee -a $LOG
    push "DeepTest RAM root booted" "$F"
fi
# results onto the drive's small results partition, if the drive is (still) there
save() {
    local dev m=/run/usbtest/out d
    dev=$(blkid -L DEEPTEST_BOOT 2>/dev/null) || { log "results: no drive"; return; }
    mkdir -p $m; mount -t ext4 "$dev" $m 2>/dev/null || { log "results: mount failed"; return; }
    d=$m/results/$(date +%Y%m%d-%H%M%S); mkdir -p $d
    cp $LOG $d/run.log; dmesg > $d/dmesg.txt; journalctl -b --no-pager > $d/journal.txt 2>/dev/null
    cp -r /run/usbtest/job $d/job 2>/dev/null; [ -d /run/usbtest/results ] && cp -r /run/usbtest/results $d/
    sync; umount $m && log "results: saved to the drive"
}
save
[ -e $J/keep ] && { log "keep: not rebooting"; exit 0; }
log "rebooting to main in 15 s"
sleep 15
sync
systemctl reboot || echo b > /proc/sysrq-trigger
