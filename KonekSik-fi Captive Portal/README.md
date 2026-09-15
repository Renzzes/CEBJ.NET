# KonekSik-fi Captive Portal (FastFi API baseline)

Captive portal **UI** wired to the same CGI API as FastFi OpenWrt
(`EXTRACTED-OPENWRT-FASTFI-V2.5.1/rootfs/www/bootstrap.js`).

**Do not modify the FASTFI / extracted rootfs tree** — it is the immutable baseline.
This package adapts the KonekSik UI to `/cgi-bin/api?action=…` only.

## Quick start

1. Double-click **`preview.bat`**
2. Browser opens `http://127.0.0.1:4180/login.html`

## API

All portal traffic uses FastFi CGI:

`/cgi-bin/api?action=<name>&…`

Core actions: `getMac`, `checkDevice`, `session_status`, `rates`, `list_esp_devices`,
`lockcoin`, `fetchcoin`, `unlockcoin`, `updateDevice`, `clearcredit`, `internet`, `voucher`.

## Working buttons (demo mock API)

| Control | Demo behavior |
|---------|----------------|
| **View Rates** | FastFi-shaped `{ price, minutes, … }` packages |
| **Insert Coin** | `lockcoin` → poll `fetchcoin` (auto ₱1 / ~4s) |
| **Done Paying** | `updateDevice` + `unlockcoin` |
| **Pause / Resume** | `internet&status=0` / `status=1` |
| **Terminate** | Captive: `action=terminate` (self). Admin: `action=client_deauth` |
| **Voucher Connect** | `voucher` — `DEMO5` / `DEMO60` / any code = 15 min |

## Validation

```bat
node validate-fastfi-portal-api.mjs
node validate-terminate.mjs
node validate-captive-portal-checklist.mjs
```

All must print `RESULT: PASS`.

### Captive Portal branding (FastFi admin → portal)

| Item | Behavior |
|------|----------|
| No custom upload | Portal uses **`/image/Default-Banner.png`** |
| Admin upload | Writes `/image/banner.jpg` + marker → portal uses custom |
| Restore Default | Admin **Restore Default** clears custom → default again |
| Music | Admin `/audio/insert.mp3` (coin/success similarly) |
| Admin UI | Two-column: **Portal Configuration** + **Live Preview** (520px scaled mock; banner = local blob only) |

## Files

- `fastfi-cgi.js` — FastFi CGI client (exact action names)
- `renzfi-app.js` / `renzfi-style.css` — UI + FastFi adapter
- `demo-server.mjs` — static files + mock `/cgi-bin/api`
- `login.html` / `status.html` — UI shells
