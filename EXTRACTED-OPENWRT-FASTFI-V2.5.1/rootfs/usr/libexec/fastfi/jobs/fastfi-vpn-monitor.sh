#!/bin/sh
# FastFi VPN Health Monitor
# Continuously monitors OpenVPN tunnel health
# Restarts VPN if it goes down for more than 2 minutes
# Add to cron: */1 * * * * /root/fastfi-vpn-monitor.sh >/dev/null 2>&1

LOCK_FILE="/var/run/fastfi-vpn-monitor.lock"
VPN_DOWN_FILE="/tmp/vpn_down_timestamp"
MAX_DOWN_TIME=60  # Seconds (1 minute)
PROCESS_NAME="openvpn"
TUNNEL_DEVICE="tun0"

# Prevent concurrent executions
exec 8>"$LOCK_FILE"
if ! flock -n 8; then
    exit 0
fi

# Function to check VPN status
check_vpn_status() {
    # Check 1: Is OpenVPN process running?
    if ! pgrep "$PROCESS_NAME" >/dev/null 2>&1; then
        return 1  # Process dead
    fi
    
    # Check 2: Does tunnel device have IP?
    VPN_IP=$(ip -4 addr show "$TUNNEL_DEVICE" 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}')
    if [ -z "$VPN_IP" ]; then
        return 1  # No tunnel IP
    fi
    
    # Check 3: Strictly verify the OpenVPN Server Gateway is natively reachable
    # We ping the tunnel subnet server (10.8.0.1) instead of ourselves
    if ! ping -c 1 -W 2 "10.8.0.1" >/dev/null 2>&1; then
        return 1  # Server gateway disconnected or unresponsive
    fi
    
    return 0  # All checks passed
}

# Main monitoring logic
if check_vpn_status; then
    # VPN is UP
    # Clear the down timestamp if it was recorded
    if [ -f "$VPN_DOWN_FILE" ]; then
        rm -f "$VPN_DOWN_FILE"
        logger -t fastfi-vpn-monitor "VPN restored - tunnel is healthy"
    fi
else
    # VPN is DOWN
    CURRENT_TIME=$(date +%s)
    
    if [ ! -f "$VPN_DOWN_FILE" ]; then
        # First detection of downtime
        echo "$CURRENT_TIME" > "$VPN_DOWN_FILE"
        logger -t fastfi-vpn-monitor "VPN DOWN detected - monitoring"
    else
        # Get when downtime started
        DOWN_SINCE=$(cat "$VPN_DOWN_FILE" 2>/dev/null)
        if [ -z "$DOWN_SINCE" ]; then
            DOWN_SINCE=$CURRENT_TIME
            echo "$DOWN_SINCE" > "$VPN_DOWN_FILE"
        fi
        
        # Calculate how long it's been down
        DOWN_DURATION=$((CURRENT_TIME - DOWN_SINCE))
        
        if [ $DOWN_DURATION -gt $MAX_DOWN_TIME ]; then
            # Been down too long, restart VPN
            logger -t fastfi-vpn-monitor "VPN down for ${DOWN_DURATION}s - restarting"
            
            # Kill any stale processes
            killall -9 openvpn 2>/dev/null
            sleep 2
            
            # Restart VPN
            if [ -x "/usr/libexec/fastfi/services/fastfi-vpn.sh" ]; then
                /usr/libexec/fastfi/services/fastfi-vpn.sh >/dev/null 2>&1
                logger -t fastfi-vpn-monitor "VPN restart initiated (/usr/libexec/fastfi/services/fastfi-vpn.sh)"
            else
                logger -t fastfi-vpn-monitor "ERROR: VPN restart script not found!"
            fi
            
            # Clear the downtime marker
            rm -f "$VPN_DOWN_FILE"
        else
            logger -t fastfi-vpn-monitor "VPN down for ${DOWN_DURATION}s (threshold: ${MAX_DOWN_TIME}s)"
        fi
    fi
fi

# Release lock
flock -u 8

exit 0
