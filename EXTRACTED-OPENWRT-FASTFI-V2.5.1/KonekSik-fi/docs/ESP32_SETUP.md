# ESP32-S3-ETH setup

## Goals

- Boot without Internet  
- Obtain/use management IP (static or DHCP)  
- Serve Admin UI over HTTP  
- Mount filesystem for `/data` and web assets  
- Reach MikroTik API on LAN  

## First boot checklist

1. Flash firmware (`firmware/` — ESP-IDF or project framework).  
2. Connect Ethernet to management/controller VLAN.  
3. Note IP (serial log / DHCP lease / configured static).  
4. Open `http://<ESP32-IP>/`  
5. Log in with local Admin credentials.  
6. Confirm Dashboard loads offline.  
7. Configure MikroTik API target (IP + credentials stored **on ESP32 only**).  
8. Verify Network Overview can read MikroTik (or shows Offline cleanly).  

## Example address

```text
http://192.168.20.50
```

Optional later: mDNS `http://koneksik.local` with IP fallback always available.

## Web assets

Production: embed or SPIFFS/LittleFS/FAT partition with Admin `index.html`, `css/`, `js/`, `public/`.

Development: prototype UI from repository root; replace `AppData` with `/api/*` as firmware lands.

## Related

- [ARCHITECTURE.md](ARCHITECTURE.md)  
- [STORAGE.md](STORAGE.md)  
- [AUTHENTICATION.md](AUTHENTICATION.md)  
- [OTA.md](OTA.md)  
