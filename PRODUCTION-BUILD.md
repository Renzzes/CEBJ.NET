# Production packaging

Double-click **`BUILD-PRODUCTION.bat`** in this folder.

It creates:

```text
KonekSik-fi Piso Wifi Production\
  01-RUIJIE-OPENWRT\              ← Ruijie sysupgrade .bin
  02-ESP-COINSLOT\
    firmware\                     ← ESP board .bin files
    Flasher-and-License\          ← flash tool + offline license (START-FLASHER.bat)
  03-GCASH-COMPANION\             ← companion APK (operator phone only)
  README-INSTALL-ORDER.txt
  BUILD-SUMMARY.txt
  logs\
```

## Prerequisites

| Output | Need on PC |
|--------|------------|
| Ruijie `.bin` | **WSL Ubuntu** |
| ESP `.bin` | **PlatformIO CLI** (`pip install platformio`) |
| Flasher + License | Copied automatically from `esp-license-provisioner` (needs **Python 3** when you run it) |
| GCash `.apk` | **Android Studio** once (Build APK) |

## After it runs

1. Flash Ruijie bin  
2. Open `02-ESP-COINSLOT\Flasher-and-License\START-FLASHER.bat` → flash ESP + write license  
3. Install APK on **your** GCash phone  
