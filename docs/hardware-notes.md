# Hardware notes (Lumia 822 / RM-845)

| | |
|---|---|
| SoC | Qualcomm MSM8960 (2x Krait, Adreno 225), "Spec A" Lumia |
| RAM | 1 GB (Linux sees ~841 MB) |
| eMMC | Samsung MAG2GA, 14.6 GiB (kernel quirk: no erase/trim) |
| PMIC | PM8921 (regulators through the RPM) |
| Wi-Fi/BT/FM | Riva (in the SoC) + WCN3660 |
| Display | 480x800, GOP framebuffer at `0x80400000` (BGRX), panel scans memory directly |
| Root key hash | `A0AE29AC24C843250D2DD0FFD409A649B4E4A09ED3B1A78413FB2B94B7476AAB` (no public EDE loader) |
| RPM firmware | 3.0.16845829 |

## eMMC partitions (GPT labels, Linux numbering, after the unlock)

| # | Label | # | Label | # | Label |
|---|---|---|---|---|---|
| p1 | DPP | p12 | BACKUP_SBL2 | p23 | MODEM_FS2 |
| p2 | MODEM_FSG | p13 | BACKUP_SBL3 | p24 | UEFI_RT_NV |
| p3 | SSD | p14 | UEFI | p25 | UEFI_RT_NV_RPMB |
| p4 | SBL1 | p15 | BACKUP_RPM | p26 | MMOS |
| p5 | SBL2 | p16 | TZ | p27 | **MainOS** (NTFS, Windows) |
| p6 | SBL3 | p17 | WINSECAPP | p28 | **Data** (NTFS, `C:\Data`) |
| p7 | BACKUP_UEFI | p18 | BACKUP_BS_NV | p29 | HACK (unlock) |
| p8 | RPM | p19 | UEFI_NV | p30 | IS_UNLOCKED_SBL3 (unlock) |
| p9 | BACKUP_TZ | p20 | PLAT | p31 | UEFI_BS_NV (unlock, SBA store) |
| p10 | BACKUP_WINSECAPP | p21 | **EFIESP** (FAT, boot files) | | |
| p11 | BACKUP_SBL1 | p22 | MODEM_FS1 | | |

The scripts look partitions up by label (`/sys/class/block/mmcblk0p*/uevent`, `PARTNAME=`), not number.

## USB

The USB controller (ChipIdea, `msm_hsusb`, `0x12500000`) only works after a manual clock fix:
`USB_HS1_XCVR_NS` (GCC `0x0090290C`) needs **bit 11 (RCG root enable) and bit 8 (M/N counter enable)**.
UEFI leaves the 60 MHz rate configured, so the Linux clock driver skips `set_rate` and never sets them,
and the branch stays "stuck off". `init` does `NS |= 0xB00` with `regdump -w` and re-binds `msm_hsusb`.
`regdump <base> <offsets...>` / `regdump -w <addr> <value>` is a tiny `/dev/mem` tool (`rootfs/regdump.c`).

USB needs RPM L3 (3.3 V) and L4 (1.8 V), both always-on in the DT.

## Memory map (EFI, relevant parts)

- `0x80000000-0x801FFFFF` SMEM (no-map)
- `0x80200000-...` usable RAM; the kernel is decompressed around `0x81a08000`
- `0x80400000` framebuffer
- `0x88E00000-0x8FFFFFFF` not System RAM (subsystem carve-outs); Riva firmware at `0x8F000000-0x8F6FFFFF`

## Misc

- `PS_HOLD` at `0x00800820` (`qcom,pshold` node) - writing it restarts the phone; `reboot` uses it.
- The second CPU core is not started (`nosmp`).
- `QCOM_TSENS` (thermal sensor child of GCC) oopses with this DT - disabled.
- The Windows WLAN driver is `QCWLAN8960.sys`, config `QCWLAN8960cfg.dat`, firmware loaded by Windows'
  PIL from `System32\qcwcnss8960.mbn`.
