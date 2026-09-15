#!/bin/sh
# FastFi V6 - NDS Re-Authentication After Service Reload
# Waits for NDS to be fully running AND for clients to be detected,
# then deauth+auth all connected clients to restore internet access.
# Called from ops.lua after wifi/network/firewall reloads.

logger -t fastfi "nds-reauth: Waiting for NDS to be ready..."

# Phase 1: Wait for NDS process to be running (max 30s)
WAIT=0
while [ $WAIT -lt 30 ]; do
    if pidof nodogsplash >/dev/null 2>&1; then
        # Check if ndsctl is also responding
        if ndsctl status >/dev/null 2>&1; then
            break
        fi
    fi
    sleep 2
    WAIT=$((WAIT + 2))
done

if ! pidof nodogsplash >/dev/null 2>&1; then
    logger -t fastfi "nds-reauth: NDS not running after 30s, aborting"
    exit 1
fi

# Phase 2: Wait for NDS to finish initializing firewall rules
# AND for at least one client to appear in ARP on br-lan (max 30s)
WAIT=0
while [ $WAIT -lt 30 ]; do
    # Check NDS is accepting commands
    if ndsctl status >/dev/null 2>&1; then
        # Check if any clients are on the nodogsplash gateway interface
        NDS_IFACE="br-lan"
        CLIENT_COUNT=$(cat /proc/net/arp | grep "$NDS_IFACE" | grep -v "00:00:00:00:00:00" | wc -l)
        if [ "$CLIENT_COUNT" -gt 0 ]; then
            # Give NDS 3 more seconds to finish "Adding" all clients
            sleep 3
            break
        fi
    fi
    sleep 1
    WAIT=$((WAIT + 1))
done

logger -t fastfi "nds-reauth: NDS ready after ${WAIT}s. Re-authenticating all clients..."

# Phase 3: Restore sessions from DB (more reliable than re-authing everyone)
# This ensures Bug 2: paid sessions are restored correctly and free riders are blocked
/usr/bin/env lua /usr/libexec/fastfi/core/sync-sessions.lua >/dev/null 2>&1

# Phase 4: Ensure Anti-Hotspot is active if enabled
if [ -f "/usr/libexec/fastfi/core/fastfi-antitether.sh" ]; then
    /usr/libexec/fastfi/core/fastfi-antitether.sh enable >/dev/null 2>&1
    logger -t fastfi "nds-reauth: Anti-hotspot rules reapplied"
fi

logger -t fastfi "nds-reauth: Complete."
