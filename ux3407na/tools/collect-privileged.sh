#!/bin/bash
# Read-only evidence collection for the UX3407NA Wi-Fi/Bluetooth/suspend investigation.
# Run as root (pkexec). It changes nothing on the system: it only reads /boot, debugfs and
# sysfs, and writes copies into the evidence folder given as $1, owned by $2.
set -u
OUT=${1:?evidence dir}; OWNER=${2:?owner}
D="$OUT/privileged-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$D"; cd "$D" || exit 1
exec > >(tee "$D/collect.log") 2>&1

echo "== ESP layout"; find /boot -maxdepth 4 \( -name '*.efi' -o -name '*.conf' -o -name '*.dtb' -o -name 'initramfs*' -o -name 'vmlinuz*' \) -printf '%TY-%Tm-%Td %TH:%TM %10s %p\n' 2>/dev/null | grep -v '/dtbs/' | sort -k3
cp /boot/limine.conf limine.conf 2>/dev/null
ls -la /boot/EFI/Linux/ /boot/EFI/limine/ 2>/dev/null

for uki in /boot/EFI/Linux/*.efi; do
  n=$(basename "$uki" .efi); mkdir -p "uki-$n"
  echo "== UKI $uki"; sha256sum "$uki"
  objdump -h "$uki" 2>/dev/null | awk '$2 ~ /^\./ {print $2, $3}' | tee "uki-$n/sections.txt"
  for s in .linux .initrd .cmdline .uname .osrel .dtb .dtbauto .hwids .ucode; do
    objcopy -O binary --only-section="$s" "$uki" "uki-$n/${s#.}.bin" 2>/dev/null
    [ -s "uki-$n/${s#.}.bin" ] || rm -f "uki-$n/${s#.}.bin"
  done
  # A UKI can carry several .dtbauto sections; objcopy keeps only one, so also note the count.
  echo "dtbauto sections: $(objdump -h "$uki" | grep -c dtbauto)"
  [ -f "uki-$n/uname.bin" ] && echo "uname: $(tr -d '\0' < "uki-$n/uname.bin")"
  [ -f "uki-$n/cmdline.bin" ] && echo "cmdline: $(tr -d '\0' < "uki-$n/cmdline.bin")"
  sha256sum "uki-$n"/*.bin
  if [ -f "uki-$n/initrd.bin" ]; then
    # List the initramfs (may be several concatenated cpio archives; first early cpio, then zstd).
    (cd "uki-$n" && mkdir -p initrd && cd initrd && \
       { cpio -t < ../initrd.bin 2>/dev/null; } > ../initrd-early-list.txt; \
       python3 -I - ../initrd.bin > ../initrd-list.txt 2>&1 <<'PY'
import sys, subprocess
data = open(sys.argv[1], 'rb').read()
i = data.find(b'\x28\xb5\x2f\xfd')  # zstd magic after the early cpio
if i < 0: print('no zstd segment found'); sys.exit()
p = subprocess.run(['zstd', '-dcq'], input=data[i:], capture_output=True)
p2 = subprocess.run(['cpio', '-t'], input=p.stdout, capture_output=True)
print(p2.stdout.decode(errors='replace'))
PY
    )
    echo "initrd firmware/modules of interest:"; grep -E 'firmware|ath12k|qca|pwrseq|pwrctrl|hci|bt|mhi|pcie' "uki-$n/initrd-list.txt" | head -60
  fi
done
echo "== running vmlinuz vs UKI .linux"; sha256sum /usr/lib/modules/$(uname -r)/vmlinuz

echo "== debugfs: GPIO state (wcn 94/116/117, pcie4 146/148, lid 92)"
mount | grep -q debugfs || mount -t debugfs none /sys/kernel/debug
grep -E 'gpio(92|94|116|117|146|148)[^0-9]' /sys/kernel/debug/gpio > gpio-interest.txt 2>/dev/null; cat gpio-interest.txt
cp /sys/kernel/debug/gpio gpio-all.txt 2>/dev/null
cp /sys/kernel/debug/pinctrl/*/pinmux-pins pinmux-pins.txt 2>/dev/null
echo "== regulators"; cat /sys/kernel/debug/regulator/regulator_summary > regulator-summary.txt 2>/dev/null; grep -iE 'wcn|l15b|pmu|pcie|0p95|3p3' regulator-summary.txt
echo "== wakeup sources"; cat /sys/kernel/debug/wakeup_sources > wakeup_sources.txt 2>/dev/null; head -3 wakeup_sources.txt
echo "== irq wake / pdc"; cat /proc/interrupts > interrupts.txt
ls /sys/kernel/debug/pwrseq 2>/dev/null && cat /sys/kernel/debug/pwrseq/* > pwrseq.txt 2>/dev/null
echo "== suspend stats"; cat /sys/kernel/debug/suspend_stats > suspend_stats.txt 2>/dev/null
echo "== pstore"; ls -la /sys/fs/pstore/ 2>/dev/null
echo "== device link / devices_deferred"; cat /sys/kernel/debug/devices_deferred > devices_deferred.txt 2>/dev/null; cat devices_deferred.txt

chown -R "$OWNER" "$D"
echo "DONE -> $D"
