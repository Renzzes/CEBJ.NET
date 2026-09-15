local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")
local M = {}

function M.list_blocks()
    local rows = sqlite.query_list(config.CONFIG_DB,
        "SELECT id, mac, reason, blocked_at, blocked_by FROM mac_blocklist ORDER BY blocked_at DESC;") or {}
    local out = {}
    for _, r in ipairs(rows) do
        table.insert(out, {
            id = tonumber(r[1]), mac = r[2], reason = r[3] or "",
            blocked_at = tonumber(r[4]) or 0, blocked_by = r[5] or ""
        })
    end
    return out
end

function M.is_blocked(mac)
    mac = tostring(mac or ""):upper()
    local row = sqlite.query_row(config.CONFIG_DB, string.format(
        "SELECT id FROM mac_blocklist WHERE mac='%s' LIMIT 1;", sqlite.quote(mac)))
    return row ~= nil
end

function M.block(mac, reason, blocked_by)
    mac = tostring(mac or ""):upper():gsub("%-", ":")
    if not mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        return false, "Invalid MAC"
    end
    sqlite.execute(config.CONFIG_DB, string.format(
        "INSERT OR REPLACE INTO mac_blocklist (mac, reason, blocked_at, blocked_by) VALUES ('%s', '%s', %d, '%s');",
        sqlite.quote(mac), sqlite.quote(reason or ""), os.time(), sqlite.quote(blocked_by or "")))
    pcall(function()
        os.execute("/usr/bin/lua /usr/libexec/fastfi/core/fastfi-macblock.lua apply >/dev/null 2>&1 &")
    end)
    return true
end

function M.unblock(mac_or_id)
    local id = tonumber(mac_or_id)
    if id then
        sqlite.execute(config.CONFIG_DB, string.format("DELETE FROM mac_blocklist WHERE id=%d;", id))
    else
        local mac = tostring(mac_or_id or ""):upper()
        sqlite.execute(config.CONFIG_DB, string.format("DELETE FROM mac_blocklist WHERE mac='%s';", sqlite.quote(mac)))
    end
    pcall(function()
        os.execute("/usr/bin/lua /usr/libexec/fastfi/core/fastfi-macblock.lua apply >/dev/null 2>&1 &")
    end)
    return true
end

function M.collect_devices()
    local by_mac = {}

    local function upsert(mac, fields)
        mac = tostring(mac or ""):upper()
        if not mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then return end
        local d = by_mac[mac] or { mac = mac, hostname = "", ip = "", status = "offline", auth = "unauthenticated",
            session = nil, radio = "", signal = "", blocked = false, plan_id = 0, plan_client_id = 0 }
        for k, v in pairs(fields or {}) do
            if v ~= nil and v ~= "" then d[k] = v end
        end
        by_mac[mac] = d
    end

    -- sessions
    local sessions = sqlite.query_list(config.SESSIONS_DB,
        "SELECT mac_address, session_end, remaining, active, paused, plan_id, plan_client_id, download, upload FROM sessions;") or {}
    local now = os.time()
    for _, s in ipairs(sessions) do
        local mac = s[1]
        local end_ts = tonumber(s[2]) or 0
        local active = tonumber(s[4]) or 0
        local remaining = tonumber(s[3]) or 0
        if remaining <= 0 and end_ts > now then remaining = end_ts - now end
        upsert(mac, {
            status = (active == 1 and remaining > 0) and "online" or "offline",
            auth = (active == 1 and remaining > 0) and "authenticated" or "unauthenticated",
            session = {
                session_end = end_ts, remaining = remaining, paused = tonumber(s[5]) or 0,
                plan_id = tonumber(s[6]) or 0, plan_client_id = tonumber(s[7]) or 0,
                download = tonumber(s[8]) or 0, upload = tonumber(s[9]) or 0
            },
            plan_id = tonumber(s[6]) or 0,
            plan_client_id = tonumber(s[7]) or 0
        })
    end

    -- DHCP leases
    local lease_paths = { "/tmp/dhcp.leases", "/var/dhcp.leases", "/tmp/hosts/odhcpd" }
    for _, path in ipairs(lease_paths) do
        local f = io.open(path, "r")
        if f then
            for line in f:lines() do
                -- dnsmasq: expiry mac ip hostname clientid
                local exp, mac, ip, host = line:match("^(%d+)%s+(%S+)%s+(%S+)%s+(%S+)")
                if mac and ip then
                    upsert(mac, { ip = ip, hostname = (host ~= "*") and host or "", status = "online" })
                else
                    -- odhcpd style loosely
                    local mac2, ip2 = line:match("(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x).-(%d+%.%d+%.%d+%.%d+)")
                    if mac2 then upsert(mac2, { ip = ip2 or "", status = "online" }) end
                end
            end
            f:close()
        end
    end

    -- iwinfo associations (best-effort)
    local p = io.popen("iwinfo 2>/dev/null | awk '/^wlan|^rai|^rax|^wl/{print $1}'")
    if p then
        local ifaces = {}
        for iface in p:lines() do table.insert(ifaces, iface) end
        p:close()
        for _, iface in ipairs(ifaces) do
            local a = io.popen("iwinfo " .. iface .. " assoclist 2>/dev/null")
            if a then
                for line in a:lines() do
                    local mac = line:match("(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)")
                    local signal = line:match("(-%d+)%s*dBm")
                    if mac then
                        upsert(mac, { status = "online", radio = iface, signal = signal and (signal .. " dBm") or "" })
                    end
                end
                a:close()
            end
        end
    end

    -- plan device names
    local plan_devs = sqlite.query_list(config.CONFIG_DB,
        "SELECT mac, hostname, client_id FROM plan_devices;") or {}
    for _, d in ipairs(plan_devs) do
        upsert(d[1], { hostname = d[2], plan_client_id = tonumber(d[3]) or 0 })
    end

    -- blocks
    for _, b in ipairs(M.list_blocks()) do
        upsert(b.mac, { blocked = true, status = "blocked" })
    end

    local out = {}
    for _, d in pairs(by_mac) do table.insert(out, d) end
    table.sort(out, function(a, b) return (a.mac or "") < (b.mac or "") end)
    return out
end

return M
