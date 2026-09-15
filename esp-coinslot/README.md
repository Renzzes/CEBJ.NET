# KonekSik-Fi multi-board coinslot firmware

Portable coinslot core for:

| Env (`pio run -e …`) | Board |
|----------------------|--------|
| `esp8266_lanbase_w5500` | ESP8266 + W5500 (FastFi lanbase pins) |
| `esp8266_wifi` | ESP8266 WiFi |
| `esp32_w5500` | ESP32 + W5500 |
| `esp32s3_w5500` | ESP32-S3 + W5500 |
| `esp32_eth` | ESP32 native Ethernet |

Pin maps are defined in:

- `include/boards/*.h` (firmware)
- `board_profiles/*.json` (flasher UI — same data)

## Build

```bash
pio run -e esp8266_lanbase_w5500
pio run -e esp32_w5500
```

## Serial license API (for provisioner)

- `KSK_ID?`
- `KSK_PINS?`
- `KSK_LICENSE_WRITE <base64json>`
- `KSK_LICENSE_READ`
- `KSK_LICENSE_CLEAR`

## Status

- ✅ Multi-board pin HAL + coin/relay + license store/serial  
- ⏳ Full router HTTP register/coin protocol (still in legacy `rootfs/fastfi-coinslot-lanbase`) — port next
