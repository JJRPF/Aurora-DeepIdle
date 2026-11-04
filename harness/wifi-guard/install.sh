#!/bin/bash
# sudo bash harness/wifi-guard/install.sh [remove]
set -e; here=$(cd "$(dirname "$0")" && pwd)
if [ "${1:-}" = remove ]; then systemctl disable wifi-guard.service || true; rm -f /etc/systemd/system/wifi-guard.service /usr/local/lib/deepidle/wifi-guard.sh; exit 0; fi
install -D -m755 "$here/wifi-guard.sh" /usr/local/lib/deepidle/wifi-guard.sh
install -m644 "$here/wifi-guard.service" /etc/systemd/system/wifi-guard.service
systemctl daemon-reload; systemctl enable wifi-guard.service
