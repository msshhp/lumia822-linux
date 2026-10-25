# Install guide

Tested on: **Nokia Lumia 822 (RM-845, Verizon), Windows 10 Mobile 15063** (installed on the 822 by
spoofing the model ID, which is a common way to get W10M on it). Other MSM8960 Lumias (820, 920, ...) are
similar but **untested**: GPT layout, regulators and the boot-manager entry may differ.

## 0. What you need

- The phone on Windows 10 Mobile, **Developer mode** on (Settings -> Update & security -> For developers),
  Device Portal and Device Discovery on.
- A Windows PC with a USB cable. For building: Git for Windows (Git Bash), WSL2 Ubuntu 24.04, .NET 8 SDK.
- On the phone (sideloaded through Device Portal, see [unlock.md](unlock.md#phone-access)):
  - **Interop Tools** - to make MTP expose the whole `C:` drive (incl. `C:\EFIESP`).
  - **CMD Injector** - gives a SYSTEM command prompt on TCP port 9999 while the app is open.
- The [release files](https://github.com/msshhp/lumia822-linux/releases/latest) (or build them: [README](../README.md#build-from-source)):
  `LL11.efi`, `linux/zImage`, `linux/lumia822.dtb`, `linux/initramfs.gz`, `linux/cmdline.txt`.

## 1. Unlock the bootloader (once)

Follow **[unlock.md](unlock.md)** exactly. Afterwards UEFI Secure Boot is off and Windows still boots
normally. Without this step the boot manager refuses the self-signed `LL11.efi`.

## 2. Copy the boot files to EFIESP

With Interop Tools' MTP change, the phone's `EFIESP` folder is visible in Explorer
(`This PC\Windows phone\...\EFIESP`, keep the phone unlocked with the screen on). Copy:

```
C:\EFIESP\LL11.efi
C:\EFIESP\linux\zImage
C:\EFIESP\linux\lumia822.dtb
C:\EFIESP\linux\initramfs.gz
C:\EFIESP\linux\cmdline.txt
C:\EFIESP\linux\authorized_keys       <- your SSH public key(s), e.g. ~/.ssh/id_ed25519.pub
C:\EFIESP\linux\wpa_supplicant.conf   <- Wi-Fi settings, see boot/wpa_supplicant.conf.example
```

Alternative without MTP: `tools/windows/push.ps1` (Wi-Fi, through CMD Injector + `recv.exe`).

`authorized_keys` and `wpa_supplicant.conf` are copied into Linux on every boot, so you can change them
later the same way. Use `wpa_passphrase` to store a hashed key instead of the plain password.

> Note on the boot loader name: the boot-manager path must **not** be exactly 8 characters long
> (`\LL9.efi` hangs, `\LL11.efi` works). Keep the name `LL11.efi`.

## 3. Point the Volume-Down boot entry at the loader

In CMD Injector's shell (from the PC: `tools/windows/pr.sh "<command>"` with `LUMIA_WP_IP` set to the
phone's IP; or type it in the app):

```
bcdedit /export C:\Data\Users\Public\Downloads\BCD.backup
bcdedit /set {bd8951c4-eabd-4c6f-aafb-4ddb4eb0469b} testsigning on
bcdedit /set {bd8951c4-eabd-4c6f-aafb-4ddb4eb0469b} nointegritychecks on
bcdedit /set {bd8951c4-eabd-4c6f-aafb-4ddb4eb0469b} path \LL11.efi
bcdedit /enum {bd8951c4-eabd-4c6f-aafb-4ddb4eb0469b}
```

`{bd8951c4-...}` is the "Reset My Phone" application that the boot manager starts when Volume Down is
held at power-on. Copy the BCD backup to your PC. If `testsigning` fails with "protected by Secure Boot
policy", unlock stage 2 is not done.

**Never use Settings -> Reset this phone** afterwards: it does not use this entry and wipes the phone.

## 4. First boot

1. Power the phone off. Hold **Volume Down**, press **Power**, keep Volume Down held until text appears.
2. A status screen shows the kernel, `persistent storage: NO (running from RAM)` and the USB/Wi-Fi state.
3. Connect the USB cable: Windows installs "Remote NDIS Compatible Device" (network) and
   "USB Serial Device (COMx)" (a root shell, no password, any terminal program).
4. SSH: `ssh root@lumia822.local` (Wi-Fi or USB) or `ssh root@192.168.42.1` (USB).

The first boot copies the Wi-Fi firmware from the phone's Windows partition
(`MainOS\Windows\System32\qcwcnss8960.mbn`) into Linux.

## 5. Make it persistent

From RAM, everything is lost at power-off. Create the persistent root (an ext4 image file in
`C:\Data\Linux\`, default 4096 MB, needs that much free space):

```
lumia-setup          # or: lumia-setup 2048
lumia-reboot         # hold Volume Down again while it restarts
```

The status screen now says `persistent storage: yes`. Install software with `apk add ...`.

## Everyday use

| | |
|---|---|
| Boot Linux | power on with Volume Down held |
| Boot Windows | power on normally |
| Restart / power off from Linux | `lumia-reboot` / `lumia-reboot poweroff` (cleanly flushes the NTFS volume) |
| Update kernel/initramfs from Linux | `mount -t vfat /dev/mmcblk0p21 /mnt/efiesp` (EFIESP), copy files, `umount` |
| Logs | `dmesg`, `/var/log/wifi.log`, `C:\Data\Linux\dmesg.txt` (readable from Windows) |
| Internet over USB instead of Wi-Fi | on the PC (elevated PowerShell): `New-NetNat -Name LumiaNat -InternalIPInterfaceAddressPrefix 192.168.42.0/24` |

See [troubleshooting.md](troubleshooting.md) when something doesn't come up.
