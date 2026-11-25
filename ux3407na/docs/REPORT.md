# ASUS Zenbook A14 UX3407NA (Snapdragon X2 Elite) — Wi-Fi, Bluetooth and suspend investigation

Date: 2026-11-20. Machine state examined: boot `de069fd6…` (current), plus the persistent journal back to
boot `d6d4a03b…` (first install, 2026-11-16). Evidence files are in `evidence/` and `runs/`; the exact
kernel source audited (v7.3 + the 563 Omarchy pkgrel-72 patches) was rebuilt in the session scratchpad.

Legend: **[confirmed]** = read directly from the machine, the logs or the source. **[inferred]** = a
conclusion drawn from confirmed facts that has not been tested on hardware. **[unknown]** = the
evidence does not exist or was lost.

---

## 1. What is actually running

| Component | Value | How verified |
|---|---|---|
| Machine | ASUS Zenbook A14 UX3407NA, DT `asus,zenbook-a14-ux3407na`, `qcom,glymur` | `/proc/device-tree` [confirmed] |
| BIOS | UX3407NA.316, 2026-10-22 (Insyde, UEFI 2.70), Secure Boot off | DMI, `bootctl` [confirmed] |
| Kernel | 7.3.0-72-omarchy, built 2026-11-17 10:00 UTC, package `linux-omarchy 7.3-72` | `uname`, pacman [confirmed] |
| Boot loader | Limine 12.10.0 → systemd-stub 262.2-1-omarchy UKI | `bootctl status` [confirmed] |
| Active entry | **"Omarchy Bluetooth test"** → `/EFI/Linux/omarchy-bluetooth-test.efi` (built 2026-11-20 00:09) | `bootctl`, `limine.conf` [confirmed] |
| Default entry | `default_entry: 2` → `//linux-omarchy` → `/EFI/Linux/omarchy_linux-omarchy.efi` (built 2026-11-18 16:12) | `limine.conf` [confirmed] |
| Kernel image in test UKI | `.linux` sha256 `cb887a1b…` = `/usr/lib/modules/7.3.0-72-omarchy/vmlinuz` = stock UKI `.linux` | objcopy + sha256 [confirmed] |
| Initramfs in test UKI | `.initrd` sha256 `4e1133e7…` = stock UKI `.initrd` (uncompressed cpio, 635 entries; **no Wi-Fi/BT firmware or ath12k/hci modules inside**; contains `pci-pwrctrl-pwrseq`, `pwrseq-qcom-wcn`; **not** `pwrseq-pcie-m2`) | objcopy + cpio [confirmed] |
| Device tree loaded | Test UKI carries a single `.dtb` (sha256 `d28c6f3c…`, identical to `~/work/ux3407na-bluetooth.N52DFw/…-test.dtb`) and **no `.dtbauto`**, so the stub always uses it. Live tree has `/wcn7850-pmu`, `regulator-wcn-0p95`, `pcie@0/wifi@0 (pci17cb,1112)`, `serial@a98000/bluetooth (qcom,wcn7850-bt)` | `/sys/firmware/devicetree`, objcopy [confirmed] |
| Stock tree | Stock UKI `.dtb` sha256 `b93a55fa…` (from `linux-omarchy-dtbs 7.3-48`) + 126 `.dtbauto`. A node-by-node diff against the test tree shows **only** the patch's changes (connector removed; 0p95 regulator, wcn7850-pmu, wifi@0, bluetooth added) | own FDT dump + diff [confirmed] |
| Command line | identical (md5) in all 32 recorded boots; includes `clk_ignore_unused pd_ignore_unused quiet splash loglevel=0` | journal [confirmed] |
| Sleep config | `/etc/systemd/sleep.conf.d/90-s2idle.conf`: `MemorySleepMode=s2idle` (file mtime 2026-11-20 01:41). Kernel default `mem_sleep` is still `[deep]` — only systemd-initiated sleeps use s2idle | file + sysfs [confirmed] |
| Lid policy | logind `HandleLidSwitch=suspend` (also on AC), `HoldoffTimeoutSec=30s`, `HandlePowerKey=ignore`, `InhibitDelayMaxSec=15`. Omarchy idle: lock 300 s, screensaver 150 s, no idle suspend | busctl, shell.json [confirmed] |
| Wi-Fi hardware | **Qualcomm QCC2072** (FastConnect C7700), PCI `17cb:1112` rev 01, subsystem **`105b:e14f`** (Foxconn, NCM820A family), on `qcom-pcie 1bf0000` (PCIe4, Gen3 x1). ath12k: `qcc2072 hw1.0`, chip_id 0x21, **board_id 0xff**, soc_id 0x40292100 | lspci, dmesg [confirmed] |
| Wi-Fi firmware | `ath12k/QCC2072/hw1.0/firmware-2.bin` from linux-firmware 20261019 → `WLAN.COL.1.0.c2-00277`, build **2024-09-11** | dmesg [confirmed] |
| Wi-Fi board data | linux-firmware `board-2.bin` has **no entry** for `105b:e14f`; Omarchy's `ath12k-board-fallback` installed `/usr/lib/firmware/updates/ath12k/QCC2072/hw1.0/board.bin` (sha256 `99b29177…`) copied from the `105b:e15a` NCM820A record (which is tagged `qmi-board-id=24`; this card reports 0xff) | package files, state file [confirmed] |
| Bluetooth hardware | Same combo chip on GENI UART14 (`a98000.serial`, ttyHS0). Reports SOC 0x40292100 (same SoC ID as the QCC2072 Wi-Fi), controller 0x21000101, product 0x20 | dmesg [confirmed] |
| Bluetooth driver path | hci_uart QCA, but probed as **`wcn7850`** because the tree says `qcom,wcn7850-bt` | dmesg [confirmed] |
| Bluetooth firmware | requests **`qca/hmtbtfw11.tlv` → -ENOENT**; runs on ROM patch 0x7b40 with no NVM. The installed linux-firmware *does* ship the QCC2072 UART files `qca/ornbtfw11.tlv`, `ornnv11.bin`, `ornbcscal11.bin` (the `…10` files are WCN7750), but the running btqca has **no "orn" names and no QCC2072 soc type**, and hci_uart has no QCC2072 compatible | dmesg, `strings btqca.ko`, `modinfo` [confirmed] |
| DSP firmware | `asus-zenbook-a14-ux3407na-firmware 20261102-1` (ADSP/CDSP from ASUS SOCPackage V1.315.4500.0) | pacman [confirmed] |
| Persistent crash records | none: `/var/lib/systemd/pstore` empty, EFI pstore backend built default-disabled, no ramoops | [confirmed] |
| RTC | `rtc-pm8xxx` reads **1970-03-08** and has **no wakealarm** → wall clock at boot comes from `/var/lib/systemd/timesync/clock`, which explains the shifted timestamps; `rtcwake` cannot be used for tests | sysfs [confirmed] |

### Mismatches and risks

1. **The Bluetooth test entry is pinned.** It is a hand-made UKI with a fixed path and no hash; `limine-entry-tool`
   and the mkinitcpio/UKI hook never rebuild it. Today it matches (same kernel, same initramfs), but the next
   `linux-omarchy` upgrade removes `/usr/lib/modules/7.3.0-72-omarchy`, after which the test entry boots a 7.3.0-72
   kernel with **no matching modules** (no Wi-Fi, Bluetooth, sound, possibly no display). Any dtbs or
   initramfs fix also bypasses it. [confirmed mechanism; consequence inferred]
2. **The Wi-Fi chip is not a WCN7850.** The earlier identification was wrong for the Wi-Fi function. The test tree
   nevertheless describes the module as a discrete WCN7850 with its own PMU (fixed 0.95 V rail, ten LDOs) — a
   description of a different board design, applied to an M.2 module. [confirmed]
3. **Bluetooth cannot load correct firmware on this kernel under either tree** (no QCC2072/"orn" support). [confirmed]
4. **Stock tree loads Wi-Fi late.** `pwrseq-pcie-m2` is not in the initramfs, so with the stock tree the Wi-Fi
   controller probes after switch-root (9–14 s vs 1 s with the test tree). Harmless by itself. [confirmed]
5. Package versions available upstream on 2026-11-20: `linux-omarchy-aarch64` pkgrel 73 (adds only UFS/Galaxy
   Book6 changes) and `linux-omarchy-dtbs` 7.3-52 (Surface Pro 11, ThinkCentre, Galaxy Book6 only). **No pending
   Omarchy change touches UX3407NA Wi-Fi/BT/suspend.** [confirmed from omacom/omarchy-pkgs history]

---

## 2. Failure timeline

Boots are identified by boot ID; times inside a boot are kernel **monotonic** seconds (suspended time excluded).
Real-time durations are derived from journal realtime stamps (the RTC delta is injected on resume, so durations
inside a boot are usable even though absolute dates are not).

| # | Boot | Tree | Suspends (mode) | Outcome |
|---|---|---|---|---|
| -31 | `d6d4a03b` | stock, kernel 7.3.0-66 | 0 | clean shutdown |
| -30 | `fcfc01a1` | stock | 3 (2 deep, 1 s2idle) | **hung in deep suspend** (last line `PM: suspend entry (deep)`) |
| -29 | `cea7ed2a` | stock | – | **reset at ~8 s** |
| -28 | `47b5faf4` | stock | – | **reset at ~15 s** |
| -27 | `1a92eeca` | stock | – | abrupt end at 104 s during `pacman -Syu` |
| -26…-24 | `071b3322`, `9c05777d`, `9ee5b90e` | stock | – | **three resets in a row at ~8–11 s** |
| -23 | `d7a1f32c` | stock | 10 | died at 9340 s right after `Performing sleep operation 'suspend'` |
| -22 | `556c9863` | stock | 6 | clean |
| -20 | `a760680e` | stock | 2 | died entering suspend at 8638 s |
| -18 | `bbe4e895` | stock | – | **reset at ~8.5 s** |
| -16 | `c075f5b1` | stock | 23 (12 deep, 11 s2idle) | **hung in deep suspend** |
| -12 | `8dd975a2` | stock | – | **reset at ~28 s** |
| -10 | `2e0bfc97` | stock | – | **reset at ~12 s** |
| -8 | `08593506` | **BT test** (first boot of it) | 1 deep | **hung in deep suspend** |
| -7 | `9f85df31` | BT test | – | **reset at ~7.4 s** |
| -6 | `c5c7c3d5` | BT test | 8 s2idle | Wi-Fi died on the 4th resume; clean shutdown |
| -4 | `1244c923` | BT test | **546 s2idle** | Wi-Fi died on resume #54; **last suspend never resumed** (black screen, forced off) |
| -3, -2 | `be65a194`, `7ed09234` | BT test | 0 | abrupt ends at 106 s / 48 s (cause unknown) |
| -1 | `faa95ddf` | BT test | – | **reset at ~12.6 s** |
| 0 | `de069fd6` | BT test | 0 so far | current |

### 2.1 What a "suspend" actually did before s2idle was forced (stock tree)

Every systemd suspend wrote `mem` with `mem_sleep=deep`. The kernel entered PSCI SYSTEM_SUSPEND
(`Disabling non-boot CPUs … psci: CPUn killed`), and on return reported failure, so systemd-sleep fell
through to the next state, `freeze` (s2idle) — two `PM: suspend entry` lines per suspend, one
`System returned from sleep operation`. Example, boot `d7a1f32c`:

```
[ 9309.407] systemd-logind: Lid closed.
[ 9309.681] PM: suspend entry (deep)
[ 9312.695] qcom-pcie 1bf0000.pcie: Timeout waiting for L2 entry! LTSSM: 0x11
[ 9312.697] Disabling non-boot CPUs ...            (CPUs 1–17 killed, then immediately re-enabled)
[ 9312.704] qcom-pcie 1bf0000.pcie: PCIe Gen.3 x1 link up
[ 9312.707] ath12k_wifi7_pci 0004:01:00.0: chip_id 0x21 … fw_version 0x100581de …   (firmware re-downloaded)
[ 9312.945] PM: suspend exit
[ 9312.961] PM: suspend entry (s2idle)
[ 9315.266] qcom-pcie 1bf0000.pcie: Timeout waiting for L2 entry! LTSSM: 0x11
[ 9315.537] systemd-sleep: System returned from sleep operation 'suspend'.
```

Real-time durations show the deep phase **sometimes really slept for hours** (boot `c075f5b1`: 2 810 s,
8 288 s, 41 437 s, 2 742 s; boot `d7a1f32c`: 4 670 s) and woke on lid-open, but at other times returned within
~3 s. It hung outright three times (`fcfc01a1`, `c075f5b1`, `08593506`). The s2idle phase always lasted only
2–4 s real time. [confirmed from journal]

### 2.2 The lid-closed loop (both trees)

With the lid closed, s2idle wakes after a few seconds with **no `Lid opened` event**, logind sees the lid still
closed and re-suspends after its 30 s hold-off, forever. Boot `1244c923` ran 546 cycles in 19 839 monotonic
seconds (one per ~30.3 s monotonic). [confirmed]

### 2.3 When Wi-Fi first failed (BT test tree, boot `1244c923`)

| Cycles | Real-time sleep per cycle | Wi-Fi after resume |
|---|---|---|
| 1–53 | ~2 s (cycle 32 s real vs 30.3 s monotonic) | OK — firmware re-downloaded each time |
| 54 | 116 s real time from entry to exit (sleep + failed resume) | **first failure** |
| 55–545 | **~21 s** (cycle 51 s real) | failed every time |
| 546 | — | never resumed |

First failure (boot `1244c923`, cycle 54):

```
[4920.305] qcom-pcie 1bf0000.pcie: Timeout waiting for L2 entry! LTSSM: 0x11
[4920.306] qcom-pcie 1bf0000.pcie: PCIe Gen.3 x1 link up
[4920.307] mhi mhi0: Wait for device to enter SBL or Mission mode
[4920.308] ath12k_wifi7_pci 0004:01:00.0: failed to set mhi state: POWER_ON(2)
[4920.308] ath12k_wifi7_pci 0004:01:00.0: failed to start mhi: -110
[4920.309] ath12k_wifi7_pci 0004:01:00.0: failed to early resume core: -110
[4920.309] ath12k_wifi7_pci 0004:01:00.0: PM: dpm_run_callback(): pci_pm_resume_early returns -110
[4920.310] ath12k_wifi7_pci 0004:01:00.0: timeout while waiting for restart complete
[4920.313] Hardware became unavailable upon resume. … WARNING: net/mac80211/util.c:1957 ieee80211_reconfig
```

Later cycles alternate `failed to start mhi: -22` / `-110` and `failed to set mhi state INIT(0) in current
mhi state (0x1)`; the chip never recovers within the boot. Totals for the boot: 492 × `failed to start mhi`,
491 × `failed to set mhi state INIT`, 544 × L2-entry timeouts. Boot `c5c7c3d5` shows the same thing after only
4 resumes. [confirmed]

### 2.4 Same symptom counts, split by device tree

| Tree | Boots with suspends | Suspend entries | `Timeout waiting for L2 entry` | `failed to start mhi` |
|---|---|---|---|---|
| Stock (M.2 connector) | 5 | 44 | 42 | **0** |
| BT test (wcn7850-pmu) | 3 | 555 | 551 | **497** |

The L2-entry timeout is present with both trees and is not by itself what breaks Wi-Fi. Wi-Fi resume failures
occur **only** with the BT test tree. [confirmed]

### 2.5 Early-boot resets

Ten boots end 7–28 s after power-on (kernel source timestamps), both trees, all with an identical command line.
Every one is cut exactly at journald's first flush to disk, so anything after that point was lost; the true reset
moment is **[unknown]**. In 6 of the 8 stock-tree cases the last persisted kernel lines are the Wi-Fi PCIe
controller (`1bf0000`) starting to probe (which on the stock tree happens after switch-root); in the two BT-tree
cases Wi-Fi had already come up at ~1 s and the last lines are remoteproc (SoCCP) / zram. No PMIC reset reason,
pstore or console capture exists. The resets do not obviously share a mechanism with the suspend failures.

---

## 3. Ranked explanations

Source references are to `linux-7.3` + Omarchy pkgrel-72 patches (the exact running kernel).

### 3.1 How the code behaves here (facts the ranking rests on)

* **ath12k (QCC2072) never uses WoW here.** Without a wowlan config mac80211 stops the device, and
  `suspend_late` powers the target down (`mhi_stop` + SoC reset). `resume_early` powers it up again and boots the
  firmware over MHI/BHI from scratch (`ath12k/core.c:168-201`, `pci.c:302-313,1470-1485`, `mhi.c:482-512`). So the
  firmware banner reprinted after every resume is normal and **does not show a power cycle**.
* **`failed to start mhi: -110`** = `mhi_sync_power_up` timed out because the device never reached mission mode
  (`bus/mhi/host/pm.c:1307-1312`). A dead link would give `-EIO` / `0xffffffff` reads instead, so at the first
  failure the chip was reachable on PCIe but its firmware boot stalled. `INIT(0) in current mhi state (0x1)` is
  the follow-on: INIT was never torn down, so every later attempt fails (`mhi.c:362-364,399`). [code fact + inference]
* **"Timeout waiting for L2 entry! LTSSM: 0x11" is a warning, not an error.** 0x11 = L0: the endpoint never
  answered PME_Turn_Off. The code then continues (`pcie-designware-host.c:1260-1268`).
* **The PCIe controller does not cut Wi-Fi power in suspend.** `skip_pwrctrl_off = pme_capable`
  (`pcie-designware-host.c:1286`); the root port has `wake-gpios` and is wakeup-enabled, so (inferred) PME-from-D3cold is
  reported and pwrctrl power-off/on is skipped in **both** trees. Only PERST# and REFCLK toggle. (Check: `sudo lspci -vv -s
  0004:00:00.0 | grep PME` should show `D3cold+`.)
* **Bluetooth stays powered across suspend.** `qca_suspend` returns immediately when the controller runs ROM
  firmware (`hci_qca.c:2699`), and pwrseq-qcom-wcn has no PM ops. Bluetooth is powered off only on rfkill / `hci down`.
* **What the trees really differ in at suspend time:** in the stock tree `pwrseq-pcie-m2` keeps W_DISABLE2# asserted
  forever, because 17cb:1112 is not in `pwrseq_m2_pci_ids` (`pwrseq-pcie-m2.c:187-206`), so the Bluetooth half of the
  chip stays **off**. In the test tree BT_EN (GPIO 116) is high whenever Bluetooth is up, and the Bluetooth core sits
  powered on ROM code with no NVM/board config through every suspend and every Wi-Fi SoC reset on resume. The 3.3 V
  rail is always on in the test tree (the fake always-on 0.95 V regulator forces its parent on). wcn7850 sequencing
  also has no BT_EN↔WLAN_EN spacing delay (qca6390 has 100 ms).
* **The test tree is a copy of the Zenbook A16 description** (Omarchy patches 2500/2501: same fake 0.95 V rail,
  `qcom,wcn7850-pmu`, GPIO 116/117, `pci17cb,1112`, `qcom,wcn7850-bt`). Nothing in those patches shows suspend
  was tested on the A16.
* **Wake paths:** the lid IRQ is switched to rising edge for suspend, so only lid-**open** wakes (`gpio_keys.c:607-609`).
  PCIe WAKE# (GPIO 148, PDC 141) is a **level-low** wake IRQ on the root port (`drivers/pci/of.c:622`), wake-enabled by
  default; any low level on it during sleep wakes the system immediately. Glymur has no dual-edge PDC errata flag.

### 3.2 Ranking

| # | Explanation | Confidence | Supporting evidence | Against / open |
|---|---|---|---|---|
| **H1** | **Wi-Fi resume failure is caused by the Bluetooth test tree**, most likely because the chip's Bluetooth half is kept powered on ROM firmware (BT_EN high, no NVM) while the Wi-Fi half is reset and re-booted on every resume; eventually the Wi-Fi firmware boot stalls and never recovers without a full power cycle. | **High** that the tree is the trigger (0/44 vs 497/555). **Moderate** on the exact mechanism | §2.4 counts; first failure after 4 and 54 resumes, then permanent; -110 with a reachable link = firmware stall, not power loss; the only lines the trees toggle differently are BT_EN/W_DISABLE2 | Stock sample is small (44 suspends, ~20 s2idle resumes). Bluetooth power state during boot `1244c923` is **unknown** (rfkill state file rewritten today). Mechanism needs test 6.3 |
| **H2** | **Repeated wakeups with the lid closed** = an s2idle wake source firing within ~2 s, followed by logind's 30 s re-suspend while the lid is still closed. Most likely source: the Wi-Fi card/PCIe path (WAKE# level-low IRQ or MHI), since the card stays powered and in L0 through suspend. | Loop mechanism **confirmed**. Wake source **moderate** | No `Lid opened` on wakes; real sleep ~2 s while Wi-Fi alive and ~21 s once Wi-Fi was dead; also ~2–4 s on the stock tree with Wi-Fi alive; WAKE# is level-low and wake-enabled | No `pm_wakeup_irq` / pm_debug output was ever recorded. The ~21 s wake has a different source (candidates: qcom-battmgr/pmic_glink, remoteproc, USB) |
| **H3** | **"Another suspend after each wake"** is logind behaviour (HandleLidSwitch=suspend, HoldoffTimeoutSec=30s), not a kernel retry. | **Confirmed** | ~30.3 s monotonic period, `Lid closed` once, `Suspending...` each cycle | — |
| **H4** | **Deep sleep is not usable**: PSCI SYSTEM_SUSPEND either returns at once or sleeps but reports failure (systemd then falls through to s2idle), and it hung 3 times. Forcing s2idle was right, but it exposed H2. | **High** | §2.1 | Why the firmware returns an error is unknown (BIOS/PSCI behaviour) |
| **H5** | **Final black screen** in boot `1244c923` (and the other suspend-time deaths) = a hang in suspend or early resume, **or** a resume whose logs were never flushed. Not provably display-only. | **Low / unresolved** | Last record is `PM: suspend entry`; every earlier resume logged within <1 s; display stack logged no errors across 545 resumes (but panel was off with lid closed) | journald syncs only before sleep and every 5 min, so a resumed-but-black machine forced off within 5 min leaves no trace. Needs the heartbeat test (6.5) |
| **H6** | **Bluetooth instability** = wrong chip profile (WCN7850) and no patch/NVM firmware (ROM only). Cannot be fixed by any device tree on this kernel. | **Confirmed** | `hmtbtfw11.tlv -2`; no QCC2072/"orn" code in btqca/hci_qca; `orn*` firmware present but unused | Fix needs kernel support (see §4) |
| **H7** | **Early-boot resets** — cause unknown; same command line and kernel on good and bad boots, both trees; stock-tree cases cluster around the Wi-Fi PCIe controller probe; no shared mechanism with the suspend failures is demonstrated. | **Low** | §2.5 | All evidence lost after journald's first flush; no PMIC reset reason captured |
| — | Display warning `gcc_usb3_tert_phy_com_aux_clk stuck at 'off'` (DP2/HDMI-bridge PHY at 88e1000, on every connector probe) | Unrelated to the internal panel; low relevance | trace via `msm_dp_bridge_detect` → `qmp_combo_dp_init` | No Omarchy patch addresses it |

### 3.3 Unresolved questions

1. Which wake source fires ~2 s into s2idle, and which fires at ~21 s? (needs `pm_debug_messages`)
2. Does Wi-Fi survive repeated resumes on the test tree when Bluetooth is rfkill-blocked? (separates "Bluetooth powered" from "other tree differences")
3. Does the root port really report PME from D3cold (so pwrctrl power-off is skipped)?
4. Was boot `1244c923`'s last suspend a hang or an unlogged resume with a black display?
5. What resets the machine during early boot?
6. Why does PSCI SYSTEM_SUSPEND return failure even after hours of real sleep?

---

## 4. Kernel fixes and firmware updates

"In build" means present in `linux-7.3` + Omarchy pkgrel-72 (checked in the source). Upstream state as of
2026-11-20 (mainline ≈ v7.4-rc3+, linux-firmware latest tag 20261019).

| Item | Reference | Upstream status | In this build? | Applies here? | Notes |
|---|---|---|---|---|---|
| ath12k QCC2072 enablement (18 patches) | d8e1f4a19310 "wifi: ath12k: enable QCC2072 support" | v7.0 | **Yes** | Yes | Base support |
| ath12k: unprepare MHI on power-up failure (stale `ATH12K_MHI_INIT` bit makes every later start fail) | patchwork linux-wireless 20261031224009.2323055-3-vz@kernel.org | posted 2026-10-31, **not merged** | **No** (`pci.c:1458-1462` returns without cleanup) | **Yes** — explains why Wi-Fi never recovers after the first stall (`INIT(0) … (0x1)`) | Mitigates the "stays dead" part, not the first stall |
| ath12k: recover from firmware crash during resume (4 patches) | patchwork linux-wireless cover 20261112110008.1229-1-tvlad744@gmail.com | posted 2026-11-12, **not merged** | No | Likely (non-WoW resume, `failed to resume core: -110`) | Tested on WCN7880 only |
| Bluetooth: qca: QCC2072 UART support (`qcom,qcc2072-bt`, ORN firmware/NVM, board-ID NVM) | patchwork bluetooth 20260727-rb3-industrial-bt-uart-v2-2-… | v2, **changes requested, not merged** | **No** (no QCC2072/"orn" anywhere in btqca/hci_qca) | **Yes — the missing Bluetooth piece** | Carries a Tested-by on the Zenbook A16 |
| pcie-m2: 17cb:1112 Bluetooth ID | 162ea02941a9, then reverted "Drop undocumented QCC2072 compatible" | reverted 2026-07-23 | No | Needed for Bluetooth via the stock connector tree | Without it the stock tree never creates a BT device |
| hci_qca M.2 Bluetooth via pwrseq ("monza-wireless" v7) | lore 20261005-monza-wireless-v7-1-… | not merged | 1/8 only (Omarchy 2379) | Partly | |
| pwrseq-qcom-wcn: power off WLAN at probe | dbd674ccf30f | v7.3 | **Yes** (`GPIOD_OUT_LOW`) | Test tree only | |
| pwrseq-qcom-wcn: increase WCN7850 power-up delay | bd60a639b621 | v7.4-rc3 | **No** (still 50 ms) | Test tree only (wcn7850-pmu route) | Fixes BT `-110` when BT powers first |
| PCI qcom: only check bridge nodes for PERST# | 1b3b0bc2b367 (v7.4-rc1) ≈ Omarchy 2501 | v7.4-rc1 | **Yes** (via 2501) | Test tree | |
| pci-pwrctrl-pwrseq `pci17cb,1112` match | Omarchy 2501 | Omarchy only | **Yes** | Test tree | |
| dwc: non-fatal L2 timeout | in v7.3 | — | Yes | Both | The warning is expected here |
| PCI pwrctrl power-off across system suspend | — | **no upstream patch** | — | Both | Today pwrctrl is skipped when PME-from-D3cold is reported |
| Glymur PDC / GDSC / eDP pending fixes ("pdc: restore configuration on resume", "gcc-glymur collapse-voting for PCIe GDSCs", "edp: lane drive level on Glymur") | linux-next / lists | pending | Partly (Omarchy has several edp v8 patches 2330-2346) | Possibly (wake IRQs, PCIe power, blank screen) | Not verified on this machine |
| Upstream UX3407NA DT | 7e38885d78f7 (Bjorn Andersson) | v7.4-rc1 | **Yes** = Omarchy 2641 = stock tree | Yes | Uses `pcie-m2-e-connector`, no Bluetooth child |
| linux-firmware ath12k/QCC2072 `firmware-2.bin` | WLAN.COL.1.0.c2-00277 | unchanged since 2026-08-31 | **Installed** (20261019) | Yes | **No newer Wi-Fi firmware exists** |
| linux-firmware `board-2.bin` entry for 105b:e14f | — | **none** (only 17cb:1110, 105b:e15a) | Fallback copy of e15a in `/usr/lib/firmware/updates` | Yes | ASUS's own `bdwlan_qcc2072_1p0_ncm820A.elf` (in the same SOCPackage this machine's DSP firmware came from) is what Windows uses for 105b:e14f; Omarchy's A16 package installs exactly that |
| linux-firmware QCC2072 UART BT `ornbtfw11.tlv`/`ornnv11.bin` 1.1.0-00391, new `ornnv11.b18` | 58b6166634a1 (2026-11-12) | after the last tag | **No** (have 00355; and `ornbtfw10`=WCN7750, not QCC2072) | Only once kernel support exists | Useless on this kernel |
| ASUS BIOS | installed **316 (2026-10-22)** | newest BSP listed: V1.315.4500.0 (2026-09-03) with BIOS 315, WLAN 685.13804.110.0, BT 685.13804.30.0 | — | — | **Could not confirm** any BIOS newer than 316 (ASUS BIOS API returned FAIL); 316 is newer than every listed package. Release notes unavailable |
| Omarchy packages | linux-omarchy 7.3-73, dtbs 7.3-52 | released | not installed | **No** UX3407NA-relevant change | Note: Omarchy disables sleep entirely on the A16 (omarchy#13820) |

---

## 5. Proposed changes

Ordered by risk. **Nothing below has been applied.** Items marked *after test* depend on the §6 results.

| # | Change | Why | Rollback | Verification |
|---|---|---|---|---|
| P1 | **Use the stock `linux-omarchy` entry day to day** (it is already `default_entry: 2`); boot the Bluetooth test entry only for Bluetooth tests. | The only configuration with zero Wi-Fi resume failures (0/44). Costs Bluetooth, which today runs on ROM firmware anyway. | Pick "Omarchy Bluetooth test" in Limine | 10 short + 1 overnight suspend with Wi-Fi reconnecting each time |
| P2 | **Retire or rebuild the test UKI before the next `linux-omarchy` upgrade.** If you keep it, rebuild it from the current `vmlinuz`/initramfs + test DTB after every kernel update (`ukify build --linux … --initrd … --devicetree …`). | It is pinned to 7.3.0-72; after an upgrade it boots without modules. | Keep a copy of the current `.efi` | `bootctl status` + `uname -r` match `pacman -Q linux-omarchy` |
| P3 | Interim, while testing: stop the closed-lid loop with a logind drop-in (`HandleLidSwitch=lock`, `HandleLidSwitchExternalPower=lock`) and suspend manually. | Prevents hundreds of wake/sleep cycles and the battery/heat that goes with them. | Delete the drop-in, `systemctl kill -s HUP systemd-logind` | Closing the lid locks; no `PM: suspend entry` in the journal |
| P4 | Make s2idle the kernel default too: append `mem_sleep_default=s2idle` to `KERNEL_CMDLINE[default]` in `/etc/default/limine` and rebuild (`limine-mkinitcpio` / `omarchy` UKI hook). Keep `90-s2idle.conf`. | Anything that suspends outside systemd currently gets `deep`, which hung 3 times. | Remove the parameter, rebuild | `cat /sys/power/mem_sleep` shows `[s2idle]` |
| P5 *after test 6.2* | If the early wake is the Wi-Fi/PCIe path: a udev rule disabling wakeup on `0004:00:00.0` (root port WAKE#/PME) and/or `mhi0`. | Lets the machine stay asleep with the lid closed. WoWLAN is not used, so nothing is lost. | Delete the rule | Lid closed 30 min → one suspend entry, real sleep ≈ 30 min |
| P6 *after test 6.3* | If Bluetooth being powered is what breaks Wi-Fi resume on the test tree: a `/etc/systemd/system-sleep/` hook that soft-blocks Bluetooth before sleep and restores it after. | Keeps Bluetooth usable on the test tree without the Wi-Fi stall. | Delete the hook | 20 suspends on the test tree, 0 MHI failures |
| P7 *after test 6.7* | Recovery helper: on `failed to start mhi`, rebind the device (`echo 0004:01:00.0 > /sys/bus/pci/drivers/ath12k_wifi7_pci/unbind` then `…/bind`, or reload the modules). | Works around the missing "unprepare MHI on power-up failure" fix until it lands. | Remove helper | Wi-Fi returns without a reboot after a failed resume |
| P8 | Ask Omarchy (via `omarchy-contribute`) to carry: the ath12k MHI-unprepare fix, the QCC2072 Bluetooth series + `pcie-m2` 1112 ID, bd60a639b621, and an A14 board file taken from ASUS's `bdwlan_qcc2072_1p0_ncm820A.elf` (as the A16 package does). | These are the real fixes; all are outside what a local config can do. | n/a | New package versions; repeat §6.1 |
| P9 | Optional: install ASUS's `bdwlan_qcc2072_1p0_ncm820A.elf` from the SOCPackage the A14 firmware package already downloads, as `board.bin` (the fallback tool then steps aside). | Correct calibration data for 105b:e14f. Not expected to affect suspend. | Remove the file; `ath12k-board-fallback` reinstalls its copy | `iw dev` link rates and `dmesg` board load; no new errors |

Not recommended now: editing the test tree further (it mirrors the A16 template, and the evidence points at
Bluetooth-side power/state, not polarity or regulators), forcing `deep`, or a BIOS change before a newer BIOS is
confirmed to exist.

---

## 6. Controlled test plan

Rules for every test: save work first; keep the charger connected; run `tools/heartbeat.sh &` in a terminal;
run `tools/capture-state.sh <label>` (as root via `sudo` for GPIO/regulator/lspci data) **before and after**;
after any forced power-off, collect `journalctl -b -1 -k -o short-monotonic` and the heartbeat file before
doing anything else. Wake the machine with the **power key or a key press** (the RTC has no wake alarm).
Recovery from a hang: hold the power key ~10 s; at the Limine menu pick the entry you want (the stock
`linux-omarchy` entry is always there, plus five snapshot entries).

### 6.0 One-time preparation (reversible, diagnostic only)

| Change | Command | Undo |
|---|---|---|
| Log every wake source and device timing | `echo 1 \| sudo tee /sys/power/pm_debug_messages /sys/power/pm_print_times` (runtime only) | reboot |
| Stop the closed-lid re-suspend loop while testing | `/etc/systemd/logind.conf.d/90-test-lid.conf`: `[Login]` `HandleLidSwitch=ignore` `HandleLidSwitchExternalPower=ignore`, then `sudo systemctl kill -s HUP systemd-logind` | delete file, HUP again |
| Keep logs up to a hang | `/etc/systemd/journald.conf.d/90-test-sync.conf`: `[Journal]` `SyncIntervalSec=2s`, then `sudo systemctl restart systemd-journald` | delete file, restart |
| See the console on early-boot resets | in the Limine menu press `e` on the entry and remove `quiet splash loglevel=0`, add `loglevel=7 ignore_loglevel` for that one boot | nothing persists |

### 6.1 Baseline A/B — same kernel, same firmware, s2idle, lid **open**, Bluetooth soft-blocked

| Step | Stock entry (`linux-omarchy`) | BT test entry |
|---|---|---|
| 1 | 5 × `systemctl suspend`, wake each with the power key after ~60 s | same |
| capture | `pm_wakeup_irq`, `PM: Triggering wakeup from IRQ`/`wakeup source` lines, wakeup_counts delta, real sleep time, ath12k banner after each resume, `iw dev`/`nmcli` connectivity | same |
| supports H1 (test tree breaks Wi-Fi resume) | 5/5 Wi-Fi OK on stock **and** any MHI failure on test | |
| weakens H1 | MHI failures on stock too, or 5/5 OK on test | |
| supports H3 (Wi-Fi/PCIe is the early wake) | wake source reported = `mhi0`, PCIe root port `0004:00:00.0` (PME/AER) or its IRQ, after ~2 s, on both trees | |

Also once per tree: `sudo lspci -vv -s 0004:00:00.0 | grep -i pme` (expect `PME(D0+,D1-,D2-,D3hot+,D3cold+)`; confirms pwrctrl power-off is skipped).

Progress to longer sleeps (5 min, then 30 min, then overnight on the stock entry) only after 5 short cycles pass.

### 6.2 Isolate Wi-Fi (on whichever tree reproduces the early wake)

1. `nmcli radio wifi off`; suspend 60 s; note real sleep time and wake source.
2. Unload Wi-Fi entirely: `sudo modprobe -r ath12k_wifi7 ath12k`; repeat.
3. With Wi-Fi loaded, disable only its wake paths: `echo disabled | sudo tee /sys/bus/pci/devices/0004:00:00.0/power/wakeup /sys/bus/pci/devices/0004:01:00.0/mhi0/power/wakeup` (check the exact mhi0 path with `ls /sys/class/wakeup/`); repeat.
4. Restore with `sudo modprobe ath12k_wifi7` / `enabled`.

If the 2–4 s wake disappears in 2 or 3 and the sleep extends to the ~20 s pattern (or longer), Wi-Fi/PCIe is the
early wake source; the remaining ~20 s wake is then the next target (likely `qcom-battmgr`/`pmic_glink`
notifications or a remoteproc — check with the same `power/wakeup` method).

### 6.3 Isolate Bluetooth (BT test entry only)

Run 6.1 again with `rfkill unblock bluetooth` and `bluetoothctl power on`. If Wi-Fi survives with Bluetooth
blocked but fails with it powered (or vice-versa), the shared `wcn7850-pmu` sequencing is implicated; record
GPIO 116/117/94 before suspend and after resume each time (root capture).

### 6.4 Lid-triggered suspend

Only after 6.1–6.3: remove `90-test-lid.conf`, close the lid for 2 min, open it. Pass = one suspend entry, no
re-suspend loop in the journal, Wi-Fi up, screen on within 5 s.

### 6.5 Display recovery

During any resume where the screen stays black: wait 30 s, toggle Caps Lock (LED), press `Super+Esc`/try a VT
switch, then force off. Afterwards: if the heartbeat file kept advancing after the resume time and the journal
shows `PM: suspend exit`, the **system was alive and the failure is display-only** (look at `msm_dpu`/`msm_dp`/
`phy-qcom-edp`/`panel` lines); if the heartbeat stops before resume and there is no `suspend exit`, it was a
**system hang in suspend/resume**.

### 6.6 Early-boot resets

Boot 10 times on the stock entry with the console visible (6.0, last row) and `SyncIntervalSec=2s`. Photograph the
screen at the moment of the reset. If resets cluster at the Wi-Fi controller probe, repeat with Wi-Fi blacklisted
for one boot (add `module_blacklist=pwrseq_pcie_m2` in the Limine editor: on the stock tree this keeps the Wi-Fi PCIe controller from probing at all).

### 6.7 Recovery after a Wi-Fi stall (any time it happens)

Before rebooting, try `sudo modprobe -r ath12k_wifi7 ath12k && sudo modprobe ath12k_wifi7`. If Wi-Fi comes back,
the permanent part of the failure is the stale MHI INIT state (driver), and only the first stall is a
hardware/firmware event. If it does not come back, the chip itself needs a power cycle (supports the
"Bluetooth half kept powered" mechanism of H1).

### 6.8 Order of work

1. 6.0 preparation → 2. 6.1 on the **stock** entry → 3. 6.1 on the **test** entry with Bluetooth blocked → 4. 6.3
(Bluetooth on) → 5. 6.2 wake-source isolation → 6. 6.4 lid → 7. long sleeps → 8. 6.6 resets (separate session).
Each step is short and supervised; stop and collect evidence at the first hang.

---

## Addendum, 2026-11-22: stock tree also loses Wi-Fi (H1 weakened)

Boot `dc1944690be24310864c087c29e9d49a` (kernel 7.3.0-72) ran the **stock** tree: `pwrseq_pcie_m2` was loaded, and there was no `hci_uart` or `wcn7850-pmu`. It recorded 150 s2idle cycles with the lid closed (monotonic 53151–57743 s).

- Cycles 1 and 2 each slept about 2 s and resumed cleanly. Wi-Fi was reinitialised after each one ("chip_id … board_id 0xff" was printed again).
- Cycle 3 was the first real sleep, about 115 s (entry at 53211.8, resume at 53326.8). On resume, "failed to set mhi state: POWER_ON(2)" and "failed to start mhi: -110" appeared, followed by "Hardware became unavailable upon resume". Wi-Fi was dead for the rest of the boot.
- After the lid was opened at 57764.8, Hyprland probed the DP connector and got `WARNING clk-branch.c:87` and "Failed to enable clk 'com_aux': -16". These led to "phy phy-88e1000.phy.10: phy init failed --> -16", repeated 36 times. This is the USB-C/DP combo PHY, not eDP. The user rebooted about 150 s later.

**Consequence:** the BT test tree is not required for the Wi-Fi resume failure. The better-supported trigger is now that sleep lasts long enough for the SoC to reach a deeper idle state; short 2 s wakes survive. The tree may still change how often the failure happens. The H1 ranking in §3 is superseded. The leading lead is now H1′: a long s2idle loses the Wi-Fi card or link state on both trees. Test 6.1 should vary sleep length (about 5 s against about 2–5 min) on the stock entry.

**Other changes since the report:**
- linux-omarchy was upgraded to 7.3-77 and dtbs to 7.3-56 on 2026-11-22.
- `/usr/lib/modules` now contains only 7.3.0-77, so the pinned "Omarchy Bluetooth test" UKI (7.3.0-72) has no modules on disk. Do not boot it.

### Applied 2026-11-23: P-hook (Wi-Fi driver reload around sleep)

The failure reproduced on kernel 7.3.0-77 with the stock tree. In boot `4992dff0`, the first real sleep (monotonic 3804.7 → 3917.3 s, about 113 s) ended with "failed to start mhi: -110" and "Hardware became unavailable upon resume".

Installed `/usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload` (source: `tools/50-ux3407na-wifi-reload`). Before sleep it runs `modprobe -r ath12k_wifi7 ath12k`; after wake it runs `modprobe ath12k_wifi7`.

- **Verify:** after a sleep of at least 3 minutes, Wi-Fi reconnects and `journalctl -b -k | grep -c 'failed to start mhi'` is 0. The `journalctl -b | grep ux3407na-wifi-reload` lines show an unload and a load for each cycle.
- **Rollback:** `sudo rm /usr/lib/systemd/system-sleep/50-ux3407na-wifi-reload`. To disable it temporarily, `sudo touch /etc/ux3407na-wifi-reload.disable`.

### 2026-11-23: early-wake source identified (H2 refuted)

In boot `6ceed930` there were 157 s2idle cycles, all with the hook active and `ath12k_wifi7` unloaded during sleep. Each cycle still woke about 1.6 s after entry, so the Wi-Fi driver is not the wake source.

`/sys/power/pm_wakeup_irq` = 260, which `/proc/interrupts` lists as `PDC 14 Edge dp_hs_phy_2` with a count of 157, one for every suspend. This is the D+ line wake IRQ of port 2 on the multiport USB controller `a400000.usb` (`usb_mp_hsphy1`, behind the NXP PTN3222 eUSB2 redriver at i2c5 0x43, reset GPIO 184).

- No USB device is enumerated on that controller.
- `a400000.usb/power/wakeup` = enabled.

The wake is spurious: a D+ edge on an empty port, probably a redriver or PHY glitch during low-power entry. The 30 s re-suspend is normal logind behaviour while the lid stays closed.

- **Proposed fix:** set `a400000.usb/power/wakeup` to disabled, temporarily at first and then through a udev rule.
- **Cost:** a device plugged into that USB port can no longer wake the laptop.

### Applied 2026-11-23: USB multiport wake disabled — loop fixed

The fix was first applied temporarily (`echo disabled > /sys/devices/platform/soc@0/a400000.usb/power/wakeup`) and tested in boot `6ceed930`. The lid was closed at 16:00:17 and the laptop stayed suspended for 21 min of real time until the lid was opened at 16:21:25.

- `pm_wakeup_irq` = 62 (`gpio 92 Edge lid`), and IRQ 260 stayed at 157.
- The hook unloaded and reloaded the Wi-Fi driver, Wi-Fi reconnected, and `failed to start mhi` = 0.

Wall-clock times were used here because the monotonic clock stops during s2idle. Earlier "about 2 s" figures taken from monotonic gaps measure resume overhead, not sleep length.

Made persistent with `/etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules` (source: `tools/`).

- **Verify after the next reboot:** `cat /sys/devices/platform/soc@0/a400000.usb/power/wakeup` prints `disabled`.
- **Rollback:** `sudo rm /etc/udev/rules.d/70-ux3407na-usb-mp-nowake.rules`, then reboot.

### 2026-11-23: which port

The USB-A port is multiport **port 1**: an HP USB flash drive enumerated as `usb 1-1` on `a400000.usb` at 16:27:45. The false-wake port is port 2 (`dp_hs_phy_2`), which is not the USB-A port and has nothing enumerated on it.

At 16:27:59 the flash drive disconnected. Re-enumeration then failed at full speed with `error -71` (EPROTO), including after a port power-cycle. This port problem is not caused by the wakeup setting, because `power/wakeup` only arms the sleep wake IRQs.

## Addendum 2026-11-25: Bluetooth (QCC2072)

**Evidence.** On the old test tree (`qcom,wcn7850-bt`, kernel 7.3-72) Bluetooth worked on ROM code only. In boots 08593506 and 1244c923, hci0 came up (SOC 0x40292100, ROM 0x101) and A2DP audio streamed. btqca requested `qca/hmtbtfw11.tlv` (-2), the WCN7850 name. QCC2072's files are `ornbtfw11.tlv`, `ornnv11.bin` and `ornbcscal11.bin`, all installed. The stock tree creates no Bluetooth device.

Kernel 7.3-77 already has two of the pieces:
- The M.2 E-key serdev creation in `pwrseq-pcie-m2`.
- Manivannan's hci_qca M.2 pwrseq support (Omarchy patch 2379).

It lacks two upstream patches that are not merged as of 2026-11-25:
- QCC2072 support in btqca/hci_qca: v2 2/6, qcom-next `4963fd8a20b1`.
- PCI ID 17cb:1112 → `qcom,qcc2072-bt` in pwrseq-pcie-m2: v2 3/6, qcom-next `bc2b6da4d0b5`. It was dropped from pwrseq/for-next because the binding is undocumented.

Patches 1–3 of this series plus Manivannan's are reported working on the Zenbook A16 UX3607OA (Tested-by on 2026-11-10). That report also saw a TLV download timeout (-110) in about 1 boot in 5.

**Built and installed.** I rebuilt `btqca`, `hci_uart` and `pwrseq-pcie-m2` out of tree for 7.3.0-77-omarchy from the exact package source:
- linux-7.3 tarball, sha256 matching the PKGBUILD, plus the 582 Omarchy patches from omarchy-pkgs commit `8c387fae`.
- Patch 0001 needed a manual rebase: two `case` labels in `qca_serdev_probe`.

**Source check.** The unmodified `btusb` and `pwrseq-pcie-m2` builds have the same defined and imported symbols as the packaged ones. `btqca` and `hci_uart` differ only by the QCC2072 additions.

The modules are installed to `/usr/lib/modules/7.3.0-77-omarchy/updates/ux3407na-bt/`, so the stock kernel, stock device tree and stock UKI are unchanged. Everything is in `omarchy-setup/ux3407na/bt/`, including `build-modules.sh` and a pacman reminder hook.

**Rollback:** `./uninstall.sh --bt`, then reboot.

**Status:** not yet verified on a boot.

## Addendum 2026-11-25 (later): Bluetooth verified on the stock boot entry

- Boots `324d74be` (-2) and `46898b40` (0): `setting up qcc2072`, SOC 0x40292100 ROM 0x101, `Downloading qca/ornbtfw11.tlv`, `ornnv11.bin`, `ornbcscal11.bin` → `QCA FW build version: BTFW.ORNE.1.1.0-00355-PATCH-1_DEF … CSCAL_MTP_260210`, `QCA setup on UART is completed`. No `Failed to send TLV segment` on either boot (2/2 so far).
- The `ornnv11.b17` / `ornbcscal11.b17` `-2` lines are normal: the driver tries a board-specific file first and falls back to the generic `.bin`.
- Each Bluetooth power-on re-downloads the firmware (≈1.6 s); seen at +58.65 s in boot 0 after `rfkill unblock bluetooth`.
- Sony WH-CH520 paired and connected: card profile `a2dp-sink`, codec AAC; HFP/HSP UUIDs offered.
- `verify.sh`: all ok.
- The `clk-branch.c:87` WARNINGs (display clocks: udev-worker/plymouthd/Hyprland in `drm_mode_getconnector`) occur in every earlier boot too (2–47 per boot); not related to the Bluetooth modules.
- Open: boot -2 has no shutdown messages after +140 s, and boot -1 (`30de7ef4`) lasted about 8 s. Ask the user whether they forced a power-off. If not, this fits the unexplained early resets.
- Still to test: lid-closed sleep ≥3 min with Bluetooth on (BT reconnect, no new wake source); TLV -110 over more boots; HFP microphone.

## Addendum 2026-11-25: random resets: survey of 48 boots, and logging change

- **Boots that died 7–16 s after starting:** 14 (-45 -44 -42 -41 -40 -34 -26 -23 -17 -14 -13 -8 -6 -1).
  - Each one's last persisted record is the journald flush to /var, or kernel messages from just before it (PCIe 0004 host bridge, zram, remoteproc soccp/cdsp available).
  - A normal boot always followed.
- **Boots that ended without shutdown records 28 s to 8 min into use:** about 15 (-43 -37 -35 -33 -31 -29 -28 -21 -19 -18 -12 -10 -7 -5 -2), plus -39 (2.6 h).
  - Some of these may be power-button presses by the user.
  - Boots that ended inside `PM: suspend entry` (-46 -36 -32 -24 -20) are probably forced power-offs from the old suspend hangs.
- **Last kernel messages before a reset:** nothing in common (Wi-Fi association, the Chrome wireless-extensions warning, the BNEP init). There are no oopses or warnings.
- **Seen on kernels 7.3.0-72, -75 and -77,** on both the test and stock trees, so it predates the Bluetooth modules. The user confirms random reboots "before too".
- **The reset comes from below Linux.** `kernel.panic=0` (a Linux panic would hang, not reboot), qcom_wdt is `inactive`, systemd RuntimeWatchdog is 0, and /var/lib/systemd/pstore is empty. That points to firmware, hypervisor or TZ, a secure watchdog or bus error, or PMIC (power or thermal).
  - This is inferred: the actual reset reason is unknown.
- **Logging gap:** journald used the default `SyncIntervalSec=5min`, so up to 5 min before each reset was lost. Installed `/etc/systemd/journald.conf.d/50-ux3407na-reset-debug.conf` (`SyncIntervalSec=5s`; repo `files/`) and restarted journald.
  - Remove it later with `./uninstall.sh --reset-debug`.
- **Next:**
  - After the next unexpected reboot, read `journalctl -b -1` (the final seconds should now be on disk).
  - Read the PMIC PON/fault reason registers as root (first confirm the PMK8550-class PON register layout).
  - Check for a BIOS newer than UX3407NA.316.
  - Ask the user whether the resets happen on AC or on battery.
