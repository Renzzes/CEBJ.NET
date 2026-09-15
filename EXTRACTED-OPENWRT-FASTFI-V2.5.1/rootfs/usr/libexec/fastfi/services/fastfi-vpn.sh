#!/bin/sh
# FastFi OpenVPN Remote Access Client Script (Auto Device-ID Auth)
# Cron: */5 * * * * /root/fastfi-vpn.sh
#
# Zero-touch: device uses its own MAC address as credentials.
# Downloads CA cert from server on first run.

VPN_SERVER="147.93.158.194"
VPN_PORT="1194"

SERVER_URL="https://fastfi.cloud"
DB="/www/data/bindcode.db"
PID_FILE="/var/run/fastfi-vpn.pid"
ENABLED_FLAG="/etc/fastfi_vpn_enabled"
ENROLLED_FLAG="/etc/fastfi_enrolled"

# Guard: Only run if the user has enabled the VPN in the admin panel
if [ ! -f "$ENABLED_FLAG" ] && [ "$1" != "--force" ]; then
    exit 0
fi

logger -t fastfi-vpn "VPN check started (force=$1)"
TOKEN_FILE="/etc/fastfi_remote_token"
AUTH_FILE="/etc/fastfi-vpn-auth.txt"
CA_FILE="/etc/openvpn/fastfi-ca.crt"
CURL_TIMEOUT="--max-time 10"
VPN_HTTP_PORT="${VPN_HTTP_PORT:-80}"

LICENSE_KEY=$(sqlite3 "$DB" "SELECT license_key FROM config WHERE id=1;" 2>/dev/null)
# Retrieve device ID (reflash-stable hardware ID; kept in sync with config.lua
# so VPN auth, telemetry and license flows all use the SAME device_id).
. /usr/libexec/fastfi/core/fastfi-machine-id.sh
MACHINE_ID=$(fastfi_machine_id)

# Guard: abort if MAC address is empty
if [ -z "$MACHINE_ID" ]; then
    logger -t fastfi-vpn "ERROR: Cannot detect a valid MAC address for identity. Aborting."
    exit 1
fi

# Self-healing: auto-install OpenVPN if missing
if ! which openvpn >/dev/null 2>&1; then
    logger -t fastfi-vpn "OpenVPN not installed. Attempting auto-install..."
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        opkg update >/dev/null 2>&1
        opkg install openvpn-openssl >/dev/null 2>&1
        if which openvpn >/dev/null 2>&1; then
            logger -t fastfi-vpn "OpenVPN auto-installed successfully."
        else
            logger -t fastfi-vpn "ERROR: OpenVPN auto-install failed. Will retry next cycle."
            exit 1
        fi
    else
        logger -t fastfi-vpn "No internet — cannot auto-install OpenVPN. Will retry next cycle."
        exit 1
    fi
fi

# Auto-generate VPN auth file from device MAC (username=password=MAC)
echo "$MACHINE_ID" > "$AUTH_FILE"
echo "$MACHINE_ID" >> "$AUTH_FILE"

# Download CA certificate on first run
if [ ! -f "$CA_FILE" ]; then
    curl $CURL_TIMEOUT -s -o "$CA_FILE" "$SERVER_URL/api/v1/admin/vpn/ca"
    if [ ! -s "$CA_FILE" ]; then
        logger -t fastfi-vpn "ERROR: Failed to download CA certificate (attempt 1/3). Retrying..."
        _CA_RETRY_COUNT=1
        while [ $_CA_RETRY_COUNT -lt 3 ]; do
            sleep $((2 ** _CA_RETRY_COUNT))  # exponential backoff: 2s, 4s
            curl $CURL_TIMEOUT -s -o "$CA_FILE" "$SERVER_URL/api/v1/admin/vpn/ca"
            [ -s "$CA_FILE" ] && break
            _CA_RETRY_COUNT=$((${_CA_RETRY_COUNT} + 1))
            logger -t fastfi-vpn "Retrying CA certificate download (attempt ${_CA_RETRY_COUNT}/3)..."
        done
        if [ ! -s "$CA_FILE" ]; then
            rm -f "$CA_FILE"
            logger -t fastfi-vpn "CRITICAL: Could not download CA certificate after 3 attempts"
            exit 1
        fi
    fi
    logger -t fastfi-vpn "Downloaded CA certificate OK"
fi

# Mutex lock to prevent concurrent execution
_LOCK_FILE="/var/run/fastfi-vpn.lock"
exec 9>"$_LOCK_FILE"
if ! flock -n 9; then
    logger -t fastfi-vpn "Another instance is running. Exiting."
    exit 0
fi

# Check if OpenVPN is already running
VPN_RUNNING=0
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    VPN_RUNNING=1
fi

# Get VPN IP from tun0
VPN_IP=$(ip -4 addr show tun0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}')

# Kill stale OpenVPN if PID alive but no tun0 IP
if [ -z "$VPN_IP" ] && [ "$VPN_RUNNING" = "1" ]; then
    logger -t fastfi-vpn "Stale VPN process detected (PID alive, no tun0). Killing."
    kill "$(cat "$PID_FILE")" 2>/dev/null
    sleep 2
    kill -9 "$(cat "$PID_FILE")" 2>/dev/null
    rm -f "$PID_FILE"
    VPN_RUNNING=0
fi

# If no VPN IP, start OpenVPN
if [ -z "$VPN_IP" ] && [ "$VPN_RUNNING" = "0" ]; then
    openvpn --daemon --writepid "$PID_FILE" \
        --client \
        --dev tun \
        --proto udp \
        --remote "$VPN_SERVER" "$VPN_PORT" \
        --resolv-retry infinite \
        --nobind \
        --persist-key \
        --persist-tun \
        --auth-user-pass "$AUTH_FILE" \
        --ca "$CA_FILE" \
        --remote-cert-tls server \
        --cipher AES-256-GCM \
        --auth SHA256 \
        --verb 3 9>&-
    
    # Wait for VPN to establish connection (extended 45s for slow handshakes)
    _VPN_WAIT_COUNT=0
    while [ $_VPN_WAIT_COUNT -lt 45 ]; do
        sleep 1
        VPN_IP=$(ip -4 addr show tun0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}')
        [ -n "$VPN_IP" ] && break
        _VPN_WAIT_COUNT=$((${_VPN_WAIT_COUNT} + 1))
    done
    VPN_IP=$(ip -4 addr show tun0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}')
fi

# VPN is up — send heartbeat or enroll
if [ -n "$VPN_IP" ]; then
    # Add tun0 to LAN firewall zone (if not already configured)
    if ! uci get network.vpntun >/dev/null 2>&1; then
        uci set network.vpntun=interface
        uci set network.vpntun.proto='none'
        uci set network.vpntun.device='tun0'
        uci commit network
        uci add_list firewall.@zone[0].network='vpntun'
        uci commit firewall
        /etc/init.d/network reload >/dev/null 2>&1
        /etc/init.d/firewall restart >/dev/null 2>&1
        # Re-sync sessions because firewall/network reload can drop nodogsplash auth
        (sleep 3 && lua /usr/libexec/fastfi/core/sync-sessions.lua >/dev/null 2>&1) &
        logger -t fastfi-vpn "Added tun0 to LAN firewall zone"
    fi
    
    # Allow HTTP/HTTPS from VPN tunnel
    . /usr/libexec/fastfi/services/fastfi-firewall.sh
    allow_vpn_tunnel
    if [ -f "$ENROLLED_FLAG" ]; then
        # Heartbeat — connected
        curl $CURL_TIMEOUT -s -X POST "$SERVER_URL/api/v1/device/remote-access/heartbeat" \
          -H "Content-Type: application/json" \
          -d "{\"device_id\":\"$MACHINE_ID\",\"license_key\":\"$LICENSE_KEY\",\"vpn_ip\":\"$VPN_IP\",\"vpn_port\":${VPN_HTTP_PORT},\"connected\":true}" > /dev/null 2>&1
    else
        # Need to Enroll for remote access
        if [ -f "$TOKEN_FILE" ]; then
            REMOTE_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null | tr -d '\n\r ')
            if [ -n "$REMOTE_TOKEN" ]; then
                RESPONSE=$(curl $CURL_TIMEOUT -s -X POST "$SERVER_URL/api/v1/device/remote-access/enroll" \
                  -H "Content-Type: application/json" \
                  -d "{\"device_id\":\"$MACHINE_ID\",\"license_key\":\"$LICENSE_KEY\",\"remote_token\":\"$REMOTE_TOKEN\",\"vpn_ip\":\"$VPN_IP\",\"vpn_port\":${VPN_HTTP_PORT},\"tunnel_type\":\"openvpn\"}")

                # Validate JSON response
                if echo "$RESPONSE" | grep -q '"status":"ok"' 2>/dev/null; then
                    SUBDOMAIN=$(echo "$RESPONSE" | sed 's/.*"subdomain":"\([^"]*\)".*/\1/')
                    if [ -n "$SUBDOMAIN" ]; then
                        echo "https://$SUBDOMAIN.fastfi.cloud" > "$ENROLLED_FLAG"
                        rm -f "$TOKEN_FILE"
                        logger -t fastfi-vpn "Enrolled: https://$SUBDOMAIN.fastfi.cloud"
                    else
                        logger -t fastfi-vpn "Enrollment failed: invalid subdomain in response"
                        echo "Invalid subdomain in response" > /tmp/fastfi_enroll_error
                        rm -f "$TOKEN_FILE"
                    fi
                else
                    logger -t fastfi-vpn "Enrollment failed: server returned error. Response: $RESPONSE"
                    echo "$RESPONSE" > /tmp/fastfi_enroll_error
                    rm -f "$TOKEN_FILE"
                fi
            else
                logger -t fastfi-vpn "Enrollment failed: $TOKEN_FILE is empty"
                echo "Token file is empty" > /tmp/fastfi_enroll_error
                rm -f "$TOKEN_FILE"
            fi
        else
            logger -t fastfi-vpn "Cannot enroll: $TOKEN_FILE not found."
        fi
    fi
else
    # VPN is down — send offline heartbeat if enrolled
    if [ -f "$ENROLLED_FLAG" ]; then
        curl $CURL_TIMEOUT -s -X POST "$SERVER_URL/api/v1/device/remote-access/heartbeat" \
          -H "Content-Type: application/json" \
          -d "{\"device_id\":\"$MACHINE_ID\",\"license_key\":\"$LICENSE_KEY\",\"vpn_ip\":\"\",\"vpn_port\":${VPN_HTTP_PORT},\"connected\":false}" > /dev/null 2>&1
    fi
fi

# Release mutex lock
flock -u 9
