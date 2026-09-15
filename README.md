# CEBJ.NET — KonekSik-fi Piso WiFi

Custom Piso WiFi for **Ruijie / Reyee RG-EW1200G PRO** (hardware 3.32), built on an OpenWrt image with KonekSik admin, captive portal, ESP coinslot licensing, and optional GCash companion.

**GitHub:** [Renzzes/CEBJ.NET](https://github.com/Renzzes/CEBJ.NET)  
**Contact:** clarenceemmanueljamora@gmail.com

---

## What is in this repo

| Path | Purpose |
|------|---------|
| `EXTRACTED-OPENWRT-FASTFI-V2.5.1/rootfs/` | Router source / overlay (Admin UI, Lua API, OTA script) |
| `KonekSik-fi Piso Wifi Production/` | Packaged production outputs (sysupgrade `.bin`, ESP tools) |
| `esp-coinslot/` | ESP coinslot firmware sources |
| `esp-license-provisioner/` | Offline ESP flasher + license tools (source) |
| `gcash-companion/` | Optional operator GCash companion app source |
| `tools/` | Build / validate helpers (OEM ReyeeOS validator, symlink checks) |
| `BUILD-PRODUCTION.bat` | Full production packager |
| `BUILD-RUIJIE-BIN.bat` | Rebuild Ruijie sysupgrade `.bin` only |
| `KONEKSIK-GUIDE.md` | Full operator / developer guide |

---

## Quick start

1. Read `START-HERE.txt` and `KONEKSIK-GUIDE.md`.
2. Preview Admin UI on this PC: run `PREVIEW-UI.bat` → open `http://127.0.0.1:8765/admin-preview.html`.
3. Flash the production image from:
   `KonekSik-fi Piso Wifi Production/01-RUIJIE-OPENWRT/KonekSik-fi-EW1200G-PRO-sysupgrade.bin`

### Flash KonekSik (manual)

1. Open router Admin → **OTA Update**.
2. Under **KonekSik Firmware**, upload the `.bin` above.
3. Confirm → **Flash KonekSik firmware** → wait for reboot. Do not power off mid-flash.

### System OTA (online)

Admin → **OTA Update** → **System OTA Update** → **Check for Updates**.

This checks **this repository’s GitHub Releases**:

- Owner / repo: `Renzzes/CEBJ.NET`
- Channel: `latest`
- Preferred asset: `update.tar.gz` (code overlay OTA)

It no longer uses any third-party FastFi GitHub project.

### OEM ReyeeOS restore (separate path)

Under **OEM Firmware — ReyeeOS**, upload an official Ruijie package (example: `EW_3.0(1)B11P313_*_encrypto.tar.gz`) to restore stock ReyeeOS. This erases KonekSik and writes only the named `firmware` MTD partition. Not the same as KonekSik OTA.

---

## Build (developers)

Requirements: Windows + WSL for the Ruijie ImageBuilder path.

```bat
BUILD-RUIJIE-BIN.bat
```

or full pack:

```bat
BUILD-PRODUCTION.bat
```

Do **not** run as Administrator. After UI/Lua changes, rebuild so the production `.bin` includes them.

---

## Releases

GitHub Releases on this repo are the System OTA source of truth.

Typical release assets:

| Asset | Used by |
|-------|---------|
| `update.tar.gz` | System OTA (online) |
| `sha256sums` | OTA checksum verification |
| `KonekSik-fi-EW1200G-PRO-sysupgrade.bin` | Manual flash / first install |

Bump `/www/version.txt` in the image when you publish a newer release so routers detect the update.

---

## Safety notes

- Keep a config backup before any flash.
- Never flash OEM ReyeeOS packages through the **KonekSik Firmware** path.
- Do not commit GitHub tokens or license secrets into this tree.
- Ruijie OEM stock archives are omitted from git (see `.gitignore`); keep your own licensed copies offline.

---

## License / branding

CEBJ.NET / KonekSik-fi — custom Piso WiFi project.  
Inspired by community Piso WiFi / OpenWrt workflows; this tree is maintained under **Renzzes/CEBJ.NET**.
