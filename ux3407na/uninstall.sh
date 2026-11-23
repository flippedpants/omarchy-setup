#!/bin/sh
# Remove the UX3407NA sleep/Wi-Fi fixes and restore the default behaviour.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" = 0 ] || exec sudo "$HERE/uninstall.sh" "$@"

rm -f /usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload
rm -f /etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules
rm -f /etc/ux3407na-wifi-reload.disable
udevadm control --reload

W=/sys/devices/platform/soc@0/a400000.usb/power/wakeup
[ -w "$W" ] && echo enabled > "$W"

echo "Removed. Wi-Fi may fail after long sleeps and the lid-closed wake loop will return."
