# Hardware

## Assumed components (do not replace)

| Component | Role |
|---|---|
| **ESP32-S3-ETH + PSRAM** | Local application server and controller |
| Coin acceptor | Pulse / coin input to ESP32 |
| Display | Local UI / status (existing unit) |
| Relays / sensors | Existing peripherals |
| Ethernet PHY on board | LAN to management network |
| **MikroTik hEX Refresh** | Router / Hotspot / CAPsMAN |
| **MikroTik RouterOS WiFi AP** | CAP / bridge wireless |

Hardware is treated as already available. Firmware integrates existing peripherals rather than redesigning them.

## ESP32-S3-ETH

- Serves Admin over Ethernet  
- Holds application state and JSON files  
- Speaks RouterOS API to the hEX on the management VLAN  
- Must boot and serve Admin with **no Internet**  

## hEX Refresh

- Network engine only  
- Enough NAND for RouterOS (+ optional Hotspot portal files)  
- Expose API only on management network  

## Access Point

- Compatible MikroTik RouterOS wireless AP  
- Mode: **CAP / AP / bridge** — not an independent router  

## Power and recovery

ESP32 must persist critical state before reboot and recover sales/sessions after power loss. See [STORAGE.md](STORAGE.md) and [RECOVERY.md](RECOVERY.md).
