#!/bin/bash
# Adds the Riva/WCN3660 Wi-Fi description (ported from qcom-apq8064.dtsi, MSM8960 = same Riva block)
# to the base DTB from build_base_dtb.sh. Rail limits come from the MSM8960 expressatt board.
#   build_wifi_dtb.sh [base.dtb] [out.dtb]     (defaults: out/lumia822-base.dtb -> out/lumia822.dtb)
# The result is what goes to \linux\lumia822.dtb on EFIESP.
. "$(dirname "$0")/fdt-common.sh"
IN=${1:-$REPO/out/lumia822-base.dtb}; OUT=${2:-$REPO/out/lumia822.dtb}
start_from "$IN"

# reserved memory: SMEM and the WCNSS firmware region (both outside Linux RAM on this phone)
node / reserved-memory; P=/reserved-memory
prop $P "#address-cells" u32:1; prop $P "#size-cells" u32:1; prop $P ranges empty
node $P smem@80000000; prop $P/smem@80000000 reg u32:0x80000000,0x200000; prop $P/smem@80000000 no-map empty; prop $P/smem@80000000 phandle u32:0x110
node $P wcnss@8f000000; prop $P/wcnss@8f000000 reg u32:0x8f000000,0x700000; prop $P/wcnss@8f000000 no-map empty; prop $P/wcnss@8f000000 phandle u32:0x111

# SFPB hardware mutex, SMEM, SMSM
node /soc hwmutex@1200600; P=/soc/hwmutex@1200600
prop $P compatible qcom,sfpb-mutex; prop $P reg u32:0x01200600,0x100; prop $P "#hwlock-cells" u32:1; prop $P phandle u32:0x112
node / smem; prop /smem compatible qcom,smem; prop /smem memory-region u32:0x110; prop /smem hwlocks u32:0x112,3
node / smsm; P=/smsm
prop $P compatible qcom,smsm; prop $P "#address-cells" u32:1; prop $P "#size-cells" u32:0
prop $P qcom,ipc-1 u32:0x7,8,4; prop $P qcom,ipc-2 u32:0x7,8,14; prop $P qcom,ipc-3 u32:0x7,8,23
node $P apps@0; prop $P/apps@0 reg u32:0; prop $P/apps@0 "#qcom,smem-state-cells" u32:1; prop $P/apps@0 phandle u32:0x113
node $P wcnss@3; prop $P/wcnss@3 reg u32:3; prop $P/wcnss@3 interrupts u32:0,204,1; prop $P/wcnss@3 interrupt-controller empty; prop $P/wcnss@3 "#interrupt-cells" u32:2; prop $P/wcnss@3 phandle u32:0x114

# RPM clock controller (as in the upstream msm8960 WCNSS series). Its probe hands off every RPM clock
# with an apps vote at max; without it the apps CPU has no fabric votes of its own, and the SoC froze
# as soon as Riva left reset and its own RPM requests made the RPM re-aggregate the bus clocks.
P=/soc/rpm@108000; node $P clock-controller; P=$P/clock-controller
prop $P compatible "strs:qcom,rpmcc-apq8064|qcom,rpmcc"; prop $P "#clock-cells" u32:1
prop $P clocks u32:0x12,0x11; prop $P clock-names "strs:pxo|cxo"; prop $P phandle u32:0x11d
# With rpmcc present USB stopped probing; use the upstream msm8960 USB clocks, where the controller
# holds the Daytona fabric (iface) itself: core = USB_HS1_H_CLK (126), fs = USB_HS1_XCVR_CLK (128)
prop /soc/usb@12500000 clocks u32:0x11d,10,0x17,126,0x17,128; prop /soc/usb@12500000 clock-names "strs:iface|core|fs"

# TrustZone SCM (PAS authenticates the signed Riva firmware). Deliberately no "core" clock: SCM
# enables and disables it around every call, and the disable votes the Daytona fabric to 0, which
# killed USB (upstream avoids that by making USB hold the same clock).
node / firmware; node /firmware scm; prop /firmware/scm compatible "strs:qcom,scm-apq8064|qcom,scm"

# TLMM pin controller with only the WLAN 5-wire interface state (GPIO 84-88, function "wlan")
node /soc pinctrl@800000; P=/soc/pinctrl@800000
prop $P compatible qcom,msm8960-pinctrl; prop $P reg u32:0x800000,0x4000; prop $P gpio-controller empty
prop $P gpio-ranges u32:0x0d,0,0,152; prop $P "#gpio-cells" u32:2; prop $P interrupts u32:0,16,4
prop $P interrupt-controller empty; prop $P "#interrupt-cells" u32:2; prop $P phandle u32:0x0d
node $P wlan-active-state; P2=$P/wlan-active-state
prop $P2 pins "strs:gpio84|gpio85|gpio86|gpio87|gpio88"; prop $P2 function wlan; prop $P2 drive-strength u32:6; prop $P2 bias-pull-down empty; prop $P2 phandle u32:0x116

# RPM regulators for Riva and the WCN3660 (values from MSM8960 expressatt = Qualcomm reference).
# S3 (VDD_CX) and L24 (VDD_MX) start at 1.05 V: the regulator core programs the range minimum when the
# current voltage is unknown, and expressatt's 0.5/0.75 V minimums froze the SoC once Riva started.
R=/soc/rpm@108000/regulators
node $R s2;  prop $R/s2 regulator-min-microvolt u32:1300000; prop $R/s2 regulator-max-microvolt u32:1300000; prop $R/s2 qcom,switch-mode-frequency u32:1600000; prop $R/s2 bias-pull-down empty; prop $R/s2 phandle u32:0x117
node $R s3;  prop $R/s3 regulator-always-on empty; prop $R/s3 regulator-min-microvolt u32:1050000; prop $R/s3 regulator-max-microvolt u32:1150000; prop $R/s3 qcom,switch-mode-frequency u32:4800000; prop $R/s3 bias-pull-down empty; prop $R/s3 phandle u32:0x118
node $R s4;  prop $R/s4 regulator-always-on empty; prop $R/s4 regulator-min-microvolt u32:1800000; prop $R/s4 regulator-max-microvolt u32:1800000; prop $R/s4 qcom,switch-mode-frequency u32:1600000; prop $R/s4 bias-pull-down empty; prop $R/s4 qcom,force-mode u32:3; prop $R/s4 phandle u32:0x119
node $R l10; prop $R/l10 regulator-min-microvolt u32:3000000; prop $R/l10 regulator-max-microvolt u32:3000000; prop $R/l10 bias-pull-down empty; prop $R/l10 phandle u32:0x11a
node $R l24; prop $R/l24 regulator-always-on empty; prop $R/l24 regulator-min-microvolt u32:1050000; prop $R/l24 regulator-max-microvolt u32:1150000; prop $R/l24 bias-pull-down empty; prop $R/l24 phandle u32:0x11b
node $R lvs2; prop $R/lvs2 bias-pull-down empty; prop $R/lvs2 phandle u32:0x11c

# Riva remote processor + WCN3660 + SMD edge with the WCNSS control and Wi-Fi functions
node /soc riva-pil@3200800; P=/soc/riva-pil@3200800
prop $P compatible qcom,riva-pil
prop $P reg u32:0x03200800,0x1000,0x03202000,0x2000,0x03204000,0x100
prop $P reg-names "strs:ccu|dxe|pmu"
prop $P interrupts-extended u32:0x1,0,199,1,0x114,6,1
prop $P interrupt-names "strs:wdog|fatal"
prop $P memory-region u32:0x111
prop $P firmware-name qcwcnss8960.mbn
prop $P pinctrl-names default; prop $P pinctrl-0 u32:0x116
prop $P vddcx-supply u32:0x118; prop $P vddmx-supply u32:0x11b; prop $P vddpx-supply u32:0x119
prop $P phandle u32:0x115
node $P iris; P2=$P/iris
prop $P2 compatible qcom,wcn3660; prop $P2 clocks u32:0x11; prop $P2 clock-names xo
prop $P2 vddxo-supply u32:0x25; prop $P2 vddrfa-supply u32:0x117; prop $P2 vddpa-supply u32:0x11a; prop $P2 vdddig-supply u32:0x11c
node $P smd-edge; P2=$P/smd-edge
prop $P2 interrupts u32:0,198,1; prop $P2 qcom,ipc u32:0x7,8,25; prop $P2 qcom,smd-edge u32:6; prop $P2 label riva
node $P2 wcnss; P3=$P2/wcnss
prop $P3 compatible qcom,wcnss; prop $P3 qcom,smd-channels sys_mon; prop $P3 qcom,mmio u32:0x115; prop $P3 lumia,no-ctrl-handshake empty
prop $P3 firmware-name lumia/wlan_nv.bin  # NV for wcn36xx, read from /lib/firmware on the persistent root
# WP8 Riva firmware has no WCNSS_CTRL (APPS_RIVA_CTRL is DIAG and asserts); the patched wcnss_ctrl only
# binds to sys_mon for an endpoint on the edge and skips the handshake, wcn36xx sends the NV itself
node $P3 wifi; P4=$P3/wifi
prop $P4 compatible qcom,wcnss-wlan
prop $P4 interrupts u32:0,203,4,0,202,4; prop $P4 interrupt-names "strs:tx|rx"
prop $P4 qcom,smem-states u32:0x113,10,0x113,9; prop $P4 qcom,smem-state-names "strs:tx-enable|tx-rings-empty"

finish "$OUT"
