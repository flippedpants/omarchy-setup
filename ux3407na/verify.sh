#!/bin/sh
# Check that the UX3407NA fixes are installed, up to date with this repo, and working.
# Runs as your normal user; no sudo needed.
HERE=$(cd "$(dirname "$0")" && pwd)
ok=0

check_file() {  # repo copy, installed path
  if [ ! -e "$2" ]; then echo "MISSING   $2"; ok=1
  elif cmp -s "$1" "$2"; then echo "ok        $2"
  else echo "DIFFERENT $2 (run ./install.sh to update)"; ok=1; fi
}
check_file "$HERE/files/usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload" /usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload
check_file "$HERE/files/etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules" /etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules

W=$(cat /sys/devices/platform/soc@0/a400000.usb/power/wakeup 2>/dev/null || echo "not found")
if [ "$W" = disabled ]; then echo "ok        USB multiport wakeup: disabled"
else echo "PROBLEM   USB multiport wakeup: $W (expected disabled)"; ok=1; fi

[ -e /etc/ux3407na-wifi-reload.disable ] && { echo "NOTE      Wi-Fi hook is switched off by /etc/ux3407na-wifi-reload.disable"; }

grep -q '^ath12k_wifi7 ' /proc/modules && echo "ok        Wi-Fi driver ath12k_wifi7 loaded" || { echo "PROBLEM   ath12k_wifi7 not loaded"; ok=1; }

echo
echo "This boot: $(journalctl -b -k -q --no-pager 2>/dev/null | grep -c 'PM: suspend entry') suspends," \
     "$(journalctl -b -k -q --no-pager 2>/dev/null | grep -c 'failed to start mhi') Wi-Fi resume failures," \
     "$(journalctl -b -q --no-pager 2>/dev/null | grep -c 'ux3407na-wifi-reload: loaded') hook reloads"
echo "Last wake IRQ: $(cat /sys/power/pm_wakeup_irq 2>/dev/null || echo none) $(awk -v i="$(cat /sys/power/pm_wakeup_irq 2>/dev/null)" '$1==i":" {print $NF}' /proc/interrupts)"
exit $ok
