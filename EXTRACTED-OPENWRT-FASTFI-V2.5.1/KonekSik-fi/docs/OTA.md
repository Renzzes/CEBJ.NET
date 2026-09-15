# OTA update

## Goals

- Update ESP32 firmware locally and/or when Internet/remote path is available  
- Validate before install  
- Survive failed update where possible  

## UI

```
Current Version  1.0.0
Available Version 1.0.1
[ Update ]
```

## Process

1. Receive firmware image (local upload or remote when online)  
2. Verify signature/checksum  
3. Write to inactive OTA partition  
4. Set boot partition  
5. Reboot  
6. Confirm healthy boot; rollback if available and boot fails  

Never overwrite the running image without validation.

## Offline

Local Admin remains available; remote “check for update” shows Unavailable when Internet is down. Local file upload OTA can still work on LAN.

## Related

- [RECOVERY.md](RECOVERY.md)  
- [API.md](API.md)  
