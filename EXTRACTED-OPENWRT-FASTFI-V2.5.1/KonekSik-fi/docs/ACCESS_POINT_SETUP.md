# Access Point setup

## Physical / logical install

1. Connect AP Ethernet to the hEX (management VLAN / CAP discovery path).  
2. Power the AP.  
3. Put AP on management network (DHCP or static).  
4. Enable **CAP** mode (not standalone router).  
5. Point discovery at CAPsMAN on the hEX.  
6. Provision from CAPsMAN.  
7. Verify AP appears as registered.  
8. Verify 2.4 GHz / 5 GHz radios.  
9. Verify a client can associate.  
10. Confirm Admin → Access Points shows the AP (ESP32 reading MikroTik).  

## Remember

**AP = bridge / access point**  
**hEX = router**  
**ESP32 = application server**

## Dashboard fields (when available)

Identity, model, board, serial, MAC, IP, RouterOS, uptime, CAPsMAN status, CPU, memory, storage, temperature, radio details, clients, derived health, traffic from MikroTik network statistics.

Unavailable values → **Not Available**.

## Related

- [CAPSMAN_SETUP.md](CAPSMAN_SETUP.md)  
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md)  
