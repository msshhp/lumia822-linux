#!/bin/bash
# Builds the Lumia 822 Alpine initramfs (\linux\initramfs.gz). Run on Linux/WSL as root;
# needs wget, cpio, gzip and arm-linux-gnueabihf-gcc.
#
#   build_rootfs.sh [output.gz]
#
# Optional environment:
#   AUTHORIZED_KEYS=<file>  bake an SSH public key file in as root's authorized_keys (personal builds;
#                           otherwise put \linux\authorized_keys on EFIESP, see docs)
#   HOSTKEY_DIR=<dir>       bake in a fixed dropbear host key (else one is generated on first boot)
#
# The release build uses neither, so it contains no personal keys.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$HERE/initramfs.gz}
ALPINE=v3.22
MINIROOTFS=alpine-minirootfs-3.22.7-armv7.tar.gz
MIRROR=https://dl-cdn.alpinelinux.org/alpine
PACKAGES="dropbear dnsmasq wpa_supplicant iw avahi e2fsprogs"
# Wi-Fi NV (calibration) file accepted by the 2012 Windows Phone Riva firmware: the first prima
# release (Qualcomm open source, mirrored by LineageOS). Newer NV formats are rejected (err=5).
NV_URL=https://raw.githubusercontent.com/LineageOS/android_vendor_qcom_opensource_wlan_prima/295189bdc1f9d9ce4f01e1c67662aaad2d64348a/firmware_bin/WCNSS_qcom_wlan_nv.bin
NV_SHA256=7514b311cbe1065d743b58e0300efcf675a8014ea1b3b16e0655eeac17fd99e5

CACHE=${CACHE:-/var/cache/lumia822-build}
R=$(mktemp -d /tmp/lumia-rootfs.XXXXXX)
trap 'rm -rf "$R"' EXIT
mkdir -p "$CACHE"

# --- tools and inputs (cached) ---
APK_STATIC=$CACHE/apk.static
if [ ! -x "$APK_STATIC" ]; then
    v=$(wget -qO- $MIRROR/$ALPINE/main/x86_64/APKINDEX.tar.gz | tar -xzO APKINDEX |
        grep -A1 '^P:apk-tools-static$' | sed -n 's/^V://p')
    wget -qO "$CACHE/apk-tools-static.apk" "$MIRROR/$ALPINE/main/x86_64/apk-tools-static-$v.apk"
    tar -xzf "$CACHE/apk-tools-static.apk" -C "$CACHE" sbin/apk.static 2>/dev/null
    mv "$CACHE/sbin/apk.static" "$APK_STATIC"
fi
[ -f "$CACHE/$MINIROOTFS" ] ||
    wget -qO "$CACHE/$MINIROOTFS" "$MIRROR/$ALPINE/releases/armv7/$MINIROOTFS"
[ -f "$CACHE/wlan_nv.bin" ] || wget -qO "$CACHE/wlan_nv.bin" "$NV_URL"
echo "$NV_SHA256  $CACHE/wlan_nv.bin" | sha256sum -c --quiet

# --- base system + packages (signatures checked against Alpine's keys from the minirootfs) ---
tar -xzf "$CACHE/$MINIROOTFS" -C "$R"
printf '%s\n' "$MIRROR/$ALPINE/main" "$MIRROR/$ALPINE/community" > "$R/etc/apk/repositories"
"$APK_STATIC" --root "$R" --arch armv7 --keys-dir "$R/etc/apk/keys" --no-scripts --no-cache \
    -U add $PACKAGES > /dev/null
# what the skipped pre-install scripts would have done: avahi's system user
grep -q '^avahi:' "$R/etc/group" || echo 'avahi:x:86:' >> "$R/etc/group"
grep -q '^avahi:' "$R/etc/passwd" ||
    echo 'avahi:x:86:86:avahi:/var/run/avahi:/sbin/nologin' >> "$R/etc/passwd"
grep -q '^avahi:' "$R/etc/shadow" || echo 'avahi:!::0:::::' >> "$R/etc/shadow"
sed -i 's/^#\?enable-dbus=.*/enable-dbus=no/; s/^#\?host-name=.*/host-name=lumia822/;
        s/^#\?use-ipv6=.*/use-ipv6=no/; s/^#\?publish-workstation=.*/publish-workstation=yes/' \
    "$R/etc/avahi/avahi-daemon.conf"

# --- Lumia files ---
arm-linux-gnueabihf-gcc -static -O2 -o "$R/bin/regdump" "$HERE/regdump.c"
install -m 0755 "$HERE/init" "$R/init"
install -D -m 0755 "$HERE/wifi-start.sh" "$R/etc/local.d/start.sh"
install -m 0755 "$HERE/lumia-reboot" "$R/sbin/lumia-reboot"
install -m 0755 "$HERE/lumia-setup" "$R/sbin/lumia-setup"
sed -i 's/\r$//' "$R/init" "$R/etc/local.d/start.sh" "$R/sbin/lumia-reboot" "$R/sbin/lumia-setup"
install -D -m 0644 "$CACHE/wlan_nv.bin" "$R/lib/firmware/lumia/wlan_nv.bin"
sed -i 's/^root:[^:]*:/root:*:/' "$R/etc/shadow"      # no root password: SSH keys / serial console only
mkdir -p "$R/root/.ssh" "$R/etc/dropbear" "$R/etc/wpa_supplicant" && chmod 700 "$R/root/.ssh"
if [ -n "$AUTHORIZED_KEYS" ]; then install -m 0600 "$AUTHORIZED_KEYS" "$R/root/.ssh/authorized_keys"; fi
if [ -n "$HOSTKEY_DIR" ]; then install -m 0600 "$HOSTKEY_DIR"/dropbear_*_host_key "$R/etc/dropbear/"; fi
echo lumia822 > "$R/etc/hostname"
mknod -m 600 "$R/dev/console" c 5 1 2>/dev/null || true
mknod -m 666 "$R/dev/null" c 1 3 2>/dev/null || true
mknod -m 620 "$R/dev/tty0" c 4 0 2>/dev/null || true

(cd "$R" && find . | cpio -o -H newc --quiet | gzip -9) > "$OUT"
ls -l "$OUT"
