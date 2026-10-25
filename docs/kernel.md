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

## Patches

| Patch | What and why |
|---|---|
| `0001-efi-allow-EFI_EARLYCON-on-ARM` | `EFI_EARLYCON` depends on `!ARM` upstream; it works on ARM with 0002. |
| `0002-mm-early_ioremap-ARM-late-fixmap` | after `early_ioremap_reset()` ARM had no `__late_set_fixmap` and hit `BUG()`; ARM can keep using `__set_fixmap`. |
| `0003-clk-qcom-rpm-vote-PXO-and-CXO-for-apps` | **the Wi-Fi freeze fix**: mainline never votes the PXO/CXO crystals for the apps CPU. When Riva starts and sends its own RPM requests, the RPM may switch PXO off and the whole SoC stops (CPU, timer). Downstream kernels vote them through `msm_xo`. |
| `0004-remoteproc-qcom_wcnss-no-auto-boot` | Riva is started from userspace (`echo start > /sys/class/remoteproc/remoteproc0/state`), after USB/SSH are up, so a Riva problem can't stop the boot. |
| `0005-soc-qcom-wcnss_ctrl-optional-handshake` | DT flag `lumia,no-ctrl-handshake`: the Windows Phone 8 Riva firmware has no `WCNSS_CTRL` channel; skip the version/NV handshake and create the wcn36xx device directly. |
| `0006-wcn36xx-treat-API-0.x-firmware-as-old` | that firmware reports API 0.1.1.0; it needs the v0 `config_bss`/`config_sta` messages, no feature-caps exchange and the old beacon-miss format (like the 1.2.2.24 firmware). |

These are workarounds for this phone, not upstream-ready patches; 0003 and 0006 are the most likely
upstream candidates.
