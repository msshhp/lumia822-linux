#!/bin/bash
# Builds the Lumia 822 kernel (zImage with EFI stub) on Linux/WSL.
# Needs: build-essential gcc-arm-linux-gnueabihf bc bison flex libssl-dev libelf-dev cpio xz-utils wget
#
#   kernel/build.sh [workdir]      (default: out/kernel) -> <workdir>/zImage
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${1:-$HERE/../out/kernel}
VER=7.3
mkdir -p "$WORK"; cd "$WORK"
[ -f linux-$VER.tar.xz ] || wget -q https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$VER.tar.xz
if [ ! -d linux-$VER ]; then
    tar -xf linux-$VER.tar.xz
    for p in "$HERE"/patches/*.patch; do echo "applying $(basename "$p")"; patch -d linux-$VER -p1 -s < "$p"; done
fi
cd linux-$VER
cp "$HERE/lumia822.config" .config
export ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
make olddefconfig > /dev/null
make -j"$(nproc)" zImage
cp arch/arm/boot/zImage "$WORK/zImage"
ls -l "$WORK/zImage"
