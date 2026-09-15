#!/bin/sh

# FastFi Remote Access Heartbeat Script

SERVER_URL="https://fastfi.cloud"
DB="/www/data/bindcode.db"
ENROLL_FILE="/etc/fastfi_enrolled"
LOCK_FILE="/var/run/fastfi-heartbeat.lock"

# Mutex lock to prevent concurrent execution
exec 8>"$LOCK_FILE"
if ! flock -n 8; then
    exit 0
fi

# Check if enrolled
if [ ! -f "$ENROLL_FILE" ]; then
    exit 0
fi

# Get device identity (reflash-stable hardware ID; in sync with config.lua)
. /usr/libexec/fastfi/core/fastfi-machine-id.sh
MACHINE_ID=$(fastfi_machine_id)

LICENSE_KEY=$(sqlite3 "$DB" "SELECT license_key FROM config WHERE id=1;" 2>/dev/null)

if [ -z "$LICENSE_KEY" ] || [ -z "$MACHINE_ID" ]; then
    exit 1
fi

# Get VPN IP
VPN_IP=$(ip -4 addr show tun0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}')

if [ -n "$VPN_IP" ]; then
    # Send heartbeat - online
    curl -s --max-time 10 -X POST "$SERVER_URL/api/v1/device/remote-access/heartbeat" \
        -H "Content-Type: application/json" \
        -d "{\"device_id\":\"$MACHINE_ID\",\"license_key\":\"$LICENSE_KEY\",\"vpn_ip\":\"$VPN_IP\",\"vpn_port\":80,\"connected\":true}" \
        > /dev/null 2>&1
else
    # VPN not connected - send offline heartbeat (keep enrollment alive)
    curl -s --max-time 10 -X POST "$SERVER_URL/api/v1/device/remote-access/heartbeat" \
        -H "Content-Type: application/json" \
        -d "{\"device_id\":\"$MACHINE_ID\",\"license_key\":\"$LICENSE_KEY\",\"connected\":false}" \
        > /dev/null 2>&1
    # Note: Don't remove enrollment file on VPN down - only remove on explicit logout
fi
