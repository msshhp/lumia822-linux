# Kernel

Linux **7.3** (kernel.org tarball) + the patches in [`kernel/patches/`](../kernel/patches) + the config
[`kernel/lumia822.config`](../kernel/lumia822.config). Everything needed is built in (no modules).

```bash
kernel/build.sh            # downloads, patches, configures and builds -> out/kernel/zImage
```

Toolchain: `gcc-arm-linux-gnueabihf` 13.3 (Ubuntu 24.04). The resulting `zImage` has the EFI stub and
is booted by `LL11.efi`.

## Config

Base: `/boot/config` of postmarketOS `linux-postmarketos-mainline-7.3-r0` (armv7). Changes on top:

| Change | Why |
|---|---|
| `EFI_EARLYCON=y`, `FB_EFI`, `SYSFB`, `FRAMEBUFFER_CONSOLE` | on-screen console from the first kernel line (needs patch 0001/0002) |
| USB gadget, configfs, RNDIS, ACM `=y` | USB networking and serial console without modules |
| `QCOM_TSENS` off | the tsens child of gcc-msm8960 oopsed |
| lockdown off, `DEVMEM=y`, `STRICT_DEVMEM` off | `/dev/mem` for register access (`regdump`) |
| `NTFS3_FS=y`, `NTFS3_LZX_XPRESS=y`, `NTFS_FS` off | read/write the Windows Data partition; MainOS uses LZX/Xpress |
| `MMC_BLOCK_MINORS=32` | the eMMC has 31 partitions |
| `CFG80211`, `MAC80211`, `WCN36XX`, `QCOM_WCNSS_PIL`, `QCOM_WCNSS_CTRL`, `QCOM_RPROC_COMMON`, `QCOM_MDT_LOADER`, `QCOM_PIL_INFO`, `QCOM_SMD_RPM`, `RPMSG_QCOM_GLINK(_SMEM)` `=y` | Wi-Fi |
| `QCOM_SYSMON` off | without QRTR it makes the WCNSS probe fail ("failed to initialize qmi handle") |
| `EXTRA_FIRMWARE=""` | the Riva firmware is loaded from `/lib/firmware` at runtime (not redistributable) |
| `LOCALVERSION="-lumia"` | |
| `RTC_DRV_PM8XXX=y`, `QCOM_PM8XXX_XOADC=y` | PM8921 RTC and housekeeping ADC (battery voltage/temperature) without modules |
| `CHARGER_PM8921_LITE=y` | the charger driver from patch 0011 |

## Patches

| Patch | What and why |
|---|---|
| `0001-efi-allow-EFI_EARLYCON-on-ARM` | `EFI_EARLYCON` depends on `!ARM` upstream; it works on ARM with 0002. |
| `0002-mm-early_ioremap-ARM-late-fixmap` | after `early_ioremap_reset()` ARM had no `__late_set_fixmap` and hit `BUG()`; ARM can keep using `__set_fixmap`. |
| `0003-clk-qcom-rpm-vote-PXO-and-CXO-for-apps` | **the Wi-Fi freeze fix**: mainline never votes the PXO/CXO crystals for the apps CPU. When Riva starts and sends its own RPM requests, the RPM may switch PXO off and the whole SoC stops (CPU, timer). Downstream kernels vote them through `msm_xo`. |
| `0004-remoteproc-qcom_wcnss-no-auto-boot` | Riva is started from userspace (`echo start > /sys/class/remoteproc/remoteproc0/state`), after USB/SSH are up, so a Riva problem can't stop the boot. |
| `0005-soc-qcom-wcnss_ctrl-optional-handshake` | DT flag `lumia,no-ctrl-handshake`: the Windows Phone 8 Riva firmware has no `WCNSS_CTRL` channel; skip the version/NV handshake and create the wcn36xx device directly. |
| `0006-wcn36xx-treat-API-0.x-firmware-as-old` | that firmware reports API 0.1.1.0; it needs the v0 `config_bss`/`config_sta` messages, no feature-caps exchange and the old beacon-miss format (like the 1.2.2.24 firmware). |
| `0007-clk-qcom-rpm-vote-TCXO-D0-for-XOADC` | votes the PM8921 TCXO D0 buffer on (RPM `CXO_BUFFERS` = 2), as downstream `msm_xo` does for the PMIC ADC and the charger's 19.2 MHz clock. |
| `0008-ARM-qcom-boot-secondary-CPUs-via-parking-protocol` | **second CPU core**: enable-method `lumia,parking-protocol`. The UEFI parks CPU1 in the ACPI parking-protocol mailbox from the MADT (`lumia,parked-address`); the kernel writes the entry point and the CPU ID there and sends an SGI. The mainline Krait ACC/SAW reset (`qcom,kpss-acc-v1`) resets the core, but the secure firmware then never enters the Linux boot address. An online CPU1 cannot be offlined again (`-EPERM`), it would not return to the mailbox. |
| `0009-iio-adc-qcom-pm8xxx-xoadc-use-channel-RSV` | **mainline bug**: the per-channel input reference (`amux_ip_rsv`, `PMIC_IN` for nearly all channels) was never copied from the channel table, so every conversion measured the XO input and all channels read the same. |
| `0010-iio-adc-qcom-pm8xxx-xoadc-PM8921-codes-are-signed` | the PM8921 XOADC result is two's complement (GND about -16000, 0.625 V about -3000, 1.25 V about +9900); read as unsigned, everything between the references and above them came out wrong (e.g. `vph_pwr` 3.74 V instead of 4.09 V). Flipped to offset binary for the unsigned calibration math. |
| `0011-power-supply-minimal-PM8921-charger` | `lumia,pm8921-charger`: programs charge voltage, battery current and USB input current from DT, enables the hardware charger state machine, restarts it after the safety timer expires, limits current at 45 °C and pauses at 50 °C battery temperature, reports `/sys/class/power_supply/{battery,usb}`. See [hardware-notes.md](hardware-notes.md#battery-and-charger). |

These are workarounds for this phone, not upstream-ready patches; 0003, 0006, 0009 and 0010 are the most
likely upstream candidates.
