# Recovery

## Power interruption

```
Power lost → ESP32 restarts → load persistent state
  → recover sales → recover valid sessions → reconcile time → resume
```

Do not wipe active sessions on every reboot. Re-evaluate expiration against trusted clock.

## Corrupted JSON

1. Prefer last good atomic backup / `.bak`  
2. Fall back to empty defaults for non-critical caches  
3. Never invent sales history  

## Failed OTA

1. Boot previous partition if rollback supported  
2. Serial reflash as last resort  
3. Document version that failed  

## Lost Admin password

Technician recovery via serial console / recovery mode to reset Admin hash. Customer network must not access recovery.

## MikroTik misconfiguration

ESP32 Admin remains reachable on LAN. Fix RouterOS via Winbox on management path; re-apply PPPoE from Admin if needed.

## ESP32 firmware failure

Reflash via USB/serial; restore from owner backup JSON after healthy boot.

## Related

- [STORAGE.md](STORAGE.md)  
- [OTA.md](OTA.md)  
- [BACKUP_RESTORE.md](BACKUP_RESTORE.md)  
- [AUTHENTICATION.md](AUTHENTICATION.md)  
