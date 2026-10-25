# Wi-Fi (Riva / WCN3660)

The MSM8960's Wi-Fi/BT/FM block is **Riva** (WCNSS), a separate ARM core with its own firmware, plus the
external **WCN3660** radio ("iris"). Linux drivers: `qcom_wcnss` (remoteproc: loads and starts Riva),
`qcom_smd` (shared-memory channels), `wcnss_ctrl`, `wcn36xx` (mac80211 driver).

## How it is brought up

[`rootfs/wifi-start.sh`](../rootfs/wifi-start.sh) (runs at boot):

1. If `/lib/firmware/qcwcnss8960.mbn` is missing, mount the Windows `MainOS` partition read-only and copy
   `Windows\System32\qcwcnss8960.mbn` (the phone's own firmware; 2,006,492 bytes, ELF loading at
   `0x8F000000`). It is authenticated by TrustZone (PAS id 6), so it must be Qualcomm-signed - this one is.
2. `echo start > /sys/class/remoteproc/remoteproc0/state`.
3. Set a MAC address (the NV file has none): `02:` + 5 bytes of `md5("lumia822-wlan-" + eMMC serial)`.
4. **`iw dev wlan0 set power_save off` before associating** (see below), `wpa_supplicant`, `udhcpc`.
5. Watchdog: if the gateway stops answering 3 checks (60 s apart) in a row, reconnect.

Configuration: `/etc/wpa_supplicant/wpa_supplicant.conf`, installed at boot from
`C:\EFIESP\linux\wpa_supplicant.conf`. Log: `/var/log/wifi.log`.

## Device tree

[`dts/build_wifi_dtb.sh`](../dts/build_wifi_dtb.sh), ported from `qcom-apq8064.dtsi` (Riva block is the
same) and matching the msm8960 WCNSS series that went upstream in 2026:

- reserved memory: SMEM `0x80000000` (2 MB), WCNSS `0x8F000000` (7 MB); hwmutex `0x1200600`, `smem`,
  `smsm` (apps + wcnss, IRQ 204), SCM (`qcom,scm-apq8064`), TLMM with the WLAN pins (GPIO 84-88).
- **RPM clock controller** (`qcom,rpmcc-apq8064`), and USB clocks as upstream (`iface` = Daytona
  fabric). Without USB holding the fabric clock, USB stops once rpmcc exists. Do not give SCM a `core`
  clock: its enable/disable around every call votes the fabric down to 0.
- RPM regulators: S2 1.3 V, S3 (VDD_CX) 1.05-1.15 V, S4 1.8 V, L10 3.0 V, L24 (VDD_MX) 1.05-1.15 V, LVS2.
  The minimum matters: the regulator core programs the range minimum, and expressatt's 0.5/0.75 V
  minimums for S3/L24 are wrong here.
- `riva-pil@3200800`: IRQ 199 (watchdog), smsm bit 6 (fatal), firmware `qcwcnss8960.mbn`; iris =
  `qcom,wcn3660`; SMD edge IRQ 198, `qcom,ipc = <&l2cc 8 25>`.
- `wcnss` node: `qcom,smd-channels = "sys_mon"`, `lumia,no-ctrl-handshake`,
  `firmware-name = "lumia/wlan_nv.bin"` (the NV file for wcn36xx).

## What was wrong, in order (useful for other old Qualcomm phones)

1. **SoC hard-freeze < 0.5 s after Riva leaves reset** (`qcom_pas_auth_and_reset` returns 0, then nothing,
   not even a timer tick). Cause: the apps processor never voted for the **PXO/CXO** crystals in the RPM.
   Riva's first RPM requests make the RPM re-aggregate and it turns PXO off. Fix: kernel patch 0003.
   (Bus-fabric votes alone did not help; debug approach: busy-loop prints of `jiffies`/`local_clock()`
   right after the TrustZone call.)
2. **No `WCNSS_CTRL` channel**: the 2012 firmware exposes `APPS_RIVA_CTRL` (that is DIAG - sending the
   version request makes Riva assert in `diagpkt.c`), `WLAN_CTRL`, `APPS_RIVA_DATA`, BT, FM, `sys_mon`.
   Fix: patch 0005; wcn36xx talks to `WLAN_CTRL` itself.
3. **NV rejected** (`hal_load_nv response failed err=5`): only the very first prima NV format is accepted.
4. **`config_bss`/`config_sta` rejected** (status 5) after association: the firmware (API 0.1.1.0) needs
   the v0 message layout. Fix: patch 0006.
5. **TX stalls** ("Failed to flush hardware tx queues", TX counter stuck) shortly after connecting: entering
   power save (BMPS) breaks the TX ring with this firmware; disabling power save afterwards does not
   recover it. Fix: power save off before association.

Known quirks: every network is reported on a 5 GHz frequency in scans (a known wcn36xx/firmware
oddity), one `hal_start_scan ... err=5` at startup; both harmless so far. Bluetooth/FM channels exist
but are unused.

## NV file

`wlan/prima/WCNSS_qcom_wlan_nv.bin` from the first prima release (June 2012), Qualcomm's open-source
Android WLAN driver, mirrored by LineageOS:
`https://raw.githubusercontent.com/LineageOS/android_vendor_qcom_opensource_wlan_prima/295189bdc1f9d9ce4f01e1c67662aaad2d64348a/firmware_bin/WCNSS_qcom_wlan_nv.bin`
(28,456 bytes, SHA-256 `7514b311cbe1065d743b58e0300efcf675a8014ea1b3b16e0655eeac17fd99e5`).
Later versions (29,776 / 29,816 bytes) are rejected by this firmware. It is generic calibration data,
not tuned for this phone; the Windows driver's `QCWLAN8960cfg.dat` is a different (config) format.
