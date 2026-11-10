#!/bin/bash
# GH-5, on main at boot (usbtest-return.service) when a DeepTest boot was armed: record how it went.
#  - a one-shot request that is still set means Limine never took it (the test boot did not happen):
#    clear it, so the next reboot cannot go to DeepTest by surprise;
#  - collect what the test boot pushed to ntfy since it was armed, and its results from the drive;
#  - tell the owner. The agent session reads $S/last and $S/results/<n>/.
S=/var/lib/deepidle/usbtest
VAR=/sys/firmware/efi/efivars/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
[ -e $S/armed ] || exit 0
. <(tr ' ' '\n' < $S/armed | grep -E '^(epoch|label)=' )
N=$(date +%Y%m%d-%H%M%S); R=$S/results/$N; mkdir -p $R
rm -f /boot/deeptest/failtest
TOOK=yes
if [ -e $VAR ]; then TOOK=no; chattr -i $VAR 2>/dev/null; rm -f $VAR; fi
# the boot.bin flag: the loader clears it when it takes the test image; still set = the loader never saw it
NV=$(ls /sys/bus/spmi/devices/0-0b/spmi_nvmem*/nvmem 2>/dev/null | head -1); FLAG=$(dd if=$NV bs=1 skip=$((0x6010)) count=1 2>/dev/null | xxd -p)
[ "$FLAG" = 00 ] || printf '\x00' | dd of=$NV bs=1 seek=$((0x6010)) count=1 conv=notrunc 2>/dev/null
{ cat $S/armed; echo "returned=$(date -Is) away=$(( $(date +%s) - epoch ))s oneshot_taken=$TOOK bootbin_flag_left=$FLAG kernel=$(uname -r) stage2=$(tr -d '\0' < /proc/device-tree/chosen/asahi,m1n1-stage2-version 2>/dev/null)"; } > $R/summary
TOPIC=$(sudo -u jjr python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~jjr/.config/agent-notify/config.json")))["ntfy_topic"])' 2>/dev/null || echo agent-notify)
for i in $(seq 1 30); do
    curl -fsS -m 15 "https://ntfy.sh/$TOPIC/json?poll=1&since=$epoch" > $R/ntfy.json 2>/dev/null && break; sleep 4
done
python3 - $R/ntfy.json > $R/ntfy.txt 2>/dev/null <<'PY'
import json,sys,time
for l in open(sys.argv[1]):
    try: m=json.loads(l)
    except Exception: continue
    if m.get("event")=="message": print(time.strftime("%H:%M:%S",time.localtime(m["time"])), "|", m.get("title",""), "|", m.get("message",""))
PY
DEV=$(blkid -L DEEPTEST_BOOT 2>/dev/null) && { M=$(mktemp -d); mount -o ro "$DEV" $M 2>/dev/null && { cp -r $M/results/. $R/drive/ 2>/dev/null; umount $M; }; rmdir $M 2>/dev/null; }
SAW=$(grep -c "DeepTest" $R/ntfy.txt 2>/dev/null || echo 0)
echo "reports_from_test_boot=$SAW" >> $R/summary
mv $S/armed $R/armed; ln -sfn $R $S/last
sudo -u jjr /home/jjr/.local/bin/agent-notify send -t "Back on main after DeepTest '$label'" -m "$(tail -2 $R/summary | tr '\n' ' ') results: $R" >/dev/null 2>&1
exit 0
