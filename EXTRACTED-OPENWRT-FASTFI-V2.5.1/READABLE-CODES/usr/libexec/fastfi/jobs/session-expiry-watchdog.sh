#!/bin/sh
# Session Expiry Watchdog - Runs continuously with Android 15 MAC randomization support
# Start via cron: @reboot /root/session-expiry-watchdog.sh &
# OR via init.d

DB="/www/data/sessions.db"

# Ensure log directory exists
mkdir -p /www/data/logs

COUNTER=0
while true
do
    NOW=$(date +%s)
    
    # ── Clock Sync Check ─────────────────────────────────────
    if [ "$NOW" -lt 1704067200 ]; then
        # Only log every minute to avoid log spam
        [ $((NOW % 60)) -lt 10 ] && logger -t fastfi-watchdog "Waiting for clock sync ($NOW)..."
        sleep 5
        continue
    fi
    
    # Cache ndsctl json for UI stats (non-blocking for web server)
    ndsctl json > /tmp/nds_clients.json 2>/dev/null

    # ========================================
    # SESSIONS TABLE - Primary (supports device_id for Android/iOS)
    # ========================================
    # Default (main vendo) sub-vendo id: a non-default sub_vendo_id on an expired
    # session means the client is on a sub-vendo L3 interface (nft captive gate),
    # where ndsctl is a no-op — its WAN is dropped by rebuilding the gate (which
    # reaps authed IPs from ACTIVE sessions, so the now-inactive IP is removed).
    DEF_SV=$(sqlite3 /www/data/bindcode.db "SELECT id FROM sub_vendos WHERE is_default=1 LIMIT 1;" 2>/dev/null)
    [ -z "$DEF_SV" ] && DEF_SV=0
    rm -f /tmp/fastfi-gate-rebuild.flag

    # Query active sessions (device_id tracking supports Android 15 MAC randomization).
    # Paused sessions (paused=1) are EXEMPT from session_end expiry — pausing freezes the
    # clock, so a stale session_end must not zero their remaining time (recomputed as
    # now+remaining on resume). Only non-paused expired sessions are reaped here.
    sqlite3 "$DB" "SELECT device_id, mac_address, session_end, sub_vendo_id FROM sessions WHERE active=1 AND paused=0 AND session_end <= $NOW;" 2>/dev/null | while IFS='|' read DEVICE_ID MAC END SUBV
    do
        if [ -n "$END" ]; then
            # Deauth by MAC if available (main vendo / nodogsplash; no-op for
            # sub-vendo clients, which are gated by nft — flagged below instead).
            if [ -n "$MAC" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Deauthing MAC: $MAC (device_id: $DEVICE_ID, expired)" >> /www/data/logs/session-expiry.log
                ndsctl deauth "$MAC" >/dev/null 2>&1
            fi

            # Non-default sub-vendo expiry: flag an nft gate rebuild (the while
            # loop runs in a pipeline subshell, so we signal via a marker file).
            if [ -n "$SUBV" ] && [ "$SUBV" != "$DEF_SV" ] && [ "$SUBV" != "0" ]; then
                touch /tmp/fastfi-gate-rebuild.flag
            fi

            # Update session by device_id (primary key for Android/iOS support)
            DEVICE_ID_SAFE=$(printf '%s' "$DEVICE_ID" | sed "s/'/''/g")
            sqlite3 "$DB" "UPDATE sessions SET active=0, paused=0, remaining=0 WHERE device_id='$DEVICE_ID_SAFE';" 2>/dev/null

            # Also update by MAC if available (for compatibility)
            if [ -n "$MAC" ]; then
                MAC_SAFE=$(printf '%s' "$MAC" | sed "s/'/''/g")
                sqlite3 "$DB" "UPDATE sessions SET active=0, paused=0, remaining=0 WHERE mac_address='$MAC_SAFE';" 2>/dev/null
            fi
        fi
    done

    # If any non-default sub-vendo session expired this tick, rebuild the nft
    # gate (drops the expired IPs) + shaper (drops their shaping). Background so
    # the watchdog loop never blocks; one rebuild per tick regardless of count.
    if [ -f /tmp/fastfi-gate-rebuild.flag ]; then
        rm -f /tmp/fastfi-gate-rebuild.flag
        ( /usr/bin/env lua /usr/libexec/fastfi/core/fastfi-gate.lua >/dev/null 2>&1; \
          /usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1 ) &
    fi

    # ========================================
    # FULL SYNC - Every 60 seconds (Garbage Collector)
    # ========================================
    COUNTER=$((COUNTER + 1))
    if [ $COUNTER -ge 12 ]; then
        COUNTER=0
        # Get all currently authenticated MACs from NDS
        # Filter for "state": "authenticated" and extract the MAC
        ndsctl json 2>/dev/null | grep -B 2 '"state": "authenticated"' | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | tr '[:upper:]' '[:lower:]' | while read NDS_MAC
        do
            # Check if this MAC has an ACTIVE session in the database
            CHECK=$(sqlite3 "$DB" "SELECT count(*) FROM sessions WHERE lower(mac_address)=lower('$NDS_MAC') AND active=1 AND session_end > $NOW;" 2>/dev/null)
            if [ "$CHECK" = "0" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Garbage Collector: Deauthing stale MAC: $NDS_MAC" >> /www/data/logs/session-expiry.log
                ndsctl deauth "$NDS_MAC" >/dev/null 2>&1
            fi
        done
        # Sub-vendo GC: rebuild the nft captive gate from ACTIVE sessions so any
        # sub-vendo authed IP whose session became inactive by a non-expiry path
        # (clear_credit, admin disconnect, pause-then-lapse) is dropped. The
        # rebuild is atomic (no open-WAN window). Main vendo is unaffected (NDS).
        ( /usr/bin/env lua /usr/libexec/fastfi/core/fastfi-gate.lua >/dev/null 2>&1 ) &
    fi

    sleep 5
done
