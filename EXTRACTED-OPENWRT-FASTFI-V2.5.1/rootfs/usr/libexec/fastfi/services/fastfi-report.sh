#!/bin/sh
# ------------------------------------------
# FastFi OpenWrt Router Telemetry (cron job)
# ------------------------------------------

SERVER_URL="https://fastfi.cloud"
LOCK_FILE="/var/run/fastfi-report.lock"

# Mutex lock to prevent concurrent execution (prevents process piling)
exec 8>"$LOCK_FILE"
if ! flock -n 8; then
    exit 0
fi

# 3. Get OpenWrt Local Database Variables
DB="/www/data/bindcode.db"
SESSIONS_DB="/www/data/sessions.db"
# Get license key (must match the key used during activation)
LICENSE_KEY=$(sqlite3 "$DB" "SELECT license_key FROM config WHERE id=1;" 2>/dev/null)
# If empty, leave it empty so the backend triggers keyless license recovery
[ -z "$LICENSE_KEY" ] && LICENSE_KEY=""

# 3b. Get individual sales since last successful report
LAST_REPORT_ID=$(sqlite3 "$DB" "SELECT COALESCE(last_report_id, 0) FROM config LIMIT 1;" 2>/dev/null)
[ -z "$LAST_REPORT_ID" ] && LAST_REPORT_ID=0

SALES_LOG=$(sqlite3 "$SESSIONS_DB" \
  "SELECT id, amount, coins, created_at, COALESCE(mac_address,'') FROM sales WHERE id > $LAST_REPORT_ID ORDER BY id ASC LIMIT 500;" \
  2>/dev/null | awk -F'|' '{
    if($5!="") printf "{\"amount\":%s,\"coins\":%s,\"timestamp\":\"%s\",\"mac\":\"%s\"},", $2,$3,$4,$5;
    else printf "{\"amount\":%s,\"coins\":%s,\"timestamp\":\"%s\"},", $2,$3,$4
}' | sed 's/,$//')

MAX_REPORTED_ID=$(sqlite3 "$SESSIONS_DB" \
  "SELECT COALESCE(MAX(id), $LAST_REPORT_ID) FROM sales WHERE id > $LAST_REPORT_ID;" 2>/dev/null)
[ -z "$MAX_REPORTED_ID" ] && MAX_REPORTED_ID=$LAST_REPORT_ID

# 4. Get device identity (MACHINE_ID) — reflash-stable hardware ID.
# Sourced helper stays in sync with usr/lib/lua/fastfi/config.lua so the
# shell telemetry and the Lua activate/recover paths send the SAME device_id.
. /usr/libexec/fastfi/core/fastfi-machine-id.sh
MACHINE_ID=$(fastfi_machine_id)
[ -z "$MACHINE_ID" ] && MACHINE_ID="000000000000"

# 5. Get WiFi SSIDs (assumes iface[0]=2.4G iface[1]=5G)
WIFI_2G=$(uci -q get wireless.@wifi-iface[0].ssid)
WIFI_5G=$(uci -q get wireless.@wifi-iface[1].ssid)
[ -z "$WIFI_2G" ] && WIFI_2G="FastFi_2G"
[ -z "$WIFI_5G" ] && WIFI_5G="FastFi_5G"

# 6. Get system uptime
UPTIME=$(cat /proc/uptime | awk '{print int($1)}')

# 7. Get Coin Rates from SQLite and construct JSON array manually
RATES_JSON=$(sqlite3 "$DB" "SELECT price, minutes, download_mb, upload_mb FROM coin_rates;" 2>/dev/null | awk -F'|' '{
    printf "{\"price\":%s,\"minutes\":%s,\"download\":%s,\"upload\":%s},", 
    $1, $2, $3, $4
}' | sed 's/,$//')

# 9. Get WiFi Clients from SQLite and construct JSON array manually
# OpenWrt sqlite3 might output pipe-separated fields depending on the flags
CLIENTS_JSON=$(sqlite3 "$DB" "SELECT mac_address, days, minutes, download_mb, upload_mb, is_paused, is_blocked FROM wifi_clients;" 2>/dev/null | awk -F'|' '{
    printf "{\"mac\":\"%s\",\"days\":%s,\"minutes\":%s,\"download\":%s,\"upload\":%s,\"PauseClient\":\"%s\",\"BlockClient\":\"%s\"},", 
    $1, $2, $3, $4, $5, ($6==1?"Yes":"No"), ($7==1?"Yes":"No")
}' | sed 's/,$//')

# 9b. Get ESP License Keys for verification
ESP_DB="/www/data/esp_coinslot.db"
ESP_KEYS_JSON=""
if [ -f "$ESP_DB" ]; then
    ESP_KEYS_JSON=$(sqlite3 "$ESP_DB" "SELECT license_key FROM esp_licenses;" 2>/dev/null | awk '{printf "\"%s\",", $1}' | sed 's/,$//')
fi

# 10. Get VPN Status
VPN_IP=$(ip -4 addr show tun0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}')
VPN_PORT="${VPN_HTTP_PORT:-80}"
VPN_CONNECTED="false"
[ -n "$VPN_IP" ] && VPN_CONNECTED="true"

# 11. Construct JSON Payload securely without bash injection issues
# Include ESP keys in report for license verification
ESP_KEYS_PART=""
if [ -n "$ESP_KEYS_JSON" ]; then
    ESP_KEYS_PART="\"esp_keys\": [$ESP_KEYS_JSON],"
fi

JSON_PAYLOAD=$(cat <<EOF
{
  "device_id": "$MACHINE_ID",
  "license_key": "$LICENSE_KEY",
  "uptime": $UPTIME,
  "ssidname_24g": "$WIFI_2G",
  "ssidname_5g": "$WIFI_5G",
  $ESP_KEYS_PART
  "vpn_ip": "$VPN_IP",
  "vpn_port": $VPN_PORT,
  "vpn_connected": $VPN_CONNECTED,
  "enrolled": $([ -f "/etc/fastfi_enrolled" ] && echo "true" || echo "false"),
  "sales_log": [$SALES_LOG],
  "coin_rates": [$RATES_JSON],
  "wifi_clients": [$CLIENTS_JSON]
}
EOF
)

# 6. Call API using cURL
API_RESPONSE=$(curl -s --connect-timeout 10 --max-time 30 -X POST "$SERVER_URL/api/v1/device/report" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD")

# 7. Handle server response
STATUS=$(echo "$API_RESPONSE" | grep -o '"status":"[^"]*"' | sed 's/"status":"//;s/"//')

if [ "$STATUS" = "ok" ]; then
    PLAN_CODE=$(echo "$API_RESPONSE" | grep -o '"plan":"[^"]*"' | sed 's/"plan":"//;s/"//')
    # Normal success: advance last_report_id, clean up reported sales, update heartbeat
    sqlite3 "$DB" "UPDATE config SET last_report_id = $MAX_REPORTED_ID WHERE id=1;"
    # Mark reported sales instead of deleting them to preserve local history
    sqlite3 "$SESSIONS_DB" "UPDATE sales SET reported = 1 WHERE id <= $MAX_REPORTED_ID;"
    # Sync expires_at from server response to keep local config up to date
    EXPIRES=$(echo "$API_RESPONSE" | grep -o '"expires_at":"[^"]*"' | sed 's/"expires_at":"//;s/"//')
    if [ -n "$EXPIRES" ]; then
        sqlite3 "$DB" "UPDATE config SET expires_at='$EXPIRES' WHERE id=1;"
    fi
    if [ -n "$PLAN_CODE" ]; then
        sqlite3 "$DB" "UPDATE config SET plan_code='$PLAN_CODE' WHERE id=1;"
    fi
    # Keyless recovery via the 'ok' path: if we reported with no local key
    # (reflash / wiped key) and the cloud returned a bound license_key, persist
    # it + mark active. Some FastFi Cloud builds reply status:'ok' (not
    # 'license_recovery') with the recovered key, so without this the key is
    # dropped and recovery falsely reports "no license bound".
    RECOVERED_KEY=$(echo "$API_RESPONSE" | grep -o '"license_key":"[^"]*"' | sed 's/"license_key":"//;s/"//')
    # Check if license is expired
    EXPIRED=$(echo "$API_RESPONSE" | grep -o '"expired":true')
    if [ -n "$EXPIRED" ]; then
        sqlite3 "$DB" "INSERT OR REPLACE INTO device_status (id, last_heartbeat, last_server_response, last_sync_success) \
            VALUES (1, datetime('now'), 'license_expired', 1);"
        sqlite3 "$DB" "UPDATE config SET license_status='inactive', license_key='', plan_code='', expires_at='' WHERE id=1;"
        echo "WARNING: License has expired (expires_at: $EXPIRES)"
    else
        if [ -z "$LICENSE_KEY" ] && [ -n "$RECOVERED_KEY" ]; then
            sqlite3 "$DB" "UPDATE config SET license_key='$RECOVERED_KEY', license_status='active' WHERE id=1;"
            echo "License key recovered (status=ok): $RECOVERED_KEY (expires: $EXPIRES)."
        fi
        sqlite3 "$DB" "INSERT OR REPLACE INTO device_status (id, last_heartbeat, last_server_response, last_sync_success) \
            VALUES (1, datetime('now'), 'ok', 1);"
    fi
    
    # Update ESP license status from server response
    if [ -f "$ESP_DB" ]; then
        echo "$API_RESPONSE" | sed -e 's/[[:space:]]//g' -e 's/},{/}\n{/g' | grep '"license_key":"ESP-' | while IFS= read -r ITEM; do
            ESP_KEY=$(echo "$ITEM" | grep -o '"license_key":"ESP-[^"]*"' | cut -d'"' -f4)
            ESP_STATUS=$(echo "$ITEM" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
            ESP_EXPIRES=$(echo "$ITEM" | grep -o '"expires_at":"[^"]*"' | cut -d'"' -f4)
            [ -z "$ESP_KEY" ] && continue
            
            # Map server status to local
            LOCAL_STATUS="used"
            [ "$ESP_STATUS" = "unused" ] && LOCAL_STATUS="available"
            [ "$ESP_STATUS" = "not_bound" ] && LOCAL_STATUS="available"
            [ "$ESP_STATUS" = "expired" ] && LOCAL_STATUS="expired"
            [ "$ESP_STATUS" = "revoked" ] && LOCAL_STATUS="revoked"
            [ "$ESP_STATUS" = "invalid" ] && LOCAL_STATUS="invalid"
            
            if [ -n "$ESP_EXPIRES" ]; then
                sqlite3 "$ESP_DB" "UPDATE esp_licenses SET status='$LOCAL_STATUS', expires_at='$ESP_EXPIRES' WHERE license_key='$ESP_KEY';"
            else
                sqlite3 "$ESP_DB" "UPDATE esp_licenses SET status='$LOCAL_STATUS' WHERE license_key='$ESP_KEY';"
            fi
            
            if [ "$LOCAL_STATUS" = "invalid" ] || [ "$LOCAL_STATUS" = "revoked" ] || [ "$LOCAL_STATUS" = "available" ]; then
                sqlite3 "$ESP_DB" "UPDATE esp_licenses SET used_slot_id=NULL, used_at=NULL WHERE license_key='$ESP_KEY';"
                sqlite3 "$ESP_DB" "UPDATE esp_slots SET license_status='unlicensed', license_key=NULL WHERE license_key='$ESP_KEY';"
            else
                sqlite3 "$ESP_DB" "UPDATE esp_slots SET license_status='$LOCAL_STATUS' WHERE license_key='$ESP_KEY';"
            fi
            echo "ESP license verified: $ESP_KEY → $ESP_STATUS (local: $LOCAL_STATUS)"
        done
    fi

elif [ "$STATUS" = "license_recovery" ]; then
    PLAN_CODE=$(echo "$API_RESPONSE" | grep -o '"plan":"[^"]*"' | sed 's/"plan":"//;s/"//')
    # Reflashed device: report was accepted AND server returned bound license key + expiry
    # Treat same as ok (advance sales, clean up) + save recovered key locally
    sqlite3 "$DB" "UPDATE config SET last_report_id = $MAX_REPORTED_ID WHERE id=1;"
    sqlite3 "$SESSIONS_DB" "DELETE FROM sales WHERE id <= $MAX_REPORTED_ID;"
    RECOVERED_KEY=$(echo "$API_RESPONSE" | grep -o '"license_key":"[^"]*"' | sed 's/"license_key":"//;s/"//')
    RECOVERED_EXPIRES=$(echo "$API_RESPONSE" | grep -o '"expires_at":"[^"]*"' | sed 's/"expires_at":"//;s/"//')
    if [ -n "$RECOVERED_KEY" ]; then
        sqlite3 "$DB" "UPDATE config SET license_key='$RECOVERED_KEY' WHERE id=1;"
        if [ -n "$RECOVERED_EXPIRES" ]; then
            sqlite3 "$DB" "UPDATE config SET expires_at='$RECOVERED_EXPIRES' WHERE id=1;"
        fi
        if [ -n "$PLAN_CODE" ]; then
            sqlite3 "$DB" "UPDATE config SET plan_code='$PLAN_CODE' WHERE id=1;"
        fi
        echo "License key recovered: $RECOVERED_KEY (expires: $RECOVERED_EXPIRES)."
    fi
    EXPIRED=$(echo "$API_RESPONSE" | grep -o '"expired":true')
    if [ -n "$EXPIRED" ]; then
        sqlite3 "$DB" "INSERT OR REPLACE INTO device_status (id, last_heartbeat, last_server_response, last_sync_success) \
            VALUES (1, datetime('now'), 'license_recovered_expired', 1);"
        sqlite3 "$DB" "UPDATE config SET license_status='inactive' WHERE id=1;"
        echo "WARNING: Recovered license has expired."
    else
        # A successfully recovered (non-expired) license is immediately usable.
        sqlite3 "$DB" "UPDATE config SET license_status='active' WHERE id=1;"
        sqlite3 "$DB" "INSERT OR REPLACE INTO device_status (id, last_heartbeat, last_server_response, last_sync_success) \
            VALUES (1, datetime('now'), 'license_recovered', 1);"
    fi

else
    # Error: save the response so the web UI can display it
    ERR=$(echo "$API_RESPONSE" | sed "s/'/''/g")
    sqlite3 "$DB" "INSERT OR REPLACE INTO device_status (id, last_heartbeat, last_server_response, last_sync_success) \
        VALUES (1, datetime('now'), '$ERR', 0);"

    # Check for hard validation revocation (only EXPLICIT server-side block/revoke)
    # Do NOT revoke on "Invalid license key" — this can happen transiently when
    # server hasn't synced device binding, or during network issues.
    if echo "$API_RESPONSE" | grep -q 'Device is blocked\|revoked'; then
        sqlite3 "$DB" "UPDATE config SET license_status='inactive', license_key='', plan_code='', expires_at='' WHERE id=1;"
        echo "WARNING: API explicitly revoked local device access due to blocking/revocation."
    elif echo "$API_RESPONSE" | grep -q '"code":"device_mismatch"\|"code":"invalid_key"'; then
        # The local key is hopelessly wrong (doesn't exist, or bound to someone else)
        # Wipe the local key so the NEXT heartbeat triggers keyless auto-recovery!
        sqlite3 "$DB" "UPDATE config SET license_key='' WHERE id=1;"
        echo "WARNING: Local license key is invalid/mismatched. Wiping local key to trigger auto-recovery on next heartbeat."
    else
        echo "Report failed but license preserved locally. Server said: $API_RESPONSE"
    fi
fi

# 8. Output result
echo "$API_RESPONSE"

# ══════════════════════════════════════════════════════
# 9. ESP Coinslot Auto-Recovery
# ══════════════════════════════════════════════════════
# Rebuild the local ESP license DB (e.g. after a reflash) from `esp_children`,
# which the cloud returns in THIS script's own already-authenticated report —
# no extra HTTP call, no second credential.
#
# This replaces a per-slot loop that POSTed /report with only the coinslot's MAC
# and no license_key. That was unauthenticated "keyless recovery", which the
# cloud stopped honouring once it began requiring device_secret, so it could
# never succeed again. Worse, its loop condition was `license_status !=
# 'licensed'` and the only thing that sets 'licensed' is a successful recovery —
# so every failure re-armed the retry and each unlicensed slot re-POSTed every
# time cron ran this script, forever. That single loop produced ~99% of all
# auth_failed events reaching the cloud (~36k/day across the fleet) while never
# licensing a single coinslot.
#
# The coinslot MAC was also the wrong identity to send: slot_mac comes from the
# ESP's WiFi.macAddress() (colon-separated), whereas every FastFi device_id is
# colon-stripped, so those requests could never match a device row either.
#
# Note esp_children is only returned when the cloud recovers the ROUTER's own
# key (the reflash case this block exists for). In steady state an unlicensed
# slot is licensed by the operator entering its key in the admin panel, which
# goes through routes/esp_license.lua and is authenticated.

ESP_DB="/www/data/esp_coinslot.db"

if [ -f "$ESP_DB" ]; then
    # Pull the "esp_children":[...] array out of our own report response, then
    # emit one license_key per line. Keeps the grep/sed style used above rather
    # than adding a jq dependency to this script.
    # [^]]* not .* — the response also carries an "esp_licenses" array AFTER this
    # one, whose entries include license_key values with status invalid/revoked/
    # not_bound. A greedy .* would run to the LAST ']' in the body, swallow both
    # arrays, and license slots with rejected keys. Stopping at the first ']' is
    # safe because no esp_children value contains a bracket.
    ESP_CHILDREN=$(echo "$API_RESPONSE" | sed -n 's/.*"esp_children":\[\([^]]*\)\].*/\1/p')

    if [ -n "$ESP_CHILDREN" ]; then
        ESP_ROUTER_MAC=$(cat /sys/class/net/eth0/address 2>/dev/null | tr -d ':' | tr '[:lower:]' '[:upper:]')
        [ -z "$ESP_ROUTER_MAC" ] && ESP_ROUTER_MAC="$MACHINE_ID"

        echo "$ESP_CHILDREN" | grep -o '"license_key":"[^"]*"' | cut -d'"' -f4 | while read -r ESP_KEY; do
            [ -z "$ESP_KEY" ] && continue

            # Claim the lowest-numbered slot that still needs a key. Bound the
            # work: if no slot needs one, there is nothing to restore.
            SLOT_ID=$(sqlite3 "$ESP_DB" \
              "SELECT id FROM esp_slots WHERE license_status != 'licensed' ORDER BY id LIMIT 1;" 2>/dev/null)
            [ -z "$SLOT_ID" ] && continue

            EXISTS=$(sqlite3 "$ESP_DB" "SELECT id FROM esp_licenses WHERE license_key='$ESP_KEY';" 2>/dev/null)
            if [ -z "$EXISTS" ]; then
                sqlite3 "$ESP_DB" "INSERT INTO esp_licenses (license_key, status, router_mac, used_slot_id, used_at) \
                    VALUES ('$ESP_KEY', 'used', '$ESP_ROUTER_MAC', $SLOT_ID, datetime('now'));" 2>/dev/null
            fi
            sqlite3 "$ESP_DB" "UPDATE esp_slots SET license_status='licensed', license_key='$ESP_KEY' WHERE id=$SLOT_ID;" 2>/dev/null
            echo "ESP restored from esp_children: slot $SLOT_ID → $ESP_KEY"
        done
    fi
fi

# Response reference:
# Success:          {"status":"ok","message":"Report received","device_id":"...","expires_at":"2027-03-03 10:00:00","plan":"pro","plan_name":"Pro Plan","routing_tier":"premium","monitoring_dashboard":true,"remote_device_access":true,"plan_entitlements_active":true}
# Expired:          {"status":"ok","message":"Report received","device_id":"...","expires_at":"2025-01-01 00:00:00","expired":true,"plan":"lite","plan_name":"Lite Plan","routing_tier":"basic","monitoring_dashboard":false,"remote_device_access":false,"plan_entitlements_active":false}
# License recovery: {"status":"license_recovery","message":"Report received","device_id":"...","license_key":"STD-XXXX-XXXX-XXXX-XXXX","expires_at":"...","plan":"standard","plan_name":"Standard Plan","routing_tier":"advanced","monitoring_dashboard":true,"remote_device_access":false,"plan_entitlements_active":true}
# ESP recovery:     {"status":"license_recovery","message":"Report received","device_id":"ESP_MAC","license_key":"ESP-XXXX-XXXX-XXXX-XXXX","expires_at":"...","plan":"esp","plan_name":"ESP Plan","routing_tier":"basic","monitoring_dashboard":false,"remote_device_access":false,"plan_entitlements_active":true}
# Errors:           {"error":"license_key required"}
#                   {"error":"Invalid license key \"XXXX\" for device \"...\""}
#                   {"error":"Device is blocked"}