# Troubleshooting

## Dashboard unavailable

Check:

1. ESP32 power  
2. Ethernet link  
3. IP address (DHCP lease / static)  
4. Management VLAN / laptop IP  
5. Web server running (serial logs)  

## Internet offline (Admin still works)

Check:

1. WAN cable / modem  
2. PPPoE credentials (Admin → Internet)  
3. ISP outage  
4. Gateway / DNS  

Local Admin, sales, and coin should continue if ESP32 + LAN are up.

## AP offline

Check:

1. AP power and Ethernet  
2. Management VLAN  
3. CAPsMAN registration  
4. RouterOS on AP  

Other APs and Admin continue.

## MikroTik unavailable

Check:

1. ESP32 ↔ hEX LAN path  
2. API enabled and allowed by firewall  
3. Credentials on ESP32  
4. Management VLAN  

Admin on ESP32 stays up; network pages show MikroTik offline.

## Coin / session issues

Check ESP32 hardware wiring, rate config, and whether MikroTik Hotspot accepted the allow request.

## Time wrong / sessions expire oddly

Check time source (NTP vs RTC/local). Do not trust silent NTP when Internet is down. See [RECOVERY.md](RECOVERY.md).
