# ASUS Zenbook A14 UX3407NA (Snapdragon X2 Elite) — sleep and Wi-Fi fixes

Tested on Omarchy with `linux-omarchy` 7.3-77, BIOS UX3407NA.316, on 2026-11-23 (sleep fixes). Bluetooth: verified 2026-11-25 on two boots (firmware `BTFW.ORNE.1.1.0-00355` loads, Sony WH-CH520 headphones play over A2DP/AAC); sleep with Bluetooth on not yet tested.

## What is fixed

| Problem | Cause | Fix |
|---|---|---|
| Wi-Fi dead after waking from a sleep of more than a minute or two (`failed to start mhi: -110`, "Hardware became unavailable upon resume") | The ath12k driver cannot restart the QCC2072 Wi-Fi card in place after a real sleep | `50-ux3407na-wifi-reload` sleep hook unloads the Wi-Fi driver before suspend and loads it fresh after waking |
| Lid closed → laptop wakes after ~1.6 s, re-suspends 30 s later, forever | Spurious wake IRQ `dp_hs_phy_2` from port 2 of the multiport USB controller `a400000.usb` (nothing is connected to that port; the USB-A port is port 1) | `70-ux3407na-usb-mp-nowake.rules` udev rule disables wakeup for that controller |
| No Bluetooth at all | Kernel has no QCC2072 Bluetooth support: the M.2 power driver doesn't know PCI ID 17cb:1112, so no Bluetooth device is created, and btqca doesn't know QCC2072's `ornbtfw11`/`ornnv11` firmware names | `bt/`: rebuilds `btqca`, `hci_uart` and `pwrseq-pcie-m2` with two unmerged upstream QCC2072 patches and installs them to `/usr/lib/modules/<kernel>/updates/ux3407na-bt/` (stock kernel, stock device tree) |

Side effects: Wi-Fi takes a few seconds to reconnect after each wake, and a device in the USB-A port cannot wake the laptop (the lid, power key and built-in keyboard still can). The USB-A port otherwise works normally.

Not fixed: random resets, either 7–16 s into boot or minutes into use, with nothing in the log. The kernel is set to freeze on a crash, not reboot, so the reset comes from below Linux (firmware, hypervisor or PMIC). See `docs/REPORT.md`. While this is being diagnosed, `install.sh` also installs `files/etc/systemd/journald.conf.d/50-ux3407na-reset-debug.conf`, which makes journald write logs to disk every 5 s instead of every 5 min, so the seconds before a reset are kept. Remove it afterwards with `./uninstall.sh --reset-debug`.

## Install

```sh
git clone https://github.com/flippedpants/omarchy-setup.git
cd omarchy-setup/ux3407na
bt/build-modules.sh # builds the Bluetooth modules for the running kernel (~1 min, as your user)
./install.sh        # asks for your sudo password, then runs verify.sh
sudo reboot         # Bluetooth modules load from the next boot
```

This copies:

| Repo file | Installed to |
|---|---|
| `files/usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload` | `/usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload` |
| `files/etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules` | `/etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules` |

plus the Bluetooth modules (`bt/modules/<kernel>/*.ko` → `/usr/lib/modules/<kernel>/updates/ux3407na-bt/`), `files/etc/pacman.d/hooks/95-ux3407na-bt.hook` and `files/usr/local/lib/ux3407na/bt-check-modules`.

The sleep fixes need no reboot; Bluetooth needs one. None of these files belongs to a package, so `omarchy update` / pacman leave them alone. Rolling back to a system snapshot older than the install, or reinstalling the OS, removes them; run `./install.sh` again.

## Check it is working

```sh
./verify.sh
```

After closing the lid for a few minutes and opening it, expect: all lines `ok`, 0 Wi-Fi resume failures, the last wake IRQ is `lid` (not `dp_hs_phy_2`). Run it after kernel updates too.

## Bluetooth after a kernel update

The Bluetooth modules are built for one exact kernel. When `linux-omarchy` updates, the pacman hook prints a line like this near the end of `omarchy update`:

```
ux3407na-bt: kernel 7.3.6-2-omarchy has no QCC2072 Bluetooth modules; Bluetooth will be off on it.
```

Bluetooth is simply off on that kernel until you rebuild; nothing else is affected (Wi-Fi, sleep and the other fixes don't depend on the kernel version). To rebuild, run these from any folder, before or after rebooting into the new kernel (its `linux-omarchy-headers` must be installed, which `omarchy update` does):

```sh
~/work/omarchy-setup/ux3407na/bt/build-modules.sh 7.3.6-2-omarchy   # the version the hook printed (~1 min, as your user)
~/work/omarchy-setup/ux3407na/install.sh                            # asks for your sudo password
```

(These paths assume the repo is at `~/work/omarchy-setup`; the hook message always prints the real path.) If you missed the message: `ls /usr/lib/modules` lists the installed kernels (the name to use is the folder name, e.g. `7.3.6-2-omarchy`). After rebooting into the new kernel you can also leave the version out, and it defaults to the running kernel (`uname -r`). Then reboot (if you haven't yet) and run `~/work/omarchy-setup/ux3407na/verify.sh`.

`build-modules.sh` fetches the exact linux-omarchy source for that version (kernel.org tarball checked against the PKGBUILD sha256 + Omarchy's patches from omarchy-pkgs; it never runs the PKGBUILD), applies `bt/patches/`, and builds only the three modules against the installed headers. It refuses to build once the kernel's own btqca supports QCC2072, which means Omarchy or upstream caught up and the override can go (`./uninstall.sh --bt`). If a patch stops applying to a new kernel it fails with a clear message and nothing is installed.

Patches (`bt/patches/`, unmerged upstream as of 2026-11-25):
- `0001` Bluetooth: qca: add QCC2072 support (Vivek Sahu et al., qcom-next 4963fd8a20b1, v2 2/6), rebased onto linux-omarchy 7.3
- `0002` pwrseq-pcie-m2: add QCC2072 BT PCI ID 17cb:1112 (qcom-next bc2b6da4d0b5, v2 3/6)

Firmware used: `qca/ornbtfw11.tlv`, `qca/ornnv11.bin`, `qca/ornbcscal11.bin` from linux-firmware.

## Turn off or remove

```sh
sudo touch /etc/ux3407na-wifi-reload.disable   # pause only the Wi-Fi hook
sudo rm /etc/ux3407na-wifi-reload.disable      # resume it
./uninstall.sh --bt                            # remove only the Bluetooth modules (reboot after)
./uninstall.sh                                 # remove everything
```

## Changing a fix

Edit the file under `files/`, run `./install.sh`, test, then commit. `verify.sh` reports `DIFFERENT` if the installed copy and the repo copy have drifted apart.

## Other contents

- `docs/REPORT.md` — full investigation: hardware inventory, failure timeline with log excerpts, causes, upstream fixes, test plan, and dated addenda for each change.
- `tools/capture-state.sh` — snapshot of Wi-Fi/Bluetooth/suspend state before and after a test (`sudo` adds GPIO, regulator and wake-source detail).
- `tools/heartbeat.sh` — writes a timestamp every 2 s; after a forced power-off it shows whether the system was alive after resume.
- `tools/collect-privileged.sh` — read-only root collection of boot images, GPIO, regulator and wakeup state.
