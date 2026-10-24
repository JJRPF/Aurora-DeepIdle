#!/bin/bash
# Boot target helper for the hypervisor runs (asahi-bless, NVRAM).
#   list         read only: boot candidates and the current/next targets
#   next <name>  boot <name> once on the next boot (the default target stays)
#   clear-next   drop a pending one-time target
set -eu
case "${1:-list}" in
list)
    asahi-bless --list-volumes
    echo "default: $(asahi-bless --get-boot 2>&1)"
    echo "next:    $(asahi-bless --get-boot --next 2>&1)"
    ;;
next)
    [ -n "${2:-}" ] || { echo "usage: $0 next <volume name>"; exit 2; }
    asahi-bless --next --set-boot "$2" --yes
    echo "next:    $(asahi-bless --get-boot --next 2>&1)"
    ;;
clear-next)
    asahi-bless --clear-next --yes
    ;;
*) echo "usage: $0 list|next <name>|clear-next"; exit 2 ;;
esac
