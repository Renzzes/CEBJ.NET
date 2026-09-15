# PPPoE setup (owner via Admin)

Internet configuration is optional. Local Admin works without WAN.

## Happy path

```
Owner opens local Admin (no Internet needed)
        ↓
Networking → Network Overview → Internet Connection
        ↓
Configure Internet → Connection Type = PPPoE
        ↓
Enter ISP, username, password, optional service name, WAN interface
        ↓
[ Test Connection ] / [ Save & Connect ]
        ↓
ESP32 sends config over LAN to MikroTik (RouterOS API)
        ↓
MikroTik applies PPPoE client toward ISP
        ↓
ISP authenticates → WAN IP → Internet ONLINE
```

## UI fields

- Connection type: DHCP | **PPPoE** | Static IP  
- ISP label (display)  
- Username / password / service name  
- WAN interface (e.g. ether1)  
- Actions: Test, Save & Connect, Edit credentials, Retry  

## Security

- After save, **never** show the PPPoE password again in the UI  
- Credentials stored securely on ESP32; applied to MikroTik via API  
- Browser never holds MikroTik API secrets  

## Status views

Connected:

- Authentication: Authenticated  
- Connection: Connected  
- WAN IP, connected since, duration, reconnects today  

Failed:

- Authentication: Failed + reason  
- Edit Credentials / Retry  

## Failure modes

| Symptom | Likely cause |
|---|---|
| Auth failed | Wrong user/password/service |
| No WAN IP | ISP/modem/WAN cable |
| Connected then drops | ISP outage; MikroTik reconnect |
| Admin cannot save | ESP32 ↔ MikroTik API/LAN issue (not Internet) |

## Related

- [MIKROTIK_SETUP.md](MIKROTIK_SETUP.md)  
- [API.md](API.md)  
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md)  
