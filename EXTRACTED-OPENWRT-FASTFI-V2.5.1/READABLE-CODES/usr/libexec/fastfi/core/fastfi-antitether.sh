#!/bin/sh
# FastFi V6 - Anti-Tethering Engine
# Prevents users from bypassing hotspot billing by sharing their connection via mobile hotspot or USB tethering.
#
# How it works:
# Sets outgoing TTL to 1. The paying client's device is the final destination,
# so TTL=1 is fine — it doesn't decrement TTL for locally-destined packets.
# But if the client enables mobile hotspot, forwarded packets get TTL decremented
# from 1 to 0 and are dropped, blocking tethered freeloaders.

ACTION=$1
IFACE="br-lan"

case "$ACTION" in
    enable)
        # 1. Flush existing chains to prevent duplicates
        nft flush chain inet fw4 fastfi_antitether_postrouting 2>/dev/null
        nft flush chain inet fw4 fastfi_antitether_forward 2>/dev/null
        
        # 2. Inject custom chains into fw4
        nft -f - <<EOF
table inet fw4 {
    set hotspot_connlimit_tcp {
        type ipv4_addr
        flags dynamic
    }

    set hotspot_connlimit_all {
        type ipv4_addr
        flags dynamic
    }

    chain fastfi_antitether_postrouting {
        type filter hook postrouting priority mangle; policy accept;
        # Force TTL 1 for all traffic LEAVING the router towards clients.
        # Client receives it fine (local delivery doesn't check TTL).
        # But if client shares via hotspot, the forwarded packet hits TTL=0 and dies.
        oifname "$IFACE" ip ttl set 1
    }

    chain fastfi_antitether_forward {
        type filter hook forward priority filter; policy accept;
        # Connection limits to prevent massive scraping/abuse
        iifname "$IFACE" meta l4proto tcp tcp flags syn add @hotspot_connlimit_tcp { ip saddr ct count over 500 } counter reject with tcp reset
        iifname "$IFACE" add @hotspot_connlimit_all { ip saddr ct count over 1000 } counter reject
    }
}
EOF
        logger -t fastfi "Anti-Tethering Engine ENABLED. (TTL 1 Enforcement)"
        ;;
        
    disable)
        # Delete custom chains entirely
        nft delete chain inet fw4 fastfi_antitether_postrouting 2>/dev/null
        nft delete chain inet fw4 fastfi_antitether_forward 2>/dev/null
        logger -t fastfi "Anti-Tethering Engine DISABLED."
        ;;
        
    status)
        # Check if the postrouting chain exists
        if nft list chain inet fw4 fastfi_antitether_postrouting >/dev/null 2>&1; then
            echo "enabled"
        else
            echo "disabled"
        fi
        ;;
        
    *)
        echo "Usage: $0 {enable|disable|status}"
        exit 1
        ;;
esac
