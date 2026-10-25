#!/bin/bash
# Collects the built files into out/release/ (same layout as C:\EFIESP\) plus SHA256SUMS and a zip.
#   tools/make_release.sh <LL11.efi> <zImage> <lumia822.dtb> <initramfs.gz> [version]
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 4 ] || { sed -n '2,3p' "$0"; exit 1; }
V=${5:-dev}
R=$REPO/out/release/lumia822-linux-$V
rm -rf "$R"; mkdir -p "$R/linux"
cp "$1" "$R/LL11.efi"
cp "$2" "$R/linux/zImage"
cp "$3" "$R/linux/lumia822.dtb"
cp "$4" "$R/linux/initramfs.gz"
cp "$REPO/boot/cmdline.txt" "$R/linux/cmdline.txt"
cp "$REPO/boot/wpa_supplicant.conf.example" "$R/linux/wpa_supplicant.conf.example"
# guard against shipping personal data in the initramfs
if zcat "$R/linux/initramfs.gz" | cpio -t --quiet 2>/dev/null |
   grep -qE '(^|/)(root/\.ssh/authorized_keys|etc/dropbear/dropbear_.*_host_key|etc/wpa_supplicant/wpa_supplicant\.conf|lib/firmware/qcwcnss8960\.mbn)$'; then
    echo "initramfs contains keys/config/firmware - refusing"; exit 1
fi
(cd "$R" && sha256sum LL11.efi linux/* > SHA256SUMS && cat SHA256SUMS)
(cd "$REPO/out/release" && rm -f "lumia822-linux-$V.zip" &&
    if command -v zip >/dev/null; then zip -qr "lumia822-linux-$V.zip" "lumia822-linux-$V";
    else powershell -NoProfile -Command "Compress-Archive -Path 'lumia822-linux-$V' -DestinationPath 'lumia822-linux-$V.zip'"; fi)
ls -l "$REPO/out/release/lumia822-linux-$V.zip"
