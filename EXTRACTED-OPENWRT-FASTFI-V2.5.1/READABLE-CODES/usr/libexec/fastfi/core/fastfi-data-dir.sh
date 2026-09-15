#!/bin/sh
# Move the SQLite data out of the uhttpd document root.
#
# /www is uhttpd's docroot, so /www/data/*.db were downloadable by any client on
# the LAN — vouchers, licence key, sessions, sales, and the admin session tokens.
# The real directory now lives in /etc/fastfi/data and /www/data is a symlink to
# it; uhttpd runs with -S so it will not serve through the link.
#
# This MUST run before anything opens a database, because config.lua does
# `mkdir -p /www/data` on first use and would recreate a REAL directory,
# reopening the hole. It is called from init.d/fastfi (before db.init) and again
# from rc.local as the every-boot safety net.
set -e

REAL=/etc/fastfi/data
LINK=/www/data

mkdir -p "$REAL"

# Already correct? nothing to do.
if [ -L "$LINK" ] && [ "$(readlink -f "$LINK")" = "$(readlink -f "$REAL")" ]; then
    exit 0
fi

# A real directory is sitting where the symlink should be: migrate its contents.
if [ -d "$LINK" ] && [ ! -L "$LINK" ]; then
    cp -a "$LINK/." "$REAL/" 2>/dev/null || true
    rm -rf "$LINK"
fi

ln -sfn "$REAL" "$LINK"
chmod 700 "$REAL" 2>/dev/null || true
logger -t fastfi "data dir: /www/data -> $REAL (uhttpd must run with -S)"
exit 0