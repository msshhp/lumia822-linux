# Troubleshooting

| Symptom | Likely cause / what to do |
|---|---|
| Volume Down boot shows the Nokia logo, then black | Boot-app path of exactly 8 characters (rename, e.g. `\LL11.efi`); or `testsigning`/`nointegritychecks` not set; or `LL11.efi` unsigned. |
| `bcdedit /set ... testsigning on` -> "protected by Secure Boot policy" | Unlock stage 2 (SBA NV store) not done. |
| Loader messages stop at `[x]` | It prints each step; missing `\linux\` files show up as errors and the screen stays for 20 s. |
| Kernel text, then the phone restarts after a few seconds | Kernel panic (`panic=3`) - read the last screen lines (take a photo); check `cmdline.txt` and the DTB. |
| Status screen: `persistent storage: NO` | No `C:\Data\Linux\rootfs.img` (run `lumia-setup`), or it couldn't be mounted. |
| Changes lost after a reboot | Same as above - you were running from RAM. |
| `USB: waiting for USB controller` | USB controller did not probe. The transceiver clock fix in `init` failed, or the DT's USB clocks are wrong (with rpmcc, USB must hold the Daytona fabric clock). `C:\Data\Linux\dmesg.txt` has the kernel log (read it from Windows). |
| No RNDIS adapter / IP on the PC | Wait ~30 s after boot; the PC gets `192.168.42.2` by DHCP. Re-plug the cable. |
| USB worked, then the PC can't reach `192.168.42.1` (ARP "incomplete", `usb0` counters frozen) | Seen once, cause unknown, not reproduced under load. Over Wi-Fi: `G=/sys/kernel/config/usb_gadget/g1; U=$(cat $G/UDC); echo "" > $G/UDC; echo $U > $G/UDC; ip addr add 192.168.42.1/24 dev usb0`. Otherwise reboot. |
| Loader: `kernel size` far below ~14 MB, phone resets right after "Entering in SVC mode" | Truncated `zImage` (interrupted copy). Restore from Windows: push a good file to `C:\EFIESP\linux\zImage`. Always check `sha256sum` before copying onto EFIESP. |
| `ssh: Could not resolve hostname lumia822.local` | Windows resolves mDNS natively; some tools (MSYS ssh in Git Bash usually works) may not. Use the IP from the status screen. |
| `Permission denied (publickey)` | Put your public key in `C:\EFIESP\linux\authorized_keys` and reboot, or add it via the USB serial shell. |
| No `wlan0` | `/var/log/wifi.log`. Firmware not found (MainOS not readable?) or Riva failed: `dmesg | grep -iE "wcnss|riva|wcn36xx|remoteproc"`. |
| `wlan0` up but not connected | Missing/wrong `wpa_supplicant.conf`; check `wpa_cli -i wlan0 status`. |
| Connected but no traffic, "Failed to flush hardware tx queues" | Power save got enabled - the hook disables it before connecting; the watchdog reconnects within ~3 minutes. |
| Whole phone freezes when Riva starts | Kernel without patch 0003 (PXO/CXO vote). |
| `ntfs3: volume is dirty` | Normal after a hard reset; Linux mounts with `force`. Boot Windows once to let it check the volume. |
| Windows doesn't boot any more | Hold Volume Down+Power ~10 s to force restart. If Windows itself is broken, restore with your FFU (`thor2`/WPinternals flash mode) - but the boot loaders are only recoverable while they still boot. |
