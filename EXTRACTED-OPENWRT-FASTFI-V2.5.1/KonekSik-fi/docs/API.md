# Local REST API

All endpoints are served by the **ESP32**. Browser never calls MikroTik directly.

Auth: Admin session cookie/token required except `POST /api/auth/login`.

During early development, the Admin prototype may still use in-memory `AppData`; firmware should implement these routes and the UI will migrate to `fetch('/api/...')`.

## Status

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/status` | ESP32, MikroTik, Internet, AP summary |

## Sales / sessions / vouchers / devices

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/sales` | List / filter sales |
| POST | `/api/sales` | Record sale (internal/hardware) |
| GET | `/api/sessions` | List sessions |
| POST | `/api/sessions` | Create / extend |
| GET | `/api/vouchers` | List vouchers |
| POST | `/api/vouchers` | Generate / import |
| DELETE | `/api/vouchers` | Delete one or bulk |
| GET | `/api/devices` | Connected devices |
| POST | `/api/devices/block` | Block MAC |
| POST | `/api/devices/disconnect` | Disconnect |

## Network

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/network` | Internet + MikroTik overview |
| POST | `/api/network/pppoe` | Save/apply PPPoE (ESP32 → MikroTik) |
| GET | `/api/access-points` | AP list / detail |
| POST | `/api/access-points/restart` | Restart AP via MikroTik |

## System

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/system` | CPU/mem/storage/temp, version, time |
| POST | `/api/system/reboot` | Persist then reboot ESP32 |
| POST | `/api/system/ota` | Start OTA |
| GET | `/api/system/backup` | Export JSON backup |
| POST | `/api/system/restore` | Restore with confirmation |

## Error shape

```json
{ "ok": false, "error": "mikrotik_unreachable", "message": "MikroTik API timeout" }
```

Separate ESP32 / MikroTik / Internet / AP failure codes — do not collapse to a single “offline”.

## Security

- No MikroTik or PPPoE passwords in responses  
- Rate-limit login  
- HTTPS optional later; LAN still requires auth  
