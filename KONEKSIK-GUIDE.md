# KonekSik-fi — Operator & Development Guide

This document covers building, flashing, UI preview, and continuing work on another PC/laptop.

---

## Project folders (what matters)

| Path | Purpose |
|------|---------|
| `EXTRACTED-OPENWRT-FASTFI-V2.5.1\rootfs\` | OpenWrt / Admin UI source (edit here) |
| `esp-coinslot\` | ESP coinslot firmware source |
| `esp-license-provisioner\` | ESP flasher + license tool (Python source + `BUILD-EXE.bat`) |
| `gcash-companion\` | GCash companion Android app (operator phone only) |
| `KonekSik-fi Piso Wifi Production\` | Ready-to-use outputs (bins, flasher, APK) |
| `PREVIEW-UI.bat` | Local Admin UI preview in browser |
| `BUILD-RUIJIE-BIN.bat` | Build Ruijie `.bin` only |
| `BUILD-PRODUCTION.bat` | Full production pack (Ruijie + ESP + flasher + APK) |

---

## A. Daily development (Admin dashboard)

1. Double-click **`PREVIEW-UI.bat`**
2. Open **http://127.0.0.1:8765/admin-preview.html**
3. Edit files under `EXTRACTED-OPENWRT-FASTFI-V2.5.1\rootfs\www\` (and related Lua under `rootfs\usr\...`)
4. Hard-refresh the browser (Ctrl+F5) after changes

Preview uses **mock data** — it does not change a live router.

When you are satisfied with the Admin UI, build firmware (section C) and flash the Ruijie.

---

## B. Move to another PC / laptop (continue development)

### What to copy

Copy the **entire** project folder:

`RUIJIE EW1200G PRO DOWNGRADE FILES\`

USB drive, zip, OneDrive, etc. all work.

That keeps:

- Source code (Admin, ESP, flasher, GCash)
- Production outputs (including the Ruijie `.bin` if already built)
- All `.bat` helpers

You do **not** need to copy WSL/Ubuntu from the old PC.

### On the new laptop — first open

1. Place the folder anywhere (Documents is fine)
2. Open that folder in Cursor
3. For UI work only: run **`PREVIEW-UI.bat`** (needs Python for the tiny web server)

### On the new laptop — when you need each tool

| Goal | What to do |
|------|------------|
| Preview / edit Admin UI | `PREVIEW-UI.bat` |
| Flash a router with an **already built** `.bin` | Use file in `Production\01-RUIJIE-OPENWRT\` — **no rebuild** |
| Build a **new** Ruijie `.bin` after UI changes | Install WSL once, then `BUILD-RUIJIE-BIN.bat` (see C) |
| Full production pack | `BUILD-PRODUCTION.bat` (see C) |
| Flash ESP + license | Use flasher `.exe` or `START-FLASHER.bat` (see D) |

### Syncing back to the office PC

Copy the updated project folder (or at least changed source + new `.bin`) back the same way. Machines do not sync automatically.

---

## C. Build firmware / production pack

### C1. Ruijie OpenWrt `.bin` only

**One-click:** `BUILD-RUIJIE-BIN.bat`

**First time on a PC:**

1. Script may install **WSL + Ubuntu** (Admin once; then **reboot**)
2. Open Ubuntu once if asked → create username/password → `exit`
3. Run `BUILD-RUIJIE-BIN.bat` again **normally** (do **not** Run as administrator)
4. Wait 15–45+ minutes on first build

**Output:**

`KonekSik-fi Piso Wifi Production\01-RUIJIE-OPENWRT\KonekSik-fi-EW1200G-PRO-sysupgrade.bin`

**When to re-run:** only after you change OpenWrt/Admin source and want a new image.  
**When transferring laptops:** if the `.bin` is already in that folder, you can flash without rebuilding.

### C2. Full production pack

**One-click:** `BUILD-PRODUCTION.bat`

Builds/packs into `KonekSik-fi Piso Wifi Production\`:

1. `01-RUIJIE-OPENWRT\` — Ruijie sysupgrade `.bin` (needs WSL)
2. `02-ESP-COINSLOT\` — ESP firmware bins (needs PlatformIO) + Flasher-and-License
3. `03-GCASH-COMPANION\` — APK if Android build exists

Check each folder’s `STATUS.txt` (OK / SKIPPED / FAILED).

**Tip:** If you only need the router image, `BUILD-RUIJIE-BIN.bat` is enough.  
`BUILD-PRODUCTION.bat` already includes the Ruijie step — you usually do **not** need both every time.

### Prerequisites cheat sheet

| Output | Need on that PC |
|--------|-----------------|
| Ruijie `.bin` | WSL Ubuntu |
| ESP `.bin` | PlatformIO (`pip install platformio`) |
| Flasher `.exe` | Already built, or run `esp-license-provisioner\BUILD-EXE.bat` |
| Flasher via Python | Python 3 |
| GCash APK | Android Studio (once) |

---

## D. Flash Ruijie (router)

**File:** `01-RUIJIE-OPENWRT\KonekSik-fi-EW1200G-PRO-sysupgrade.bin`

### Router already on KonekSik / OpenWrt Admin

1. Connect PC to the Ruijie
2. Open Admin in browser → log in
3. **OTA Update** → **Upload Firmware**
4. Choose the `.bin` → **Upload & Prepare** → **Flash**
5. Wait for reboot — do not power off mid-flash

### Still stock Ruijie (no KonekSik Admin yet)

Use your usual EW1200G Pro recovery / downgrade / first-install method, then use Admin OTA for later updates.

---

## E. ESP flasher + license

### Preferred (`.exe` — no Python needed to run)

1. Open:

   `KonekSik-fi Piso Wifi Production\02-ESP-COINSLOT\Flasher-and-License\`

2. Double-click **`START-FLASHER.bat`**  
   (or `KonekSik-ESP-Flasher\KonekSik-ESP-Flasher.exe`)

3. Keep the whole **`KonekSik-ESP-Flasher`** folder together when copying to another PC.

### If `.exe` is missing — Python mode

1. Install Python 3 (add to PATH)
2. Double-click `run.bat` or `START-FLASHER.bat`
3. First run creates `.venv` and installs packages

### Rebuild the `.exe` later

```text
esp-license-provisioner\BUILD-EXE.bat
```

Copies into Production `Flasher-and-License\` when that folder exists.

### Every ESP unit (provisioning)

1. Plug ESP via USB
2. Open flasher
3. Select **board** (e.g. ESP32 + W5500)
4. Select **COM port** (Refresh if needed)
5. Browse matching firmware, e.g. `firmware\esp32_w5500-firmware.bin`  
   (If empty: build ESP with PlatformIO / `BUILD-PRODUCTION.bat`)
6. Click **Flash + License** (full provision)
7. Do **not** skip the license step

**Keep private:** `keys\` (signing key). Back it up; do not share the private `.pem`.

### After ESP is flashed

Wire coin / relay / Ethernet (W5500) per the pin map in the flasher UI, then configure / bind in Ruijie Admin.

---

## F. GCash companion (optional)

- Install APK from `03-GCASH-COMPANION\` on the **operator** phone only (the phone that receives GCash)
- Customers do **not** install this app
- See that folder’s `HOW-TO-INSTALL.txt`

## F2. Remote Access — Tailscale (optional, free)

Not FastFi VPN. On-demand only (start when needed, stop to free RAM).

1. Create account: https://login.tailscale.com  
2. Install Tailscale on your phone/laptop and sign in  
3. Create an auth key: https://login.tailscale.com/admin/settings/keys  
4. On the router Admin → **Remote Access** → **Install Tailscale** → paste key → **Start remote**  
5. Open the shown Admin URL (`http://100.x.x.x/admin.html`) from your phone/laptop  
6. When done → **Stop (free RAM)**  

Requires a firmware build that includes the new Tailscale Admin page (rebuild/flash after these source changes).

---

## G. Recommended install order (new site / new unit)

1. Flash Ruijie with `KonekSik-fi-EW1200G-PRO-sysupgrade.bin`
2. Flash ESP + write license with Flasher
3. Configure Admin (rates, APs, bind ESP, etc.)
4. Optional: GCash companion on operator phone

---

## H. Quick answers

**Do I run the build bats only once?**  
Once per PC to produce outputs; again only when source changes or the other PC doesn’t have the finished files.

**Laptop has the copied `.bin` — rebuild?**  
No, not just to flash. Rebuild only after you change firmware/Admin source on that laptop.

**Admin preview vs real router?**  
Preview = local mock UI. Real config needs the built `.bin` flashed to the Ruijie.

**Production vs Ruijie bat?**  
- Ruijie only → `BUILD-RUIJIE-BIN.bat`  
- Everything → `BUILD-PRODUCTION.bat`

---

## I. Checklist — new laptop setup

- [ ] Copy full project folder from office PC
- [ ] Open in Cursor
- [ ] Run `PREVIEW-UI.bat` to continue Admin UI work
- [ ] If flashing only: use existing Production `.bin` / flasher `.exe`
- [ ] If rebuilding Ruijie: install WSL/Ubuntu once → reboot → `BUILD-RUIJIE-BIN.bat` (not as Admin)
- [ ] If rebuilding ESP bins: install PlatformIO → `BUILD-PRODUCTION.bat` or `pio run`
- [ ] Copy updated folder back to office when done
