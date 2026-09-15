#!/bin/sh
# ═══════════════════════════════════════════════════════════════════
# FastFi V6 — Config / Data / Code Backup & Rollback
# ═══════════════════════════════════════════════════════════════════
# Target:  OpenWrt (BusyBox ash)
# Purpose: Snapshot router state before an OTA apply so a failed/errored
#          update can be rolled back. Backups live in /www/data/backups/
#          (persistent ext4 rootfs, survives reboot — NOT /tmp).
#
# Usage:
#   fastfi-backup.sh backup [full]        Snapshot config+data (+code if full)
#                                         Prints the tarball path on success.
#   fastfi-backup.sh restore <tarball>    Extract a snapshot back over root.
#   fastfi-backup.sh list                  List snapshots (size  filename).
#   fastfi-backup.sh cleanup [keep=N]     Keep only the newest N snapshots.
#
# NOTE on scope (single ext4 rootfs, NO A/B partition):
#   A .bin sysupgrade that breaks the kernel CANNOT be rolled back in-device
#   — that needs an external SD-card reflash tool. This tool rolls back CONFIG/DATA always,
#   and CODE when the OTA used the overlay (.tar.gz) path. The post-OTA
#   watchdog (fastfi-rollback-watchdog.sh) drives the automatic restore.
# ═══════════════════════════════════════════════════════════════════
# NOTE: no `set -e`. Every failure path below is handled explicitly (and
# df/du/make_args degrade gracefully), so a failing early command must NOT
# silently abort the script before it prints a result — that left the admin
# UI with "backup failed (no output)". Each branch echoes a 'backup: ...'
# reason to stdout (the API surfaces it) or the tarball path on success.

BACKUP_DIR="/www/data/backups"
VERSION_FILE="/www/version.txt"
LOG_TAG="fastfi-backup"
# Retain only the NEWEST snapshot. The 16 MB overlay (Ruijie EW1200G Pro /
# Newifi D2) has only ~3-4 MB free; even ~1.3 MB config-only snapshots
# overflow it if 5 are kept (~6.5 MB). One pre-OTA snapshot is all rollback
# ever needs — the previous-version history was never used by the watchdog
# and only filled the overlay, which is what aborted OTA applies pre-reboot.
KEEP_DEFAULT=1

# Config + data — always snapshotted. /www/data is included but the backups
# subdir is EXCLUDED so snapshots don't archive each other (recursive bloat).
CONFIG_PATHS="/etc/fastfi /etc/config /etc/openvpn /www/version.txt"
DATA_PATHS="/www/data"
# Top-level FastFi flag files (optional — may not exist on a given box).
FLAG_FILES="/etc/fastfi_admin_pass.conf /etc/fastfi_rates.conf /etc/fastfi_enrolled /etc/fastfi_vpn_enabled"
# Code — only snapshotted in 'full' mode (overlay rollback target).
CODE_PATHS="/www /usr/lib/lua/fastfi /usr/libexec/fastfi"

log() { logger -t "$LOG_TAG" "$*" 2>/dev/null || true; echo "[$(date '+%H:%M:%S')] $*" >&2; }

current_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE" 2>/dev/null | head -1 | tr -dc '0-9.\n' | head -1
    else
        echo "unknown"
    fi
}

# Build a space-separated argument list of paths that actually exist.
make_args() {
    _out=""
    for _p in "$@"; do
        if [ -e "$_p" ]; then _out="$_out $_p"; fi
    done
    echo "$_out"
}

do_backup() {
    mode="${1:-config}"
    if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
        echo "backup: cannot create $BACKUP_DIR — rootfs read-only or full. Free space or expand the rootfs, then retry."
        exit 1
    fi

    ver="$(current_version)"
    ts="$(date '+%Y%m%d-%H%M%S')"
    out="${BACKUP_DIR}/fastfi-${ver}-${ts}.tar.gz"

    paths="$(make_args $CONFIG_PATHS $FLAG_FILES)"
    if [ -d "/www/data" ]; then
        for p in /www/data/*; do
            if [ "$p" != "/www/data/backups" ] && [ -e "$p" ]; then
                paths="$paths $p"
            fi
        done
    fi
    if [ "$mode" = "full" ]; then
        for p in /www/*; do
            if [ "$p" != "/www/data" ] && [ -e "$p" ]; then
                paths="$paths $p"
            fi
        done
        paths="$paths $(make_args /usr/lib/lua/fastfi /usr/libexec/fastfi)"
    fi

    if [ -z "$paths" ]; then
        log "backup: nothing to archive"
        echo "backup: nothing to archive"
        exit 1
    fi

    # Prune old snapshots BEFORE the size check so they free space first.
    do_cleanup "$KEEP_DEFAULT" >/dev/null 2>&1 || true

    # Free-space precheck on the target filesystem (rootfs is a small ~104M
    # ext4). Estimate the source set and bail with a clear message before we
    # risk a partial write. df/du degrade gracefully: if we can't read them,
    # skip the gate and rely on the partial-tar cleanup below.
    avail_kb=$(df -P "$BACKUP_DIR" 2>/dev/null | awk 'NR>1{print $4; exit}')
    [ -z "$avail_kb" ] && avail_kb=0
    need_kb=0
    for _p in $paths; do
        s=$(du -sk "$_p" 2>/dev/null | awk '{print $1}')
        [ -n "$s" ] && [ "$s" -gt 0 ] 2>/dev/null && need_kb=$((need_kb + s)) || true
    done
    # gzip headroom. The tarball is COMPRESSED, so for the mixed text +
    # already-compressed-media source set it is typically ~30-50% of the
    # uncompressed size. The old 110% estimate was far too conservative and
    # falsely bailed "insufficient space" on the Ruijie's small overlay, which
    # then aborted the OTA apply (router never rebooted). Use 50% + 1 MB slack.
    need_kb=$((need_kb / 2 + 1024))
    if [ "$avail_kb" -gt 0 ] && [ "$need_kb" -gt 0 ] && [ "$need_kb" -gt "$avail_kb" ]; then
        need_mb=$((need_kb / 1024))
        have_mb=$((avail_kb / 1024))
        msg="backup: insufficient space on rootfs — need ~${need_mb} MB, have ${have_mb} MB free. Remove old backups/large files or expand the rootfs, then retry."
        log "$msg"
        echo "$msg"
        exit 2
    fi

    # -C / so archive stores paths without leading /; restore extracts at /.
    # Always exclude the backups dir itself to prevent snapshots archiving snapshots.
    # If tar fails (e.g. ENOSPC mid-write) remove the half-written tarball so
    # it doesn't consume space and confuse `list`; print a clear reason.
    # shellcheck disable=SC2086  # intentional word-splitting of path list
    if ! tar -C / -czf "$out" $paths 2>/dev/null; then
        rm -f "$out" 2>/dev/null
        msg="backup: tar failed — removed partial file. Rootfs may be full; free space or expand the rootfs, then retry."
        log "$msg"
        echo "$msg"
        exit 1
    fi

    log "backup created: $out ($(du -h "$out" 2>/dev/null | cut -f1))"
    echo "$out"
}

do_restore() {
    tarball="$1"
    if [ -z "$tarball" ]; then
        log "restore: missing tarball argument"
        exit 1
    fi
    if [ ! -f "$tarball" ]; then
        log "restore: tarball not found: $tarball"
        exit 1
    fi

    log "restoring from $tarball"
    if ! tar -C / -xzf "$tarball" 2>/dev/null; then
        log "restore: extraction failed"
        exit 1
    fi

    # Re-commit any restored UCI config so it takes effect on next start.
    uci commit 2>/dev/null || true
    # Re-fix script permissions (tarballs from Windows strip the +x bit).
    chmod +x /usr/libexec/fastfi/core/*.sh 2>/dev/null || true
    chmod +x /usr/libexec/fastfi/core/*.lua 2>/dev/null || true
    chmod +x /etc/init.d/fastfi 2>/dev/null || true
    chmod +x /etc/uci-defaults/* 2>/dev/null || true
    log "restore complete — reboot required for changes to take effect"
}

do_list() {
    mkdir -p "$BACKUP_DIR" 2>/dev/null
    found=0
    for f in "$BACKUP_DIR"/fastfi-*.tar.gz; do
        [ -f "$f" ] || continue
        found=1
        printf "%s\t%s\n" "$(du -h "$f" 2>/dev/null | cut -f1)" "$(basename "$f")"
    done
    [ "$found" = "1" ] || echo "(no snapshots)"
}

do_cleanup() {
    keep="${1:-$KEEP_DEFAULT}"
    mkdir -p "$BACKUP_DIR" 2>/dev/null
    # Newest-first, skip the newest `keep`, remove the rest.
    ls -1t "$BACKUP_DIR"/fastfi-*.tar.gz 2>/dev/null | tail -n +$((keep + 1)) | while read -r old; do
        [ -f "$old" ] && rm -f "$old" && log "cleanup: removed old backup $(basename "$old")"
    done
    return 0
}

case "${1:-}" in
    backup)  shift; do_backup "${1:-config}" ;;
    restore) shift; do_restore "$1" ;;
    list)    do_list ;;
    cleanup) shift; do_cleanup "${1:-$KEEP_DEFAULT}" ;;
    *)
        echo "Usage: $0 {backup [full] | restore <tarball> | list | cleanup [keep=N]}" >&2
        exit 1
        ;;
esac