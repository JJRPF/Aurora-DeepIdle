#!/bin/bash
# A separate macOS 14.8.x volume for the Aura hypervisor sleep trace (docs/s2r-plan.md, Phase 3).
# Asahi's m1n1-hypervisor guide pins 14.8.3 for the M1-M3 series; Apple's catalog no longer offers
# it (checked 2026-10-24: only 14.8.7, 14.8.8, 14.8.9), so the guest is 14.8.9, the same Sonoma XNU
# line. macOS 15 and later need SPTM, which Aura does not load. The everyday macOS and Linux stay.
#
# Step 1, in the everyday macOS (downloads the installer, adds an empty volume, opens the installer):
#   curl -fsSL https://raw.githubusercontent.com/JJRPF/Aurora-DeepIdle/GH-8-S2R-NextSteps/tools/macos-hv-testvol.sh | bash
# Step 2, in the new macOS 14.8.3, after Setup Assistant (turns off its automatic updates, then
# runs macos-hv-prep.sh: the sleep job and the data the hypervisor run needs):
#   curl -fsSL .../tools/macos-hv-testvol.sh | bash -s -- setup
set -euo pipefail

NAME=macOSTest
# Guest version: 14.8.9 by default; HV_GUEST=13.7.8 picks the Ventura fallback (never tried as a guest).
# Apple's software update catalog entries (the pkg, its size and SHA-1 as listed there), used when
# softwareupdate no longer lists the version.
WANT=${HV_GUEST:-14.8.9}
case "$WANT" in
14.8.9) # product 140-88558, build 23J631
    APPNAME="Install macOS Sonoma.app"
    PKG_URL=https://swcdn.apple.com/content/downloads/13/30/140-88558-A_TN3FIE7J63/p61cqj3ktmcqilz3q64ls4ekp1os9c8qbp/InstallAssistant.pkg
    PKG_SIZE=13654790295
    PKG_SHA1=10632733f9b4ab1397fffc98b53e6790e4c2c1b0 ;;
13.7.8) # product 093-22004, build 22H730
    APPNAME="Install macOS Ventura.app"
    PKG_URL=https://swcdn.apple.com/content/downloads/09/46/093-22004-A_QNZEDC334I/phigx2zvoggml6sh79my4y51fnvgy8hix4/InstallAssistant.pkg
    PKG_SIZE=12205110942
    PKG_SHA1=072098c6b951701714537d333f8e7dded6d64390 ;;
*) echo "HV_GUEST must be 14.8.9 or 13.7.8"; exit 1 ;;
esac
BRANCH=GH-8-S2R-NextSteps
RAW=https://raw.githubusercontent.com/JJRPF/Aurora-DeepIdle/$BRANCH/tools

# Everything runs inside main(), so bash has read the whole script before any command can
# read from stdin (with curl | bash, stdin is the script itself).
main() {
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || { echo "run this in macOS on the Mac"; exit 1; }
TTY=/dev/tty
ask() { local a; printf '%s' "$1" > $TTY; read -r a < $TTY; printf '%s' "$a"; }
plist() { local f; f=$(mktemp); diskutil info -plist "$1" > "$f"; plutil -extract "$2" raw "$f" 2>/dev/null || true; rm -f "$f"; }
ver=$(sw_vers -productVersion)

if [ "${1:-}" = setup ]; then
    [ "$ver" = "$WANT" ] || { echo "this macOS is $ver; run setup in the new $WANT system"; exit 1; }
    [ "$(plist / VolumeName)" = "$NAME" ] || { echo "this system is not on the $NAME volume"; exit 1; }
    echo "== $NAME setup: administrator password for sudo"
    sudo -v < $TTY
    # The hypervisor guest must stay at exactly $WANT: no automatic macOS updates here.
    sudo softwareupdate --schedule off || true
    for k in AutomaticCheckEnabled AutomaticDownload AutomaticallyInstallMacOSUpdates \
             CriticalUpdateInstall ConfigDataInstall; do
        sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate $k -bool false
    done
    sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool false
    echo "automatic updates off"
    if fdesetup status | grep -q "FileVault is On"; then
        echo "note: FileVault is on here, so each hypervisor run needs someone at the Mac to unlock it."
        echo "      Turning it off (System Settings > Privacy & Security > FileVault) lets the runs go unattended."
    fi
    f=$(mktemp)
    curl -fsSL "$RAW/macos-hv-prep.sh" -o "$f"
    bash "$f"
    rm -f "$f"
    echo
    echo "Next: keep $NAME as the startup disk, shut down, hold the power key, choose Options,"
    echo "and run the recovery script there (see the PR comment)."
    exit 0
fi

# Step 1, in the everyday macOS.
case "$ver" in 1[3-9].*|2*) ;; *) echo "macOS $ver is too old to fetch $WANT"; exit 1 ;; esac
[ "$(plist / VolumeName)" != "$NAME" ] || { echo "this is already $NAME; run with: setup"; exit 1; }
APP="/Applications/$APPNAME"

echo "== administrator password for sudo"
sudo -v < $TTY

# The app's own version is the installer's, not the macOS it installs, so an installer is reused
# only when this script downloaded it (marker file).
MARK=/Users/Shared/hv-testvol-installer.txt
if [ -d "$APP" ] && [ "$(cat $MARK 2>/dev/null)" = "$WANT" ]; then
    echo "reusing the $WANT installer downloaded earlier: $APP"
elif [ -d "$APP" ]; then
    echo "$APP is already here, but not from this script, so its version is unknown."
    echo "Move it to the Trash and run this again; nothing was changed."
    exit 1
else
    echo "== looking for the $WANT full installer"
    list=$(softwareupdate --list-full-installers 2>&1 || true)
    if grep -q "Version: $WANT," <<< "$list"; then
        echo "== downloading $WANT (about 14 GB)"
        sudo softwareupdate --fetch-full-installer --full-installer-version $WANT
    else
        echo "softwareupdate does not list $WANT; using the catalog's InstallAssistant.pkg."
        pkg=/Users/Shared/InstallAssistant-$WANT.pkg
        echo "== downloading $WANT (about 14 GB, resumable)"
        curl -fL -C - "$PKG_URL" -o "$pkg"
        [ "$(stat -f %z "$pkg")" = "$PKG_SIZE" ] || { echo "size mismatch: not $PKG_SIZE bytes; delete $pkg and retry"; exit 1; }
        echo "== checking SHA-1"
        [ "$(shasum -a 1 "$pkg" | cut -d' ' -f1)" = "$PKG_SHA1" ] || { echo "SHA-1 mismatch; delete $pkg and retry"; exit 1; }
        sudo installer -pkg "$pkg" -target /
        rm -f "$pkg"
    fi
    [ -d "$APP" ] || { echo "the download did not leave $APP"; exit 1; }
    echo "$WANT" > $MARK
fi

C=$(plist / APFSContainerReference)
[ -n "$C" ] || { echo "cannot find the APFS container of /"; exit 1; }
if diskutil list "$C" | grep -q " $NAME "; then
    echo "volume $NAME already exists in $C"
else
    free=$(diskutil apfs list -plist "$C" > /tmp/apfs.plist; plutil -extract Containers.0.CapacityFree raw /tmp/apfs.plist)
    rm -f /tmp/apfs.plist
    echo
    echo "Adds an empty APFS volume \"$NAME\" to $C (the container of this macOS; $((free / 1000000000)) GB free)."
    echo "It shares the free space; nothing on the existing volumes changes."
    [ "$(ask 'Type yes to continue: ')" = yes ] || { echo "cancelled"; exit 1; }
    sudo diskutil apfs addVolume "$C" APFS "$NAME"
fi

cat <<EOF

The installer opens now. In it:
  1. Continue, agree, and choose the disk "$NAME" (Show All Disks if needed). Never Macintosh HD.
  2. It restarts on its own and installs $WANT onto $NAME (about 30 minutes).
  3. Setup Assistant on the new system: a local admin account (any name and password, no Apple
     Account), and leave "FileVault" off when it asks, so the hypervisor runs need nobody at the Mac.
     Skip Location, Analytics, Screen Time and Siri.
  4. In the new system, open Terminal and run:
       curl -fsSL $RAW/macos-hv-testvol.sh | bash -s -- setup
EOF
open "$APP"
}

main "$@"
