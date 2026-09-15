# Database schema (JSON)

Schemas are logical. Firmware may split or index files as needed. Types are JSON-native.

## config.json

| Field | Type | Required | Notes |
|---|---|---|---|
| deviceId | string | yes | e.g. KSK-001 |
| siteName | string | yes | |
| timezone | string | yes | Asia/Manila |
| mikrotik.host | string | yes | Management IP |
| mikrotik.apiUser | string | yes | Stored on device only |
| mikrotik.apiPass | string | yes | Secure storage; never to browser |

## settings.json

Owner preferences: theme, refresh interval, notification toggles, branding paths.

## state.json

Runtime: last boot, time source, NTP last sync, pending flush flags.

## sales.json — array of

```json
{
  "id": "TXN-000001",
  "timestamp": "2026-08-27T10:42:00+08:00",
  "amount": 10,
  "paymentMethod": "coin",
  "planId": "PLAN-001",
  "durationSeconds": 3600,
  "status": "completed",
  "mac": "AA:BB:CC:DD:EE:FF",
  "apId": "AP-01"
}
```

## sessions.json — array of

```json
{
  "id": "SES-000001",
  "mac": "AA:BB:CC:DD:EE:FF",
  "ip": "192.168.10.21",
  "planId": "PLAN-001",
  "startTime": "2026-08-27T10:42:00+08:00",
  "expirationTime": "2026-08-27T11:42:00+08:00",
  "status": "active",
  "downloadBytes": 0,
  "uploadBytes": 0
}
```

## vouchers.json — array of

| Field | Type | Notes |
|---|---|---|
| code | string | Unique |
| plan | string | Display / plan id |
| duration | string | |
| speed | string | Basic/Standard/Premium/Custom |
| status | string | available \| active \| used \| expired \| disabled |
| created | string | ISO or display |
| used | string | or "—" |

## devices.json / access_points.json / network.json

Caches of last-known MikroTik-derived views for offline Admin display; refresh when LAN API works.

## Relationships

- Sale may reference `planId`, `mac`, `sessionId`  
- Session may reference Hotspot user / MAC on MikroTik  
- Voucher code unique; redeem updates status + creates session  

See repository `data/*.json` for seed examples.
