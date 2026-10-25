#!/bin/bash
# Builds and signs LL11.efi, the Windows boot application that starts the Linux EFI-stub kernel.
# Run in Git Bash (Windows) or on Linux.
#
#   LLVM_MINGW=<llvm-mingw dir>  OSSLSIGNCODE=<osslsigncode exe>  loader/build.sh [out.efi]
#
# llvm-mingw:   https://github.com/mstorsjo/llvm-mingw/releases (tested: 20260922, msvcrt x86_64)
# osslsigncode: https://github.com/mtrojnar/osslsigncode/releases (tested: 2.14)
# The signing certificate is self-signed; it only has to exist because the boot manager entry has
# testsigning + nointegritychecks set (see docs/boot-chain.md). sign/test.key is created on first run.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$HERE/../out/LL11.efi}
mkdir -p "$(dirname "$OUT")"
B=${LLVM_MINGW:?set LLVM_MINGW to the llvm-mingw directory}/bin
OSC=${OSSLSIGNCODE:-osslsigncode}
X=; [ -x "$B/clang.exe" ] && X=.exe
W() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
cd "$HERE"

if [ ! -f sign/test.key ]; then
    mkdir -p sign
    MSYS_NO_PATHCONV=1 openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
        -keyout sign/test.key -out sign/test.crt -subj "/CN=Lumia Test Signing" \
        -addext "extendedKeyUsage=codeSigning"
fi

# No MOVW/MOVT (literal-pool HIGHLOW relocations like BootShim), no NEON/VFP (not enabled in the
# boot manager context), freestanding; linked as a Windows boot application.
build() {
    "$B/clang$X" --target=thumbv7-pc-windows-msvc -std=c11 -O2 $1 \
        -mno-movt -mfpu=none -mno-implicit-float -fno-vectorize -fno-slp-vectorize \
        -ffreestanding -fno-builtin -fno-stack-protector -c loader.c -o "$T/loader.obj"
    MSYS_NO_PATHCONV=1 "$B/ld.lld$X" -flavor link -subsystem:boot_application \
        -entry:BlApplicationEntry -nodefaultlib -dynamicbase -machine:arm -out:"$(W "$2")" "$(W "$T/loader.obj")"
}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# Every working build had an odd number of HIGHLOW fixups (the .reloc block then ends with an ABSOLUTE
# pad entry, like BootShim). Possibly unnecessary - see docs/boot-chain.md - but kept.
build "" "$T/t.efi"
n=$("$B/llvm-readobj$X" --coff-basereloc "$T/t.efi" | grep -c "Type: HIGHLOW")
if [ $((n % 2)) -eq 0 ]; then build "-DRELOC_PAD" "$OUT"; else cp "$T/t.efi" "$OUT"; fi
"$B/llvm-readobj$X" --coff-basereloc "$OUT" | grep -oE "Type: [A-Z0-9_]+" | sort | uniq -c
echo "NEON/VFP instructions: $("$B/llvm-objdump$X" -d "$OUT" | grep -cE '\sv[a-z]+[0-9.]*\s' || true)"

# PE header as in BootShim (lld will not drop DYNAMIC_BASE etc. on ARM)
pe=$(od -An -tu4 -j 60 -N 4 "$OUT" | tr -d ' '); opt=$((pe + 24))
w16() { printf "\\x$(printf %02x $(($2 & 255)))\\x$(printf %02x $((($2 >> 8) & 255)))" |
        dd of="$OUT" bs=1 seek=$1 conv=notrunc 2>/dev/null; }
w16 $((pe + 22)) 0x122   # FileHeader.Characteristics = EXECUTABLE_IMAGE|LARGE_ADDRESS_AWARE|32BIT_MACHINE
w16 $((opt + 40)) 0      # MajorOperatingSystemVersion
w16 $((opt + 42)) 0      # MinorOperatingSystemVersion
w16 $((opt + 48)) 1      # MajorSubsystemVersion
w16 $((opt + 50)) 0      # MinorSubsystemVersion
w16 $((opt + 70)) 0      # DllCharacteristics

"$OSC" sign -certs "$(W sign/test.crt)" -key "$(W sign/test.key)" -h sha256 \
    -in "$(W "$OUT")" -out "$(W "$OUT.signed")" > /dev/null && mv -f "$OUT.signed" "$OUT"
ls -l "$OUT"
