#!/bin/bash
# PSCI-via-EFI boot tests (S2R plan, Phase 1), one boot each, owner's go for each.
#   sudo bash install.sh step0   Aura as the stage 2, stock DTB and U-Boot, stock kernel (default entry)
#   sudo bash install.sh step1a  the psci-efi-test kernel on the STOCK boot.bin (no PSCI node, spin-table): is the kernel build itself fine?
#   sudo bash install.sh step1m  as step1 but the kernel gets maxcpus=1: it only probes the EFI PSCI handler, then run.sh
#                                 brings the secondaries online one at a time from the running system (logged)
#   sudo bash install.sh step1   the psci-efi-test kernel + Aura + patched U-Boot + PSCI DTB (GRUB next_entry)
#   sudo bash install.sh suspend maxcpus=1 kernel, Aura with the SYSTEM_SUSPEND stub (Phase 2a): no CPU is ever offlined
#   sudo bash install.sh ram     hotplug cycles from a RAM-only initramfs (ram/): the LUKS root and btrfs are never opened, so a hang cannot hurt them
#   sudo bash install.sh remove  undo everything (units, GRUB entry, test kernel, stock boot.bin back)
# Installs next to the existing kernels; none of the owner's is touched. The default GRUB entry never
# changes and the stock boot.bin goes back early in the test boot (psci-efi-early.service); a boot that
# hangs before that keeps the test image on the ESP, and `remove` (or the stock restore) fixes it.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
H=$(cd "$(dirname "$0")" && pwd)
REL=7.2.11-psci-efi+
STAGE=/home/jjr/Work/staging-psci-efi
BIN0=/home/jjr/Work/psci-test/boot.bin.aura-stage2; SHA0=19d5f8f627f966a1
BIN1=/home/jjr/Work/psci-test/boot.bin.psci-test15;  SHA1=a5e3ced5b3007515
BIN2=/home/jjr/Work/psci-test/boot.bin.psci-test31;  SHA2=2be4308831440462
STOCK=/var/lib/deepidle/boot.bin.default; STOCKSHA=76f850895fed53d1
stockback() {
    [ "$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)" = $STOCKSHA ] || {
        cp $STOCK /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync; }
}
if [ "${1:-}" = remove ]; then
    rm -f /var/lib/deepidle/psci-efi-armed
    systemctl disable psci-efi-early.service psci-efi-run.service 2>/dev/null || true
    rm -f /etc/systemd/system/psci-efi-early.service /etc/systemd/system/psci-efi-run.service
    rm -f /usr/local/lib/deepidle/psci-efi-early.sh /usr/local/lib/deepidle/psci-efi-run.sh
    rm -f /etc/grub.d/46_psci_ram /boot/initramfs-psci-ram.img /etc/grub.d/45_psci_efi /boot/vmlinuz-psci-efi-test /boot/initramfs-psci-efi-test.img
    rm -rf "/usr/lib/modules/$REL"
    grub-editenv /boot/grub/grubenv unset next_entry
    stockback
    grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
    systemctl daemon-reload
    echo "psci-efi removed; boot.bin $(sha256sum /boot/m1n1/boot.bin | cut -c1-16)"
    exit 0
fi
STEP=${1:?step0 | step1 | remove}
case $STEP in step0) BIN=$BIN0; SHA=$SHA0 ;; step1) BIN=$BIN1; SHA=$SHA1 ;; step1a) BIN=$STOCK; SHA=$STOCKSHA ;; step1m) BIN=$BIN1; SHA=$SHA1 ;; suspend) BIN=$BIN2; SHA=$SHA2 ;; ram) BIN=$BIN1; SHA=$SHA1 ;; *) echo "step0 | step1a | step1m | step1 | suspend | ram | remove"; exit 1 ;; esac

# Preconditions
[ "$(sha256sum $STOCK | cut -c1-16)" = $STOCKSHA ] || { echo "stock boot.bin copy missing or wrong"; exit 1; }
[ "$(sha256sum $BIN | cut -c1-16)" = $SHA ] || { echo "test boot.bin $BIN missing or wrong"; exit 1; }
[ "$(sha256sum /boot/m1n1/boot.bin | cut -c1-16)" = $STOCKSHA ] || { echo "ESP boot.bin is not stock; stopping"; exit 1; }
[ -z "$(grub-editenv /boot/grub/grubenv list | grep -E "^next_entry=.+" || true)" ] || { echo "a next_entry is already set; stopping"; exit 1; }
systemctl cat linux-modules-cleanup.service | grep -q keep-pinned || { echo "keep-pinned drop-in missing"; exit 1; }
for d in /usr/lib/modules/*/; do
    [ -e "$d/.keep" ] || pacman -Qoq "$d" >/dev/null 2>&1 || { echo "unprotected module tree $d"; exit 1; }
done
mkdir -p /var/lib/deepidle /usr/local/lib/deepidle

if [ $STEP != step0 ] && [ -e /boot/vmlinuz-psci-efi-test ] && [ -e /etc/grub.d/45_psci_efi ] && [ -d "/usr/lib/modules/$REL" ]; then
    echo "psci-efi-test kernel already installed"
elif [ $STEP != step0 ]; then
    [ -d $STAGE/lib/modules/$REL ] && [ -f $STAGE/boot/vmlinuz-psci-efi-test ] || { echo "staging $STAGE missing"; exit 1; }
    # /boot has no room for two test kernels: the deepidle3 one (a test artifact) goes first
    if [ -e /etc/grub.d/44_deepidle3 ] || [ -e /boot/vmlinuz-deepidle3-test ]; then
        bash /home/jjr/Work/deepidle-harness/deepidle3/install.sh remove
    fi
    cp -a $STAGE/lib/modules/$REL /usr/lib/modules/
    rm -f "/usr/lib/modules/$REL/build"
    chown -R root:root "/usr/lib/modules/$REL"
    touch "/usr/lib/modules/$REL/.keep"
    depmod "$REL"
    install -m 644 $STAGE/boot/vmlinuz-psci-efi-test /boot/vmlinuz-psci-efi-test
    mkinitcpio -k "$REL" -g /boot/initramfs-psci-efi-test.img > /var/lib/deepidle/mkinitcpio-psci-efi.log 2>&1 || true
    [ -s /boot/initramfs-psci-efi-test.img ] || { echo "initramfs failed, see /var/lib/deepidle/mkinitcpio-psci-efi.log"; exit 1; }
fi

if [ $STEP != step0 ]; then
    # GRUB entries (never the default): the test kernel, and the same with maxcpus=1
    sed -e "s/Deep idle test kernel (7.1.12-2-11.35-sep-ARCH-deepidle)/Deep idle PSCI-via-EFI test ($REL)/" \
        -e 's/--id deepidle-test-kernel/--id psci-efi-test-kernel/' \
        -e 's/vmlinuz-deepidle-test/vmlinuz-psci-efi-test/' -e 's/initramfs-deepidle-test.img/initramfs-psci-efi-test.img/' \
        /etc/grub.d/43_deepidle | awk '/^menuentry .Deep idle DTB test/{exit} {print}' | grep -v '^MENU$' | grep -v "^cat <<'MENU'" > /tmp/psci-entry.$$
    { echo "#!/bin/sh"; echo "cat <<'MENU'"; cat /tmp/psci-entry.$$
      sed -e "s/(7.1.12-psci-efi+)/(7.1.12-psci-efi+, maxcpus=1 efi=debug)/" -e 's/--id psci-efi-test-kernel/--id psci-efi-test-kernel-mc1/' \
          -e 's/ panic=10$/ panic=10 maxcpus=1 efi=debug/' /tmp/psci-entry.$$
      echo "MENU"; } > /etc/grub.d/45_psci_efi
    rm -f /tmp/psci-entry.$$
    chmod 755 /etc/grub.d/45_psci_efi
    grub-mkconfig -o /boot/grub/grub.cfg > /var/lib/deepidle/grub-mkconfig-psci-efi.log 2>&1
    grep -q "id psci-efi-test-kernel " /boot/grub/grub.cfg && grep -q "id psci-efi-test-kernel-mc1" /boot/grub/grub.cfg || { echo "GRUB entries missing, see log"; exit 1; }
fi

if [ $STEP = ram ]; then
    # Own GRUB entry: the test kernel with the RAM-only initramfs, no root= and no cryptdevice
    bash $H/ram/build.sh /boot/initramfs-psci-ram.img.tmp >/dev/null && mv /boot/initramfs-psci-ram.img.tmp /boot/initramfs-psci-ram.img
    cat > /etc/grub.d/46_psci_ram <<'G'
#!/bin/sh
cat <<'MENU'
menuentry 'Deep idle PSCI hotplug RAM-only test' --class gnu-linux --id psci-ram-kernel {
    insmod part_gpt
    insmod fat
    search --no-floppy --fs-uuid --set=root 6407-ED7C
    linux /vmlinuz-psci-efi-test rdinit=/init panic=10 maxcpus=1 loglevel=7 psci_ram_cycles=3
    initrd /initramfs-psci-ram.img
}
MENU
G
    # a free run of 64 ESP clusters (256 KB) at the top of the FAT, for the raw log
    RAWOFF=$(python3 -I - <<'PY'
import struct
f=open('/dev/nvme0n1p4','rb'); b=f.read(512)
bps,spc,rsv,nfat=struct.unpack('<HBHB',b[11:17]); fatsz=struct.unpack('<I',b[36:40])[0]
f.seek(rsv*bps); fat=f.read(fatsz*bps); data0=rsv+nfat*fatsz
tot=struct.unpack('<I',b[32:36])[0]; ncl=(tot-data0)//spc+2
need=64*4096//(bps*spc); run=0
for i in range(min(ncl,len(fat)//4)-1,1,-1):
    if struct.unpack_from('<I',fat,4*i)[0]&0x0fffffff: run=0
    else:
        run+=1
        if run>=need: print((data0+(i-2)*spc)*bps); break
PY
)
    [ -n "$RAWOFF" ] || { echo "no free ESP run for the raw log"; exit 1; }
    sed -i "s/psci_ram_cycles=3/psci_ram_raw=$RAWOFF psci_ram_cycles=3/;s/psci_ram_cycles=3/psci_ram_cycles=${RAM_CYCLES:-3}${RAM_WAIT:+ psci_ram_wait=$RAM_WAIT}/" /etc/grub.d/46_psci_ram
    chmod 755 /etc/grub.d/46_psci_ram
    grub-mkconfig -o /boot/grub/grub.cfg > /var/lib/deepidle/grub-mkconfig-psci-ram.log 2>&1
    grep -q "id psci-ram-kernel" /boot/grub/grub.cfg || { echo "RAM entry missing"; exit 1; }
fi

gcc -O2 -o /usr/local/lib/deepidle/mmio-read $H/../mmio/mmio-read.c || exit 1
gcc -O2 -o /usr/local/lib/deepidle/scan-magic $H/../mmio/scan-magic.c || exit 1
install -m 755 $H/early.sh /usr/local/lib/deepidle/psci-efi-early.sh
install -m 755 $H/run.sh /usr/local/lib/deepidle/psci-efi-run.sh
install -m 644 $H/psci-efi-early.service $H/psci-efi-run.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable psci-efi-early.service psci-efi-run.service

# Arm one boot
echo $STEP > /var/lib/deepidle/psci-efi-armed
cp $BIN /boot/m1n1/boot.bin.tmp && sync && mv /boot/m1n1/boot.bin.tmp /boot/m1n1/boot.bin && sync
case $STEP in step1m|suspend) NE=psci-efi-test-kernel-mc1 ;; ram) NE=psci-ram-kernel ;; step0) NE= ;; *) NE=psci-efi-test-kernel ;; esac
[ -n "$NE" ] && grub-editenv /boot/grub/grubenv set next_entry=$NE
echo "armed $STEP: boot.bin $(sha256sum /boot/m1n1/boot.bin | cut -c1-16)${NE:+, next_entry $NE}."
echo "Reboot when ready. Results: /var/lib/deepidle/results-psci-efi-$STEP-*/"
