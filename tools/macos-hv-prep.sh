#!/bin/bash
# macOS side of the Aura hypervisor sleep trace (docs/s2r-plan.md, Phase 3). Run once in macOS:
#   curl -fsSL https://raw.githubusercontent.com/JJRPF/Aurora-DeepIdle/<branch>/tools/macos-hv-prep.sh | bash
# Remove what it installed:
#   curl -fsSL .../tools/macos-hv-prep.sh | bash -s -- remove
#
# It does three things:
# 1. Installs a sleep job (/usr/local/bin/hvsleep.sh and /Library/LaunchDaemons/local.hvsleep.plist).
#    It runs at every boot but does nothing unless the boot-args contain hvsleep=1, which only the
#    hypervisor run passes. With that marker it waits 5 minutes, schedules a wake 5 minutes later
#    and puts macOS to sleep (log: /var/log/hvsleep.log).
# 2. Collects what the hypervisor run needs: the macOS version, FileVault and SIP status, the
#    installed kernelcache, the volume layout (to point the guest at this macOS), the live device
#    tree (ioreg) and the power settings and sleep history (pmset).
# 3. Copies it all to the controller (asks for its ssh login, e.g. user@host; nothing is stored).
# Reads and copies only; the one change to this Mac is the sleep job above.
set -euo pipefail

# Everything runs inside main(), so bash has read the whole script before any command can
# read from stdin (with curl | bash, stdin is the script itself).
main() {
[ "$(uname -s)" = Darwin ] || { echo "run this in macOS"; exit 1; }
TTY=/dev/tty
ask() { local a; printf '%s' "$1" > $TTY; read -r a < $TTY; printf '%s' "$a"; }

if [ "${1:-}" = remove ]; then
    sudo launchctl bootout system/local.hvsleep 2>/dev/null || true
    sudo rm -f /Library/LaunchDaemons/local.hvsleep.plist /usr/local/bin/hvsleep.sh
    echo "sleep job removed (/var/log/hvsleep.log kept, if it exists)"
    exit 0
fi

echo "== Aura hypervisor test prep: administrator password for sudo"
sudo -v < $TTY

# 1. Sleep job
sudo mkdir -p /usr/local/bin
sudo tee /usr/local/bin/hvsleep.sh > /dev/null <<'EOF'
#!/bin/bash
# Aura hypervisor sleep test: does nothing unless booted with the boot-arg hvsleep=1.
sysctl -n kern.bootargs | grep -q 'hvsleep=1' || exit 0
exec >> /var/log/hvsleep.log 2>&1
echo "$(date) hvsleep: waiting 5 min"
sleep 300
pmset schedule wake "$(date -v+5M '+%m/%d/%y %H:%M:%S')"
echo "$(date) hvsleep: sleeping now"
pmset sleepnow
EOF
sudo tee /Library/LaunchDaemons/local.hvsleep.plist > /dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.hvsleep</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>/usr/local/bin/hvsleep.sh</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
sudo chown root:wheel /usr/local/bin/hvsleep.sh /Library/LaunchDaemons/local.hvsleep.plist
sudo chmod 755 /usr/local/bin/hvsleep.sh
sudo chmod 644 /Library/LaunchDaemons/local.hvsleep.plist
plutil -lint /Library/LaunchDaemons/local.hvsleep.plist
echo "sleep job installed (inactive without hvsleep=1)"

# 2. Collect
D=$(mktemp -d /tmp/hvprep.XXXXXX)
O=$D/macos-hv-prep-$(date +%Y%m%d-%H%M%S)
mkdir -p "$O"
run() { local f=$1; shift; "$@" > "$O/$f" 2>&1 || echo "(exit $?)" >> "$O/$f"; }
run sw_vers.txt sw_vers
run uname.txt uname -a
run filevault.txt fdesetup status
run csrutil.txt csrutil status
run bootargs.txt sysctl kern.bootargs kern.osversion kern.version hw.model
run nvram.txt nvram -p
run diskutil-info-root.txt diskutil info /
run diskutil-info-root.plist diskutil info -plist /
run diskutil-apfs.txt diskutil apfs list
run diskutil-apfs.plist diskutil apfs list -plist
run diskutil-list.txt diskutil list
run bless.txt bless --info --getBoot
run pmset-settings.txt pmset -g
run pmset-custom.txt pmset -g custom
run pmset-sched.txt pmset -g sched
run pmset-assertions.txt pmset -g assertions
run pmset-log.txt pmset -g log
run hardware.txt system_profiler SPHardwareDataType SPSoftwareDataType
run ioreg-devicetree.txt ioreg -p IODeviceTree -l -w0
run ioreg-power.txt ioreg -r -c IOPMrootDomain -l -w0
run kextstat.txt kmutil showloaded --list-only

# The kernelcache of the running system: Preboot/<volume group>/boot/<hash>/.../kernelcache
VG=$(diskutil info -plist / | plutil -extract APFSVolumeGroupID raw - 2>/dev/null || true)
KC_LIST=$O/kernelcache-candidates.txt
sudo find /System/Volumes/Preboot -path '*com.apple.kernelcaches/kernelcache' \
    -exec ls -lT {} \; > "$KC_LIST" 2>&1 || true
KC=""
if [ -n "$VG" ]; then
    KC=$(sudo find "/System/Volumes/Preboot/$VG/boot" -path '*com.apple.kernelcaches/kernelcache' \
         -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
fi
[ -n "$KC" ] || KC=$(sudo find /System/Volumes/Preboot -path '*com.apple.kernelcaches/kernelcache' \
         -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
if [ -n "$KC" ]; then
    sudo cp "$KC" "$O/kernelcache"
    sudo chown "$(id -u)" "$O/kernelcache"
    echo "volume group $VG; copied $KC" >> "$KC_LIST"
else
    echo "no kernelcache found" >> "$KC_LIST"
fi
[ -e /var/log/hvsleep.log ] && cp /var/log/hvsleep.log "$O/" 2>/dev/null || true

( cd "$D" && tar czf "$(basename "$O").tar.gz" "$(basename "$O")" )
T=$O.tar.gz
echo "collected: $(du -h "$T" | cut -f1) ($(sw_vers -productVersion) $(sw_vers -buildVersion), $(fdesetup status | head -1))"

# 3. Send
DEST=$(ask "Controller ssh login (user@host): ")
[ -n "$DEST" ] || { echo "no destination; the archive stays at $T"; exit 1; }
RDIR=$(ask "Folder on the controller [deepidle/macos]: ")
RDIR=${RDIR:-deepidle/macos}
ssh -o StrictHostKeyChecking=accept-new "$DEST" "mkdir -p '$RDIR'" < $TTY
scp -o StrictHostKeyChecking=accept-new "$T" "$DEST:$RDIR/" < $TTY
echo "sent $(basename "$T") to the controller's $RDIR/"
rm -rf "$D"
echo "Done. Boot back into Linux; nothing here runs again unless booted with hvsleep=1."
}

main "$@"
