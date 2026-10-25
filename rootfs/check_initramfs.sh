#!/bin/bash
# Lists what a built initramfs contains that matters for a release (no personal keys!).
F=${1:?usage: check_initramfs.sh <initramfs.gz>}
zcat "$F" | cpio -t --quiet 2>/dev/null > /tmp/ls.txt
for p in root/.ssh/authorized_keys etc/dropbear/dropbear_ed25519_host_key etc/wpa_supplicant/wpa_supplicant.conf \
         lib/firmware/qcwcnss8960.mbn lib/firmware/lumia/wlan_nv.bin usr/sbin/avahi-daemon sbin/wpa_supplicant \
         usr/sbin/iw sbin/mkfs.ext4 usr/sbin/dropbear usr/sbin/dnsmasq bin/regdump sbin/lumia-setup etc/local.d/start.sh init; do
    grep -qx "\./$p\|$p" /tmp/ls.txt && echo "present: $p" || echo "absent:  $p"
done
