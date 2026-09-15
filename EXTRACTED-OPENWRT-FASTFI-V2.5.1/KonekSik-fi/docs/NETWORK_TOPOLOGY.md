# Network topology

## Logical diagram

```
ISP
 │
 │  PPPoE / DHCP / Static
 ▼
hEX Refresh
 │
 ├── VLAN 10  Customer     192.168.10.0/24   (Hotspot clients)
 ├── VLAN 20  Management   192.168.20.0/24   (APs, Winbox, optional Admin path)
 └── VLAN 30  Controller   192.168.30.0/24   (ESP32-S3-ETH preferred)
       │
       ├── ESP32-S3-ETH   e.g. 192.168.30.50  or 192.168.20.50
       └── AP management / CAP discovery
```

Exact subnet numbers are site-specific. Keep **customer** traffic separated from **management/controller**.

## Physical sketch

```
ISP modem/ONT
      │
      ▼
  hEX ether1 (WAN)
      │
  hEX LAN / bridge / VLAN-aware ports
      ├── AP-01 Ethernet (management + tagged customer if used)
      ├── AP-02 Ethernet
      └── ESP32 Ethernet → Admin browser on same management path
```

## Access rules

| Network | Devices | Admin Dashboard |
|---|---|---|
| Customer VLAN | Phones | No (Hotspot only) |
| Management / Controller | ESP32, APs, owner laptop | Yes |
| WAN | ISP | N/A |

## Admin URL examples

```text
http://192.168.20.50
http://192.168.30.50
http://koneksik.local   (optional mDNS later)
```

## Related

- [MIKROTIK_SETUP.md](MIKROTIK_SETUP.md)  
- [ESP32_SETUP.md](ESP32_SETUP.md)  
- [CAPSMAN_SETUP.md](CAPSMAN_SETUP.md)  
