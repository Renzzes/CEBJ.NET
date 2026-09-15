#!/bin/sh
# FastFi Auto-Pause Daemon
# Pauses sessions when clients disconnect from WiFi, resumes when they reconnect.
# Cron: */1 * * * * /root/fastfi-autopause.sh >/dev/null 2>&1

DB="/www/data/sessions.db"
CONFIG_FILE="/etc/fastfi/autopause.conf"
LOCK_FILE="/var/run/fastfi-autopause.lock"
ABSENT_DIR="/www/data/autopause"

# ── Load config ──────────────────────────────────────────
AUTOPAUSE_ENABLED=0
AUTOPAUSE_GRACE_PERIOD=10
AUTOPAUSE_AUTO_RESUME=1

if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# Exit immediately if disabled (cheap no-op)
[ "$AUTOPAUSE_ENABLED" != "1" ] && exit 0

# ── Mutex lock ───────────────────────────────────────────
exec 7>"$LOCK_FILE"
if ! flock -n 7; then
    exit 0
fi

# ── Ensure absent tracking dir exists ────────────────────
mkdir -p "$ABSENT_DIR"

NOW=$(date +%s)

# ── Clock Sync Check ─────────────────────────────────────
# If the clock is not synced (e.g. 1970 after reboot), exit to avoid
# corrupting session times (SESSION_END - 1970 = decades of time).
if [ "$NOW" -lt 1704067200 ]; then
    # Only log every few minutes to avoid log spam
    if [ $((NOW % 60)) -lt 10 ]; then
        logger -t fastfi-autopause "System clock not synced ($NOW), skipping run."
    fi
    exit 0
fi

# ── Get all connected MACs (Multi-source for reliability) ───────────
CONNECTED_MACS=""

# Source 1: WiFi Association (iw) - The most real-time source
for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
    MACS=$(iw dev "$iface" station dump 2>/dev/null | awk '/Station/{print tolower($2)}')
    CONNECTED_MACS="$CONNECTED_MACS $MACS"
done

# Deduplicate
CONNECTED_MACS=$(echo "$CONNECTED_MACS" | tr ' ' '\n' | sort -u | tr '\n' ' ')
CONN_COUNT=$(echo "$CONNECTED_MACS" | wc -w)

# Helper: check if MAC is associated with WiFi
is_wifi_connected() {
    local mac=$(echo "$1" | tr '[:upper:]' '[:lower:]' | xargs)
    [ -z "$mac" ] && return 1
    # Match the MAC exactly in the list
    for cmac in $CONNECTED_MACS; do
        [ "$cmac" = "$mac" ] && return 0
    done
    return 1
}

# ── Process active sessions (internet ON, time remaining) ─
# Get all active sessions: mac_address|session_end
SQL_ACTIVE="SELECT DISTINCT lower(mac_address), session_end FROM sessions WHERE active=1 AND session_end > $NOW AND (validity_end = 0 OR validity_end > $NOW) AND mac_address != '' ORDER BY session_end DESC;"
ACTIVE_SESSIONS=$(sqlite3 -cmd ".timeout 5000" "$DB" "$SQL_ACTIVE" 2>/dev/null)

if [ -n "$ACTIVE_SESSIONS" ]; then
    echo "$ACTIVE_SESSIONS" | while IFS='|' read -r MAC SESSION_END; do
        [ -z "$MAC" ] && continue

        # Skipping Preauthenticated check since whitelist is deprecated

        if is_wifi_connected "$MAC"; then
            # Client is connected — clear any grace period tracking
            if [ -f "$ABSENT_DIR/$MAC" ]; then
                logger -t fastfi-autopause "Client $MAC is back online — clearing absence tracking"
                rm -f "$ABSENT_DIR/$MAC" 2>/dev/null
            fi
        else
            # Client is NOT on WiFi
            ABSENT_FILE="$ABSENT_DIR/$MAC"

            if [ ! -f "$ABSENT_FILE" ]; then
                # First detection — start grace period
                echo "$NOW" > "$ABSENT_FILE"
                logger -t fastfi-autopause "Client $MAC absent - grace period started ${AUTOPAUSE_GRACE_PERIOD}s"
            else
                # Check if grace period has elapsed
                ABSENT_SINCE=$(cat "$ABSENT_FILE" 2>/dev/null)
                
                # Handle the case where the file contains "autopaused" string
                if [ "$ABSENT_SINCE" = "autopaused" ]; then
                    continue
                fi

                [ -z "$ABSENT_SINCE" ] && ABSENT_SINCE=$NOW
                ABSENT_DURATION=$((NOW - ABSENT_SINCE))

                if [ "$ABSENT_DURATION" -ge "$AUTOPAUSE_GRACE_PERIOD" ]; then
                    # Grace period exceeded — AUTO-PAUSE
                    REMAINING=$((SESSION_END - NOW))
                    [ "$REMAINING" -le 0 ] && continue

                    MAC_SAFE=$(printf '%s' "$MAC" | sed "s/'/''/g")
                    logger -t fastfi-autopause "Grace period exceeded for $MAC at ${ABSENT_DURATION}s - Pausing session"

                    # Pause session
                    sqlite3 -cmd ".timeout 5000" "$DB" "UPDATE sessions SET paused=1, remaining=$REMAINING, active=0 WHERE lower(mac_address)=lower('$MAC_SAFE');" 2>/dev/null
                    
                    # Log to session_history
                    sqlite3 -cmd ".timeout 5000" "$DB" "INSERT INTO session_history (device_id, mac_address, event_type, timestamp, remaining_seconds, session_end, reason, triggered_by) SELECT device_id, '$MAC_SAFE', 'paused', $NOW, $REMAINING, session_end, 'Auto-paused after grace period', 'autopause' FROM sessions WHERE lower(mac_address)=lower('$MAC_SAFE') LIMIT 1;" 2>/dev/null

                    # Deauth from captive portal
                    ndsctl deauth "$MAC" >/dev/null 2>&1

                    # Mark as auto-paused (for auto-resume detection)
                    echo "autopaused" > "$ABSENT_FILE"

                    logger -t fastfi-autopause "AUTO-PAUSED $MAC - absent ${ABSENT_DURATION}s, saved ${REMAINING}s"
                else
                    logger -t fastfi-autopause "Client $MAC still absent: ${ABSENT_DURATION}/${AUTOPAUSE_GRACE_PERIOD}s"
                fi
            fi
        fi
    done
fi

# ── Auto-resume: check paused sessions whose MAC is back on WiFi ─
if [ "$AUTOPAUSE_AUTO_RESUME" = "1" ]; then
    SQL_PAUSED="SELECT DISTINCT lower(mac_address), remaining FROM sessions WHERE paused=1 AND remaining > 0 AND (validity_end = 0 OR validity_end > $NOW) AND mac_address != '' ORDER BY remaining DESC;"
    PAUSED_SESSIONS=$(sqlite3 -cmd ".timeout 5000" "$DB" "$SQL_PAUSED" 2>/dev/null)

    if [ -n "$PAUSED_SESSIONS" ]; then
        echo "$PAUSED_SESSIONS" | while IFS='|' read -r MAC REMAINING; do
            [ -z "$MAC" ] && continue
            [ -z "$REMAINING" ] && continue

            ABSENT_FILE="$ABSENT_DIR/$MAC"

            # Only auto-resume if it was auto-paused (not manually paused by user)
            if [ -f "$ABSENT_FILE" ] && grep -q "autopaused" "$ABSENT_FILE" 2>/dev/null; then
                if is_wifi_connected "$MAC"; then
                    # Client is back on WiFi — AUTO-RESUME
                    NEW_END=$((NOW + REMAINING))
                    MAC_SAFE=$(printf '%s' "$MAC" | sed "s/'/''/g")
            
                    # Resume session
                    sqlite3 -cmd ".timeout 5000" "$DB" "UPDATE sessions SET paused=0, remaining=0, session_end=$NEW_END, active=1 WHERE lower(mac_address)=lower('$MAC_SAFE');" 2>/dev/null
                                    
                    # Log to session_history
                    sqlite3 -cmd ".timeout 5000" "$DB" "INSERT INTO session_history (device_id, mac_address, event_type, timestamp, remaining_seconds, session_end, reason, triggered_by) SELECT device_id, '$MAC_SAFE', 'resumed', $NOW, $REMAINING, $NEW_END, 'Auto-resumed after reconnection', 'autopause' FROM sessions WHERE lower(mac_address)=lower('$MAC_SAFE') LIMIT 1;" 2>/dev/null

                    # Re-auth with captive portal and re-apply speed limits.
                    # MUST deauth before auth: without it, nodogsplash leaves
                    # stale marks and reports "already authenticated" but traffic
                    # doesn't flow (see sync-sessions.lua). This matches every
                    # other grant path (portal/voucher/gcash/manual resume).
                    ndsctl deauth "$MAC" >/dev/null 2>&1
                    sleep 0.3
                    ndsctl auth "$MAC" >/dev/null 2>&1
                    /usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1

                    # Clean up tracking file
                    rm -f "$ABSENT_FILE" 2>/dev/null

                    logger -t fastfi-autopause "AUTO-RESUMED $MAC (reconnected, restored ${REMAINING}s)"
                fi
            fi
        done
    fi
fi

# ── Cleanup stale absent tracking files (older than 24h) ─
# Preserve "autopaused" markers for sessions that are still paused with time
# remaining, so auto-resume still fires when the client returns — even after
# the 24h mark (previously the marker was deleted and the client had to press
# resume manually, which read as "lost time"). Stale grace-timestamp markers
# (a client absent >24h was auto-paused long ago) and markers for sessions no
# longer paused are removed.
find "$ABSENT_DIR" -type f -mmin +1440 2>/dev/null | while IFS= read -r STALE; do
    [ -z "$STALE" ] && continue
    CONTENT=$(cat "$STALE" 2>/dev/null)
    if [ "$CONTENT" = "autopaused" ]; then
        MAC=$(basename "$STALE")
        MAC_SAFE=$(printf '%s' "$MAC" | sed "s/'/''/g")
        STILL_PAUSED=$(sqlite3 -cmd ".timeout 5000" "$DB" "SELECT count(*) FROM sessions WHERE lower(mac_address)=lower('$MAC_SAFE') AND paused=1 AND remaining > 0;" 2>/dev/null)
        [ "$STILL_PAUSED" = "1" ] && continue
    fi
    rm -f "$STALE" 2>/dev/null
done

# Release lock
flock -u 7
exit 0
