# ASUS Zenbook A14 UX3407NA (Snapdragon X2 Elite) — sleep and Wi-Fi fixes

Tested on Omarchy with `linux-omarchy` 7.3-77, BIOS UX3407NA.316, on 2026-11-23.

## What is fixed

| Problem | Cause | Fix |
|---|---|---|
| Wi-Fi dead after waking from a sleep of more than a minute or two (`failed to start mhi: -110`, "Hardware became unavailable upon resume") | The ath12k driver cannot restart the QCC2072 Wi-Fi card in place after a real sleep | `50-ux3407na-wifi-reload` sleep hook unloads the Wi-Fi driver before suspend and loads it fresh after waking |
| Lid closed → laptop wakes after ~1.6 s, re-suspends 30 s later, forever | Spurious wake IRQ `dp_hs_phy_2` from port 2 of the multiport USB controller `a400000.usb` (nothing is connected to that port; the USB-A port is port 1) | `70-ux3407na-usb-mp-nowake.rules` udev rule disables wakeup for that controller |

Side effects: Wi-Fi takes a few seconds to reconnect after each wake, and a device in the USB-A port cannot wake the laptop (the lid, power key and built-in keyboard still can). The USB-A port otherwise works normally.

Not fixed: Bluetooth (needs QCC2072 Bluetooth support that is not in the kernel yet), occasional resets early in boot. See `docs/REPORT.md`.

## Install

```sh
git clone https://github.com/flippedpants/omarchy-setup.git
cd omarchy-setup/ux3407na
./install.sh        # asks for your sudo password, then runs verify.sh
```

This copies:

| Repo file | Installed to |
|---|---|
| `files/usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload` | `/usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload` |
| `files/etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules` | `/etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules` |

No reboot is needed. Neither file belongs to a package, so `omarchy update` / pacman leave them alone. Rolling back to a system snapshot older than the install, or reinstalling the OS, removes them; run `./install.sh` again.

## Check it is working

```sh
./verify.sh
```

After closing the lid for a few minutes and opening it, expect: all lines `ok`, 0 Wi-Fi resume failures, the last wake IRQ is `lid` (not `dp_hs_phy_2`). Run it after kernel updates too.

## Turn off or remove

```sh
sudo touch /etc/ux3407na-wifi-reload.disable   # pause only the Wi-Fi hook
sudo rm /etc/ux3407na-wifi-reload.disable      # resume it
./uninstall.sh                                 # remove both fixes
```

## Changing a fix

Edit the file under `files/`, run `./install.sh`, test, then commit. `verify.sh` reports `DIFFERENT` if the installed copy and the repo copy have drifted apart.

## Other contents

- `docs/REPORT.md` — full investigation: hardware inventory, failure timeline with log excerpts, causes, upstream fixes, test plan, and dated addenda for each change.
- `tools/capture-state.sh` — snapshot of Wi-Fi/Bluetooth/suspend state before and after a test (`sudo` adds GPIO, regulator and wake-source detail).
- `tools/heartbeat.sh` — writes a timestamp every 2 s; after a forced power-off it shows whether the system was alive after resume.
- `tools/collect-privileged.sh` — read-only root collection of boot images, GPIO, regulator and wakeup state.
