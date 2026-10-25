# Userspace, persistence and networking

## Initramfs

[`rootfs/build_rootfs.sh`](../rootfs/build_rootfs.sh) (Linux/WSL, as root) builds `initramfs.gz`:

- Alpine 3.22 armv7 minirootfs + `dropbear dnsmasq wpa_supplicant iw avahi e2fsprogs`, installed with
  Alpine's static `apk` (signatures checked against the minirootfs keys, `--no-scripts`; the avahi user
  that the skipped script would create is added by the build script).
- The Lumia files from `rootfs/`: `init`, `wifi-start.sh` (as `/etc/local.d/start.sh`), `lumia-setup`,
  `lumia-reboot`, `regdump` (static, built from `regdump.c`).
- The Wi-Fi NV file, downloaded at build time and checked against a pinned SHA-256 ([wifi.md](wifi.md#nv-file)).
- **No SSH keys, no host key, no Wi-Fi config.** For a personal build, `AUTHORIZED_KEYS=<file>` and
  `HOSTKEY_DIR=<dir>` bake them in. `rootfs/check_initramfs.sh <file>` lists what a build contains.

## init

[`rootfs/init`](../rootfs/init), two stages in one script:

**Stage 1** (from the initramfs): find the `Data` partition by GPT label, mount it with `ntfs3`
(retry with `force` if Windows' dirty flag is set), loop-mount `Data\Linux\rootfs.img`, copy itself over
the image's `/init` if different (so a new initramfs updates the persistent system's init), and
`switch_root` with `PERSIST=1`. If any of that fails, continue in RAM.

**Stage 2** (persistent or RAM):

1. USB transceiver clock fix (see [hardware-notes.md](hardware-notes.md#usb)), then the configfs USB gadget:
   RNDIS (MS OS descriptors, so Windows installs it without a driver) + ACM serial.
   Fixed MACs `02:4c:75:6d:69:01` (phone) / `:02` (PC).
2. Install `authorized_keys` and `wpa_supplicant.conf` from `C:\EFIESP\linux\` if present.
3. dnsmasq (DHCP for the PC: `192.168.42.2`), dropbear (key-only), ntpd, avahi (`lumia822.local`).
4. `/etc/local.d/start.sh` in the background (Wi-Fi, [wifi.md](wifi.md)).
5. Status loop every 10 s: bind the gadget once the controller appears (the USB glue driver probes before
   the clock fix and must be re-bound), bring `usb0` up (`192.168.42.1/24`, default route via the PC
   with metric 400 so Wi-Fi wins), write `dmesg` to `C:\Data\Linux\dmesg.txt` while USB is down, redraw
   the status screen.

Shells: SSH (`ssh root@lumia822.local`), and a root shell on the USB serial port (`/dev/ttyGS0`, shown as
`USB Serial Device (COMx)` on Windows; no password - physical access only).

## Persistent root

`lumia-setup [MB]` (from the RAM system) writes `C:\Data\Linux\rootfs.img` (zero-filled, default 4096 MB),
formats it ext4 (`-E nodiscard`: no working TRIM for this eMMC) and copies the RAM system into it.

The Data partition is a normal Windows NTFS volume; Windows keeps working and sees the image as one
large file. Notes:

- Every hard reset (holding Power, a crash) leaves the NTFS volume flagged dirty. Linux mounts it anyway
  (`force`); Windows runs `chkdsk`/autochk on its next boot. Restart from Linux with `lumia-reboot`.
- Before the `force` fallback existed, a dirty flag silently made Linux run from RAM - if changes vanish
  after a reboot, check the status screen line "persistent storage".

## Internet over USB

Without Wi-Fi, the phone can use the PC's connection: the phone's default route points at
`192.168.42.2` (the PC). On the PC, elevated PowerShell:

```powershell
New-NetNat -Name LumiaNat -InternalIPInterfaceAddressPrefix 192.168.42.0/24
Set-NetIPInterface -InterfaceAlias '<RNDIS adapter, e.g. Ethernet 2>' -Forwarding Enabled
Set-NetIPInterface -InterfaceAlias '<your uplink, e.g. Wi-Fi>' -Forwarding Enabled
```

DNS on the phone: `1.1.1.1`, `8.8.8.8` (`/etc/resolv.conf`, replaced by udhcpc once Wi-Fi is up).
