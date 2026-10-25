#!/bin/bash
# Builds the base Lumia 822 DTB (CPUs, GIC, timer, clocks, RPM L3/L4, USB gadget, eMMC, PS_HOLD restart,
# PM8921 RTC + housekeeping ADC)
# from the Samsung Galaxy Express (expressatt, also MSM8960) DTB shipped in the postmarketOS kernel
# package. build_wifi_dtb.sh then adds Wi-Fi on top.
#   build_base_dtb.sh [expressatt.dtb] [out.dtb]
# Without an input file, the postmarketOS package is downloaded and the DTB extracted from it.
. "$(dirname "$0")/fdt-common.sh"
OUT=${2:-$REPO/out/lumia822-base.dtb}
mkdir -p "$(dirname "$OUT")"
SRC=$1
if [ -z "$SRC" ]; then
    PKG=linux-postmarketos-mainline-7.3-r0.apk
    mkdir -p "$REPO/out/dl"
    [ -f "$REPO/out/dl/$PKG" ] ||
        curl -fsSL -o "$(W "$REPO/out/dl/$PKG")" "https://mirror.postmarketos.org/postmarketos/master/armv7/$PKG"
    tar -xzf "$REPO/out/dl/$PKG" -C "$REPO/out/dl" boot/dtbs/qcom-msm8960-samsung-expressatt.dtb 2>/dev/null
    SRC=$REPO/out/dl/boot/dtbs/qcom-msm8960-samsung-expressatt.dtb
fi
start_from "$SRC"

# keep only the CPUs, GIC, timer, GCC, LCC, RPM, USB and the PM8921 (on SSBI; its interrupt is TLMM
# GPIO 104, the pinctrl node comes from build_wifi_dtb.sh)
step keep /clocks /cpus /memory@80000000 /chosen /soc/interrupt-controller@2000000 /soc/timer@200a000 /soc/clock-controller@900000 /soc/clock-controller@2011000 /soc/rpm@108000 /soc/usb@12500000 /soc/ssbi@500000 /iio-hwmon
step set /soc/timer@200a000 compatible "qcom,kpss-timer"
# CPU1: UEFI leaves it parked in the ACPI parking-protocol mailbox listed in the MADT (CPU0 0x80301000,
# CPU1 0x80302000); patch 0008 starts it from there. The ACC/SAW reset (qcom,kpss-acc-v1) does not work.
for c in 0 1; do
    step set /cpus/cpu@$c enable-method lumia,parking-protocol
    step set /cpus/cpu@$c lumia,parked-address u32:$((0x80301000 + c * 0x1000))
    step set /cpus/cpu@$c qcom,acc del; step set /cpus/cpu@$c qcom,saw del
done
# PM8921: keep the core (interrupt controller), RTC and XOADC (battery voltage/temperature, iio-hwmon).
# No pwrkey (its probe rewrites PON_CNTL_1, a persistent PMIC register Windows also uses), keypad,
# vibrator, GPIO/MPP blocks. The RTC stays read-only: Windows owns it.
P=/soc/ssbi@500000/pmic
step keepchildren $P rtc@11d,xoadc@197
step set $P/rtc@11d allow-set-time del
# Charger (patch 0011): UEFI leaves it off with a 100 mA USB input limit, so the phone ran from its
# battery on USB. 4.1 V instead of the cell's 4.2 V (VDD_SAFE) is kinder to a battery that is plugged
# in 24/7. PM8921 irq 15 = USBIN_VALID; ADC 0x3b = xoadc (channel 1 vbat, 8 batt_therm).
step addnode $P charger@200; C=$P/charger@200
step set $C compatible lumia,pm8921-charger; step set $C reg u32:0x200
step set $C interrupts-extended u32:0x0e,15,3; step set $C interrupt-names usbin-valid
step set $C io-channels u32:0x3b,0,1,0x3b,0,8; step set $C io-channel-names "strs:vbat|batt_therm"
step set $C lumia,vdd-max-microvolt u32:4100000
step set $C lumia,ibat-max-microamp u32:1500000
step set $C lumia,iusb-max-microamp u32:1500000
step set /chosen stdout-path del
step set / model "Nokia Lumia 822"
step set / compatible "strs:nokia,rm-845|qcom,msm8960"
# GCC: drop the tsens child (it oopses), give it cxo/pxo
step delnode /soc/clock-controller@900000/thermal-sensor
step set /soc/clock-controller@900000 clocks u32:0x11,0x12
step set /soc/clock-controller@900000 clock-names "strs:cxo|pxo"
# RPM regulators: keep only L3 (USB 3.3V) and L4 (USB 1.8V), drop all *-supply props
step keepchildren /soc/rpm@108000/regulators l3,l4
step delprops /soc/rpm@108000/regulators -supply
# USB as gadget
step set /soc/usb@12500000 dr_mode peripheral
# PS_HOLD restart
step addnode /soc restart@800820
step set /soc/restart@800820 compatible "qcom,pshold"
step set /soc/restart@800820 reg u32:0x800820,4
# L3 always-on (L4 already is in expressatt)
step set /soc/rpm@108000/regulators/l3 regulator-always-on empty
# eMMC: fixed dummy supply + BAM DMA + SDCC1 (PL18x)
step addnode / emmc-vdd-regulator; P=/emmc-vdd-regulator
step set $P compatible regulator-fixed; step set $P regulator-name emmc_vdd
step set $P regulator-min-microvolt u32:2950000; step set $P regulator-max-microvolt u32:2950000
step set $P regulator-always-on empty; step set $P phandle u32:0x102
step addnode /soc dma-controller@12402000; P=/soc/dma-controller@12402000
step set $P compatible "qcom,bam-v1.3.0"; step set $P reg u32:0x12402000,0x4000; step set $P interrupts u32:0,0x62,4
step set $P clocks u32:0x17,0x6e; step set $P clock-names bam_clk; step set $P "#dma-cells" u32:1; step set $P qcom,ee u32:0; step set $P phandle u32:0x101
step addnode /soc mmc@12400000; P=/soc/mmc@12400000
step set $P compatible "strs:arm,pl18x|arm,primecell"; step set $P reg u32:0x12400000,0x2000; step set $P arm,primecell-periphid u32:0x51180
step set $P interrupts u32:0,0x68,4; step set $P clocks u32:0x17,0x78,0x17,0x6e; step set $P clock-names "strs:mclk|apb_pclk"
step set $P bus-width u32:8; step set $P max-frequency u32:96000000; step set $P non-removable empty; step set $P cap-mmc-highspeed empty
step set $P vmmc-supply u32:0x102; step set $P dmas u32:0x101,2,0x101,1; step set $P dma-names "strs:tx|rx"; step set $P status okay

finish "$OUT"
