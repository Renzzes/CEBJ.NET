# Authentication

## Requirements

- Local Admin login works **without Internet**  
- No external IdP  
- Dashboard not usable without login  

## Login

```
Username / Password → ESP32 validates → session issued → Admin shell
```

Prototype UI currently uses client-side check (`admin` / `admin`). Production must move verification to ESP32 with hashed passwords.

## Session

- Server-side session or signed token  
- Idle expiration (owner-configurable)  
- Logout clears session  
- Failed login lockout / rate limit  

## Password storage

- Never store Admin password in plain text on flash  
- Prefer salted hash (e.g. PBKDF2 / Argon2 where feasible on ESP32)  
- Change password from Settings  

## Secrets never sent to browser

- MikroTik API password  
- PPPoE password  
- VPN private keys  

## Recovery

Lost Admin password: documented technician recovery (serial/factory recovery account). See [RECOVERY.md](RECOVERY.md).
