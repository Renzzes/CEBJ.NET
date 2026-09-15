#!/bin/sh
# ═══════════════════════════════════════════════════════════════════
# FastFi V6 — Post-OTA Health Watchdog (one-shot, launched from rc.local)
# ═══════════════════════════════════════════════════════════════════
# Target:  OpenWrt (BusyBox ash)
#
# If /etc/fastfi/ota_pending exists (written by fastfi-ota.sh *before* an
# apply), wait up to HEALTH_TIMEOUT seconds for the box to come up healthy:
#   1. core-loop running
#   2. uhttpd running
#   3. public API responds (device_status) — proves the Lua router + DB
# On success: disarm (remove the marker). On failure: restore the backup
# named in the pending file and reboot back into the previous state.
#
# /tmp is RAM-cleared on reboot, so the marker MUST be on persistent storage
# (/etc/fastfi) — that's why fastfi-ota.sh writes it there, not /tmp.
#
# Scope limit: this catches a BAD OVERLAY apply (non-atomic cp -r left the
# box half-applied) or a misbehaving .tar.gz. A .bin sysupgrade whose kernel
# won't boot never reaches this script — recovery then needs an external
# SD-card reflash tool. There is no A/B partition.
# ═══════════════════════════════════════════════════════════════════
set -u

PENDING_FILE="/etc/fastfi/ota_pending"
HEALTH_TIMEOUT=300      # 5 minutes
PROBE_URL="http://127.0.0.1/cgi-bin/api?action=device_status"
LOG_TAG="fastfi-rollback"

log() { logger -t "$LOG_TAG" "$*" 2>/dev/null || true; echo "[$(date '+%H:%M:%S')] $*" >&2; }

# Marker must survive the post-apply reboot → persistent storage.
[ -f "$PENDING_FILE" ] || exit 0

# Parse the marker file: lines like BACKUP=<path> / VERSION=<oldver>
BACKUP=""
OLDVER=""
while IFS='=' read -r _k _v; do
    case "$_k" in
        BACKUP)  BACKUP="${_v:-}" ;;
        VERSION) OLDVER="${_v:-}" ;;
    esac
done < "$PENDING_FILE"

log "OTA pending detected (was v${OLDVER:-?}). Health-checking for up to ${HEALTH_TIMEOUT}s..."

# CORE health probe. These three signals decide whether we roll back: they
# prove the box itself is serving. Returns 0 only if all three are green.
core_healthy() {
    pgrep -f core-loop >/dev/null 2>&1 || return 1
    pidof uhttpd >/dev/null 2>&1 || return 1
    # Public API hit (no admin session needed) — a 0 exit + any body means
    # the Lua router is dispatching. BusyBox wget to localhost http.
    wget -q -O /dev/null --timeout=5 "$PROBE_URL" 2>/dev/null
}

# REMOTE-ACCESS probe. Only meaningful on a box the operator has enrolled for
# VPN remote access; on every other box it is vacuously true. Deliberately NOT
# a rollback trigger: the tunnel depends on the VPN server and the operator's
# WAN, so a transient outage must never revert a good update. It gates the
# wait (so we keep looking for it until the timeout) and, if it never comes
# up, it is reported loudly instead — otherwise a build that leaves the panel
# working but remote access dead passes health and disarms silently.
vpn_expected() {
    [ -f /etc/fastfi_vpn_enabled ] && [ -f /etc/fastfi_enrolled ]
}

vpn_healthy() {
    vpn_expected || return 0
    ip -4 addr show tun0 2>/dev/null | grep -q 'inet '
}

_elapsed=0
while [ "$_elapsed" -lt "$HEALTH_TIMEOUT" ]; do
    if core_healthy && vpn_healthy; then
        log "health check PASSED — OTA successful, disarming rollback marker."
        rm -f "$PENDING_FILE"
        exit 0
    fi
    sleep 5
    _elapsed=$((_elapsed + 5))
done

# Timed out. Distinguish "the box is broken" (roll back) from "the box is fine
# but the tunnel never came up" (do NOT roll back — report it).
if core_healthy; then
    log "CRITICAL: core health PASSED but the VPN tunnel never came up within ${HEALTH_TIMEOUT}s after the OTA."
    log "CRITICAL: remote access is DOWN on this device — check 'logread | grep fastfi-vpn'. NOT rolling back (core is healthy)."
    rm -f "$PENDING_FILE"
    exit 1
fi

log "health check FAILED after ${HEALTH_TIMEOUT}s — rolling back to previous state."
if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
    if /usr/libexec/fastfi/core/fastfi-backup.sh restore "$BACKUP" >/dev/null 2>&1; then
        log "rollback restore complete."
    else
        log "rollback restore reported errors — rebooting anyway."
    fi
    # Drop the marker BEFORE rebooting so we don't loop on the next boot.
    rm -f "$PENDING_FILE"
    sync
    log "rebooting into previous state."
    reboot
else
    log "no usable backup recorded ($BACKUP) — cannot auto-rollback. Manual recovery required."
    rm -f "$PENDING_FILE"
    exit 1
fi