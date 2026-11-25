#!/bin/bash
# Build QCC2072 Bluetooth modules (btqca, hci_uart, pwrseq-pcie-m2) for a linux-omarchy kernel.
#
# Usage: bt/build-modules.sh [kernel-release]      default: the running kernel, e.g. 7.3.0-77-omarchy
# Output: bt/modules/<kernel-release>/*.ko         then run ./install.sh to install them
#
# How: takes the exact linux-omarchy source for that release (kernel.org tarball checked against
# the PKGBUILD's sha256, plus Omarchy's patches in PKGBUILD order from omarchy-pkgs), adds the
# patches in bt/patches/, and builds only drivers/bluetooth and drivers/power/sequencing against
# the installed linux-omarchy-headers. Takes a few minutes; downloads ~160 MB the first time per
# kernel version. Runs as your normal user. Never executes the PKGBUILD.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KREL=${1:-$(uname -r)}
CACHE=${UX3407NA_BT_CACHE:-$HOME/.cache/ux3407na-bt}
PKGS_URL=https://github.com/omacom/omarchy-pkgs.git
PKGBUILD=pkgbuilds/linux-omarchy-aarch64/PKGBUILD
OUT=$HERE/modules/$KREL

die() { echo "build-modules: $*" >&2; exit 1; }

[[ $KREL =~ ^([0-9]+\.[0-9]+)(\.[0-9]+)?-([0-9]+)-omarchy$ ]] || die "unexpected kernel release '$KREL'"
pkgver=${BASH_REMATCH[1]}; [[ -n ${BASH_REMATCH[2]} && ${BASH_REMATCH[2]} != .0 ]] && pkgver+=${BASH_REMATCH[2]}
pkgrel=${BASH_REMATCH[3]}
KBUILD=/usr/lib/modules/$KREL/build
[[ -d $KBUILD ]] || die "no headers for $KREL ($KBUILD missing): install linux-omarchy-headers for that kernel"

# Stop if the kernel already supports QCC2072 Bluetooth: the override is no longer needed.
intree=$(find /usr/lib/modules/$KREL/kernel/drivers/bluetooth -name 'btqca.ko*' | head -1)
if [[ -n $intree ]] && { zstd -dcq "$intree" 2>/dev/null || xz -dc "$intree" 2>/dev/null || cat "$intree"; } | grep -aq 'ornbtfw'; then
  die "$KREL's own btqca already knows QCC2072 (ornbtfw), so no override is needed. If one is installed, remove it: sudo rm -r /usr/lib/modules/$KREL/updates/ux3407na-bt && sudo depmod $KREL"
fi

mkdir -p "$CACHE"
echo "== omarchy-pkgs: finding the commit that built linux-omarchy $pkgver-$pkgrel"
if [[ -d $CACHE/pkgs/.git ]]; then git -C "$CACHE/pkgs" fetch -q origin; else git clone -q --filter=blob:none "$PKGS_URL" "$CACHE/pkgs"; fi
commit=""
for c in $(git -C "$CACHE/pkgs" log --format=%H origin/HEAD -- "$PKGBUILD"); do
  pb=$(git -C "$CACHE/pkgs" show "$c:$PKGBUILD")
  if grep -qx "pkgver=$pkgver" <<<"$pb" && grep -qx "pkgrel=$pkgrel" <<<"$pb"; then commit=$c; break; fi
done
[[ -n $commit ]] || die "no omarchy-pkgs commit with pkgver=$pkgver pkgrel=$pkgrel"
git -C "$CACHE/pkgs" -c advice.detachedHead=false checkout -q "$commit"
PB=$CACHE/pkgs/$PKGBUILD; PD=$(dirname "$PB")
grep -q '_rcpatch=patch' "$PB" && [[ $pkgver == *rc* ]] && die "release-candidate kernels are not handled"
echo "   commit ${commit:0:12}"

src=linux-$pkgver; tarball=$CACHE/$src.tar.xz
want=$(awk '/^sha256sums=\(/{sub(/^sha256sums=\(/,""); gsub(/[\047" ]/,""); print; exit}' "$PB")
if [[ ! -f $tarball ]] || [[ $(sha256sum "$tarball" | cut -d' ' -f1) != "$want" ]]; then
  echo "== downloading $src.tar.xz"
  major=${pkgver%%.*}
  curl -fL --progress-bar -o "$tarball.part" "https://cdn.kernel.org/pub/linux/kernel/v$major.x/$src.tar.xz"
  mv "$tarball.part" "$tarball"
fi
[[ $(sha256sum "$tarball" | cut -d' ' -f1) == "$want" ]] || die "$src.tar.xz sha256 does not match the PKGBUILD"

W=$CACHE/build-$KREL; rm -rf "$W"; mkdir -p "$W"
echo "== extracting and applying Omarchy patches"
tar -C "$W" -xf "$tarball"
cd "$W/$src"
n=0
while read -r p; do
  patch -Np1 --fuzz=0 -s < "$PD/$p" || die "Omarchy patch $p failed"
  n=$((n+1))
done < <(awk '/^source=\(/,/^\)/' "$PB" | grep -oE '[^ /{}]+\.patch' | grep -v '^nvidia-')
echo "   $n patches"

echo "== applying bt/patches"
for p in "$HERE"/patches/*.patch; do
  patch -Np1 --fuzz=0 -s < "$p" || die "$(basename "$p") failed to apply to $KREL: it needs rebasing"
done

echo "== building against $KBUILD"
make -s -C "$KBUILD" M="$PWD/drivers/bluetooth" -j"$(nproc)" modules
make -s -C "$KBUILD" M="$PWD/drivers/power/sequencing" -j"$(nproc)" modules

rm -rf "$OUT"; mkdir -p "$OUT"
for f in drivers/bluetooth/btqca.ko drivers/bluetooth/hci_uart.ko drivers/power/sequencing/pwrseq-pcie-m2.ko; do
  strip --strip-debug -o "$OUT/$(basename "$f")" "$f"
done
[[ $(modinfo -F vermagic "$OUT/btqca.ko" | cut -d' ' -f1) == "$KREL" ]] || die "vermagic mismatch"
modinfo "$OUT/hci_uart.ko" | grep -q 'qcom,qcc2072-bt' || die "built hci_uart lacks qcc2072"
cd /; rm -rf "$W"
echo "== done: $OUT"
ls -la "$OUT"
echo "Next: ./install.sh"
