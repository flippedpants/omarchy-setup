#!/bin/sh
# Install the UX3407NA sleep/Wi-Fi fixes. Safe to run again (it just overwrites with the repo copy).
# Usage: ./install.sh            (asks for your sudo password)
#        ./install.sh --force    (install even if this is not a UX3407NA)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" = 0 ] || exec sudo "$HERE/install.sh" "$@"

MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)
case "$MODEL" in
  *UX3407NA*) ;;
  *) [ "${1:-}" = --force ] || { echo "This is '$MODEL', not a UX3407NA. Use --force to install anyway."; exit 1; } ;;
esac

install -Dm755 "$HERE/files/usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload" \
               /usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload
install -Dm644 "$HERE/files/etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules" \
               /etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules
udevadm control --reload

# Apply the USB wake setting now so no reboot is needed.
W=/sys/devices/platform/soc@0/a400000.usb/power/wakeup
[ -w "$W" ] && echo disabled > "$W"

echo "Installed."
"$HERE/verify.sh"
