# GH-10: sourced from /etc/default/update-m1n1 (appended after the SEP/DTBS lines).
# Boots the PMP and the T602x energy model on the J414s: m1n1 with the DT-headroom fix, and
# a J414s DTB built from the matching kernel source (t6020-j414s-pmp.dts + patches/gh10-t602x-
# energy-model-7.2.11.patch). The DTB is only used while it matches the installed linux-aurora;
# after a kernel update that has not been re-checked, the stock DTBs go in and the PMP stays off
# (a warning lands in /var/log/gh10-pmp-em.log) instead of booting a DTB from another kernel.
G=/usr/local/lib/gh10
if [ -s $G/m1n1-pmpfix.bin ] && [ -s $G/t6020-j414s-pmp-em.dtb ] && \
   [ "$(pacman -Q linux-aurora 2>/dev/null | cut -d' ' -f2)" = "$(cat $G/PKGVER 2>/dev/null)" ]; then
    M1N1=$G/m1n1-pmpfix.bin
    DTBS="$(echo "$DTBS" | grep -v '/t6020-j414s\.dtb$') $G/t6020-j414s-pmp-em.dtb"
else
    echo "$(date '+%F %T') PMP+EM DTB not used: linux-aurora $(pacman -Q linux-aurora 2>/dev/null | cut -d' ' -f2) vs built for $(cat $G/PKGVER 2>/dev/null)" >> /var/log/gh10-pmp-em.log
fi
