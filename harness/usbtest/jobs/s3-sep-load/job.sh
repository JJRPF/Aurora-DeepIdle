#!/bin/bash
# S3: does the SEP driver load and bind in the DeepTest root? No suspend, no aura-ctl. (R18B died about 10 s after its modprobe, nothing reported.)
# Facts are pushed before the modprobe; afterwards the kernel's new lines are pushed every second, so the last push shows how far it got.
J=/run/usbtest/job; M=/sys/module
PUSH_TRIES=8
SB=/sys/bus/platform/drivers/apple_sep/396400000.sep
N=$(ls -d /proc/device-tree/soc*/sep@* /proc/device-tree/soc/sep@* 2>/dev/null | head -1)
F="kernel $(uname -r); stage2 $(tr -d '\0' < /proc/device-tree/chosen/asahi,m1n1-stage2-version); panic=$(cat /proc/sys/kernel/panic)
sep node: ${N:-none} status=$(tr -d '\0' < $N/status 2>/dev/null) props: $(ls $N 2>/dev/null | tr '\n' ' ' | cut -c1-300)
reserved: $(dmesg | grep -i -E 'sep-firmware|sep' | head -4 | cut -c1-150 | tr '\n' '|')
resv nodes: $(ls /proc/device-tree/reserved-memory 2>/dev/null | tr '\n' ' ' | cut -c1-300)
nvme: $(ls /dev/nvme* 2>/dev/null | tr '\n' ' '); loaded: $(lsmod | grep -c -E '^apple_sep')"
log "$F"
push "S3 before modprobe" "$F"
sleep 2
( modprobe apple_sep xart_writes=0 provision_keybag=0 > /run/s3-modprobe.out 2>&1; echo "rc=$?" >> /run/s3-modprobe.out ) &
seen=0
for i in $(seq 1 40); do
    L=$(dmesg | grep -i -E 'sep|xart|trusted|panic|Oops|SError|Unable|dart' | grep -v usbtest-run)
    n=$(echo "$L" | wc -l)
    if [ "$n" -gt "$seen" ]; then
        B="t+$i s bound=$([ -e $SB ] && echo Y || echo N) modprobe: $(tr '\n' ' ' < /run/s3-modprobe.out 2>/dev/null)
$(echo "$L" | tail -n +$((seen+1)) | cut -c1-170 | head -25)"
        seen=$n
        PUSH_TRIES=1 push "S3 t+$i" "$B"
    else
        sleep 1
    fi
done
R="S3 survived 40 s: bound=$([ -e $SB ] && echo Y || echo N); modprobe $(tr '\n' ' ' < /run/s3-modprobe.out); ps_sep $($J/mmio-read 0x290280c00 1 2>/dev/null | awk '{print $2}')
$(dmesg | grep -i apple_sep | tail -8 | cut -c1-170)"
log "$R"; push "S3 done" "$R"
