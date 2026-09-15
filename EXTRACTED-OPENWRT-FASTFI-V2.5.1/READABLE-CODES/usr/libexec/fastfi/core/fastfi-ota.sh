#!/bin/sh
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
# KonekSik-fi / CEBJ.NET â€” Production OTA Update System
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
# Target:  OpenWrt (BusyBox ash)
# Source:  GitHub Releases (public Renzzes/CEBJ.NET)
# Version: 2.1.0
#
# Usage:
#   fastfi-ota.sh check       â€” Query GitHub for new release
#   fastfi-ota.sh download    â€” Download the update bundle
#   fastfi-ota.sh apply       â€” Flash the downloaded update
#   fastfi-ota.sh auto        â€” Unattended: check â†’ download â†’ apply
#
# Exit Codes:
#   0 = Success / up to date
#   1 = General error
#   2 = Network / API error
#   3 = Asset selection error
#   4 = Checksum verification error
#   5 = Sysupgrade test failure
#   6 = Insufficient storage
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
set -e  # Exit on error
# set -u is disabled as it can cause brittle failures with some df outputs

# â”€â”€ Configuration â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
OWNER="Renzzes"
REPO="CEBJ.NET"
CHANNEL="latest"
API_URL="https://api.github.com/repos/${OWNER}/${REPO}/releases/${CHANNEL}"
# Public releases need no token. Optional: export GITHUB_TOKEN on the router
# if the repo is ever made private (never hardcode secrets in this file).
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

VERSION_FILE="/www/version.txt"
LOG_FILE="/tmp/fw_progress.log"
WWW_LOG="/www/fw_progress.log"
TMP_DIR="/tmp"
UPDATE_BUNDLE="${TMP_DIR}/update.tar.gz"
CHECKSUM_FILE="${TMP_DIR}/sha256sums"
EXTRACT_DIR="${TMP_DIR}/_ota_extract"
RELEASE_JSON="${TMP_DIR}/_ota_release.json"

# 2 attempts (1 retry). The release-JSON fetch is small (~few KB) and capped at
# 20s/attempt (see fetch() stdout branch), so a flaky WAN fails in ~20s + backoff
# + 20s â‰ˆ 45s instead of the old 60sÃ—3 â‰ˆ 3 min. The bundle fetch keeps max-time 300
# (a 304 KB tarball over a slow uplink genuinely needs the headroom).
RETRIES=2
OVERHEAD_BYTES=10485760  # 10 MB safety margin
SYSUPGRADE_IN_PROGRESS=0

# Rollback safety net (Item 4). Before any destructive apply we snapshot
# router state so the post-OTA watchdog (fastfi-rollback-watchdog.sh) can
# restore it if the box comes up unhealthy. The marker is written to
# PERSISTENT storage because /tmp is cleared on the post-apply reboot.
BACKUP_SCRIPT="/usr/libexec/fastfi/core/fastfi-backup.sh"
ROLLBACK_PENDING="/etc/fastfi/ota_pending"
# Set after a successful .tar.gz overlay apply and removed before a .bin
# sysupgrade. Its presence means the FastFi code tree already lives in the
# overlay upper layer, so a subsequent .tar.gz cp overwrites in place (~0 net
# flash growth) and is always safe on a tight 16 MB overlay. Its absence means
# the code is still in squashfs (fresh flash / just .bin-reflashed), so a
# .tar.gz cp would grow the overlay by ~the full code size â€” select the .bin
# instead when free space is short. See select_update_asset().
OVERLAY_MARKER="/etc/fastfi/.ota_overlay_code"

# arm_rollback <mode>  (mode = "config": config+data snapshot only â€” used by
# both the .bin sysupgrade and the .tar.gz overlay OTA paths, so the 16 MB
# overlay is never pressured by re-archiving the whole code tree.)
arm_rollback() {
    local mode="$1"
    # All writes here are guarded: under `set -e` an unguarded mkdir/printf
    # redirect onto a full 16 MB overlay aborts the whole apply BEFORE the
    # reboot â€” leaving the operator stuck ("router never reboots"). A missing
    # rollback marker is harmless; an aborted apply is not.
    { mkdir -p /etc/fastfi 2>/dev/null || true; }
    log "Creating pre-OTA backup (mode=${mode}) for rollback safety..."
    local bk rc=0
    # The backup is a SAFETY NET, not a prerequisite. A failed backup
    # (common: rootfs overlay too full to fit the snapshot on the Ruijie's
    # 16 MB partition, often a falsely-conservative free-space precheck) MUST
    # NOT block an update the operator explicitly requested. The previous
    # `|| die 1` aborted apply before reboot, and proceed_update ran it under
    # `>/dev/null 2>&1`, so the operator saw "nothing happens, router never
    # reboots" and clicked Apply forever. Log the reason and proceed without a
    # rollback net rather than leave the box permanently un-updatable.
    bk="$("$BACKUP_SCRIPT" backup "$mode" 2>>"$LOG_FILE")" || rc=$?
    if [ "$rc" -ne 0 ]; then
        log "WARNING: pre-OTA backup failed (rc=${rc}: ${bk:-no reason}). Proceeding WITHOUT rollback safety net so the update is not blocked."
        { printf 'BACKUP=\nVERSION=%s\n' "$(get_current_version)" > "$ROLLBACK_PENDING" 2>/dev/null || true; }
        chmod 600 "$ROLLBACK_PENDING" 2>/dev/null || true
        return 0
    fi
    local oldver
    oldver="$(get_current_version)"
    { printf 'BACKUP=%s\nVERSION=%s\n' "$bk" "$oldver" > "$ROLLBACK_PENDING" 2>/dev/null || true; }
    chmod 600 "$ROLLBACK_PENDING" 2>/dev/null || true
    log "Rollback armed: backup=${bk} previous_version=${oldver}"
}

# â”€â”€ Logging â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Log truncation moved to specific commands to prevent 'check' from clearing status

log() {
    local ts
    ts=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Ensure symlink exists so web server can see it
    if [ ! -L "${WWW_LOG}" ]; then
        ln -sf "${LOG_FILE}" "${WWW_LOG}" 2>/dev/null || true
    fi
    
    # Guarded: an unguarded `>> ${LOG_FILE}` aborts the apply under `set -e`
    # if /tmp is somehow read-only/full, killing the update before the reboot.
    { echo "[$ts] $1" >> "${LOG_FILE}" 2>/dev/null || true; }
    chmod 666 "${LOG_FILE}" 2>/dev/null || true
    echo "[$ts] $1" >&2
}

die() {
    local code="$1"; shift
    log "FATAL: $*"
    exit "$code"
}

# â”€â”€ Cleanup Trap â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
cleanup() {
    # Never delete files if sysupgrade is about to take over
    if [ "$SYSUPGRADE_IN_PROGRESS" -eq 1 ]; then
        return
    fi
    rm -f "${TMP_DIR}/_ota_headers.txt"
    rm -f "${CHECKSUM_FILE}"
    # NOTE: we intentionally do NOT delete ${RELEASE_JSON} here. The admin UI
    # runs check, download, and apply as THREE SEPARATE processes (ops.lua:
    # io.popen check â†’ os.execute download â†’ os.execute apply). Each process
    # fires this EXIT trap on exit; deleting RELEASE_JSON when `check` exits
    # meant `download` (a separate process) found it gone, so find_asset_url
    # and get_asset_digest both short-circuited on `[ -f RELEASE_JSON ]` â†’ no
    # checksum source â†’ FATAL "No checksum found for update.tar.gz" on EVERY
    # UI click. (Only the single-process `auto` cron path survived.) Keeping
    # RELEASE_JSON across invocations â€” like we keep UPDATE_BUNDLE for apply â€”
    # fixes the UI OTA flow. /tmp is wiped on reboot so it can't go stale
    # across boots, and each `check` overwrites it fresh on every run.
    # Note: we keep UPDATE_BUNDLE so "apply" can run after "download"
}
trap cleanup EXIT

# â”€â”€ HTTP Fetch Abstraction â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Tries: curl â†’ uclient-fetch â†’ wget (in SSL capability order)
# Usage: fetch <url> <output_file|->
#        Returns 0 on success, 1 on failure
fetch() {
    local url="$1"
    local output="$2"
    local attempt=1
    local delay=1
    local rc=1
    local auth_header=""

    if [ -n "${GITHUB_TOKEN}" ]; then
        auth_header="Authorization: Bearer ${GITHUB_TOKEN}"
    fi

    while [ "$attempt" -le "$RETRIES" ]; do
        rc=1

        # â”€â”€ curl (preferred) â”€â”€
        if command -v curl >/dev/null 2>&1; then
            if [ "$output" = "-" ]; then
                # stdout branch = release JSON only (small, ~few KB). Tight 20s
                # cap so a stalled api.github.com connection fails fast and the
                # single retry (RETRIES=2) re-attempts instead of hanging 60sÃ—3.
                curl -s -L --connect-timeout 15 --max-time 20 \
                    ${auth_header:+-H "$auth_header"} \
                    -H "User-Agent: KonekSik-CEBJ-Router" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "$url" && rc=0
            else
                curl -s -L --connect-timeout 15 --max-time 300 \
                    ${auth_header:+-H "$auth_header"} \
                    -H "User-Agent: KonekSik-CEBJ-Router" \
                    -H "Accept: application/octet-stream" \
                    -o "${output}.part" "$url" && rc=0
                [ "$rc" -eq 0 ] && mv "${output}.part" "$output"
            fi

        # â”€â”€ uclient-fetch (OpenWrt native) â”€â”€
        elif command -v uclient-fetch >/dev/null 2>&1; then
            if [ "$output" = "-" ]; then
                uclient-fetch --no-check-certificate -q -O - \
                    ${auth_header:+--header="$auth_header"} \
                    --header="User-Agent: KonekSik-CEBJ-Router" \
                    "$url" 2>/dev/null && rc=0
            else
                # Accept: application/octet-stream is REQUIRED for the GitHub
                # Assets API endpoint to return file content â€” without it the
                # endpoint returns the asset's JSON metadata (HTTP 200) and we
                # save ~1.5 KB of JSON as if it were the bundle/sha256sums, so
                # every verify then fails. (The curl branch already sends this;
                # uclient-fetch/wget were missing it â€” a real bug on boxes with
                # no curl, which fall through to uclient-fetch.) The stdout
                # branch above intentionally does NOT send octet-stream: it fetches
                # the release JSON from /releases/latest, which 415's on
                # octet-stream and wants the v3+json / default accept.
                uclient-fetch --no-check-certificate -q \
                    -O "${output}.part" \
                    ${auth_header:+--header="$auth_header"} \
                    --header="User-Agent: KonekSik-CEBJ-Router" \
                    --header="Accept: application/octet-stream" \
                    "$url" 2>/dev/null && rc=0
                [ "$rc" -eq 0 ] && mv "${output}.part" "$output"
            fi

        # â”€â”€ wget (SSL-capable variant only) â”€â”€
        elif command -v wget >/dev/null 2>&1; then
            if [ "$output" = "-" ]; then
                wget -qO- --no-check-certificate \
                    ${auth_header:+--header="$auth_header"} \
                    --header="User-Agent: KonekSik-CEBJ-Router" \
                    "$url" 2>/dev/null && rc=0
            else
                # See uclient-fetch file-output branch: octet-stream is required
                # for asset downloads from the Assets API (else JSON metadata).
                wget -q --no-check-certificate \
                    -O "${output}.part" \
                    ${auth_header:+--header="$auth_header"} \
                    --header="User-Agent: KonekSik-CEBJ-Router" \
                    --header="Accept: application/octet-stream" \
                    "$url" 2>/dev/null && rc=0
                [ "$rc" -eq 0 ] && mv "${output}.part" "$output"
            fi
        else
            die 2 "No HTTPS-capable tool found (need curl, uclient-fetch, or wget-ssl)"
        fi

        # Success â€” break retry loop
        if [ "$rc" -eq 0 ]; then
            return 0
        fi

        log "Fetch attempt $attempt/$RETRIES failed for $(basename "$url"). Retrying in ${delay}s..."
        sleep "$delay"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done

    return 1
}

# â”€â”€ Version Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Strip leading 'v' and trim whitespace
normalize_version() {
    echo "$1" | sed 's/^[[:space:]]*v//; s/[[:space:]]*$//'
}

# Compare two dot-separated versions: returns 0 if $1 < $2
version_lt() {
    local a="$1" b="$2"
    # If they're equal, not less-than
    [ "$a" = "$b" ] && return 1

    local IFS='.'
    set -- $a
    local a1="${1:-0}" a2="${2:-0}" a3="${3:-0}"
    set -- $b
    local b1="${1:-0}" b2="${2:-0}" b3="${3:-0}"

    [ "$a1" -lt "$b1" ] 2>/dev/null && return 0
    [ "$a1" -gt "$b1" ] 2>/dev/null && return 1
    [ "$a2" -lt "$b2" ] 2>/dev/null && return 0
    [ "$a2" -gt "$b2" ] 2>/dev/null && return 1
    [ "$a3" -lt "$b3" ] 2>/dev/null && return 0
    return 1
}

get_current_version() {
    local ver=""

    # Primary source
    if [ -f "${VERSION_FILE}" ]; then
        ver="$(cat "${VERSION_FILE}" 2>/dev/null)"
    fi

    # Fallback: OpenWrt release
    if [ -z "$ver" ] && [ -f /etc/openwrt_release ]; then
        ver="$(. /etc/openwrt_release 2>/dev/null && echo "${DISTRIB_RELEASE:-}")"
    fi

    # Fallback: firmware_version
    if [ -z "$ver" ] && [ -f /etc/firmware_version ]; then
        ver="$(cat /etc/firmware_version 2>/dev/null)"
    fi

    normalize_version "${ver:-0.0.0}"
}

# â”€â”€ GitHub API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
get_latest_release() {
    log "Querying GitHub API for latest release..."

    local json
    json="$(fetch "${API_URL}" "-")"

    if [ -z "$json" ]; then
        die 2 "Empty response from GitHub API. Check internet and token."
    fi

    # Check for API errors
    if echo "$json" | grep -q '"message"'; then
        local errmsg
        errmsg="$(echo "$json" | grep -o '"message": *"[^"]*"' | head -1 | cut -d'"' -f4)"
        die 2 "GitHub API error: ${errmsg}"
    fi

    # Persist for asset parsing
    echo "$json" > "${RELEASE_JSON}"
    chmod 666 "${RELEASE_JSON}" 2>/dev/null || true

    # Extract tag
    LATEST_VER="$(echo "$json" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)"
    LATEST_VER="$(normalize_version "${LATEST_VER}")"

    if [ -z "${LATEST_VER}" ]; then
        die 2 "Could not parse tag_name from GitHub release."
    fi

    log "Latest release: ${LATEST_VER}"
}

# â”€â”€ Board Detection â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
get_board_name() {
    local board=""

    # Method 1: ubus (preferred, always available on OpenWrt)
    if command -v ubus >/dev/null 2>&1; then
        board="$(ubus call system board 2>/dev/null | \
                 grep -o '"board_name": *"[^"]*"' | cut -d'"' -f4)"
    fi

    # Method 2: /tmp/sysinfo/board_name
    if [ -z "$board" ] && [ -f /tmp/sysinfo/board_name ]; then
        board="$(cat /tmp/sysinfo/board_name 2>/dev/null)"
    fi

    # Normalize: replace commas and slashes with hyphens
    board="$(echo "$board" | tr ',/' '-')"

    if [ -z "$board" ]; then
        die 3 "Could not detect board name. Ensure 'ubus' is available."
    fi

    echo "$board"
}

# â”€â”€ Asset URL Resolution â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Finds the download URL for a named asset in the release JSON.
# GitHub private repos require downloading via the Assets API with
# the Accept: application/octet-stream header (handled by fetch()).
find_asset_url() {
    local asset_name="$1"

    [ -f "${RELEASE_JSON}" ] || return 1

    # GitHub's release JSON is minified to a single line, with a nested
    # "uploader":{...} object inside every asset. Splitting on '{' puts each
    # asset's "id" and "name" on the SAME line (the uploader's opening '{'
    # comes after id+name), so name -> id maps reliably. We then download via
    # the Assets API endpoint, NOT the asset's browser_download_url: for a
    # PRIVATE repo authenticated with a PAT Bearer token, github.com/.../
    # releases/download/<tag>/<file> returns 404 â€” only the API endpoint
    # honors token auth and 302-redirects to a signed objects.githubusercontent
    # URL. (Verified empirically; the old browser_download_url "primary" was
    # both broken by the nested uploader AND 404'd even when extracted.)
    local asset_id
    asset_id="$(tr '{' '\n' < "${RELEASE_JSON}" | \
                grep "\"name\": *\"${asset_name}\"" | \
                grep -o '"id": *[0-9]*' | head -1 | \
                grep -o '[0-9]*')"

    if [ -z "$asset_id" ]; then
        log "WARNING: asset '${asset_name}' not found in release JSON."
        return 1
    fi

    echo "https://api.github.com/repos/${OWNER}/${REPO}/releases/assets/${asset_id}"
}

# â”€â”€ Asset Digest (sha256 from the release JSON, no extra fetch) â”€â”€
# Returns the sha256 hex GitHub records for a named asset via its per-asset
# "digest":"sha256:<hex>" field, read from RELEASE_JSON (already fetched
# during check/auto). This is the PRIMARY checksum source for verify_checksum:
# it needs NO second network fetch, so a transient sha256sums-download failure
# can no longer block an otherwise-good OTA with "No checksum file found".
#
# Parsing: after `tr '{' '\n', the asset's "digest" and "browser_download_url"
# land on the same line (the line that starts inside the uploader object and
# runs to the asset's closing brace), while the asset's "name" is on the
# previous line. So we anchor on browser_download_url â€” unique per asset, ends
# in /<asset_name> â€” and pull "digest" off that same line. BusyBox-safe.
get_asset_digest() {
    local asset_name="$1"
    [ -f "${RELEASE_JSON}" ] || return 1
    tr '{' '\n' < "${RELEASE_JSON}" | \
        grep "\"browser_download_url\": *\"[^\"]*/${asset_name}\"" | \
        grep -o '"digest": *"sha256:[0-9a-f]*"' | head -1 | \
        sed 's/.*sha256://; s/"//g'
}

# â”€â”€ Hybrid asset selection (.tar.gz if it fits, else .bin) â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Non-fatal board name (empty string on failure) â€” a board-detection glitch
# must NOT abort a .tar.gz update that does not need a .bin fallback.
get_board_name_soft() {
    local board=""
    if command -v ubus >/dev/null 2>&1; then
        board="$(ubus call system board 2>/dev/null | \
                 grep -o '"board_name": *"[^"]*"' | cut -d'"' -f4)"
    fi
    [ -z "$board" ] && [ -f /tmp/sysinfo/board_name ] && \
        board="$(cat /tmp/sysinfo/board_name 2>/dev/null)"
    board="$(echo "$board" | tr ',/' '-')"
    echo "$board"
}

# Free space (KB) on the rootfs/overlay mount (df -P /, the upper overlay).
overlay_free_kb() {
    df -P / 2>/dev/null | awk 'NR>1{print $4; exit}'
}

# Estimate (KB) of overlay copy-up a FRESH-flash .tar.gz apply would need,
# using the on-device code tree as a proxy for the incoming bundle's size.
# Exclude /www/data (operator data, NOT in the bundle â€” make_archive excludes
# it) so a box with lots of customer data isn't falsely routed to .bin.
overlay_cpneed_kb() {
    du -sk --exclude=/www/data /www /usr/lib/lua/fastfi /usr/libexec/fastfi 2>/dev/null | \
        awk '{s+=$1} END{print s+0}'
}

# Decide which update asset this device should pull. Sets ASSET_URL/ASSET_NAME.
#
# v2.2.9: OTA is .tar.gz-ONLY. A per-device <board>-sysupgrade.bin is NEVER
# selected by Check for Updates, even if one is present in the release. Reason:
# on the 16 MB boards (Ruijie EW1200G Pro / Newifi D2) a .bin sysupgrade was
# observed in the field to WIPE the operator's /www/data â€” license key, gcash
# setup, and coin rates all reset to defaults, box left inactive. The .tar.gz
# apply is additive (cp -r never deletes /www/data) and preserves all operator
# data, so it is the only safe OTA asset. The code-only .tar.gz (~1.6 MB
# copy-up, ~316 KB download) fits a fresh 16 MB Ruijie (~3.7 MB free), so no
# .bin recourse is needed. If a box genuinely cannot fit the .tar.gz, the
# apply-time space gate die-6s VISIBLY (no reboot, no wipe) and the admin frees
# overlay or manually reflashes the .bin out-of-band. The .bin assets are also
# no longer uploaded to OTA releases (see OTA_LOGIC.md Â§6); a .bin for manual
# flashing is distributed separately. KEEP .tar.gz-only â€” do NOT re-add .bin
# selection here.
select_update_asset() {
    ASSET_URL=""
    ASSET_NAME=""

    local tar_url
    tar_url="$(find_asset_url "update.tar.gz" 2>/dev/null || true)"
    if [ -n "$tar_url" ]; then
        ASSET_URL="$tar_url"
        ASSET_NAME="update.tar.gz"
        log "Selected update.tar.gz (OTA is .tar.gz-only; .bin never selected)."
    fi
}

# â”€â”€ URL Safety Validation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
validate_download_url() {
    local url="$1"
    case "$url" in
        https://api.github.com/*) return 0 ;;
        https://github.com/*) return 0 ;;
        https://*.githubusercontent.com/*) return 0 ;;
        *)
            die 2 "Untrusted download URL: $url"
            ;;
    esac
}

# â”€â”€ Storage Check â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
ensure_tmp_space() {
    local need_bytes="$1"
    log "Checking available space in ${TMP_DIR}..."
    local avail_kb
    # Use tail -1 to handle wrapped df output from long filesystem names
    avail_kb="$(df -k "${TMP_DIR}" | tail -n 1 | awk '{print $4}')"
    
    if [ -z "$avail_kb" ] || ! echo "$avail_kb" | grep -q '^[0-9]*$'; then
        log "WARNING: Could not parse df output. Skipping storage check."
        return 0
    fi
    
    local avail_bytes=$((avail_kb * 1024))
    local total_need=$((need_bytes + OVERHEAD_BYTES))

    if [ "$avail_bytes" -lt "$total_need" ]; then
        local need_mb=$((total_need / 1048576))
        local avail_mb=$((avail_bytes / 1048576))
        die 6 "Insufficient storage. Need ${need_mb}MB, have ${avail_mb}MB in ${TMP_DIR}."
    fi

    log "Storage OK: $((avail_bytes / 1048576))MB available."
}

# â”€â”€ Download â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
download_asset() {
    local url="$1"
    local dest="$2"

    validate_download_url "$url"

    log "Downloading $(basename "$dest")..."

    if ! fetch "$url" "$dest"; then
        die 2 "Download failed after ${RETRIES} attempts: $(basename "$dest")"
    fi

    if [ ! -s "$dest" ]; then
        rm -f "$dest"
        die 2 "Downloaded file is empty: $(basename "$dest")"
    fi

    local size
    size="$(du -h "$dest" | cut -f1)"
    log "Downloaded $(basename "$dest") ($size)"
}

# â”€â”€ Checksum Verification â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Two independent sources for the expected hash; EITHER suffices:
#  1. The asset "digest":"sha256:<hex>" from the release JSON already fetched
#     during check/auto (get_asset_digest). PRIMARY â€” needs no network, so a
#     transient sha256sums-download failure can no longer block an OTA.
#  2. The sha256sums file (best-effort fetch in download/auto, or placed
#     manually). SECONDARY fallback.
# FAIL-OPEN (v2.2.4 parity, restored F10): if NEITHER source yields a hash, we
# log a WARNING and PROCEED without verifying rather than FATAL the update. A
# missing checksum SOURCE is a network/metadata problem, not evidence the
# bundle is bad â€” and hard-failing here (the v2.3.4-v2.3.9 behavior) is exactly
# what stranded boxes in the field with a "No checksum found" FATAL they could
# never recover from via the UI. The download path already re-fetches
# RELEASE_JSON if it's missing and F8 keeps it alive across check->download, so
# the digest is virtually always available and we DO verify in the common case;
# this branch only fires when both the JSON digest and the sha256sums fetch are
# unavailable. A genuine checksum MISMATCH (corruption / tampering) still dies
# below â€” fail-open applies ONLY to "no source found", never to "wrong hash".
verify_checksum() {
    local firmware="$1"
    local sumfile="$2"
    local basename_fw
    basename_fw="$(basename "$firmware")"

    log "Verifying SHA256 checksum..."

    local expected=""
    local source=""

    # Primary: digest straight from the release JSON (no extra fetch).
    if [ -f "${RELEASE_JSON}" ]; then
        expected="$(get_asset_digest "${basename_fw}")"
        [ -n "$expected" ] && source="release JSON digest"
    fi

    # Fallback: the sha256sums file, if present.
    if [ -z "$expected" ] && [ -f "$sumfile" ]; then
        expected="$(grep "${basename_fw}" "$sumfile" | awk '{print $1}')"
        [ -n "$expected" ] && source="sha256sums file"
    fi

    if [ -z "$expected" ]; then
        log "WARNING: No checksum available for ${basename_fw} (not in release JSON digest nor sha256sums). Proceeding WITHOUT verification (2.2.4 parity). A real checksum mismatch would still FATAL; this only fires when no checksum source could be obtained."
        return 0
    fi

    # Compute actual hash
    local actual
    actual="$(sha256sum "$firmware" | awk '{print $1}')"

    if [ "$expected" != "$actual" ]; then
        log "CHECKSUM MISMATCH!"
        log "  Expected: $expected"
        log "  Got:      $actual"
        die 4 "SHA256 checksum verification failed!"
    fi

    log "Checksum verified OK (via ${source})."
}

# â”€â”€ Sysupgrade Test â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
test_upgrade() {
    local firmware="$1"

    # Only run sysupgrade --test if the file is a .bin image
    # (skip for tar.gz bundles which are file-level overlays)
    case "$firmware" in
        *.bin)
            log "Running sysupgrade validation test..."
            if ! sysupgrade --test "$firmware" 2>/dev/null; then
                die 5 "sysupgrade --test failed. Firmware image may be corrupt or incompatible."
            fi
            log "Sysupgrade test passed."
            ;;
        *.tar.gz)
            log "Bundle update (tar.gz) â€” skipping sysupgrade test."
            ;;
    esac
}

# â”€â”€ Upgrade Execution â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
perform_upgrade() {
    local firmware="$1"

    case "$firmware" in
        *.bin)
            # Config-only snapshot: a broken .bin kernel can't be rolled
            # back in-device (no A/B), but config/data backup lets the
            # watchdog restore a bootable-but-misconfigured new firmware.
            arm_rollback config
            # A .bin sysupgrade reflows squashfs, so the code goes back to the
            # read-only lower layer and is NOT in the overlay afterward. Drop
            # the marker so the next check re-evaluates overlay headroom rather
            # than assuming in-place cp. sysupgrade.conf preserves /etc/fastfi,
            # so a pre-exec rm is what stops the (otherwise-restored) marker.
            { rm -f "$OVERLAY_MARKER" 2>/dev/null || true; }
            log "Starting sysupgrade (preserving config)..."
            SYSUPGRADE_IN_PROGRESS=1
            # exec hands control entirely to sysupgrade â€” no return
            exec sysupgrade -c "$firmware"
            ;;
        *.tar.gz)
            # Config+data snapshot ONLY â€” do NOT archive the whole code tree.
            # The 16 MB overlay (Ruijie EW1200G Pro / Newifi D2) has only ~3-4 MB
            # free; a 'full' snapshot re-archives the multi-MB /www+luma+libexec
            # code, and retaining several of them overflowed the overlay â€” the
            # root cause of OTA applies aborting before the reboot. The apply's
            # cp -r overwrites files in place (~0 net flash growth), so with a
            # small config-only snapshot the overlay stays healthy and a code
            # rollback is rarely needed; the non-fatal arm_rollback below is the
            # net if a half-apply ever does occur. Matches the .bin path.
            arm_rollback config
            log "Applying overlay update from bundle..."
            { rm -rf "${EXTRACT_DIR}" 2>/dev/null || true; }
            mkdir -p "${EXTRACT_DIR}" || die 1 "Cannot create extract dir ${EXTRACT_DIR}."

            if ! tar -xzf "$firmware" -C "${EXTRACT_DIR}" 2>/dev/null; then
                die 1 "Failed to extract update bundle."
            fi

            # â”€â”€ Pre-apply overlay free-space gate (16 MB safety) â”€â”€
            # The check-time hybrid pick estimates headroom from the on-device
            # code, but the ACTUAL copy-up size is the extracted bundle's. If
            # the overlay cannot hold it, drop ALL backups to recover space and
            # re-check; if it still cannot, bail VISIBLY (exit 6 + FATAL log,
            # no reboot) so the admin panel shows the real reason and the box
            # stays on the working old version instead of aborting mid-cp into
            # a franken-system. This is the backstop that makes the .tar.gz
            # path safe on the Ruijie.
            #
            # IMPORTANT: the marker matters here too. If OVERLAY_MARKER is set
            # the code already lives in the overlay and cp overwrites IN PLACE
            # (~0 net flash growth), so the effective need is ~0 â€” NOT the full
            # bundle size. Charging the full size here would falsely die-6 the
            # very in-place-overwrite case the marker is meant to greenlight.
            local cp_need_kb free_kb effective_need peak_kb
            cp_need_kb="$(du -sk "${EXTRACT_DIR}/www" "${EXTRACT_DIR}/usr/lib/lua/fastfi" "${EXTRACT_DIR}/usr/libexec/fastfi" "${EXTRACT_DIR}/etc" 2>/dev/null | awk '{s+=$1} END{print s+0}')"
            # Peak = the largest single file in the bundle. During `cp -r`,
            # overlayfs copies each file up to the upper layer BEFORE
            # overwriting it, so the momentary space above the running total is
            # one file's size. The margin only needs to cover THAT peak â€” not a
            # flat 1 MB. A flat 1 MB margin (v2.2.5) was so conservative it
            # rejected a 3.7 MB-free Ruijie that genuinely fits (copy-up ~2.8 MB
            # + 0.5 MB peak = ~3.3 MB). Measuring the real peak lets the .tar.gz
            # apply whenever it truly fits, and only die-6s when it doesn't.
            # BusyBox `du -k` rounds up to 4 KB blocks, so this already includes
            # block-rounding slack; fall back to 512 KB if the find is empty.
            peak_kb="$(find "${EXTRACT_DIR}/www" "${EXTRACT_DIR}/usr/lib/lua/fastfi" "${EXTRACT_DIR}/usr/libexec/fastfi" "${EXTRACT_DIR}/etc" -type f -exec du -k {} \; 2>/dev/null | sort -rn | awk 'NR==1{print $1+0}')"
            [ "${peak_kb:-0}" -gt 0 ] || peak_kb=512
            free_kb="$(overlay_free_kb)"
            if [ -f "$OVERLAY_MARKER" ]; then
                effective_need=0   # in-place overwrite, ~0 net
            else
                effective_need="${cp_need_kb:-0}"
            fi
            if [ "${free_kb:-0}" -gt 0 ] && [ "${effective_need:-0}" -gt 0 ] && \
               [ "$((free_kb))" -lt "$((effective_need + peak_kb))" ]; then
                log "WARNING: overlay low (free ${free_kb}KB < need ${effective_need}KB + peak ${peak_kb}KB). Dropping all backups to recover space..."
                "$BACKUP_SCRIPT" cleanup 0 >/dev/null 2>&1 || true
                free_kb="$(overlay_free_kb)"
            fi
            if [ "${free_kb:-0}" -gt 0 ] && [ "${effective_need:-0}" -gt 0 ] && \
               [ "$((free_kb))" -lt "$((effective_need + peak_kb))" ]; then
                # Overlay genuinely cannot hold the .tar.gz even after dropping
                # backups. Bail VISIBLY (exit 6 + FATAL log, no reboot) so the
                # admin panel shows the real reason and the box stays on the
                # working old version instead of aborting mid-cp into a
                # franken-system. Do NOT auto-fallback to .bin here â€” the
                # .tar.gz fits on any overlay with >= need+peak free (the common
                # 3-4 MB Ruijie case); this die only fires when it truly can't.
                die 6 "Insufficient overlay space for .tar.gz apply: need ~$((effective_need/1024))MB + ${peak_kb}KB peak, have $((free_kb/1024))MB free. Free up overlay space (remove old backups) or reflash the per-device .bin sysupgrade image manually."
            fi
            log "Overlay headroom OK (free ${free_kb:-?}KB, effective need ${effective_need:-?}KB, peak ${peak_kb:-?}KB, bundle ${cp_need_kb:-?}KB)."

            # Overlay files from the bundle onto the system.
            # CRITICAL: under `set -e` an UNGUARDED cp failure (rare now that the
            # space gate passed, but possible on EACCES/RO) would abort the apply
            # BEFORE the reboot â€” the "router never reboots" bug. Wrap each in an
            # `if` (its body is exempt from set -e) with an inner `||` so a copy
            # failure logs a WARNING, flips overlay_ok, and we still reach reboot.
            # Snapshot the running version BEFORE the overlay cp. The /www cp
            # below copies the bundle's www/version.txt (the NEW version) over
            # /www/version.txt; if the libexec cp then fails (overlay_ok=0), the
            # box would report the NEW version while still running the OLD
            # fastfi-ota.sh â€” so future "Check for Updates" sees current==latest
            # â†’ UPTODATE â†’ the box never self-heals. prev_version is restored in
            # that case (see the version block below) to keep the box honest.
            local prev_version=""
            [ -f "${VERSION_FILE}" ] && prev_version="$(cat "${VERSION_FILE}" 2>/dev/null)"
            # Track success so we only mark the code in-overlay on a clean copy.
            local overlay_ok=1
            if [ -d "${EXTRACT_DIR}/www" ]; then
                cp -r "${EXTRACT_DIR}/www/"* /www/ 2>>"$LOG_FILE" || { log "WARNING: copy of /www failed"; overlay_ok=0; }
            fi
            if [ -d "${EXTRACT_DIR}/usr/lib/lua/fastfi" ]; then
                cp -r "${EXTRACT_DIR}/usr/lib/lua/fastfi/"* /usr/lib/lua/fastfi/ 2>>"$LOG_FILE" || { log "WARNING: copy of lua/fastfi failed"; overlay_ok=0; }
            fi
            if [ -d "${EXTRACT_DIR}/usr/libexec/fastfi" ]; then
                cp -r "${EXTRACT_DIR}/usr/libexec/fastfi/"* /usr/libexec/fastfi/ 2>>"$LOG_FILE" || { log "WARNING: copy of libexec/fastfi failed"; overlay_ok=0; }
            fi
            if [ -d "${EXTRACT_DIR}/etc" ]; then
                cp -r "${EXTRACT_DIR}/etc/"* /etc/ 2>>"$LOG_FILE" || { log "WARNING: copy of /etc failed"; overlay_ok=0; }
            fi

            # Fix execute permissions lost from Windows-generated tarballs.
            # MUST cover the same set as etc/uci-defaults/99-fastfi-setup: that
            # script is the only other place jobs/ and services/ get +x, it runs
            # on FIRST BOOT ONLY, and it is excluded from the .tar.gz (v2.2.8).
            # So anything newly added under jobs/ or services/ arrives from the
            # tarball non-executable and â€” if it is not chmod'd here â€” silently
            # never runs on an OTA'd box while working fine on a fresh flash.
            log "Fixing script permissions..."
            chmod +x /usr/libexec/fastfi/core/*.sh 2>/dev/null || true
            chmod +x /usr/libexec/fastfi/core/*.lua 2>/dev/null || true
            chmod +x /usr/libexec/fastfi/jobs/*.sh 2>/dev/null || true
            chmod +x /usr/libexec/fastfi/jobs/*.lua 2>/dev/null || true
            chmod +x /usr/libexec/fastfi/services/*.sh 2>/dev/null || true
            chmod +x /www/cgi-bin/api 2>/dev/null || true
            chmod +x /etc/init.d/fastfi 2>/dev/null || true
            chmod +x /etc/uci-defaults/* 2>/dev/null || true

            # Run migration script if provided. Use [ -f ] (not [ -x ]): the
            # tarball may ship migrate.sh without an exec bit (Windows-built
            # archives write 0666), and sh runs it regardless â€” an [ -x ] guard
            # would silently skip migrations on every box. make_archive.py now
            # sets +x too, but this keeps it robust against a bit-less tarball.
            if [ -f "${EXTRACT_DIR}/migrate.sh" ]; then
                log "Running migration script..."
                sh "${EXTRACT_DIR}/migrate.sh" >> "${LOG_FILE}" 2>&1 || \
                    log "WARNING: migrate.sh exited with error"
            fi

            # Update version file â€” ONLY on a clean overlay copy. If the
            # libexec cp failed (overlay_ok=0) the new OTA code did NOT land,
            # so we restore prev_version (snapshotted above the cp block)
            # instead of writing the new one. This prevents the box from
            # reporting the new version (which the /www cp already wrote to
            # /www/version.txt) while still running the old, broken
            # fastfi-ota.sh â€” a state that would make future "Check for
            # Updates" return UPTODATE and block self-healing. Restoring keeps
            # the box honestly on the old version so the next check retries.
            if [ "$overlay_ok" = 1 ]; then
                local new_ver
                new_ver="$(cat "${EXTRACT_DIR}/VERSION" 2>/dev/null || echo "")"
                if [ -n "$new_ver" ]; then
                    { echo "$new_ver" > "${VERSION_FILE}" 2>/dev/null || log "WARNING: could not write ${VERSION_FILE}"; }
                    log "Version updated to ${new_ver}"
                fi
            else
                if [ -n "$prev_version" ]; then
                    { echo "$prev_version" > "${VERSION_FILE}" 2>/dev/null || log "WARNING: could not restore ${VERSION_FILE}"; }
                    log "WARNING: overlay copy incomplete â€” restored version to ${prev_version}. Box keeps old OTA code; will retry next update."
                fi
            fi

            # Mark the code as living in the overlay so the next .tar.gz cp is
            # known to overwrite in place (~0 net flash growth). Only set it on
            # a clean copy; a partial copy leaves the marker absent so the next
            # check re-evaluates headroom (and likely routes to .bin).
            if [ "$overlay_ok" = 1 ]; then
                { : > "$OVERLAY_MARKER" 2>/dev/null || true; }
            fi

            # Cleanup (guarded): never let a failed rm abort before reboot.
            { rm -rf "${EXTRACT_DIR}" 2>/dev/null || true; }
            { rm -f "${UPDATE_BUNDLE}" 2>/dev/null || true; }
            log "Update applied successfully. Rebooting..."
            sync
            reboot
            ;;
    esac
}

# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
# COMMAND DISPATCH
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
case "${1:-}" in

    # â”€â”€ CHECK â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    "check")
        CURRENT_VER="$(get_current_version)"
        log "Current firmware version: ${CURRENT_VER}"

        get_latest_release  # sets LATEST_VER, writes RELEASE_JSON

        if [ "${LATEST_VER}" = "${CURRENT_VER}" ]; then
            echo "STATUS=UPTODATE"
            log "System is up to date (${CURRENT_VER})."
            exit 0
        fi

        if ! version_lt "${CURRENT_VER}" "${LATEST_VER}"; then
            echo "STATUS=UPTODATE"
            log "Installed version (${CURRENT_VER}) >= latest (${LATEST_VER}). No update."
            exit 0
        fi

        # Locate the download asset â€” HYBRID: .tar.gz if it fits the overlay,
        # else the per-device <board>-sysupgrade.bin full image. select_update_asset
        # measures overlay headroom (or the in-overlay marker) to decide, so a
        # tight 16 MB box auto-falls-back to the .bin (always fits) instead of
        # pulling a .tar.gz whose apply would abort mid-copy.
        select_update_asset

        if [ -z "$ASSET_URL" ]; then
            die 3 "No compatible update asset found in release ${LATEST_VER}."
        fi

        echo "STATUS=AVAILABLE"
        echo "VERSION=${LATEST_VER}"
        echo "URL=${ASSET_URL}"
        echo "ASSET=${ASSET_NAME}"
        log "Update ${LATEST_VER} available (${ASSET_NAME})"
        ;;

    # â”€â”€ DOWNLOAD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    "download")
        : > "${LOG_FILE}"  # Truncate log for new download
        URL="${2:-}"
        ASSET_NAME="${3:-update.tar.gz}"

        if [ -z "$URL" ]; then
            # Try to read from saved state
            URL="$(cat "${TMP_DIR}/_ota_url" 2>/dev/null || true)"
        fi

        if [ -z "$URL" ]; then
            die 1 "No download URL provided."
        fi

        DEST="${TMP_DIR}/${ASSET_NAME}"

        # Record what we chose and clear any stale firmware of the OPPOSITE
        # type from a previous check, so `apply` (which prefers
        # /tmp/update.tar.gz first) cannot accidentally flash a leftover
        # .tar.gz when this download was a .bin â€” or vice versa.
        { echo "$ASSET_NAME" > "${TMP_DIR}/_ota_asset_name" 2>/dev/null || true; }
        case "$ASSET_NAME" in
            *-sysupgrade.bin)
                { rm -f "${UPDATE_BUNDLE}" "${TMP_DIR}/update.tar.gz" 2>/dev/null || true; }
                ;;
            *.tar.gz)
                { rm -f ${TMP_DIR}/*-sysupgrade.bin 2>/dev/null || true; }
                ;;
        esac

        # Storage check (10MB is enough for a 1.9MB update + overhead)
        ensure_tmp_space 10485760

        # Self-sufficiency guard: verify_checksum and find_asset_url both need
        # RELEASE_JSON. In the normal UI flow, `check` (a separate process)
        # wrote it and cleanup() no longer deletes it, so it's present here. But
        # if `download` is ever invoked standalone (manual SSH, or /tmp wiped
        # between check and download), re-fetch so verify has the digest. This
        # is best-effort: get_latest_release die 2's on a fetch failure, which
        # stops the update â€” but note verify_checksum itself is now FAIL-OPEN
        # (F10/2.2.4 parity): if RELEASE_JSON is present but yields no digest
        # and sha256sums is also missing, it logs a WARNING and proceeds rather
        # than FATALing. So this re-fetch exists to ENABLE verification when
        # possible, not to gate the update on it.
        if [ ! -f "${RELEASE_JSON}" ]; then
            log "RELEASE_JSON missing at download time â€” re-fetching release metadata..."
            get_latest_release
        fi

        # Download the update asset
        download_asset "$URL" "$DEST"

        # Drop any sums file left over from a previous run before fetching, so
        # a stale one can never be matched against a freshly downloaded bundle.
        { rm -f "${CHECKSUM_FILE}" 2>/dev/null || true; }
        # Best-effort sha256sums fetch â€” FALLBACK ONLY. verify_checksum prefers
        # the asset "digest" from the release JSON (already fetched during
        # `check`, no network), so this second fetch is no longer on the
        # critical path. If it fails, the JSON digest still verifies the bundle
        # and the OTA proceeds; pre-v2.3.8 a failure here was a hard FATAL.
        CHECKSUM_URL="$(find_asset_url "sha256sums" 2>/dev/null || true)"
        if [ -n "$CHECKSUM_URL" ]; then
            log "Downloading checksum file (fallback)..."
            fetch "$CHECKSUM_URL" "${CHECKSUM_FILE}" 2>/dev/null || \
                log "WARNING: Could not download sha256sums (will use release JSON digest)."
        fi

        # Always attempt verification. verify_checksum tries the JSON digest
        # first, then this sums file if present; if NEITHER yields a hash it
        # logs a WARNING and proceeds (F10/2.2.4 fail-open) instead of FATALing.
        # A real mismatch still dies.
        verify_checksum "$DEST" "${CHECKSUM_FILE}"

        # Sysupgrade test (for .bin files only)
        test_upgrade "$DEST"

        log "Download complete"
        ;;

    # â”€â”€ APPLY â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    "apply")
        # Find what was downloaded. Prefer the asset the most recent
        # `download` recorded (hybrid-safe: a stale /tmp/update.tar.gz from a
        # prior check can no longer shadow a freshly downloaded .bin), then
        # fall back to presence-based detection.
        FIRMWARE=""
        _ota_asset_name="$(cat "${TMP_DIR}/_ota_asset_name" 2>/dev/null || true)"
        if [ -n "$_ota_asset_name" ] && [ -f "${TMP_DIR}/${_ota_asset_name}" ]; then
            FIRMWARE="${TMP_DIR}/${_ota_asset_name}"
        elif [ -f "${UPDATE_BUNDLE}" ]; then
            FIRMWARE="${UPDATE_BUNDLE}"
        elif [ -f "${TMP_DIR}/update.tar.gz" ]; then
            FIRMWARE="${TMP_DIR}/update.tar.gz"
        else
            # Search for any sysupgrade.bin in /tmp
            FIRMWARE="$(ls ${TMP_DIR}/*-sysupgrade.bin 2>/dev/null | head -1)"
        fi

        if [ -z "$FIRMWARE" ] || [ ! -f "$FIRMWARE" ]; then
            die 1 "No downloaded firmware found. Run 'download' first."
        fi

        log "Applying: $(basename "$FIRMWARE")..."
        perform_upgrade "$FIRMWARE"
        ;;

    # â”€â”€ AUTO (Unattended) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    "auto")
        # Guard: never silently reboot while paying customers have active
        # sessions â€” a 3 AM cron reboot kicks them off mid-session. Defer to
        # the next scheduled run instead. Checked BEFORE truncating the
        # progress log so a skipped run doesn't wipe a manual update's log.
        _active=$(sqlite3 /www/data/sessions.db "SELECT COUNT(*) FROM sessions WHERE active=1;" 2>/dev/null || echo 0)
        if [ "${_active:-0}" -gt 0 ]; then
            { echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auto-update deferred: ${_active} active session(s). Will retry next scheduled run." >> /tmp/ota-cron.log 2>/dev/null || true; }
            exit 0
        fi
        : > "${LOG_FILE}"  # Truncate log for auto update
        log "=== FastFi Unattended OTA Update ==="

        CURRENT_VER="$(get_current_version)"
        log "Current: ${CURRENT_VER}"

        get_latest_release

        if [ "${LATEST_VER}" = "${CURRENT_VER}" ]; then
            log "Already up to date."
            exit 0
        fi

        if ! version_lt "${CURRENT_VER}" "${LATEST_VER}"; then
            log "No update needed."
            exit 0
        fi

        # Find asset â€” HYBRID (.tar.gz if it fits the overlay, else .bin).
        select_update_asset

        [ -z "$ASSET_URL" ] && die 3 "No compatible asset found."

        DEST="${TMP_DIR}/${ASSET_NAME}"

        ensure_tmp_space 52428800
        download_asset "$ASSET_URL" "$DEST"

        # Checksum â€” unattended path matches `download`: verify_checksum
        # prefers the release JSON digest (no second fetch); the sha256sums
        # fetch here is a best-effort fallback. If neither yields a hash it
        # proceeds with a WARNING (F10/2.2.4 fail-open); a mismatch still dies.
        { rm -f "${CHECKSUM_FILE}" 2>/dev/null || true; }
        CHECKSUM_URL="$(find_asset_url "sha256sums" 2>/dev/null || true)"
        if [ -n "$CHECKSUM_URL" ]; then
            fetch "$CHECKSUM_URL" "${CHECKSUM_FILE}" 2>/dev/null || true
        fi
        verify_checksum "$DEST" "${CHECKSUM_FILE}"

        test_upgrade "$DEST"
        perform_upgrade "$DEST"
        ;;

    # â”€â”€ HELP / UNKNOWN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    *)
        echo "FastFi OTA Update System v2.0"
        echo ""
        echo "Usage: $(basename "$0") <command>"
        echo ""
        echo "Commands:"
        echo "  check      Check for updates (used by admin panel)"
        echo "  download   Download the update bundle"
        echo "  apply      Apply a previously downloaded update"
        echo "  auto       Unattended: check â†’ download â†’ verify â†’ apply"
        echo ""
        echo "Exit codes:"
        echo "  0 = Success / up to date"
        echo "  1 = General error"
        echo "  2 = Network / API error"
        echo "  3 = Asset not found"
        echo "  4 = Checksum mismatch"
        echo "  5 = Sysupgrade test failed"
        echo "  6 = Insufficient storage"
        exit 1
        ;;
esac
