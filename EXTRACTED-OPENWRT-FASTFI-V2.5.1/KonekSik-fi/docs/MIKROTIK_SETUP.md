# MikroTik setup (technician)

This is **technician / Winbox** work. The owner dashboard must not replace it with a raw RouterOS editor.

## Goals

- Working WAN (PPPoE / DHCP / Static)  
- Customer VLAN + Hotspot  
- Management / controller path for ESP32 and APs  
- CAPsMAN for CAP APs  
- RouterOS API reachable **only** from management/controller network  

## Checklist

1. **Initial** — reset/baseline, set identity, admin password, services  
2. **WAN** — ether1; PPPoE client or DHCP client or static  
3. **LAN / bridge** — bridge ports for APs and ESP32 as designed  
4. **VLANs** — Customer (e.g. 10), Management (20), Controller (30)  
5. **DHCP** — customer pool; management pool for APs/ESP32 if needed  
6. **NAT** — masquerade WAN  
7. **Firewall** — drop WAN to management; allow ESP32 → API; no customer → Winbox/API  
8. **Client isolation** — Hotspot / bridge horizon / AP isolation as required  
9. **Hotspot** — on customer interface; login page; walled garden **without** exposing Admin to all guests  
10. **Bandwidth** — simple queue / hotspot user profiles (owner uses named profiles via ESP32 later)  
11. **API** — enable `api` / `api-ssl` on management only; create ESP32 service user with least privilege  
12. **CAPsMAN** — enable on hEX; provision CAP radios  
13. **Management access** — owner MAC bypass or management SSID so Admin is reachable  

## Owner vs technician

| Task | Who |
|---|---|
| Create VLANs, Hotspot, CAPsMAN, API user | Technician |
| Enter PPPoE username/password in Admin | Owner (ESP32 pushes to MikroTik) |
| View AP status, block device, adjust plan speed | Owner |
| Edit Queue Tree / mangle | Technician only |

## ESP32 credentials (on device only)

Store MikroTik API username/password in ESP32 secure storage — **never** in browser JS.

## Related

- [PPPOE_SETUP.md](PPPOE_SETUP.md)  
- [CAPSMAN_SETUP.md](CAPSMAN_SETUP.md)  
- [NETWORK_TOPOLOGY.md](NETWORK_TOPOLOGY.md)  
