# AGENTS.md - working on lumia822-linux

Guide for developers and coding agents (Claude Code, Codex, ...) continuing this project. Read
[README.md](README.md) first, then the doc for the area you touch.

## Current state (2026-10)

Working on a real RM-845 running W10M 15063: unlocked (Spec A), Volume-Down boot into Linux 7.3,
Alpine 3.22 with persistent ext4-image root on the NTFS Data partition, USB RNDIS + ACM, SSH, mDNS
(`lumia822.local`), Wi-Fi (WPA2) with the phone's own Riva firmware. Used as a headless home server.

Not done: battery/charger (PM8921 charger + fuel gauge) - **highest priority before running 24/7**,
backlight, buttons (Volume/Power as input), touch, SD card (SDCC3), second CPU core (SPM/SAW,
`nosmp`), cpufreq, thermal, audio, modem, GPU, Bluetooth (channels `APPS_RIVA_BT_*` exist), clean
upstreamable patches.

## Access to a phone

| Phone runs | Access |
|---|---|
| Linux | `ssh root@lumia822.local` or `ssh root@192.168.42.1` (USB); `tools/lumia-ssh.sh '<cmd>'`; USB serial root shell |
| Windows 10 Mobile | CMD Injector app open -> SYSTEM shell on TCP 9999: `tools/windows/pr.sh '<cmd>'` (`LUMIA_WP_IP=<phone IP>`); files: MTP (`tools/windows/mtp.ps1`) or `tools/windows/push.ps1` |

Booting Linux needs a human: power on with **Volume Down held**. `lumia-reboot` without it lands in
Windows. Ask the user and wait for "it's up" before reconnecting.

## Development loop (kernel / DTB / initramfs)

1. Build on the PC (`kernel/build.sh` in WSL, `dts/*.sh`, `rootfs/build_rootfs.sh` in WSL).
2. If Linux on the phone is reachable, install from Linux - no Windows round trip:
   ```sh
   cat file | ssh root@192.168.42.1 'cat > /tmp/f'        # scp also works
   echo "<sha256 from the PC>  /tmp/f" | sha256sum -c       # never copy an unverified file
   mount -t vfat /dev/mmcblk0p21 /mnt/efiesp               # EFIESP (label EFIESP)
   cp /mnt/efiesp/linux/zImage /mnt/efiesp/linux/zImage.prev   # keep the last working one
   cp /tmp/f /mnt/efiesp/linux/zImage && sync && sha256sum /mnt/efiesp/linux/zImage
   umount /mnt/efiesp; lumia-reboot
   ```
3. If the new build breaks USB/SSH, recovery is a Windows round trip: user boots Windows normally,
   opens CMD Injector, you `push.ps1` the old file back to `C:\EFIESP\linux\`.
4. When USB is dead but the persistent root works, `init` writes `dmesg` to `C:\Data\Linux\dmesg.txt`
   (readable from Windows through CMD Injector/MTP).

Design rule that saved this project several times: **anything risky starts from userspace after SSH is
up** (e.g. Riva: `auto_boot = false`, started by the Wi-Fi hook). A freeze then costs one reboot, not a
Windows round trip.

## Debugging hard freezes

The screen is the only output when the SoC dies. Useful: `dmesg -n 8` before the risky step so kernel
messages go to the framebuffer synchronously (ask the user for a photo), stream `cat /proc/kmsg` over SSH
to the PC, temporary `pr_info("LUMIA-TRACE ...")` lines before each step, and a busy-loop printing
`jiffies`/`local_clock()` to tell "CPU stopped" from "timer stopped". Remove traces before committing
(`git grep LUMIA-TRACE` must be empty).

## Gotchas (each cost hours)

- Boot-manager app path of exactly **8 characters** hangs (`\LL9.efi`). Use `\LL11.efi`.
- Loader: no VFP/NEON, no MOVW/MOVT, no writes to `.data` after the context switch.
- **NTFS dirty flag** after any hard reset: without `force`, `ntfs3` refuses rw and init silently ran from
  RAM, so "persisted" changes vanished. Always check `mount | grep ' / '` (`/dev/loop0` = persistent).
- Restart with `lumia-reboot`, not `reboot -f`.
- An upload loop that ignores failures (`for f in ...; do ssh ...; done; ssh 'cp ...'`) once put a truncated
  zImage on EFIESP and rebooted - looked like a crash, cost a Windows round trip. Verify sha256 on the phone
  before `cp`, and stop on the first error.
- Stage 1 copies the initramfs `/init` over the image's `/init` - keep `rootfs/init` and the deployed
  initramfs in sync, or your edits to the image's `/init` get overwritten.
- Over SSH, `pkill -f <pattern>` matches the SSH session's own command line and kills it.
- Git Bash: `MSYS_NO_PATHCONV=1` for DT paths like `/soc/...`; Windows tools need `cygpath -w` paths.
  Heredocs/`sed` through several shell layers mangle backslashes (`\n` in C strings, `\U` in sed
  replacements) - write files with an editor tool or use `chr(92)` in Python.
- Busybox `dmesg` has no `-w`/`-C`; use `cat /proc/kmsg`.
- With the RPM clock controller present, USB must hold the Daytona fabric clock (DT `iface` clock), and
  SCM must not get a `core` clock.
- Riva: power save must be off **before** association (`iw dev wlan0 set power_save off`).
- Agent safety rules may (rightly) refuse raw writes to boot partitions; the user runs those steps.
- Don't publish personal data: `rootfs/build_rootfs.sh` only bakes in keys when `AUTHORIZED_KEYS`/
  `HOSTKEY_DIR` are set; run `rootfs/check_initramfs.sh` on any initramfs before releasing it.
  No proprietary blobs in the repo or releases (FFU, SBL/UEFI images, engineering SBL3, Riva firmware).

## Conventions

- Shell scripts: bash on the PC, busybox `sh` on the phone; comments explain *why*, at the density of the
  existing files. Partitions by GPT label, not number.
- Kernel changes as patches in `kernel/patches/` (`diff -u` against the kernel.org tree, `patch -p1`),
  one fix per patch, explained in [docs/kernel.md](docs/kernel.md). Config changes go into
  `kernel/lumia822.config` and the table in docs/kernel.md.
- DTB changes as `fdttool` steps in `dts/*.sh` (the build must stay reproducible from the postmarketOS
  expressatt DTB); document new nodes in the relevant doc.
- Releases: `LL11.efi`, `linux/{zImage,lumia822.dtb,initramfs.gz,cmdline.txt}`, `SHA256SUMS`, built from a
  tagged commit and tested on a phone (boot, USB, SSH, Wi-Fi, `lumia-setup` on a fresh image).
