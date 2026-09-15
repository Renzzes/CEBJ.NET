# Storage

## Principles

- All application data is **local** on the ESP32.  
- No remote database.  
- Prefer **RAM state + controlled persistence** over rewriting large JSON on every tick.  

## Layout

```text
/data
├── config.json
├── state.json
├── sales.json
├── sessions.json
├── vouchers.json
├── devices.json
├── access_points.json
├── network.json
├── settings.json
└── logs/
```

Example shapes also live under repository `data/` for development.

## Flash write rules

Do **not** rewrite large files on every small change.

Implement:

- In-RAM authoritative state  
- Batched / delayed flush  
- Atomic replace (write temp → rename) where filesystem supports it  
- Validate after write for sales and other critical records  
- Recovery after interrupted write  

Sales path:

1. Accept transaction  
2. Validate  
3. Persist  
4. Confirm storage  
5. Update UI  

## Optional later

SD card for large logs/archives — not required for MVP if flash + PSRAM suffice.

## Related

- [DATABASE_SCHEMA.md](DATABASE_SCHEMA.md)  
- [RECOVERY.md](RECOVERY.md)  
- [BACKUP_RESTORE.md](BACKUP_RESTORE.md)  
