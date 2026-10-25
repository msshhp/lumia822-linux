# Boot chain

```
power on + Volume Down
 -> PBL -> SBL1 -> SBL2 (patched) -> SBL3 (patched engineering) -> UEFI (patched, Secure Boot off)
 -> Windows Boot Manager (bootmgfw.efi on EFIESP)
 -> BCD entry {bd8951c4-eabd-4c6f-aafb-4ddb4eb0469b} ("Reset My Phone", normally resetphone.efi)
    path \LL11.efi, testsigning on, nointegritychecks on
 -> LL11.efi (loader/loader.c): back to the UEFI context
 -> LoadImage/StartImage \linux\zImage (Linux EFI stub)
      DTB:        \linux\lumia822.dtb  (installed as the EFI device-tree configuration table)
      initramfs:  \linux\initramfs.gz  (LoadFile2 + LINUX_EFI_INITRD_MEDIA_GUID device path)
      cmdline:    \linux\cmdline.txt
```

Without Volume Down the boot manager takes the normal Windows entry, so Windows is unaffected.

## LL11.efi

A Windows *boot application* (PE subsystem 16), not a UEFI application: the boot manager only starts
those. At entry (`BlApplicationEntry`) it restores the firmware's MMU/exception context the boot manager
replaced (same steps as WOA-Project's BootShim), so UEFI boot services work again, then acts as a minimal
UEFI loader. It prints progress (`[1]`..`[8]`) on the screen through the UEFI console and pauses a few
seconds so the messages can be read.

Build: [`loader/build.sh`](../loader/build.sh). Rules found by trial and error on this firmware:

- **No NEON/VFP instructions** (`-mfpu=none -mno-implicit-float -fno-vectorize -fno-slp-vectorize`): VFP
  is not enabled in the boot manager's context and the first VFP instruction faults silently.
- **No MOVW/MOVT relocations** (`-mno-movt`): only literal-pool `IMAGE_REL_BASED_HIGHLOW` fixups (like
  BootShim) were accepted.
- **No writes to the image's own `.data` after the context switch** - keep mutable state on the stack or in
  pool memory.
- PE header like BootShim's: subsystem version 1.0, OS version 0.0, DllCharacteristics 0, Characteristics
  0x122. lld can't produce that on ARM, so the script patches the bytes.
- Signed with any Authenticode certificate (self-signed is fine) - required even with `testsigning`.
- **Boot-application path length:** a path of exactly **8 characters** including the leading backslash
  (`\LL9.efi`, `\HW1.efi`) hangs silently (Nokia logo, then black). Proven by booting the identical
  binary as `\HW1.efi` (hang) and `\HWT1.efi` (runs). 7 and 9+ characters work.
- An odd number of HIGHLOW fixups (`-DRELOC_PAD` adds one) was used in every working build. It was
  introduced while chasing what turned out to be the path-length bug, so it is probably not needed, but
  it is untested without it.

## Memory and display at kernel start

- GOP framebuffer at `0x80400000`, 480x800, 32 bpp BGRX; the panel scans memory directly (no flush).
  Linux uses it via `efifb` + `earlycon=efifb keep_bootcon`.
- Usable low RAM starts at `0x80200000`; the EFI stub decompresses the kernel around `0x81a08000`.
- `0x88E00000-0x8FFFFFFF` is not System RAM in the EFI map (firmware/subsystem carve-outs); the Riva
  firmware region `0x8F000000` (7 MB) is inside it. SMEM is at `0x80000000` (2 MB).

## Command line

[`boot/cmdline.txt`](../boot/cmdline.txt):

```
console=tty0 earlycon=efifb keep_bootcon cma=0 clk_ignore_unused pd_ignore_unused regulator_ignore_unused
maxcpus=1 efi=debug,noruntime,novamap loglevel=8 ignore_loglevel panic=3 rdinit=/init
```

- `clk/pd/regulator_ignore_unused`: the DT does not describe every consumer of what UEFI left on (display!).
- `maxcpus=1`: CPU1 is not started during boot; `init` onlines it 20 s after SSH is up (kernel patch
  0008, UEFI parking-protocol mailbox). `touch /etc/lumia-nosmp` on the root image keeps it offline.
- `efi=noruntime,novamap`: UEFI runtime services are not used.
- `panic=3`: a panic restarts the phone (into Windows unless Volume Down is held).
