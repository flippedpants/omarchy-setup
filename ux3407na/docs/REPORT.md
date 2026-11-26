# ASUS Zenbook A14 (UX3407NA) on Omarchy: Wi-Fi, sleep, Bluetooth and random resets

*Last updated 2026-11-27. Covers about 55 boots in the journal, from the first Omarchy boot (mid-November) to 27 November 2026.*

This report covers four problems with Linux on this laptop: what was wrong, what caused it, what was changed, and what is still open. Each problem has a short **in plain words** summary first, then the technical detail. Words like *s2idle*, *MHI* or *PS_HOLD* are explained in the [glossary](#glossary) at the end.

**How sure is each statement?**

| Label | Meaning |
|---|---|
| **Confirmed** | Seen directly: in the logs, on the hardware, in the kernel source, or by a test. |
| **Likely** | Follows from confirmed facts, but not tested. |
| **Unknown** | No evidence yet. |

---

## Contents

1. [Summary](#1-summary)
2. [The laptop](#2-the-laptop)
3. [Problem 1: Wi-Fi dies after sleep](#3-problem-1-wi-fi-dies-after-sleep)
4. [Problem 2: the laptop keeps waking up with the lid closed](#4-problem-2-the-laptop-keeps-waking-up-with-the-lid-closed)
5. [Problem 3: no Bluetooth](#5-problem-3-no-bluetooth)
6. [Problem 4: random resets](#6-problem-4-random-resets)
7. [Smaller issues](#7-smaller-issues)
8. [What is installed, and how to maintain it](#8-what-is-installed-and-how-to-maintain-it)
9. [Upstream fixes to watch for](#9-upstream-fixes-to-watch-for)
10. [Timeline](#10-timeline)
11. [Theories that turned out wrong](#11-theories-that-turned-out-wrong)
12. [Glossary](#glossary)
13. [Appendix: key log excerpts](#appendix-key-log-excerpts)

---

## 1. Summary

| # | Problem | Status | What fixed it |
|---|---|---|---|
| 1 | Wi-Fi stops working after the laptop sleeps for more than a minute or two | **Worked around**: 170 sleeps since 23 Nov, 0 failures | A sleep hook unloads the Wi-Fi driver before sleep and loads it fresh after waking |
| 2 | With the lid closed, the laptop wakes about 1.6 s after sleeping, sleeps again 30 s later, and repeats forever | **Fixed**: stays asleep for hours; only the lid wakes it | A udev rule stops one USB controller from waking the laptop. The wake was a false signal from a USB port with nothing plugged in |
| 3 | No Bluetooth at all | **Fixed**: headphones work (A2DP/AAC), survives sleep, 7/7 firmware loads OK | Three kernel modules rebuilt with two unreleased upstream patches. They must be rebuilt after each kernel update (about 1 min) |
| 4 | The laptop freezes for a few seconds, then reboots by itself | **Open**: cause narrowed down, not found | 1-second logging is on, to capture the next one |
| – | Smaller issues: USB-A flash drive errors, USB-C display output clock error, broken "deep" sleep, old test boot entry | See [section 7](#7-smaller-issues) | – |

Everything installed lives in the repo **`~/work/omarchy-setup/ux3407na/`**. It has install, uninstall and check scripts; see [section 8](#8-what-is-installed-and-how-to-maintain-it). Nothing in Omarchy's own files (`/usr/share/omarchy`) was changed.

---

## 2. The laptop

| Part | Value |
|---|---|
| Model | ASUS Zenbook A14 UX3407NA |
| Processor | Qualcomm Snapdragon X2 Elite (codename *glymur*): 18 cores in 3 clusters of 6 (top speeds 3.42, 4.03 and 4.03 GHz) |
| BIOS | UX3407NA.316 (2026-10-22). No newer version could be confirmed |
| OS | Omarchy (Arch Linux ARM), dual boot with Windows |
| Kernel | `linux-omarchy` 7.3.6-5 (was 7.3.0-72 when this started) |
| Boot | Limine boot menu, then a unified kernel image (UKI) that contains the kernel, initramfs and device tree |
| Wi-Fi + Bluetooth chip | **Qualcomm QCC2072** combo on an M.2 card (Foxconn NCM820A, PCI ID `17cb:1112`, subsystem `105b:e14f`). Wi-Fi runs over PCIe; Bluetooth over a serial line (UART14). *Not* a WCN7850, as first assumed |
| Wi-Fi firmware | `WLAN.COL.1.0.c2-00277` (built 2024-09-11; no newer version exists in linux-firmware) |
| Bluetooth firmware | `BTFW.ORNE.1.1.0-00355` (`qca/ornbtfw11.tlv`, `ornnv11.bin`, `ornbcscal11.bin`) |
| Power-management chip (PMIC) | Qualcomm PMK8850 plus helper PMICs on the SPMI bus |
| Sleep mode | *s2idle* (forced by `/etc/systemd/sleep.conf.d/90-s2idle.conf`, because *deep* sleep hung) |
| Clock quirk | The hardware clock (RTC) reads 1970 and can't set wake alarms, so boot-time timestamps are approximate and timed wake tests aren't possible |

---

## 3. Problem 1: Wi-Fi dies after sleep

### In plain words

After the laptop slept for more than a minute or two, Wi-Fi was gone until a reboot. Short sleeps of a few seconds were fine. The Wi-Fi driver can't restart the card after a real sleep: the card's own firmware fails to start. Then the driver gets stuck and doesn't retry. The workaround removes the driver completely before sleep and loads it from scratch after waking, as at boot.

### What happened (Confirmed)

After waking from a sleep of a minute or more:

```
ath12k_wifi7_pci 0004:01:00.0: failed to set mhi state: POWER_ON(2)
ath12k_wifi7_pci 0004:01:00.0: failed to start mhi: -110
Hardware became unavailable upon resume
```

- `-110` means *timed out*. The card was still reachable over PCIe, but its firmware never finished starting. A card that had lost power would give a different error.
- After that first failure the driver is left half-initialised. Every later attempt fails with `failed to set mhi state INIT(0) in current mhi state (0x1)`, so Wi-Fi stays dead for the rest of the boot.
- Seen on the stock setup (kernel 7.3.0-72 and -77) and on the old Bluetooth test boot entry, so neither causes it.
- The driver doesn't use Wake-on-WLAN here. It switches the card off on every sleep and reboots the card's firmware on every wake. That's why the Wi-Fi firmware banner reappears after each wake; this is normal.

**Why the card's firmware stalls after a longer sleep:** Unknown. The likely factor is that a longer sleep lets the processor reach a deeper power state. Two upstream patches, not yet merged, address parts of this (see [section 9](#9-upstream-fixes-to-watch-for)).

### The fix

**File:** `/usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload` (repo: `files/usr/lib/systemd/system-sleep/`)

- **Before sleep:** `modprobe -r ath12k_wifi7 ath12k` unloads the Wi-Fi driver.
- **After waking:** `modprobe ath12k_wifi7` loads it fresh, exactly like at boot.
- It writes one journal line per step (`ux3407na-wifi-reload: unloaded… / loaded…`).
- **Pause it without uninstalling:** `sudo touch /etc/ux3407na-wifi-reload.disable` (delete the file to resume).

**Results (Confirmed):** 170 sleep/wake cycles since 23 Nov with 0 `failed to start mhi` errors. Sleeps tested include 18 minutes, 21 minutes and 3 hours.

**Trade-off:** Wi-Fi takes a few seconds to reconnect after each wake.

---

## 4. Problem 2: the laptop keeps waking up with the lid closed

### In plain words

With the lid closed, the laptop slept, woke about 1.6 seconds later, and went back to sleep 30 seconds after that, over and over: one boot did it 546 times. The wake came from an empty USB port giving a false "something was plugged in" signal. Telling that USB controller it may not wake the laptop fixed it.

### What happened (Confirmed)

- **The 30-second re-sleep is normal.** systemd-logind puts the laptop back to sleep if the lid is still closed 30 s after a wake.
- **The real problem was the wake itself.** After a sleep, the kernel records which interrupt woke it:
  - `/sys/power/pm_wakeup_irq` read **260**, which is `dp_hs_phy_2`. That's the data line of **port 2** on the *multiport USB controller* (`a400000.usb`), behind a signal booster chip (NXP PTN3222).
  - Over one boot it fired once per sleep: 157 times in 157 sleeps.
  - Nothing is connected to port 2. The physical USB-A port is port 1.
  - It's a glitch, most likely from the booster chip or the port's PHY as they enter low power.
- **First suspect, ruled out:** Wi-Fi was suspected first, but the wakes kept happening with the Wi-Fi driver fully unloaded (see [section 11](#11-theories-that-turned-out-wrong)).
- **Measurement trap:** the "~2 s sleeps" seen early on were measured with the kernel's *monotonic* clock, which stops during sleep, so they understated real sleep time. Real sleep length has to be read from wall-clock times.

### The fix

**File:** `/etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules` (repo: `files/etc/udev/rules.d/`)

```
ACTION=="add|bind", SUBSYSTEM=="platform", KERNEL=="a400000.usb", ATTR{power/wakeup}="disabled"
```

**Result (Confirmed):** the lid stayed closed for 21 minutes and the laptop stayed asleep the whole time. The wake reason was the lid opening (IRQ 62, `lid`), and IRQ 260 didn't fire again.

**Trade-offs:**
- A device in the USB-A port can't wake the laptop. The lid, power key and keyboard still can.
- The port otherwise works normally.

---

## 5. Problem 3: no Bluetooth

### In plain words

The kernel didn't support this Bluetooth chip yet:
- On the normal boot entry, Bluetooth didn't exist at all.
- An earlier hand-made test boot entry pretended the chip was a different model (WCN7850). Bluetooth then worked on the chip's built-in basic code only, because the kernel asked for firmware files that don't exist for this chip.

Three kernel modules were rebuilt with two upstream patches that aren't released yet. They load instead of the kernel's own copies, and Bluetooth now works properly on the normal boot entry.

### How Bluetooth starts on this laptop

```
Wi-Fi card found on PCIe (ID 17cb:1112)
  └─ pwrseq-pcie-m2   "this card also has Bluetooth on serial port UART14": creates the device, switches its power line
       └─ hci_uart    talks to the chip over the serial line: power-on, speed up to 3.2 Mbit/s, sleep/wake
            └─ btqca  loads Qualcomm's firmware into the chip's memory (nothing is written permanently)
                 └─ hci0 → bluetoothd → your headphones
```

### What was missing (Confirmed)

| Module | What was wrong | Patch |
|---|---|---|
| `pwrseq-pcie-m2` | Its list of Wi-Fi cards with Bluetooth didn't include `17cb:1112`, so no Bluetooth device was created | `0002`: adds the ID (upstream qcom-next `bc2b6da4d0b5`) |
| `hci_uart` and `btqca` | Didn't know the QCC2072, so they had no power-on steps for it and asked for the wrong firmware file names | `0001`: adds QCC2072 support (upstream qcom-next `4963fd8a20b1`, rebased onto Omarchy's 7.3) |

Both patches are from the Qualcomm series "Bluetooth: qca: enable QCC2072" (v2). They aren't merged upstream as of 27 Nov: a reviewer rejected the device-tree binding. Another user tested them on the sister model, the Zenbook A16, on 10 Nov.

### The fix

**Files:**
- **The modules:** `/usr/lib/modules/<kernel>/updates/ux3407na-bt/{btqca,hci_uart,pwrseq-pcie-m2}.ko`
  - Linux prefers modules in `updates/`, so these load instead of the originals.
  - The originals, the device tree and the boot image are untouched.
- **The build script:** `bt/build-modules.sh`
  - Downloads the exact kernel source Omarchy used for that kernel version (checked against the package checksum).
  - Applies Omarchy's patches, then the two Bluetooth patches.
  - Builds only those three modules.
- **The update reminder:** a pacman hook (`95-ux3407na-bt.hook`) runs `bt-check-modules` after every kernel update.
  - It prints a reminder when the new kernel has no Bluetooth modules yet.
  - It removes modules left behind for kernels that have been uninstalled.

**Results (Confirmed):**
- **Firmware:** `QCA setup on UART is completed` in 7 of 7 firmware loads across 5 boots. Kernels 7.3.0-77, 7.3.6-2 and 7.3.6-5.
- **Audio:** Sony WH-CH520 headphones paired and played over A2DP using the AAC codec.
- **Sleep:** Bluetooth stayed on through an 18-minute and a 3-hour sleep, and the headphones reconnected.
- **Kernel updates:** rebuilding worked for 7.3.6-2 (about 1 minute) and for 7.3.6-5, which you rebuilt yourself.

**Normal log lines that look like errors:**
- **`Direct firmware load for qca/ornnv11.b17 failed with error -2`:** the driver tries a board-specific file first, then uses the generic `ornnv11.bin`.
- **The firmware downloads again whenever Bluetooth is switched on:** the chip forgets its firmware when powered off.

**Risks:**
- On the A16, about 1 boot in 5 failed to load the firmware (`Failed to send TLV segment (-110)`). It hasn't happened here yet (0 of 7 loads). If it does, a small automatic retry could be added.
- `pwrseq-pcie-m2` also controls the Wi-Fi card's power line. If a rebuilt module ever misbehaves, Wi-Fi could be affected too.
  - **Recovery:** `./uninstall.sh --bt`, then reboot. No network needed.
- Not tested yet: the headset microphone (HFP profile).

---

## 6. Problem 4: random resets

### In plain words

Sometimes Linux freezes for a few seconds and then the laptop restarts by itself. It never happens on Windows.

- **Ruled out:** the battery, the charger, overheating, the CPU being overloaded, and Linux crashing.
- **What it is:** firmware on the Snapdragon chip itself decides to reset the machine. Most likely it notices that part of the chip has locked up.
- **What sets it off:** not found yet. It only happens in the first few minutes after power-on.
- **Plan:** wait for it to happen again with detailed logging on.

### What it looks like (Confirmed)

Pattern across about 55 boots (16–27 Nov):

| When it happens | How many | Notes |
|---|---|---|
| **7–16 s after power-on**, while drivers are still loading | 15 | A normal boot always follows. Easy to miss: it looks like a slow boot |
| **30 s to about 3 min after power-on**, after login, while apps open | about 16 | The ones you notice. Some early ones may have been power-button presses |
| Later than a few minutes | about 1 (after 2.6 h) | Boots that get past the first few minutes usually run for hours or days, sleeps included |
| On Windows | never | User report |

- **Kernels:** seen on 7.3.0-72, -75, -77 and 7.3.6-2, on both the old test entry and the normal entry. It started before any of the fixes in this report.
- **Power source:** the reset on 26 Nov was on battery. It's unknown whether any happened while plugged in.

### What the evidence says

**1. The power-management chip says the processor asked for the reset. (Confirmed)**

- **How it was read:** the PMIC keeps a log of why each power-on and reset happened. It was read with `tools/pmic-pon-log.sh`, which decodes the log using Qualcomm's layout.
- **What all 7 resets in the log show:**

  ```
  Reset Trigger: PS_HOLD     ← the processor let go of its "keep the power on" line
  Reset Type:    HARD_RESET
  PON Trigger:   HARD_RESET  ← restarted straight away
  PON successful
  ```

- **No fault entries at all:**
  - no under- or over-voltage (so not the battery or charger);
  - no over-temperature;
  - no power-chip watchdog;
  - no current-limit alarm;
  - no long power-key press.
- **Limit:** a normal `reboot` looks exactly the same in this log. It tells us *who* reset the laptop (the processor side), not *why*.

**2. Linux didn't ask for it. (Confirmed)**

- No shutdown is logged before any of these resets.
- On a crash, Linux is set to freeze, not reboot: `kernel.panic = 0`.
- Linux's own watchdog is off: `qcom_wdt` is inactive and systemd's watchdog is 0.
- No crash report was saved (`/var/lib/systemd/pstore` is empty).

**3. So it's firmware on the Snapdragon chip. (Likely)**

- That means Qualcomm's security firmware, hypervisor or power controller.
- This fits the "freezes for a few seconds, then reboots" pattern well: something on the chip locks up, Linux stops completely, and a firmware watchdog resets the machine a few seconds later.
- A common cause on new Snapdragon laptops is a driver touching a part of the chip whose clock or power is switched off. That hangs the chip's internal bus. **Likely mechanism, not proven.**

### What has been ruled out

| Suspect | How it was tested | Result |
|---|---|---|
| Battery, charger, under-voltage, overheating | PMIC reset log | **Ruled out**: no fault recorded |
| A Linux crash (kernel panic) | panic settings, journal, pstore | **Ruled out**: Linux would freeze, not reboot, and nothing was logged |
| Opening a browser | Compared 50 boots | **Ruled out**: browser start appears in many boots that ran for hours, and is missing from several that reset |
| CPU load spikes on battery (Omarchy's CPU floor, PR #18745, linked such spikes to hard resets on the sister model) | **Test 1:** 18 cores at full load for 1 s, 40 times. **Test 2:** `tools/burst-load.c`, all 18 cores switching idle↔full at the same instant, about 8,000 times, plus 15 s continuous load | **Ruled out**: no reset |
| GPU plus CPU load on battery | WebGL Aquarium (30,000 fish, fullscreen) plus Test 2 at the same time | **Ruled out**: no reset |
| Regulators or clocks switched off 30 s after boot | Checked the kernel log | **Ruled out**: nothing is switched off (`clk_ignore_unused`, `pd_ignore_unused` are set) |
| Bluetooth modules | Resets happened before they existed | **Ruled out** |

### Still possible (all unproven)

- **Display or GPU drivers.** Every boot logs "stuck clock" warnings from the display driver (`clk-branch.c:87`). The USB-C display output fails with `Failed to enable clk 'com_aux': -16`. A driver touching a block whose clock is stuck is exactly the kind of access that can hang the chip.
- **Something that happens only once, early after boot,** such as a driver starting up, firmware loading into one of the chip's helper processors, or the first power-saving step of some device. The narrow early window points this way.
- **A BIOS or firmware bug** that a newer BIOS might fix.

### What's in place now, and what to do when it happens

- **Logging:** the journal is saved to disk every **1 second**, instead of every 5 minutes. The setting is `/etc/systemd/journald.conf.d/50-ux3407na-reset-debug.conf`. The last second before the freeze will be on disk.
- **After the next reset, record:**
  1. that it reset;
  2. whether it was plugged in or on battery;
  3. what you were doing.
- **Then read:**
  - `journalctl -b -1` for the last second of logs before the freeze;
  - `sudo tools/pmic-pon-log.sh` for the reset record.
- **After a few resets,** compare the final seconds for a common trigger.
- **Also:** check ASUS support for a BIOS newer than **316**.
- **When it's solved:** `./uninstall.sh --reset-debug` puts logging back to normal.

---

## 7. Smaller issues

| Issue | What we know | Status |
|---|---|---|
| **"Deep" sleep is broken** | The kernel's default sleep mode (*deep*) hung the laptop 3 times, or returned straight away. `/etc/systemd/sleep.conf.d/90-s2idle.conf` (created 20 Nov) makes systemd use *s2idle* instead, which works with the fixes above | Avoided. Anything that suspends without systemd would still use *deep* |
| **USB-A flash drive stops working** | A flash drive worked on the USB-A port, disconnected after 14 s, then failed with `error -71` (a protocol error) on every retry. Not caused by the wake fix, which only affects waking from sleep | Open: probably the drive or a loose contact. Try another device in that port |
| **USB-C display output clock error** | Every boot: `Failed to enable clk 'com_aux': -16`, `phy init failed --> -16` for the USB-C display PHY (`88e1000`). The internal screen isn't affected | Open. External monitors over USB-C not tested. A suspect for problem 4 |
| **Old "Omarchy Bluetooth test" boot entry** | Hand-made boot image for kernel 7.3.0-72, whose modules no longer exist. Booting it would give no Wi-Fi, sound or Bluetooth. It's no longer needed | **To remove**: `/boot/EFI/Linux/omarchy-bluetooth-test.efi` and its Limine entry, after a look at `/boot/limine.conf` |
| **Wi-Fi calibration file** | linux-firmware has no calibration data for this exact card (`105b:e14f`), so Omarchy uses one from a sibling card. Windows uses ASUS's own file, `bdwlan_qcc2072_1p0_ncm820A.elf` | Optional improvement. No known symptom |

---

## 8. What is installed, and how to maintain it

### Files on the laptop

| File | Purpose | Kernel-specific? |
|---|---|---|
| `/usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload` | Problem 1: Wi-Fi driver reload around sleep | No |
| `/etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules` | Problem 2: no wakeups from the multiport USB controller | No |
| `/usr/lib/modules/<kernel>/updates/ux3407na-bt/*.ko` | Problem 3: Bluetooth modules | **Yes**: rebuild after kernel updates |
| `/etc/pacman.d/hooks/95-ux3407na-bt.hook` and `/usr/local/lib/ux3407na/bt-check-modules` | Problem 3: reminder after kernel updates; cleanup of old kernels | No |
| `/etc/systemd/journald.conf.d/50-ux3407na-reset-debug.conf` | Problem 4: 1-second log syncing (temporary) | No |

- **Updates:** none of these files belongs to a package, so `omarchy update` and pacman leave them alone.
- **Rollback and reinstall:** rolling back to a snapshot from before they were installed removes them, and so does reinstalling Linux. Run `./install.sh` again afterwards.

### Commands

All of these run from `~/work/omarchy-setup/ux3407na/`.

| Task | Command |
|---|---|
| Check everything | `./verify.sh` (no sudo; every line should say `ok`) |
| Install or update from the repo | `./install.sh` |
| Bluetooth after a kernel update | `bt/build-modules.sh <version the update printed>`, then `./install.sh` |
| Pause only the Wi-Fi hook | `sudo touch /etc/ux3407na-wifi-reload.disable` |
| Remove only Bluetooth | `./uninstall.sh --bt`, then reboot |
| Remove only the debug logging | `./uninstall.sh --reset-debug` |
| Remove everything | `./uninstall.sh` |
| Read the power chip's reset log | `sudo tools/pmic-pon-log.sh` |
| Snapshot Wi-Fi/Bluetooth/sleep state | `tools/capture-state.sh <label>` |

### Bluetooth after a kernel update

1. **The update tells you.** At the end of `omarchy update`, the hook prints a line like:

   ```
   ux3407na-bt: kernel 7.3.6-5-omarchy has no QCC2072 Bluetooth modules; Bluetooth will be off on it.
   ```

2. **Rebuild and install.** Run the two commands it prints, before or after rebooting.
3. **If you skip it,** Bluetooth is simply off on the new kernel. Nothing else is affected.
4. **When the override is no longer needed,** `build-modules.sh` refuses to build. That happens once the kernel's own Bluetooth driver supports this chip, meaning Omarchy or upstream has caught up. Run `./uninstall.sh --bt`.

---

## 9. Upstream fixes to watch for

Once these land in Omarchy's kernel, the local workarounds can go.

| Fix | Would replace | Status (27 Nov 2026) |
|---|---|---|
| Bluetooth: qca: QCC2072 support, plus `17cb:1112` in pwrseq-pcie-m2 (Qualcomm, v2 series) | The rebuilt Bluetooth modules | In qcom-next; binding rejected in review; not merged |
| ath12k: clean up MHI when power-up fails (patchwork `20261031224009.2323055-3-vz@kernel.org`) | The "stays dead after the first failure" part of problem 1 | Posted 31 Oct, not merged |
| ath12k: recover from firmware crash during resume (4 patches, `20261112110008.1229-1-tvlad744@gmail.com`) | Possibly the Wi-Fi sleep hook | Posted 12 Nov, not merged; tested only on another chip |
| linux-firmware: newer QCC2072 Bluetooth firmware 1.1.0-00391 (commit `58b6166634a1`) | Fixes a headset-microphone (HFP mSBC) bug | After the last linux-firmware release (20261019) |
| Calibration file for `105b:e14f` | Omarchy's borrowed calibration file | None upstream |
| ASUS BIOS newer than 316 | Possibly problem 4 | Not found |

---

## 10. Timeline

| Date | What happened |
|---|---|
| Mid-Nov | Omarchy installed (kernel 7.3.0-66). Dates before 17 Nov are approximate because of the clock quirk |
| 17 Nov | Kernel 7.3.0-72. First random resets in the journal. Sleep sometimes hangs in *deep* mode |
| 20 Nov | A hand-made "Bluetooth test" boot entry with a modified device tree is in use: Bluetooth works on basic built-in code. Systemd forced to *s2idle*. The lid-closed wake loop appears (546 cycles in one boot). Wi-Fi dies after sleep. Investigation starts, and the first report blames the test entry for the Wi-Fi failures |
| 22 Nov | Kernel 7.3.0-77. **Wi-Fi fails after sleep on the normal entry too**, so the test-entry theory is dropped. The test entry no longer has matching modules |
| 23 Nov | Wi-Fi sleep hook installed. The wake-loop source is found (USB port 2, IRQ 260), and the udev rule fixes it. Verified with a 21-minute lid-closed sleep |
| 25 Nov | Bluetooth modules built and installed; **Bluetooth verified** with headphones. Repo `omarchy-setup` created. Survey of 48 boots finds about 30 resets. Journal syncing set to 5 s. Kernel updates to 7.3.6-2 and modules rebuilt |
| 26 Nov | Reset on 7.3.6-2. **PMIC reset log decoded**: the processor requested every reset, with no power or thermal fault. CPU load tests on battery: no reset |
| 27 Nov | GPU plus CPU test: no reset. Journal syncing set to 1 s. Kernel 7.3.6-5, Bluetooth rebuilt by the user. This report rewritten |

---

## 11. Theories that turned out wrong

These are kept so the same paths aren't walked again.

| Theory | Why it looked right | What disproved it |
|---|---|---|
| "The Bluetooth test boot entry breaks Wi-Fi after sleep" | On 20 Nov: 497 Wi-Fi failures in 555 sleeps on the test entry, 0 in 44 on the normal entry | 22 Nov: the normal entry failed the same way. Its earlier sleeps had mostly been too short to trigger the problem |
| "The ~2 s sleeps mean something wakes the laptop instantly, probably Wi-Fi" | Sleep looked about 2 s long | That measurement used the monotonic clock, which stops during sleep. With the Wi-Fi driver fully unloaded, the wakes continued. The real source was USB port 2 |
| "The Wi-Fi chip is a WCN7850" | The old test entry described it that way | The PCI ID `17cb:1112` and the driver say QCC2072 |
| "Random resets are CPU power spikes on battery (Omarchy's CPU floor)" | Omarchy's PR #18745 linked hard resets on battery to the CPU running flat out on the sister model. Here, clusters jump to 3–4 GHz even when idle | About 8,000 synchronised all-core load steps on battery, and GPU plus CPU load together: no reset |
| "Opening the browser triggers resets" | A browser warning was often the last kernel line before a reset | It's also there in boots that ran for hours, and missing from several resets |

---

## Glossary

| Term | Meaning |
|---|---|
| **s2idle / deep sleep** | Two Linux sleep modes. *s2idle* ("suspend to idle") freezes software and lets the hardware idle; *deep* asks the firmware to power down more. Deep is broken here, so s2idle is used |
| **Monotonic clock** | The kernel's "time since boot" clock. It stops while the laptop sleeps, so log gaps measured with it understate how long a sleep lasted |
| **Kernel module** | A driver loaded into the kernel when its hardware appears (`.ko` file). Modules in `updates/` take priority over the kernel's own |
| **Device tree** | A file describing the board's hardware (which chip sits on which bus, which pins control power) for the kernel |
| **UKI** | Unified kernel image: one boot file containing the kernel, initramfs and device tree. Omarchy boots these via Limine |
| **PCIe** | The fast internal bus the Wi-Fi card uses |
| **MHI** | Qualcomm's protocol for loading firmware into the Wi-Fi card and talking to it over PCIe. "failed to start mhi" means the card's firmware didn't come up |
| **UART / serdev** | A serial line. Bluetooth on this card talks over UART14; *serdev* is the kernel's name for a device on such a line |
| **pwrseq** | Kernel "power sequencing" drivers that switch a device's power and enable lines on in the right order |
| **Firmware (chip)** | Code that runs inside a chip (Wi-Fi, Bluetooth). Linux loads it from `/usr/lib/firmware` every time the chip powers up |
| **Firmware (platform)** | Code that runs on the Snapdragon itself below Linux: BIOS/UEFI, Qualcomm's security firmware (TrustZone), hypervisor and power controllers |
| **Wake IRQ** | The interrupt that woke the laptop from sleep. Linux records the last one in `/sys/power/pm_wakeup_irq` |
| **udev rule** | A rule that sets device options when the device appears. Used here to disable wakeup on one USB controller |
| **PMIC** | Power-management IC: the chip that supplies every voltage and turns the laptop on and off |
| **PS_HOLD** | The signal line from the processor to the PMIC meaning "keep me powered". Dropping it requests a reset |
| **SDAM** | Small memory blocks inside the PMIC. Firmware writes the power-on/reset log there |
| **Watchdog** | A timer that resets the machine if it isn't "petted" regularly, which catches hangs |
| **uclamp / CPU floor** | A Linux setting that makes the speed governor treat a task as at least X% busy. Omarchy's floor is 75% in balanced mode |
| **A2DP / HFP** | Bluetooth audio profiles: A2DP is high-quality playback, HFP is headset mode with a microphone |

---

## Appendix: key log excerpts

**Wi-Fi failing after a real sleep** (boot `1244c923`, the first failure in that boot):

```
qcom-pcie 1bf0000.pcie: Timeout waiting for L2 entry! LTSSM: 0x11     ← harmless warning, seen on every sleep
qcom-pcie 1bf0000.pcie: PCIe Gen.3 x1 link up
mhi mhi0: Wait for device to enter SBL or Mission mode
ath12k_wifi7_pci 0004:01:00.0: failed to set mhi state: POWER_ON(2)
ath12k_wifi7_pci 0004:01:00.0: failed to start mhi: -110
Hardware became unavailable upon resume.
```

**The false wake source** (boot `6ceed930`, before the fix):

```
$ cat /sys/power/pm_wakeup_irq
260
$ grep '260:' /proc/interrupts
260: ... PDC 14 Edge dp_hs_phy_2      ← 157 wakes = 157 sleeps
```

**Bluetooth starting correctly** (7.3.6-x with the rebuilt modules):

```
Bluetooth: hci0: setting up qcc2072
Bluetooth: hci0: QCA Downloading qca/ornbtfw11.tlv
Bluetooth: hci0: QCA Downloading qca/ornnv11.bin
Bluetooth: hci0: QCA Downloading qca/ornbcscal11.bin
Bluetooth: hci0: QCA FW build version: BTFW.ORNE.1.1.0-00355-PATCH-1_DEF
Bluetooth: hci0: QCA setup on UART is completed
```

**Before the fix, on the old test entry** (wrong chip type, so no firmware):

```
Bluetooth: hci0: setting up wcn7850
bluetooth hci0: Direct firmware load for qca/hmtbtfw11.tlv failed with error -2
```

**The PMIC reset log** (`tools/pmic-pon-log.sh`, 26 Nov; one cycle of seven, all identical):

```
[RESET     ] *** Reset Trigger: PS_HOLD (SoC dropped PS_HOLD)
[RESET     ] *** Reset Type: HARD_RESET
[OFF       ] PON Trigger: HARD_RESET
[PON       ] --- Begin PON sequence
[PON       ] Waiting on PS_HOLD
[ON        ] PON successful
```

---

*The full chronological notes, including the original 20 Nov hardware audit, the source-code analysis of the Wi-Fi and PCIe drivers, per-boot tables and the first test plan, are in `REPORT-investigation-log.md`.*
