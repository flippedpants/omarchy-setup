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

# Bluetooth (QCC2072 modules from bt/build-modules.sh)
K=$(uname -r)
check_file "$HERE/files/etc/pacman.d/hooks/95-ux3407na-bt.hook" /etc/pacman.d/hooks/95-ux3407na-bt.hook
[ -x /usr/local/lib/ux3407na/bt-check-modules ] && echo "ok        /usr/local/lib/ux3407na/bt-check-modules" || { echo "MISSING   /usr/local/lib/ux3407na/bt-check-modules"; ok=1; }
for m in btqca hci_uart pwrseq-pcie-m2; do
  inst=/usr/lib/modules/$K/updates/ux3407na-bt/$m.ko
  if [ ! -e "$inst" ]; then echo "MISSING   $inst (run bt/build-modules.sh, then ./install.sh)"; ok=1
  elif [ -e "$HERE/bt/modules/$K/$m.ko" ] && ! cmp -s "$HERE/bt/modules/$K/$m.ko" "$inst"; then echo "DIFFERENT $inst (run ./install.sh)"; ok=1
  else echo "ok        $inst"; fi
done
if [ "$(readlink -f "$(modinfo -n btqca 2>/dev/null)")" = "/usr/lib/modules/$K/updates/ux3407na-bt/btqca.ko" ]; then echo "ok        modprobe picks the QCC2072 btqca"
else echo "PROBLEM   modprobe picks $(modinfo -n btqca 2>/dev/null) (run: sudo depmod $K)"; ok=1; fi
if [ -e /sys/class/bluetooth/hci0 ]; then
  echo "ok        Bluetooth adapter hci0 present"
  fw=$(journalctl -b -k -q --no-pager 2>/dev/null | grep -oE 'QCA Downloading qca/[a-z0-9._]+|QCA Failed to request file: [^ ]+|Failed to send TLV segment \(-?[0-9]+\)' | sort | uniq -c | tr '\n' ';')
  echo "          firmware this boot: ${fw:-no QCA download lines}"
elif grep -q '^btqca ' /proc/modules; then echo "PROBLEM   btqca loaded but no hci0 (firmware download failed? see: journalctl -b -k | grep -i bluetooth)"; ok=1
else echo "NOTE      no Bluetooth adapter this boot (modules installed after boot? reboot)"; ok=1; fi

check_file "$HERE/files/etc/systemd/journald.conf.d/50-ux3407na-reset-debug.conf" /etc/systemd/journald.conf.d/50-ux3407na-reset-debug.conf
[ -e /etc/systemd/journald.conf.d/50-ux3407na-reset-debug.conf ] &&
  echo "          journald sync interval now: $(systemd-analyze cat-config systemd/journald.conf 2>/dev/null | grep -E '^SyncIntervalSec' | tail -1)"

echo
echo "This boot: $(journalctl -b -k -q --no-pager 2>/dev/null | grep -c 'PM: suspend entry') suspends," \
     "$(journalctl -b -k -q --no-pager 2>/dev/null | grep -c 'failed to start mhi') Wi-Fi resume failures," \
     "$(journalctl -b -q --no-pager 2>/dev/null | grep -c 'ux3407na-wifi-reload: loaded') hook reloads"
echo "Last wake IRQ: $(cat /sys/power/pm_wakeup_irq 2>/dev/null || echo none) $(awk -v i="$(cat /sys/power/pm_wakeup_irq 2>/dev/null)" '$1==i":" {print $NF}' /proc/interrupts)"
exit $ok
