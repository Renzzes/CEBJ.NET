# ESP32-S3-ETH firmware

Application + controller firmware for KonekSik-fi.

## Layout

```text
firmware/
├── README.md          (this file)
├── CMakeLists.txt     (ESP-IDF root — add when initializing IDF project)
├── main/              # app entry, web server glue
├── hardware/          # coin, display, relays, sensors
├── networking/        # Ethernet, IP, mDNS optional
├── mikrotik/          # RouterOS API client (secrets stay here)
├── storage/           # JSON persist, atomic writes
├── api/               # HTTP /api/* handlers
├── auth/              # Admin login, sessions
├── ota/               # OTA validate + install
└── system/            # time, reboot, health, logs
```

## Phases

See root [README.md](../README.md). Start with Ethernet + HTTP + static Admin assets from repository root (`index.html`, `css/`, `js/`, `public/`).

## Rules

- Browser never receives MikroTik / PPPoE secrets  
- Local Admin works offline  
- Persist sales before acknowledging success  
- Prefer lightweight embedded HTTP; no large frameworks on device  
