#!/bin/sh
# ------------------------------------------
# FastFi OpenWrt Device Activation (run once)
# ------------------------------------------

SERVER_URL="https://fastfi.cloud"
DB="/www/data/bindcode.db"

# 1. Get license key from local database
LICENSE_KEY=$(sqlite3 "$DB" "SELECT license_key FROM config WHERE id=1;" 2>/dev/null)
if [ -z "$LICENSE_KEY" ]; then
    echo "ERROR: No license_key found in $DB"
    exit 1
fi

# 2. Get device identity (reflash-stable hardware ID; in sync with config.lua)
. /usr/libexec/fastfi/core/fastfi-machine-id.sh
MACHINE_ID=$(fastfi_machine_id)
[ -z "$MACHINE_ID" ] && MACHINE_ID="000000000000"

# 3. Activate device with FastFi server
RESPONSE=$(curl -s -X POST "$SERVER_URL/api/v1/device/activate" \
  -H "Content-Type: application/json" \
  -d "{\"license_key\":\"$LICENSE_KEY\",\"device_id\":\"$MACHINE_ID\"}")

echo "$RESPONSE"

# 4. Save activation result to local DB so the device UI can show status
STATUS=$(echo "$RESPONSE" | grep -o '"status":"ok"')
if [ -n "$STATUS" ]; then
    # Extract expires_at from response (e.g. "expires_at":"2027-03-03 10:00:00")
    EXPIRES=$(echo "$RESPONSE" | sed 's/.*"expires_at":"\([^"]*\)".*/\1/')
    PLAN_CODE=$(echo "$RESPONSE" | sed 's/.*"plan":"\([^"]*\)".*/\1/')

    # Save expires_at to config table so your web UI can show the expiry date
    if [ -n "$EXPIRES" ] && [ "$EXPIRES" != "$RESPONSE" ]; then
        EXPIRES_SAFE=$(echo "$EXPIRES" | sed "s/'/''/g")
        sqlite3 "$DB" "UPDATE config SET expires_at = '$EXPIRES_SAFE' WHERE id = 1;"
        echo "License expires at: $EXPIRES"
    fi
    if [ -n "$PLAN_CODE" ] && [ "$PLAN_CODE" != "$RESPONSE" ]; then
        PLAN_CODE_SAFE=$(echo "$PLAN_CODE" | sed "s/'/''/g")
        sqlite3 "$DB" "UPDATE config SET plan_code = '$PLAN_CODE_SAFE' WHERE id = 1;"
        echo "Assigned plan: $PLAN_CODE"
    fi

    # Mark device as active — your web UI can read device_status to show "active"
    sqlite3 "$DB" "INSERT OR REPLACE INTO device_status (id, last_heartbeat, last_server_response, last_sync_success) \
        VALUES (1, datetime('now'), 'activated', 1);"
    # Unlock the hotspot by setting license_status to active
    sqlite3 "$DB" "UPDATE config SET license_status='active' WHERE id=1;"
    echo "Activation successful. Status saved to local DB."
else
    # Save the error response so your web UI can display it
    ERR=$(echo "$RESPONSE" | sed "s/'/''/g")
    sqlite3 "$DB" "INSERT OR REPLACE INTO device_status (id, last_heartbeat, last_server_response, last_sync_success) \
        VALUES (1, datetime('now'), '$ERR', 0);"
    echo "Activation failed. Check device_status table for details."
fi

# Response reference:
# Success: {"status":"ok","message":"Device activated successfully","device_id":"...","device_status":"approved","expires_at":"2027-03-03 10:00:00"}
# Errors:  {"error":"Invalid license key"}
#          {"error":"License key has already been used"}
#          {"error":"Device is blocked"}
