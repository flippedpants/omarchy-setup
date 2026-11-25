#!/bin/sh
# Install the UX3407NA fixes. Safe to run again (it just overwrites with the repo copy).
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

# 1. Sleep: Wi-Fi driver reload around suspend, and no wakeups from the multiport USB controller.
install -Dm755 "$HERE/files/usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload" \
               /usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload
install -Dm644 "$HERE/files/etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules" \
               /etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules
udevadm control --reload
W=/sys/devices/platform/soc@0/a400000.usb/power/wakeup
[ -w "$W" ] && echo disabled > "$W"

# 2. Bluetooth: QCC2072 modules built by bt/build-modules.sh, for every installed kernel we have them for.
install -Dm755 "$HERE/files/usr/local/lib/ux3407na/bt-check-modules" /usr/local/lib/ux3407na/bt-check-modules
sed -i "s|^REPO=.*|REPO=$HERE|" /usr/local/lib/ux3407na/bt-check-modules
install -Dm644 "$HERE/files/etc/pacman.d/hooks/95-ux3407na-bt.hook" /etc/pacman.d/hooks/95-ux3407na-bt.hook
for m in "$HERE"/bt/modules/*/; do
  [ -d "$m" ] || continue
  k=$(basename "$m")
  if [ ! -d "/usr/lib/modules/$k/kernel" ]; then echo "skip Bluetooth modules for $k (kernel not installed)"; continue; fi
  install -Dm644 -t "/usr/lib/modules/$k/updates/ux3407na-bt" "$m"/btqca.ko "$m"/hci_uart.ko "$m"/pwrseq-pcie-m2.ko
  depmod "$k"
  echo "installed Bluetooth modules for $k"
done
/usr/local/lib/ux3407na/bt-check-modules

# 3. Diagnostics (temporary): journald syncs every 5 s so the seconds before a random reset survive.
install -Dm644 "$HERE/files/etc/systemd/journald.conf.d/50-ux3407na-reset-debug.conf" \
               /etc/systemd/journald.conf.d/50-ux3407na-reset-debug.conf
systemctl restart systemd-journald

echo "Installed. Bluetooth modules take effect after a reboot."
"$HERE/verify.sh" || true
