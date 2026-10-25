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

## Second CPU core

Windows Phone 8 UEFI starts both Krait cores and parks CPU1 using the ACPI *multiprocessor parking
protocol*. The MADT (ACPI tables at `0xbeac1000`, MADT at `0xbea43000`) has GICC entries with parking
version 1 and mailboxes **CPU0 `0x80301000`, CPU1 `0x80302000`**. The firmware loop lives in the mailbox page
itself (offset `0x800`): `if ((mbox[0] & 0xff) == MPIDR.Aff0 && mbox[8]) { r0 = mbox; mbox[8] = 0; bx mbox[8]; }
else wfi`. Kernel patch 0008 writes `secondary_startup_arm` to `+8`, the CPU ID to `+0` and sends an SGI.

What does not work: the mainline Krait bring-up through the ACC/SAW registers (`qcom,kpss-acc-v1`). It
resets the core (ACC `CPU_PWR_CTL` goes to `0x180`), but the secure firmware then does not jump to the
Linux cold-boot address, and CPU1 is lost until the next reboot.

No cpufreq/cpuidle yet: both cores run at the clock UEFI left (BogoMIPS 13.5 is the timer, not the CPU).

## Battery and charger

PM8921 on SSBI (`0x500000`, PMIC interrupt = TLMM GPIO 104), HWREV `0xF4`/`0x06`. The charger is a hardware
state machine (trickle, fast charge, end of charge, recharge, battery temperature limits). **Windows UEFI
leaves it disabled**: `CHG_CNTRL_3` bit 7 = 0, `VDD_MAX` 3.60 V, USB input limit (`PBL_ACCESS2[4:2]`)
100 mA. Without a driver the phone sat in FSM state 3 (`ON_BAT`) and drained its battery on USB.

The `lumia,pm8921-charger` driver (patch 0011) sets, from the DT: charge voltage **4.10 V** (the cell
allows 4.2 V = UEFI's `VDD_SAFE`; less wear while always plugged in), battery current 1.5 A, USB input
1.5 A (about 7 W, what Windows Phone charges with), recharge below 4.00 V, then enables the state machine.
It restarts the charger when the safety timer (`CHG_TCHG_MAX`, 240 min from UEFI) has put it into
`CHG_FAIL`. Status: `/sys/class/power_supply/battery/{status,capacity,voltage_now,temp}` and
`.../usb/online`. `capacity` is estimated from the voltage (no fuel gauge; the PM8921 BMS is unused), so
it reads high while charging.

The limits can be changed at runtime (microamps; lost at reboot, the DT values apply again):
`echo 500000 > /sys/class/power_supply/usb/input_current_limit` (e.g. for a PC port that cuts out above
500 mA; the PMIC's own VIN_MIN loop at 4.3 V already backs off when VBUS sags) and
`.../battery/constant_charge_current_max`. Measured on a PC port: 500 mA input did not cover the system
under load (battery still discharging); 1.5 A raised the battery voltage by 150 mV with VBUS at 4.55 V.

Temperature: besides the PMIC's own hot/cold cutoff, the driver reduces the battery current to 325 mA at
45 °C (full current again below 42 °C) and pauses charging at 50 °C (resumes below 45 °C), like
downstream's warm/hot handling. Measured: about 43 °C battery / 53 °C die while charging at
7 W right after a 10-minute two-core load test.

| Register | | Register | |
|---|---|---|---|
| `0x005` PBL_ACCESS2 | [4:2] USB input limit index (100/500/700/850/900/1100/1300/1500 mA), bit 1 enum timer stop | `0x216` CHG_CNTRL_3 | bit 7 auto charge enable, bits 1:0 clear ATC/charge failed |
| `0x205` CHG_IBAT_MAX | 225 mA + 50 mA x [5:0] | `0x220` CHG_VDD_MAX | 3240 mV + 20 mV x [6:0] (+10 mV bit 7) |
| `0x206` CHG_TEST | bank access: write `0x80 \| bank<<4 \| data`, read: write `bank<<4`, read back | `0x221` CHG_VDD_SAFE | upper limit for VDD_MAX |
| `0x213` CHG_VBAT_DET | recharge threshold, same encoding as VDD_MAX | `0x1c0`/`0x1c3` | IRQ block select / real-time status (block 1 bit 7 USBIN_VALID, block 2 bit 1 FASTCHG) |

FSM state: write `0xc2` to CHG_TEST, then bank 7 [3:0] and bank 4 [0] (state 3 on battery, 7 fast charge,
8 trickle, 9 charge failed, 10 end of charge).

**Housekeeping ADC (XOADC)** at `0x197`: two mainline bugs fixed (patches 0009/0010, see
[kernel.md](kernel.md)). Channels in `/sys/bus/iio/devices/iio:device0` (`vbat`, `vph_pwr`, `usb_vbus`,
`batt_therm`, `die_temp`, ...); voltages in microvolts.

## Misc

- `PS_HOLD` at `0x00800820` (`qcom,pshold` node) - writing it restarts the phone; `reboot` uses it.
- PM8921 RTC (`rtc0`) is read-only for Linux (Windows owns it); it reads near 1970, `ntpd` sets the time.
- `QCOM_TSENS` (thermal sensor child of GCC) oopses with this DT - disabled.
- The Windows WLAN driver is `QCWLAN8960.sys`, config `QCWLAN8960cfg.dat`, firmware loaded by Windows'
  PIL from `System32\qcwcnss8960.mbn`.
