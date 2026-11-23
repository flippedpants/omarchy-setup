#!/bin/bash
# Snapshot Wi-Fi / Bluetooth / suspend state before and after a test.
# Usage: capture-state.sh <label>        (as your user; adds root-only data when run with sudo)
# Writes ~/work/kernel-investigation/runs/<timestamp>-<label>/
set -u
LABEL=${1:?label}
BASE=/home/dakshgupta/work/kernel-investigation/runs
D="$BASE/$(date +%Y%m%d-%H%M%S)-$LABEL"; mkdir -p "$D"; cd "$D" || exit 1

{
  echo "boot_id=$(cat /proc/sys/kernel/random/boot_id)"
  echo "uptime=$(cut -d' ' -f1 /proc/uptime)"
  echo "kernel=$(uname -r)"
  echo "model=$(tr -d '\0' < /proc/device-tree/model)"
  if [ -d /proc/device-tree/wcn7850-pmu ]; then echo "tree=bluetooth-test"; elif [ -d /proc/device-tree/wlan-connector ]; then echo "tree=stock-m2-connector"; else echo "tree=unknown"; fi
  echo "mem_sleep=$(cat /sys/power/mem_sleep)"
  echo "pm_debug_messages=$(cat /sys/power/pm_debug_messages) pm_print_times=$(cat /sys/power/pm_print_times)"
  echo "pm_wakeup_irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null || echo none)"
  echo "lid_gpio92=$(grep -oE "gpio92 *: [a-z]+ +[a-z]+" /sys/kernel/debug/gpio 2>/dev/null || echo needs-root)"
} > summary.txt
grep -r . /sys/power/suspend_stats/ > suspend_stats.txt 2>/dev/null
for w in /sys/class/wakeup/wakeup*; do
  printf '%s\t%s\t%s\t%s\n' "$(cat "$w/name")" "$(cat "$w/event_count")" "$(cat "$w/wakeup_count")" "$(cat "$w/last_change_ms" 2>/dev/null)"
done | sort > wakeup_counts.tsv
rfkill list > rfkill.txt 2>&1
nmcli -t -f DEVICE,STATE,CONNECTION dev > nmcli.txt 2>&1
timeout 5 bluetoothctl show > bluetoothctl.txt 2>&1
cat /sys/bus/pci/devices/0004:01:00.0/power/runtime_status > wifi_runtime_status.txt 2>&1
journalctl --show-cursor -n 0 -q --no-pager > journal_cursor.txt 2>&1
journalctl -b -k -o short-monotonic --no-pager -q -n 300 > dmesg_tail.txt 2>&1

if [ "$(id -u)" = 0 ]; then
  grep -E 'gpio(92|94|116|117|146|148)[^0-9]' /sys/kernel/debug/gpio > gpio.txt 2>/dev/null
  cat /sys/kernel/debug/regulator/regulator_summary > regulators.txt 2>/dev/null
  cat /sys/kernel/debug/wakeup_sources > wakeup_sources.txt 2>/dev/null
  lspci -vvv -s 0004:01:00.0 > lspci_wifi.txt 2>&1
  lspci -vvv -s 0004:00:00.0 > lspci_rootport.txt 2>&1
  chown -R "${SUDO_USER:-dakshgupta}": "$D"
fi
cat summary.txt
echo "saved: $D"
