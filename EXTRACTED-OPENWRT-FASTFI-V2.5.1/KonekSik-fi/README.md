# KonekSik-fi

**KonekSik-fi** is a local Piso WiFi / plan WiFi appliance for Philippine sites.

The **ESP32-S3-ETH (with PSRAM)** is the application server: Admin Dashboard, API, sales/sessions/vouchers storage, coin hardware, and MikroTik orchestration.

The **MikroTik hEX Refresh** is the network engine: WAN/PPPoE, DHCP, NAT, firewall, Hotspot, bandwidth, CAPsMAN.

**MikroTik Access Points** run as CAP/bridge radios — not routers.

No cloud host, mini PC, Raspberry Pi, or external database is required for local operation.

---

## Hardware (assumed available)

- ESP32-S3-ETH + PSRAM  
- Coin acceptor and existing ESP32 peripherals (display, relays, sensors)  
- MikroTik hEX Refresh  
- Compatible MikroTik RouterOS WiFi AP(s)  

---

## Architecture (short)

```
ISP → hEX Refresh → AP (Wi-Fi users)
                 → ESP32-S3-ETH → Admin browser
```

Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · [docs/SYSTEM-FLOW.md](docs/SYSTEM-FLOW.md)

---

## Access the Admin Dashboard

On the local network (example):

```text
http://192.168.20.50
```

Optional hostname (later): `http://koneksik.local`

Prototype login: `admin` / `admin`

Internet is **not** required to open Admin, log in, view sales, or configure PPPoE for the MikroTik.

---

## Development (this repository)

| Area | Location |
|---|---|
| Admin UI prototype | `index.html`, `css/`, `js/`, `public/` |
| ESP32 firmware | `firmware/` |
| Example JSON shapes | `data/` |
| Documentation | `docs/` |

Open `index.html` in a browser for UI prototyping. Production serves the same assets from the ESP32 HTTP server.

---

## Local vs Internet

| Condition | Local Admin |
|---|---|
| Internet offline | Available |
| PPPoE down | Available |
| MikroTik offline | ESP32 Admin still available; network pages show MikroTik offline |
| AP offline | Other APs and Admin continue |

---

## Documentation index

See [docs/README.md](docs/README.md).

---

## Implementation phases

1. ESP32 Ethernet + web server + filesystem + Admin assets  
2. Local JSON storage (config, sales, sessions, vouchers)  
3. Authentication  
4. Hardware (coin, display)  
5. MikroTik RouterOS API client  
6. PPPoE configure/status via ESP32 → MikroTik  
7. Access Points / CAPsMAN views  
8. Bandwidth / security / devices  
9. OTA  
10. Backup / restore  

---

## License / ownership

Owner console for on-site operators. Technician configures RouterOS; owner uses KonekSik-fi Admin.
