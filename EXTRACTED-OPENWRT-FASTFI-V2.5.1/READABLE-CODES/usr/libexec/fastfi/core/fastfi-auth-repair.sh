#!/bin/sh
# FastFi V6 - Auth Repair
# Re-authenticates active sessions whose client is connected to WiFi but is
# MISSING a nodogsplash auth grant.
#
# Why this exists: nodogsplash keeps auth grants in RAM, so they vanish on
# reboot. The boot-time sync-sessions.lua (and its clock-sync rescue in
# core-loop.sh) re-auth only clients that are on WiFi at the moment they run.
# When a phone rejoins the SSID AFTER those one-shot restores have finished
# (common after a power-loss reboot, especially once NTP finally syncs the
# clock on RTC-less boards), the DB still says active=1 with time remaining
# but NDS has no grant -> the phone sees the captive portal with a running
# timer and NO internet, fixed only by a manual pause/resume. This repair
# closes that window.
#
# Non-disruptive: it only ever acts on clients that are NOT already
# authenticated in NDS, so healthy connected clients are never de-authed.
# Triggered periodically from core-loop.sh (~every 30s).

DB="/www/data/sessions.db"
LOCK_FILE="/var/run/fastfi-auth-repair.lock"

# ── Mutex: skip if a previous run is still going ──────────
exec 8>"$LOCK_FILE"
if ! flock -n 8; then
    exit 0
fi

NOW=$(date +%s)

# Clock not synced yet (1970 on RTC-less boards) — can't trust session_end.
if [ "$NOW" -lt 1704067200 ]; then
    exit 0
fi

# NDS must be up and answering.
pidof nodogsplash >/dev/null 2>&1 || exit 0
ndsctl status >/dev/null 2>&1 || exit 0

# ── Snapshot NDS state once ───────────────────────────────
# If ndsctl json returns nothing (error/not ready), bail rather than risk
# treating every client as unauthenticated and mass-deauthing.
NDS_JSON=$(ndsctl json 2>/dev/null)
[ -z "$NDS_JSON" ] && exit 0

# Authenticated MACs in NDS (lowercase, deduped).
AUTH_MACS=$(printf '%s\n' "$NDS_JSON" | grep -B 2 '"state": "authenticated"' | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | tr '[:upper:]' '[:lower:]' | sort -u)

# ── WiFi-associated MACs (multi-interface, deduped) ───────
CONN_MACS=""
for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
    CONN_MACS="$CONN_MACS $(iw dev "$iface" station dump 2>/dev/null | awk '/Station/{print tolower($2)}')"
done
CONN_MACS=$(echo "$CONN_MACS" | tr ' ' '\n' | sort -u | tr '\n' ' ')

is_wifi_connected() {
    local mac
    mac=$(echo "$1" | tr '[:upper:]' '[:lower:]' | xargs)
    [ -z "$mac" ] && return 1
    for cmac in $CONN_MACS; do
        [ "$cmac" = "$mac" ] && return 0
    done
    return 1
}

is_nds_authed() {
    [ -z "$AUTH_MACS" ] && return 1
    for amac in $AUTH_MACS; do
        [ "$amac" = "$1" ] && return 0
    done
    return 1
}

# ── Active, non-paused sessions with time remaining ───────
SQL_ACTIVE="SELECT DISTINCT lower(mac_address) FROM sessions WHERE active=1 AND paused=0 AND session_end > $NOW AND (validity_end = 0 OR validity_end > $NOW) AND mac_address != '';"
ACTIVE=$(sqlite3 -cmd ".timeout 5000" "$DB" "$SQL_ACTIVE" 2>/dev/null)

[ -z "$ACTIVE" ] && exit 0

echo "$ACTIVE" | while IFS= read -r MAC; do
    [ -z "$MAC" ] && continue

    # Only repair if the client is physically on WiFi...
    is_wifi_connected "$MAC" || continue
    # ...and NDS has NOT granted them auth.
    is_nds_authed "$MAC" && continue

    logger -t fastfi-auth-repair "Repairing active session $MAC: connected but missing NDS auth grant"

    # Deauth before auth to clear any stale marks (mirrors sync-sessions.lua /
    # autopause auto-resume). On a never-authed client the deauth is a no-op.
    ndsctl deauth "$MAC" >/dev/null 2>&1
    sleep 0.3
    ndsctl auth "$MAC" >/dev/null 2>&1

    # Re-apply this client's speed limits.
    /usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1
done

flock -u 8
exit 0