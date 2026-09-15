# Architecture

## Overview

```
ESP32-S3-ETH (+ PSRAM)
       │
       ├── Web Server          → Admin HTML/CSS/JS
       ├── Local REST API      → /api/*
       ├── Auth                → local username/password
       ├── JSON Storage        → /data on flash
       ├── Hardware            → coin, display, relays, sensors
       ├── System              → time, OTA, reboot, logs
       └── MikroTik client     → RouterOS API (secrets stay here)
                │
                ▼
          MikroTik hEX Refresh
                │
                ├── WAN / PPPoE / DHCP / NAT / Firewall / VLAN
                ├── Hotspot + queues
                └── CAPsMAN
                        │
                   ┌────┼────┐
                   ▼    ▼    ▼
                 AP-01 AP-02 AP-03  (CAP / bridge)
```

## Responsibilities

### ESP32-S3-ETH — application + controller

- Serve Admin Dashboard over Ethernet/LAN  
- Local authentication (works offline)  
- Persist sales, sessions, vouchers, settings  
- Coin processing and peripheral control  
- Orchestrate MikroTik (status, PPPoE config, device/session actions)  
- OTA, backup/export, reboot, health  

### MikroTik hEX Refresh — network engine

- WAN, PPPoE, routing, NAT, firewall, DHCP, VLAN  
- Hotspot / access control and bandwidth  
- CAPsMAN and AP management  
- Does **not** host the Admin app or sales database  

### Access Point — wireless engine

- CAP / AP / bridge mode only  
- Radios for customer and (optionally) management SSIDs  
- Status and clients read through MikroTik / CAPsMAN  

## Trust boundary

```
Browser  ──HTTP──►  ESP32  ──RouterOS API──►  MikroTik
```

Never embed MikroTik API passwords, PPPoE passwords, or VPN keys in frontend JavaScript.

## Failure isolation

| Failure | Admin on ESP32 | Notes |
|---|---|---|
| Internet / ISP down | Available | Remote Access offline |
| MikroTik unreachable | Available | Network pages show offline |
| One AP offline | Available | Other APs continue |
| ESP32 down | Unavailable | Coin/Admin stop until power/firmware restored |

## Related docs

- [SYSTEM-FLOW.md](SYSTEM-FLOW.md)  
- [NETWORK_TOPOLOGY.md](NETWORK_TOPOLOGY.md)  
- [API.md](API.md)  
- [STORAGE.md](STORAGE.md)  
