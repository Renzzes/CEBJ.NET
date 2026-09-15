# KonekSik-fi — System flow (hardware to software)

This document describes how KonekSik-fi is meant to run on site: **one ESP32-S3-ETH (application server)**, **one MikroTik hEX Refresh (network engine)**, **Access Points as CAPs**, and **optional Sub Vendo / coin peripherals**.

There is **no cloud host**, **no mini PC**, **no Raspberry Pi**, and **no external database**. The owner's browser opens the Admin Dashboard **directly from the ESP32** on the local network.

The repo root Admin UI (`index.html`, `css/`, `js/`) is the **owner console prototype**. In production those assets are served by the ESP32 web server.

---

## 1. What each piece is

| Piece | What it is | What it is not |
|---|---|---|
| **ESP32-S3-ETH (+ PSRAM)** | Local KonekSik-fi application server: Admin UI, API, JSON storage, auth, coin/hardware control, MikroTik orchestration | Not the router. Does not replace DHCP, NAT, Hotspot, or CAPsMAN |
| **MikroTik hEX Refresh** | Network engine: WAN, PPPoE, DHCP, NAT, firewall, VLAN, Hotspot, queues, CAPsMAN | Not the Admin host. Does not store sales/vouchers |
| **Access Points (CAPs)** | Wi-Fi radios / bridges managed by CAPsMAN | Not routers. No PPPoE, no DHCP of their own |
| **Sub Vendo / peripherals** | Coin acceptor, display, relays, sensors on ESP32 paths | Not the portal server by themselves |
| **Admin Dashboard** | Owner console served by the ESP32 | Not shown to unpaid customers |
| **Captive Portal** | Phone login page (Hotspot redirect target) | Not a cloud site; typically Hotspot files on the hEX or served under ESP32 if configured |

**ESP32-S3-ETH (this deployment)**

- Local web server + REST API  
- Nonvolatile JSON storage (sales, sessions, vouchers, settings)  
- Talks to MikroTik over the **management network** (RouterOS API)  
- Continues serving Admin when the **Internet is offline**

**hEX Refresh**

- CPU: Dual-core EN7562CT, 950 MHz  
- RAM: 512 MB  
- Storage: 128 MB NAND (RouterOS + optional Hotspot files)

---

## 2. Where software lives

```
ESP32-S3-ETH
├── Web server          Admin Dashboard (HTML/CSS/JS)
├── Local REST API
├── Auth + sessions
├── JSON data           /data/*.json
├── Hardware drivers    coin, display, relays
└── MikroTik client     RouterOS API (credentials stay on ESP32)

MikroTik hEX Refresh
├── RouterOS v7
│     WAN / PPPoE, DHCP, NAT, Firewall, VLAN
│     Hotspot, queues, CAPsMAN
└── Optional Hotspot login files (captive portal)

Access Points (CAP / bridge)
└── Radios only — managed by CAPsMAN on the hEX
```

| Software | Stored / runs on | Opened by |
|---|---|---|
| Admin Dashboard | ESP32 web server | Owner on LAN / management path |
| Local API + DB | ESP32 flash / PSRAM-backed state | ESP32 firmware only |
| Captive Portal UI | hEX Hotspot files (or ESP32 if configured) | Phones after Hotspot redirect |
| Routing / Hotspot / CAPsMAN | hEX | Technician (Winbox) + ESP32 API orchestration |
| AP firmware | Each CAP | Technician / CAPsMAN |

**Security rule:** the browser never receives MikroTik API passwords, PPPoE passwords, or VPN keys. Path is always:

`Browser → ESP32 → RouterOS API → MikroTik`

---

## 3. Hardware path

Example site: **1 ESP32-S3-ETH + 1 hEX + 2 APs**.

```
                         Internet (ISP)
                               │
                         PPPoE / DHCP / Static
                               │
                               ▼
                    ┌─────────────────────┐
                    │  MikroTik hEX Refresh│
                    │  Router + Hotspot    │
                    │  CAPsMAN             │
                    └──────────┬──────────┘
                               │ Local network (VLANs)
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
        ┌──────────┐   ┌──────────────┐   ┌──────────┐
        │  AP-01   │   │ ESP32-S3-ETH │   │ Admin PC │
        │ CAP/bridge│   │ KonekSik-fi  │   │ browser  │
        └────┬─────┘   │ server       │   └────┬─────┘
             │ Wi-Fi   └──────┬───────┘        │
             ▼                │                │
          Phones        coin / display   http://ESP32-IP
```

- APs only forward traffic to the hEX.  
- ESP32 sits on the **management / controller** network and orchestrates MikroTik.  
- Owner reaches Admin at e.g. `http://192.168.20.50` (optional `http://koneksik.local`).

---

## 4. Two roles (do not mix them)

| Name | Device | Job |
|---|---|---|
| **Network engine** | hEX Refresh | Routing, Hotspot, CAPsMAN, bandwidth queues |
| **Application + controller** | ESP32-S3-ETH | Admin UI, sales/sessions/vouchers, coin logic, call MikroTik APIs |

“Controller” in the dashboard means **KonekSik-fi on the ESP32 is reachable**, not a second PC.

---

## 5. Who does what

**Technician (Winbox / RouterOS)** — once / as needed

- ISP / WAN baseline  
- Bridge, DHCP, Hotspot, VLANs  
- CAPsMAN and CAP APs  
- Enable RouterOS API for the ESP32 (management VLAN only)  
- Owner MAC/IP bypass or management SSID so Admin is not trapped behind Hotspot  

**Owner (Admin Dashboard on ESP32)** — daily

- Plans, coin rates, vouchers, sales  
- Sessions, devices, block/disconnect  
- View Internet / PPPoE status; configure PPPoE via ESP32 → MikroTik  
- Access Points status (via CAPsMAN data from MikroTik)  
- Settings, branding, OTA, backup/export  
- Reboot KonekSik-fi (ESP32)  

The owner UI **must not** dump raw RouterOS internals (Queue Tree, mangle, packet marks) or expose MikroTik management credentials.

**Customer**

- Joins AP Wi-Fi → Hotspot redirect → captive portal → coin or voucher → internet  

---

## 6. Local-first (Internet optional)

When the ISP is down:

| Component | Expected |
|---|---|
| Internet | Offline |
| MikroTik | Online (LAN) |
| ESP32 | Online |
| Admin Dashboard | **Available** |

Owner can still log in, view sales/sessions, manage vouchers, view MikroTik/AP status (if LAN works), and configure PPPoE for when the ISP returns.

---

## 7. Runtime flows

### 7.1 Coin payment

```
Phone → AP → hEX Hotspot → portal
Customer inserts coin → ESP32 counts pulse
ESP32 records sale + asks MikroTik to allow session/speed
Phone gets internet
```

### 7.2 Voucher

```
Phone → portal → code
ESP32 validates voucher locally → MikroTik allows phone
```

### 7.3 PPPoE from Admin

```
Owner → ESP32 Admin → Save PPPoE
ESP32 → RouterOS API → hEX configures PPPoE client
hEX ↔ ISP authentication → WAN up
```

Internet is **not** required for the owner to open Admin or submit PPPoE credentials.

### 7.4 Dashboard KPIs

Headline KPIs (prototype):

| KPI | Source |
|---|---|
| Today's / Weekly / Monthly sales | Local ESP32 sales store (prototype: mock) |
| Connected sessions / Active users | Local + MikroTik/session correlation |

Per AP + ESP32 / Sub Vendo breakdowns stay site-specific when multiple coin units exist.

---

## 8. Accessing Admin

| How you connect | Admin on ESP32 |
|---|---|
| Ethernet / management VLAN to ESP32 IP | Yes |
| Management SSID (not customer Hotspot) | Yes |
| Customer Wi-Fi + MAC/IP bypass | Possible if technician set it |
| Unpaid guest on Hotspot | No — captive portal only |

Do **not** put the Admin URL in the Hotspot walled garden for everyone.

---

## 9. Repository map

| Path | Role |
|---|---|
| `index.html`, `css/`, `js/`, `public/` | Admin UI prototype (served by ESP32 in production) |
| `firmware/` | ESP32-S3-ETH firmware (ESP-IDF / project framework) |
| `data/` | Example JSON schemas / seed shapes |
| `docs/` | Architecture and setup documentation |

Login for this prototype: `admin` / `admin`. MikroTik figures may show **Sample** until live RouterOS data is proxied by the ESP32.

---

## 10. Rules we keep

1. **ESP32 = application server**; **hEX = network engine**; **AP = wireless engine**.  
2. **No cloud / no mini PC** for Admin or local DB.  
3. Browser never holds MikroTik or PPPoE secrets.  
4. Local Admin works with Internet offline.  
5. APs are CAPs/bridges, not routers.  
6. Persist sales/sessions safely; recover after power loss.  
7. Prefer vanilla JS Admin UI; no large frameworks on-device.

---

## 11. Short summary

```
Internet → hEX Refresh (router + Hotspot + CAPsMAN)
              ↓
     AP (Wi-Fi)     ESP32-S3-ETH (Admin + API + storage + coin)
              ↓              ↓
           Phones      Owner browser (local IP)

Customer:  AP → hEX → Portal → coin/voucher (ESP32) → internet
Owner:     LAN → ESP32 Admin
Coin:      Hardware → ESP32 → MikroTik session allow
PPPoE:     Owner → ESP32 → MikroTik → ISP
```
