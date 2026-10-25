#!/bin/sh
# Wi-Fi bring-up hook (/etc/local.d/start.sh, started by /init). Log: /var/log/wifi.log
exec >> /var/log/wifi.log 2>&1
echo "=== $(date) wifi start"
part() { for u in /sys/class/block/mmcblk0p*/uevent; do grep -q "^PARTNAME=$1$" "$u" &&
         echo "/dev/$(sed -n 's/^DEVNAME=//p' "$u")" && return; done; }

# keep the USB route as a low-priority fallback so Wi-Fi becomes the default route
for i in $(seq 1 60); do ip link show usb0 >/dev/null 2>&1 && break; sleep 1; done
ip route del default via 192.168.42.2 dev usb0 2>/dev/null; ip route del default via 192.168.42.2 dev usb0 2>/dev/null
ip route add default via 192.168.42.2 dev usb0 metric 400 2>/dev/null

# Riva firmware is not redistributable: copy it from this phone's own Windows (MainOS, read-only)
FW=/lib/firmware/qcwcnss8960.mbn
if [ ! -s $FW ]; then
    mkdir -p /mnt/mainos
    if mount -t ntfs3 -o ro "$(part MainOS)" /mnt/mainos; then
        cp /mnt/mainos/Windows/System32/qcwcnss8960.mbn $FW && echo "copied Riva firmware from MainOS"
        umount /mnt/mainos
    fi
    [ -s $FW ] || { echo "no Riva firmware ($FW)"; exit 1; }
fi

# Riva does not auto-boot (patched kernel); start it here, after USB/SSH are already up
RP=/sys/class/remoteproc/remoteproc0
[ "$(cat $RP/state 2>/dev/null)" = running ] || echo start > $RP/state
for i in $(seq 1 90); do [ -e /sys/class/net/wlan0 ] && break; sleep 1; done
if [ ! -e /sys/class/net/wlan0 ]; then
    echo "no wlan0 after 90 s"; dmesg | grep -iE "wcnss|riva|wcn36xx|remoteproc|smd|smsm|smem" | tail -30
    exit 1
fi
# The NV carries no MAC address (wlan0 would be 00:00:00:00:00:00): derive a stable, locally
# administered one from the eMMC serial number so every phone gets its own.
SER=$(cat /sys/block/mmcblk0/device/serial 2>/dev/null)
MAC=$(echo "lumia822-wlan-$SER" | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*/02:\1:\2:\3:\4:\5/')
ip link set wlan0 address "$MAC"
CONF=/etc/wpa_supplicant/wpa_supplicant.conf
if [ ! -s $CONF ]; then
    ip link set wlan0 up
    echo "wlan0 is up, but there is no $CONF (put wpa_supplicant.conf in C:\\EFIESP\\linux\\)"
    exit 0
fi

# Connect. Power save must be off BEFORE associating: with the 2012 firmware, entering BMPS
# leaves the TX ring stuck ("Failed to flush hardware tx queues"), and turning it off later
# does not recover it.
connect() {
    killall wpa_supplicant udhcpc 2>/dev/null; sleep 1
    ip link set wlan0 down; ip link set wlan0 up
    iw dev wlan0 set power_save off
    wpa_supplicant -B -D nl80211 -i wlan0 -c $CONF
    udhcpc -i wlan0 -b -t 20 -T 3 -x hostname:lumia822
}
connect

# Watchdog: if the router stops answering 3 checks in a row, reconnect.
FAIL=0
while sleep 60; do
    GW=$(ip route show dev wlan0 | sed -n 's/^default via \([0-9.]*\).*/\1/p' | head -1)
    if [ -n "$GW" ] && ping -c 2 -W 3 -I wlan0 "$GW" >/dev/null 2>&1; then FAIL=0; continue; fi
    FAIL=$((FAIL + 1))
    if [ $FAIL -ge 3 ]; then echo "=== $(date) no answer from gateway, reconnecting"; connect; FAIL=0; fi
done
