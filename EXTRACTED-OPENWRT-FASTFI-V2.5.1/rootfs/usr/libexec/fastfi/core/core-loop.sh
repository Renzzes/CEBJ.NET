#!/bin/sh
# FastFi V6 Core Controller Loop
# Main monitoring and management daemon with Self-Healing v2

# Database Initialization (Run once at boot)
(
    logger -t fastfi "Database initialization started..."
    /usr/bin/env lua -e 'require("fastfi.db.init").init()'
    touch /tmp/fastfi_db_ready
    logger -t fastfi "Database initialization complete."
) &

# Time Synchronization (Run in background to avoid blocking boot)
chmod +x /usr/libexec/fastfi/services/fastfi-timesync.sh 2>/dev/null
(/usr/libexec/fastfi/services/fastfi-timesync.sh >/dev/null 2>&1) &

# One-time permission enforcement on boot
chmod +x /www/cgi-bin/* 2>/dev/null
chmod +x /usr/libexec/fastfi/core/*.sh 2>/dev/null
chmod +x /usr/libexec/fastfi/services/*.sh 2>/dev/null
chmod +x /usr/libexec/fastfi/jobs/*.sh 2>/dev/null

# Restore ESP network configs if ESP WiFi was previously configured
# This self-heals after sysupgrade or overlay wipes
ESP_SSID=$(uci -q get wireless.esp_radio0.ssid 2>/dev/null)
if [ -n "$ESP_SSID" ]; then
    NEED_RELOAD=0

    # Ensure network.espnet exists
    if [ -z "$(uci -q get network.espnet 2>/dev/null)" ]; then
        logger -t fastfi "Boot: Restoring missing network.espnet config"
        uci set network.espnet=interface
        uci set network.espnet.proto='static'
        uci set network.espnet.ipaddr='10.0.1.1'
        uci set network.espnet.netmask='255.255.255.0'
        uci commit network 2>/dev/null
        NEED_RELOAD=1
    fi

    # Ensure dhcp.espnet exists (dnsmasq DHCP pool)
    if [ -z "$(uci -q get dhcp.espnet 2>/dev/null)" ]; then
        logger -t fastfi "Boot: Restoring missing dhcp.espnet config"
        uci set dhcp.espnet=dhcp
        uci set dhcp.espnet.interface='espnet'
        uci set dhcp.espnet.start='100'
        uci set dhcp.espnet.limit='150'
        uci set dhcp.espnet.leasetime='12h'
        uci commit dhcp 2>/dev/null
        NEED_RELOAD=1
    fi

    # Ensure firewall.espzone exists
    if [ -z "$(uci -q get firewall.espzone 2>/dev/null)" ]; then
        logger -t fastfi "Boot: Restoring missing firewall.espzone config"
        uci set firewall.espzone=zone
        uci set firewall.espzone.name='espnet'
        uci set firewall.espzone.network='espnet'
        uci set firewall.espzone.input='ACCEPT'
        uci set firewall.espzone.output='ACCEPT'
        uci set firewall.espzone.forward='REJECT'
        uci set firewall.espfwd=forwarding
        uci set firewall.espfwd.src='espnet'
        uci set firewall.espfwd.dest='wan'
        uci commit firewall 2>/dev/null
        NEED_RELOAD=1
    fi

    if [ "$NEED_RELOAD" = "1" ]; then
        logger -t fastfi "Boot: Reloading services after ESP config restoration"
        /etc/init.d/network reload >/dev/null 2>&1
        /etc/init.d/firewall reload >/dev/null 2>&1
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
    fi
fi

# Function to restore all active sessions and shaper rules
restore_all_sessions() {
    logger -t fastfi "Restoring all active sessions and shaper rules..."
    /usr/bin/env lua /usr/libexec/fastfi/core/sync-sessions.lua >/dev/null 2>&1
}

# =========================================================
# CRITICAL: WAN-Aware Boot Restoration
# We wait for BOTH Nodogsplash (fully functional) and WAN
# =========================================================
logger -t fastfi "Boot: Waiting for services and connectivity..."
BOOT_WAIT=0
REPORT_SENT=0
while true; do
    NDS_UP=0
    WAN_UP=0
    
    # Check NDS is FUNCTIONAL (not just PID alive — must respond to ndsctl)
    ndsctl status >/dev/null 2>&1 && NDS_UP=1
    # Check for valid WAN IP via ubus
    ubus call network.interface.wan status 2>/dev/null | grep -q '"up": true' && WAN_UP=1
    
    # License recovery only needs WAN, not nodogsplash
    if [ "$WAN_UP" = "1" ] && [ "$REPORT_SENT" = "0" ]; then
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            logger -t fastfi "Boot: WAN connectivity confirmed. Triggering license sync."
            (/usr/libexec/fastfi/services/fastfi-report.sh >> /tmp/report.log 2>&1) &
            REPORT_SENT=1
        fi
    fi
    
    # Break when both WAN and NDS are FUNCTIONAL, or on timeout
    if [ "$NDS_UP" = "1" ] && [ "$WAN_UP" = "1" ]; then
        logger -t fastfi "Boot: NDS functional + WAN up. Ready."
        break
    fi
    
    sleep 3
    BOOT_WAIT=$((BOOT_WAIT + 1))
    
    # After 20 attempts (~60s), proceed anyway
    if [ "$BOOT_WAIT" -ge 20 ]; then
        logger -t fastfi "Boot: Timeout reached. Proceeding with available services."
        break
    fi
done

# Wait for NDS to accept auth commands (ndsctl status OK → ready for auth)
NDS_READY=0
for i in 1 2 3 4 5 6 7 8 9 10; do
    if ndsctl status 2>/dev/null | grep -q "Managed interface"; then
        NDS_READY=1
        logger -t fastfi "Boot: NDS ready for auth (attempt $i)."
        break
    fi
    sleep 1
done

# Clock-sync rescue flag. On RTC-less boards the clock is 1970 at boot until
# NTP lands; sync-sessions.lua aborts while the clock is 1970, so the boot
# restore below re-auths nobody. Without a re-trigger after the clock syncs,
# power-loss-restarted clients keep their remaining time in the DB but get no
# nodogsplash auth grant -> "timer running, no internet" until a fresh purchase.
# The main loop re-runs the restore once the clock becomes valid (step 2b).
CLOCK_RESTORE_DONE=0
if [ "$NDS_READY" = "1" ]; then
    restore_all_sessions
    # If the clock was already valid the restore actually re-authed clients, so
    # the main-loop rescue is unnecessary. Otherwise it aborted (1970) and the
    # rescue below retries once NTP lands.
    [ "$(date +%s)" -ge 1704067200 ] && CLOCK_RESTORE_DONE=1
else
    logger -t fastfi "Boot: NDS not fully ready — sessions will be restored by main loop."
fi

# Track WAN state for dynamic recovery
LAST_WAN_STATE=1
[ "$WAN_UP" = "0" ] && LAST_WAN_STATE=0

# Preauth rescue: check once after 30s to catch any sessions
# that were restored but stuck in Preauthenticated state
PREAUTH_CHECK_DONE=0
LOOP_COUNT=0

while true; do
    LOOP_COUNT=$((LOOP_COUNT + 1))
    
    # 1. Daemon Health Check
    if ! pidof nodogsplash >/dev/null 2>&1; then
        logger -t fastfi "nodogsplash not running, restarting..."
        /etc/init.d/nodogsplash restart 2>/dev/null
        sleep 5
        restore_all_sessions
        PREAUTH_CHECK_DONE=0
        LOOP_COUNT=0
    fi
    
    # 2. Preauth Rescue — runs once ~30s after boot/NDS restart
    # Catches sessions that were restored but NDS didn't fully process
    if [ "$PREAUTH_CHECK_DONE" = "0" ] && [ "$LOOP_COUNT" -ge 6 ]; then
        STUCK=$(ndsctl json 2>/dev/null | grep -c '"Preauthenticated"' || echo 0)
        if [ "$STUCK" -gt 0 ]; then
            logger -t fastfi "Preauth rescue: $STUCK clients stuck, re-syncing..."
            restore_all_sessions
        fi
        PREAUTH_CHECK_DONE=1
    fi

    # 2b. Clock-Sync Rescue — re-run the session restore once the clock becomes
    # valid, if the boot-time restore was skipped because the clock was 1970.
    # This fixes "no internet after a power-loss reboot": clients had time
    # remaining in the DB but no NDS auth grant because sync-sessions aborted.
    # Only stamp done when NDS is up, so a mid-restart doesn't burn the one shot.
    if [ "$CLOCK_RESTORE_DONE" = "0" ] && [ "$(date +%s)" -ge 1704067200 ]; then
        if pidof nodogsplash >/dev/null 2>&1; then
            logger -t fastfi "Clock now synced — restoring sessions skipped during 1970 boot window."
            restore_all_sessions
            CLOCK_RESTORE_DONE=1
        fi
    fi
    
    # 3. Connectivity Watchdog (Self-Healing)
    # If WAN was down and just came up, re-sync to fix "no recovery" bugs
    CURRENT_WAN_UP=0
    ubus call network.interface.wan status 2>/dev/null | grep -q '"up": true' && CURRENT_WAN_UP=1
    
    if [ "$CURRENT_WAN_UP" = "1" ] && [ "$LAST_WAN_STATE" = "0" ]; then
        logger -t fastfi "WAN recovery detected! Refreshing sessions and firewall."
        restore_all_sessions
        (/usr/libexec/fastfi/services/fastfi-report.sh >> /tmp/report.log 2>&1) &
    fi
    LAST_WAN_STATE=$CURRENT_WAN_UP
    
    # 4. Cache real-time speeds
    if [ "$CURRENT_WAN_UP" = "1" ]; then
        /usr/bin/env lua /usr/libexec/fastfi/core/speed-monitor.lua 2>/dev/null
    fi

    # 5. Run Auto-Pause check (backgrounded, handles its own lock)
    (/usr/libexec/fastfi/jobs/fastfi-autopause.sh >> /tmp/autopause.err 2>&1) &

    # 5b. Auth Repair — re-auth active sessions whose client reconnected to
    # WiFi AFTER the one-shot boot/clock-sync session restore already ran.
    # Fixes "timer running, no internet" after a power-loss reboot: NDS lost
    # its in-memory auth grant and the client rejoined too late for sync-sessions.
    # Non-disruptive (only touches clients not already authed). ~every 30s.
    if [ $((LOOP_COUNT % 6)) -eq 0 ]; then
        (/usr/libexec/fastfi/core/fastfi-auth-repair.sh >/dev/null 2>&1) &
    fi
    
    # 6. Handle pending SQM restarts (triggered from UI to avoid network resets)
    if [ -f /tmp/fastfi_sqm_restart_pending ]; then
        logger -t fastfi "Applying SQM changes in background..."
        rm -f /tmp/fastfi_sqm_restart_pending
        /etc/init.d/sqm restart >/dev/null 2>&1
        logger -t fastfi "SQM restart complete."
    fi
    
    # 7. Self-Healing Anti-Tethering (Check every 10s to catch firewall reloads)
    if [ $((LOOP_COUNT % 2)) -eq 0 ]; then
        if [ -f /tmp/fastfi_db_ready ]; then
            AT_STATE=$(sqlite3 /www/data/bindcode.db "SELECT anti_tethering FROM config LIMIT 1;" 2>/dev/null)
            if [ "$AT_STATE" = "1" ]; then
                if ! /usr/libexec/fastfi/core/fastfi-antitether.sh status | grep -q "enabled"; then
                    logger -t fastfi "Self-Healing: Anti-Tethering rules missing, re-enabling..."
                    /usr/libexec/fastfi/core/fastfi-antitether.sh enable >/dev/null 2>&1
                fi
            fi
        fi
    fi

    # 8. Periodic Reporting & Heartbeat (Every 60s)
    # This ensures the router stays "Online" in the dashboard even if cron is flaky.
    if [ $((LOOP_COUNT % 12)) -eq 0 ]; then
        # Telemetry Report (Sales, Clients, Rates)
        (/usr/libexec/fastfi/services/fastfi-report.sh >/dev/null 2>&1) &
        # Remote Access Heartbeat (VPN status)
        (/usr/libexec/fastfi/jobs/fastfi-heartbeat.sh >/dev/null 2>&1) &
        # (command poller removed in this release — see migrate.sh)
    fi

    sleep 5
done
