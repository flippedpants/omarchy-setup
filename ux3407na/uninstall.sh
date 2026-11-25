#!/bin/sh
# Remove the UX3407NA fixes and restore the default behaviour.
# Usage: ./uninstall.sh           remove everything
#        ./uninstall.sh --bt      remove only the Bluetooth modules (sleep fixes stay)
#        ./uninstall.sh --reset-debug   remove only the journald 5 s sync setting
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" = 0 ] || exec sudo "$HERE/uninstall.sh" "$@"

remove_reset_debug() {
  rm -f /etc/systemd/journald.conf.d/50-ux3407na-reset-debug.conf
  rmdir /etc/systemd/journald.conf.d 2>/dev/null || true
  systemctl restart systemd-journald
}
if [ "${1:-}" = --reset-debug ]; then remove_reset_debug; echo "journald is back to its default sync interval."; exit 0; fi

for d in /usr/lib/modules/*/updates/ux3407na-bt; do
  [ -d "$d" ] || continue
  k=$(basename "$(dirname "$(dirname "$d")")")
  rm -rf "$d"; rmdir "$(dirname "$d")" 2>/dev/null || true
  [ -d "/usr/lib/modules/$k/kernel" ] && depmod "$k"
  echo "removed Bluetooth modules for $k"
done
rm -f /etc/pacman.d/hooks/95-ux3407na-bt.hook /usr/local/lib/ux3407na/bt-check-modules
rmdir /usr/local/lib/ux3407na 2>/dev/null || true
if [ "${1:-}" = --bt ]; then echo "Bluetooth modules removed; reboot to go back to the stock ones."; exit 0; fi

rm -f /usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload
rm -f /etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules
rm -f /etc/ux3407na-wifi-reload.disable
remove_reset_debug
udevadm control --reload
W=/sys/devices/platform/soc@0/a400000.usb/power/wakeup
[ -w "$W" ] && echo enabled > "$W"

echo "Removed. Reboot to drop the Bluetooth modules. Wi-Fi may fail after long sleeps and the lid-closed wake loop will return."
