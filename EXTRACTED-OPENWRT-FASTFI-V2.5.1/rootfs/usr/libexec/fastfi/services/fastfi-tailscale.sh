#!/bin/sh
# KonekSik-Fi — on-demand Tailscale helper (optional remote Admin).
# Do NOT enable on boot by default — saves RAM when remote access is idle.
#
# Usage:
#   fastfi-tailscale.sh status
#   fastfi-tailscale.sh install
#   fastfi-tailscale.sh up [AUTHKEY]
#   fastfi-tailscale.sh down

set -u

AUTHKEY_FILE="/etc/fastfi_tailscale_authkey"
LOG_FILE="/tmp/fastfi-tailscale.log"
LOGIN_FILE="/tmp/fastfi-tailscale-loginurl"
STATE_DIR="/etc/tailscale"

log() {
    logger -t koneksik-tailscale "$1"
    echo "$(date '+%F %T') $1" >> "$LOG_FILE" 2>/dev/null
}

has_bin() {
    command -v tailscale >/dev/null 2>&1 && command -v tailscaled >/dev/null 2>&1
}

ensure_not_boot_enabled() {
    if [ -x /etc/init.d/tailscale ]; then
        /etc/init.d/tailscale disable >/dev/null 2>&1 || true
    fi
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s///g' | tr '\n' ' '
}

cmd_status() {
    installed=0
    running=0
    backend=0
    ip=""
    dns=""
    login_url=""
    need_login=0
    msg=""

    if has_bin; then
        installed=1
    fi

    if [ -f "$LOGIN_FILE" ]; then
        login_url=$(tr -d '\n\r' < "$LOGIN_FILE" 2>/dev/null)
    fi

    if [ "$installed" = "1" ]; then
        if pgrep -x tailscaled >/dev/null 2>&1; then
            running=1
        fi
        # BackendState: NeedsLogin | NoState | Starting | Stopped | Running
        st=$(tailscale status --json 2>/dev/null)
        if [ -n "$st" ]; then
            backend=1
            echo "$st" | grep -q '"BackendState":"Running"' && backend=2
            echo "$st" | grep -q '"BackendState":"NeedsLogin"' && need_login=1
            ip=$(tailscale ip -4 2>/dev/null | head -n1 | tr -d '\n\r')
            dns=$(echo "$st" | sed -n 's/.*"DNSName":"\([^"]*\)".*/\1/p' | head -n1 | sed 's/\.$//')
        fi
        if [ -z "$login_url" ] && [ -f "$LOG_FILE" ]; then
            login_url=$(grep -Eo 'https://login\.tailscale\.com/[^ ]+' "$LOG_FILE" 2>/dev/null | tail -n1)
        fi
    else
        msg="Tailscale not installed. Use Install, then Start with an auth key."
    fi

    admin_url=""
    if [ -n "$ip" ]; then
        admin_url="http://${ip}/admin.html"
    fi

    printf '{'
    printf '"status":"ok",'
    printf '"installed":%s,' "$installed"
    printf '"daemon_running":%s,' "$running"
    printf '"connected":%s,' "$([ "$backend" = "2" ] && [ -n "$ip" ] && echo 1 || echo 0)"
    printf '"need_login":%s,' "$need_login"
    printf '"ip":"%s",' "$(json_escape "$ip")"
    printf '"dns_name":"%s",' "$(json_escape "$dns")"
    printf '"admin_url":"%s",' "$(json_escape "$admin_url")"
    printf '"login_url":"%s",' "$(json_escape "$login_url")"
    printf '"has_authkey_saved":%s,' "$([ -s "$AUTHKEY_FILE" ] && echo 1 || echo 0)"
    printf '"message":"%s"' "$(json_escape "$msg")"
    printf '}\n'
}

cmd_install() {
    if has_bin; then
        ensure_not_boot_enabled
        echo '{"status":"ok","message":"Tailscale already installed","installed":1}'
        return 0
    fi
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo '{"status":"error","message":"No internet — cannot install Tailscale packages"}'
        return 1
    fi
    log "Installing tailscale via opkg..."
    opkg update >>"$LOG_FILE" 2>&1
    if opkg install tailscale >>"$LOG_FILE" 2>&1; then
        ensure_not_boot_enabled
        if has_bin; then
            echo '{"status":"ok","message":"Tailscale installed. It will not start on boot (RAM-safe).","installed":1}'
            return 0
        fi
    fi
    echo '{"status":"error","message":"opkg install tailscale failed. Free space/RAM may be too low, or package unavailable for this build. See /tmp/fastfi-tailscale.log"}'
    return 1
}

cmd_up() {
    key="${1:-}"
    if [ -z "$key" ] && [ -s "$AUTHKEY_FILE" ]; then
        key=$(tr -d '\n\r ' < "$AUTHKEY_FILE")
    fi
    if [ -n "$key" ]; then
        printf '%s\n' "$key" > "$AUTHKEY_FILE"
        chmod 600 "$AUTHKEY_FILE" 2>/dev/null || true
    fi

    if ! has_bin; then
        echo '{"status":"error","message":"Tailscale not installed. Click Install first."}'
        return 1
    fi
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo '{"status":"error","message":"No internet — Tailscale needs outbound connectivity"}'
        return 1
    fi

    ensure_not_boot_enabled
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    rm -f "$LOGIN_FILE"
    : > "$LOG_FILE"

    if [ -x /etc/init.d/tailscale ]; then
        /etc/init.d/tailscale start >>"$LOG_FILE" 2>&1 || true
    else
        if ! pgrep -x tailscaled >/dev/null 2>&1; then
            tailscaled --state="$STATE_DIR/tailscaled.state" --socket=/var/run/tailscale/tailscaled.sock >>"$LOG_FILE" 2>&1 &
            sleep 2
        fi
    fi

    # Give daemon a moment
    i=0
    while [ $i -lt 15 ]; do
        pgrep -x tailscaled >/dev/null 2>&1 && break
        sleep 1
        i=$((i + 1))
    done
    if ! pgrep -x tailscaled >/dev/null 2>&1; then
        echo '{"status":"error","message":"tailscaled failed to start (often low RAM). See /tmp/fastfi-tailscale.log"}'
        return 1
    fi

    if [ -n "$key" ]; then
        log "tailscale up with auth key"
        # shellcheck disable=SC2086
        if tailscale up --auth-key="$key" --accept-dns=false --accept-routes=false >>"$LOG_FILE" 2>&1; then
            ip=$(tailscale ip -4 2>/dev/null | head -n1 | tr -d '\n\r')
            echo "{\"status\":\"ok\",\"message\":\"Tailscale connected\",\"ip\":\"$(json_escape "$ip")\",\"admin_url\":\"http://${ip}/admin.html\",\"connected\":1}"
            return 0
        fi
        echo '{"status":"error","message":"tailscale up failed with auth key. Check key and logs."}'
        return 1
    fi

    # Interactive login URL mode (rare on routers; prefer auth key)
    log "tailscale up (login URL mode)"
    ( tailscale up --accept-dns=false --accept-routes=false >"$LOG_FILE" 2>&1 & )
    sleep 3
    login_url=$(grep -Eo 'https://login\.tailscale\.com/[^ ]+' "$LOG_FILE" 2>/dev/null | tail -n1)
    if [ -n "$login_url" ]; then
        echo "$login_url" > "$LOGIN_FILE"
        echo "{\"status\":\"ok\",\"message\":\"Open the login URL to authorize this router\",\"login_url\":\"$(json_escape "$login_url")\",\"connected\":0,\"need_login\":1}"
        return 0
    fi
    ip=$(tailscale ip -4 2>/dev/null | head -n1 | tr -d '\n\r')
    if [ -n "$ip" ]; then
        echo "{\"status\":\"ok\",\"message\":\"Tailscale connected\",\"ip\":\"$(json_escape "$ip")\",\"admin_url\":\"http://${ip}/admin.html\",\"connected\":1}"
        return 0
    fi
    echo '{"status":"error","message":"Could not start Tailscale. Create an auth key at login.tailscale.com and paste it, then Start again."}'
    return 1
}

cmd_down() {
    if has_bin; then
        tailscale down >>"$LOG_FILE" 2>&1 || true
    fi
    if [ -x /etc/init.d/tailscale ]; then
        /etc/init.d/tailscale stop >>"$LOG_FILE" 2>&1 || true
        ensure_not_boot_enabled
    fi
    killall tailscaled 2>/dev/null || true
    killall tailscale 2>/dev/null || true
    rm -f "$LOGIN_FILE"
    log "Tailscale stopped (RAM freed)"
    echo '{"status":"ok","message":"Remote access stopped. Tailscale is not running.","connected":0,"daemon_running":0}'
    return 0
}

case "${1:-status}" in
    status)  cmd_status ;;
    install) cmd_install ;;
    up)      cmd_up "${2:-}" ;;
    down)    cmd_down ;;
    *)
        echo '{"status":"error","message":"Usage: status|install|up|down"}'
        exit 1
        ;;
esac
