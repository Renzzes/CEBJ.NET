#!/bin/sh
# v2.1.3 migration — remove the obsolete GCash walled garden.
#
# The v2.1.2 walled garden (domain whitelist for unauthenticated clients) never
# worked in practice: the GCash app touches too many version-dependent endpoints
# and reports "no internet" behind any manageable whitelist. v2.1.3 replaces it
# with a grant-first free browsing window (see routes/gcash.lua:M.freewindow).
#
# This script runs once during OTA apply (fastfi-ota.sh runs it from the extract
# dir before reboot). It deletes the stale applier and the operator-editable
# domain list that are no longer shipped. cp -r in the OTA apply does NOT delete
# files the bundle no longer ships, so without this they'd linger on disk.
#
# Runtime nft rules (the @gcash_wl set, the forward `accept` rule, and the
# DNS-hijack dstnat dnat rules) were added at RUNTIME by the applier — never
# committed to UCI firewall config — so the post-apply reboot rebuilds fw4 from
# UCI without them. No explicit nft flush is needed (and flushing here, before
# reboot, would be pointless and could briefly disrupt clients).
#
# Best-effort: every removal is allowed to fail silently. Exits 0 regardless so
# the OTA never aborts on a already-partially-cleaned device.
rm -f /usr/libexec/fastfi/core/fastfi-gcash-wl.lua 2>/dev/null
rm -f /etc/fastfi/gcash_wl_domains.txt 2>/dev/null

# ── Remove the obsolete remote-command poller ────────────────────────────────
# fastfi-commands.sh polled /api/v1/device/<id>/commands. FastFi Cloud no longer
# serves that route (nor the ack route, nor a device_commands table) — remote
# management moved to the VPN tunnel. Because the server has an SPA catch-all,
# the dead GET does not even 404: it returns 200 with index.html, so every router
# was downloading the landing page once a minute, forever, and jq then silently
# parsed nothing.
#
# Removing it also retires three defects in that script, which are moot once it
# is gone but would be real if the endpoint ever returned again:
#   * the /ack POST sat OUTSIDE the if/elif chain, so an unknown command type or
#     a failed handler was still reported to the server as succeeded;
#   * recovery_email and the coin_rates fields were interpolated straight into
#     SQL from the server payload, unescaped;
#   * MACHINE_ID and LICENSE_KEY fell back to shared placeholders
#     ("000000000000" / "STD-XXXX-..."), so any device with a failed identity
#     lookup collided with every other such device on one command queue.
#
# The OTA .tar.gz apply is additive (cp -r never deletes), and /etc/crontabs/root
# is not shipped, so BOTH the script and its crontab line have to be removed here
# or deployed devices keep polling forever. core-loop.sh's own invocation is
# updated by the normal file copy.
rm -f /usr/libexec/fastfi/jobs/fastfi-commands.sh 2>/dev/null
_CRON=/etc/crontabs/root
if [ -f "$_CRON" ] && grep -q 'fastfi-commands\.sh' "$_CRON" 2>/dev/null; then
    sed -i '/fastfi-commands\.sh/d' "$_CRON" 2>/dev/null
    sed -i '/^# Command processor/d' "$_CRON" 2>/dev/null
    /etc/init.d/cron restart >/dev/null 2>&1
fi

# ── R1: stop uhttpd serving the SQLite DBs over HTTP (existing-box migration) ──
# The code bundle ships fastfi-data-dir.sh, which relocates /www/data to
# /etc/fastfi/data and makes /www/data a symlink. But uhttpd's no_symlinks='1'
# setting lives in etc/uci-defaults/99-fastfi-setup, which is EXCLUDED from the
# OTA tarball (uci-defaults run on first boot only; re-deploying would
# re-first-boot running boxes and wipe operator WiFi/cron settings). So existing
# boxes never receive no_symlinks via the bundle — set it here. Without it,
# uhttpd follows the /www/data symlink and the DBs (vouchers / licence key /
# sessions / sales / admin tokens) stay web-readable by any LAN client.
# Fresh flashes get no_symlinks from uci-defaults via the .bin; this block is for
# already-running boxes only. Idempotent (uci set + the data-dir script both
# no-op when already correct) and best-effort (never aborts the OTA on error).
uci set uhttpd.main.no_symlinks='1' 2>/dev/null || true
uci commit uhttpd 2>/dev/null || true
# Relocate /www/data -> /etc/fastfi/data now so the symlink exists before uhttpd
# reloads (init.d/fastfi also runs this on next boot; running it here is the
# immediate apply). The script is already on disk + executable at this point in
# the apply (file copy + chmod precede migrate.sh).
[ -x /usr/libexec/fastfi/core/fastfi-data-dir.sh ] && \
    /usr/libexec/fastfi/core/fastfi-data-dir.sh >/dev/null 2>&1 || true
/etc/init.d/uhttpd reload >/dev/null 2>&1 || \
    /etc/init.d/uhttpd restart >/dev/null 2>&1 || true

# ── SQM/shaping stack: opkg-install on existing boxes (F5) ──────────────────
# F5 (make SQM actually start + give every HTB class a leaf qdisc) needs tc +
# the cake/ifb kernel modules + sqm-scripts. A code-only OTA can't ship kernel
# modules as files, so install them via opkg from the matching feed at
# OTA-apply time (pre-reboot); the post-OTA boot then has the full shaping stack.
#
# Kernel modules require an exact vermagic match. All our .bin use the stock
# 24.10.7 kernel from the official feed, so the feed kmods install cleanly on a
# box running that image. A box on a DIFFERENT OpenWrt base is refused by opkg
# (kernel version mismatch) — SQM stays off and that box needs a .bin sysupgrade.
# Idempotent (only fires if SQM is missing), WAN-guarded, best-effort + logged;
# never aborts the OTA (sh exits 0 below regardless of opkg's result).
if ! which tc >/dev/null 2>&1 || ! ls /lib/modules/*/sch_cake.ko >/dev/null 2>&1; then
    logger -t fastfi "OTA migrate: SQM stack missing — attempting opkg install..."
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        sed -i 's|https://|http://|g' /etc/opkg/distfeeds.conf 2>/dev/null
        opkg update >/dev/null 2>&1
        if opkg install tc-tiny kmod-sched-core kmod-sched-cake kmod-ifb sqm-scripts >/dev/null 2>&1; then
            logger -t fastfi "OTA migrate: SQM stack installed (tc + cake/ifb kmods + sqm-scripts)"
        else
            logger -t fastfi "OTA migrate: SQM opkg install FAILED (kernel mismatch? needs .bin sysupgrade)"
        fi
    else
        logger -t fastfi "OTA migrate: no internet — cannot install SQM stack (needs .bin or later boot with WAN)"
    fi
else
    logger -t fastfi "OTA migrate: SQM stack already present — skip"
fi

# -- Remove the Vendo Zones (sub-vendo) + AP VLAN backend ---------------------
# Both features were removed: neither worked in the field. The OTA .tar.gz apply
# is additive (cp -r never deletes), so the retired files have to be removed
# here or they linger and keep running on deployed boxes.
#
# fastfi-vendos re-materialized sub-vendo L3 interfaces from the DB on every
# boot. Its reconcile already pcall()s the now-deleted route module and no-ops,
# but stop+disable+remove it so it is gone rather than silently failing.
#
# Any sv<id> interfaces / DHCP pools left on the box are torn down below.
/etc/init.d/fastfi-vendos stop >/dev/null 2>&1
/etc/init.d/fastfi-vendos disable >/dev/null 2>&1
rm -f /etc/init.d/fastfi-vendos 2>/dev/null
rm -f /usr/lib/lua/fastfi/api/routes/subvendo.lua 2>/dev/null
rm -f /usr/lib/lua/fastfi/db/subvendo.lua 2>/dev/null
rm -f /etc/fastfi/vlan_default.sql 2>/dev/null

# Tear down any sv<id> L3 interfaces + DHCP pools the feature left behind.
# Operators confirmed the zones were never actually used in the field, and with
# the backend gone nothing manages or recreates them -- leaving them would strand
# an unused static interface and DHCP pool on every box that ever clicked Apply.
#
# Scoped strictly to sections named sv<digits>. br_lan / lan / wan / vpntun can
# never match that pattern, so the customer LAN and the WAN are untouched.
# Changes are committed but NOT reloaded here: the post-apply reboot brings the
# network up cleanly, which is far safer than bouncing netifd mid-OTA.
_sv_removed=0
for _s in $(uci show network 2>/dev/null | sed -n 's/^network\.\(sv[0-9][0-9]*\)=interface$/\1/p'); do
    uci -q delete "network.${_s}" 2>/dev/null && _sv_removed=$((_sv_removed+1))
done
for _s in $(uci show dhcp 2>/dev/null | sed -n 's/^dhcp\.\(sv[0-9][0-9]*\)=dhcp$/\1/p'); do
    uci -q delete "dhcp.${_s}" 2>/dev/null
done
# Drop sv<id> members from any firewall zone's network list (added to the lan
# zone at apply time). Iterate zones -- the index is not guaranteed to be 0.
_zi=0
while uci -q get "firewall.@zone[${_zi}]" >/dev/null 2>&1; do
    for _n in $(uci -q get "firewall.@zone[${_zi}].network" 2>/dev/null); do
        case "$_n" in
            sv[0-9]*) uci -q del_list "firewall.@zone[${_zi}].network=${_n}" 2>/dev/null ;;
        esac
    done
    _zi=$((_zi+1))
done
uci commit network 2>/dev/null || true
uci commit dhcp 2>/dev/null || true
uci commit firewall 2>/dev/null || true

# If a zone apply had previously rewritten br-lan's ports to the DSA conduit
# (eth0 / eth0.<vid>), the physical lan* ports were dropped out of the bridge.
# heal_br_lan() is DSA-only, self-guarding and a no-op when br-lan is healthy,
# so this is safe to run unconditionally.
if /usr/bin/env lua -e 'local ok,n = pcall(require,"fastfi.util.network"); if ok and n and n.heal_br_lan and n.heal_br_lan() then os.exit(0) end os.exit(1)' >/dev/null 2>&1; then
    logger -t fastfi "OTA migrate: br-lan ports healed after sub-vendo removal"
fi

# Email-based password recovery is gone (replaced by the licence-key flow), so
# msmtp and its config are no longer used. /etc/msmtprc shipped a real Gmail
# username and password in every firmware image -- the OTA apply is additive and
# never deletes, so removing it from the repo is not enough: it has to be deleted
# here or every already-deployed router keeps those credentials on disk.
# The package itself is left installed (opkg remove mid-OTA is riskier than a few
# idle KB); new .bin builds simply no longer include it.
rm -f /etc/msmtprc 2>/dev/null
/etc/init.d/msmtp stop >/dev/null 2>&1
/etc/init.d/msmtp disable >/dev/null 2>&1

logger -t fastfi "OTA migrate: Vendo Zones + AP VLAN backend removed (${_sv_removed} sv interface(s) cleared); msmtprc credentials deleted"

exit 0