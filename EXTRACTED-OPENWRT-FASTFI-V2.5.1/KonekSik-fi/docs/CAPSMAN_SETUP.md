# CAPsMAN setup

CAPsMAN is the **AP management layer** on the hEX. It is not the Internet router and not the KonekSik-fi Admin.

## Concept

```
MikroTik hEX Refresh
        │
      CAPsMAN
        │
   ┌────┼────┐
   ▼    ▼    ▼
 AP-01 AP-02 AP-03   (CAP mode)
```

## Technician steps (summary)

1. Enable CAPsMAN on the hEX (management network).  
2. Put each AP in **CAP** mode; discover controller.  
3. Provision 2.4 / 5 GHz configurations.  
4. Verify registration, radios, and clients.  

## What Admin shows (via ESP32 → MikroTik)

```
CAPsMAN
Status ● Connected
Controller 192.168.20.1
```

Per AP:

```
CAPsMAN ● Connected
Connected Since …   (derived from duration + clock when possible)
Connection Duration …
```

## Rules

- AP = bridge/access point, **not** router  
- Do not invent radio/client fields; use **Not Available** when MikroTik does not provide them  
- Traffic accounting comes from MikroTik network/hotspot/session stats, not “CAPsMAN full client accounting”  

## Related

- [ACCESS_POINT_SETUP.md](ACCESS_POINT_SETUP.md)  
- [MIKROTIK_SETUP.md](MIKROTIK_SETUP.md)  
