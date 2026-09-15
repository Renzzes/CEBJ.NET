#!/bin/sh
# FastFi V6 Time Synchronization Service
# Ensures the router clock is synced to internet time at boot.

logger -t fastfi-timesync "Service started. Waiting for WAN..."

# 1. Wait for WAN IP (max 60 seconds)
WAIT=0
while [ $WAIT -lt 20 ]; do
    WAN_IP=$(ubus call network.interface.wan status 2>/dev/null | grep -oE '"address": "[0-9.]+"' | cut -d'"' -f4)
    if [ -n "$WAN_IP" ]; then
        logger -t fastfi-timesync "WAN IP detected: $WAN_IP"
        break
    fi
    sleep 3
    WAIT=$((WAIT + 1))
done

# 2. Force NTP Sync
logger -t fastfi-timesync "Attempting internet time sync..."

# List of reliable NTP servers
SERVERS="time.google.com time.cloudflare.com pool.ntp.org"

SYNC_SUCCESS=0
for SERVER in $SERVERS; do
    logger -t fastfi-timesync "Trying $SERVER..."
    # Use ntpd -q -n -p to sync once and exit
    if ntpd -q -n -p "$SERVER" >/dev/null 2>&1; then
        logger -t fastfi-timesync "Clock synced successfully with $SERVER"
        SYNC_SUCCESS=1
        break
    fi
done

# 3. Final verification and flag creation
NOW=$(date +%s)
if [ "$NOW" -gt 1704067200 ]; then # Jan 1 2024
    logger -t fastfi-timesync "System time verified: $(date)"
    touch /tmp/fastfi_time_ready
else
    logger -t fastfi-timesync "Failed to sync time. System clock still at $(date). Other services will wait."
fi

exit 0
