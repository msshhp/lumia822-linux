#!/bin/bash
# Builds the base Lumia 822 DTB (CPU, GIC, timer, clocks, RPM L3/L4, USB gadget, eMMC, PS_HOLD restart)
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

# keep only CPU0, GIC, timer, GCC, LCC, RPM and USB
step keep /clocks /cpus/cpu@0 /cpus/l2-cache /memory@80000000 /chosen /soc/interrupt-controller@2000000 /soc/timer@200a000 /soc/clock-controller@900000 /soc/clock-controller@2011000 /soc/rpm@108000 /soc/usb@12500000
step set /soc/timer@200a000 compatible "qcom,kpss-timer"
step set /cpus/cpu@0 enable-method del          # single CPU (cmdline also has nosmp)
step set /cpus/cpu@0 qcom,acc del
step set /cpus/cpu@0 qcom,saw del
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
