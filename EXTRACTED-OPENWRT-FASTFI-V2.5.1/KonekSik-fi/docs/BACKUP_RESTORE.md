# Backup and restore

## Why

Database is local to the ESP32. Owners need export/import without cloud.

## Export

Downloadable JSON (or zip of JSON files) including:

- Configuration (secrets redacted or encrypted)  
- Sales, sessions, vouchers  
- Settings  

UI: **Export Backup**

## Restore

1. Upload file  
2. Validate schema  
3. Create automatic backup of current data  
4. Confirm (“Overwrite local database?”)  
5. Apply restore  
6. Reboot if required  

Never overwrite without validation and confirmation.

## Related

- [STORAGE.md](STORAGE.md)  
- [DATABASE_SCHEMA.md](DATABASE_SCHEMA.md)  
- [RECOVERY.md](RECOVERY.md)  
