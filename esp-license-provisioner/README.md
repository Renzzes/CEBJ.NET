# KonekSik-Fi / FastFi — ESP License Provisioner

Windows app to **flash coinslot firmware** and **generate + burn an offline license** onto an ESP (no cloud).

## What it does

1. Detect USB COM port  
2. Flash `.bin` firmware (esptool)  
3. Read chip ID / MAC  
4. Sign an Ed25519 license with your private key  
5. Try to write license to ESP over serial (`KSK_LICENSE_WRITE …`)  
6. Log every issue under `logs/`

## Board profiles (pin maps)

Select a board in the UI to see **exact GPIOs** for:

- Coin primary / backup  
- Relay / LED  
- **W5500** CS/SCLK/MISO/MOSI (wired boards)  
- Native ETH RMII pins (ESP32-ETH)

Profiles live in `board_profiles/*.json` (shared with `esp-coinslot/`).

Supported boards:

- ESP8266 + W5500 (LANBASE)  
- ESP8266 WiFi  
- ESP32 + W5500  
- ESP32-S3 + W5500  
- ESP32 native Ethernet  

## Quick start


```bat
cd "esp-license-provisioner"
run.bat
```

Or:

```bat
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python -m app.main
```

1. Put your firmware binary at `firmware/coinslot.bin` (or Browse in the UI).  
2. First run creates `keys/issuer_ed25519.pem` + `.pub.pem` — **back up the private key**.  
3. Plug ESP → Refresh → Flash + License.

## Notes

- Your current FastFi coinslot sketch is **ESP8266** (`fastfi-coinslot-lanbase`). Prefer chip = `esp8266`.  
- Serial license write needs firmware support for:
  - `KSK_ID?` → `KSK_ID chip=… mac=…`
  - `KSK_LICENSE_WRITE <base64json>` → `KSK_LICENSE_OK`
- Until that firmware lands, the app still **generates and saves** licenses under `logs/`.

## Folder layout

```
esp-license-provisioner/
  app/           Python app
  firmware/      place .bin here
  keys/          issuer Ed25519 keys (private = secret)
  logs/          issued license log
  run.bat
  requirements.txt
```
