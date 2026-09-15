local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")
local M = {}

local function norm_mac(mac)
    mac = tostring(mac or ""):upper():gsub("%-", ":"):gsub("%s+", "")
    if mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then return mac end
    return nil
end

function M.ensure_builtin_aps()
    -- Built-in Ruijie radios as Access Points for coverage matrix
    local builtins = {
        { name = "Built-in AP 2.4GHz", iface = "radio0", location = "Ruijie onboard" },
        { name = "Built-in AP 5GHz", iface = "radio1", location = "Ruijie onboard" },
    }
    for _, b in ipairs(builtins) do
        local row = sqlite.query_row(config.CONFIG_DB, string.format(
            "SELECT id FROM access_points WHERE kind='builtin' AND iface='%s' LIMIT 1;",
            sqlite.quote(b.iface)))
        if not row then
            sqlite.execute(config.CONFIG_DB, string.format([[
                INSERT INTO access_points (name, kind, iface, mac, ip, location, status, enabled, created_at)
                VALUES ('%s', 'builtin', '%s', '', '', '%s', 'online', 1, %d);
            ]], sqlite.quote(b.name), sqlite.quote(b.iface), sqlite.quote(b.location), os.time()))
        end
    end
end

function M.list()
    M.ensure_builtin_aps()
    local rows = sqlite.query_list(config.CONFIG_DB, [[
        SELECT id, name, kind, iface, mac, ip, location, status, enabled, created_at, notes
        FROM access_points ORDER BY kind ASC, id ASC;
    ]]) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local ap = {
            id = tonumber(r[1]), name = r[2], kind = r[3] or "lan",
            iface = r[4] or "", mac = r[5] or "", ip = r[6] or "",
            location = r[7] or "", status = r[8] or "unknown",
            enabled = tonumber(r[9]) or 1, created_at = tonumber(r[10]) or 0,
            notes = r[11] or "", esp = {}
        }
        local esp_rows = sqlite.query_list(config.ESP_DB, string.format(
            "SELECT id, slot_name, slot_mac, status, license_status, last_seen FROM esp_slots WHERE ap_id=%d ORDER BY id;",
            ap.id)) or {}
        for _, e in ipairs(esp_rows) do
            table.insert(ap.esp, {
                id = tonumber(e[1]), name = e[2], mac = e[3],
                status = e[4], license_status = e[5], last_seen = tonumber(e[6]) or 0
            })
        end
        table.insert(out, ap)
    end
    return out
end

function M.save(p)
    local id = tonumber(p.id)
    local name = tostring(p.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false, "Name required" end
    local kind = (p.kind == "builtin") and "builtin" or "lan"
    local iface = tostring(p.iface or "")
    local mac = norm_mac(p.mac) or ""
    local ip = tostring(p.ip or "")
    local location = tostring(p.location or "")
    local notes = tostring(p.notes or "")
    local enabled = (tonumber(p.enabled) == 0) and 0 or 1
    local status = tostring(p.status or "unknown")

    if id then
        -- don't demote builtin kind accidentally
        local existing = sqlite.query_row(config.CONFIG_DB, string.format(
            "SELECT kind FROM access_points WHERE id=%d;", id))
        if existing and existing[1] == "builtin" then kind = "builtin" end
        sqlite.execute(config.CONFIG_DB, string.format([[
            UPDATE access_points SET name='%s', mac='%s', ip='%s', location='%s',
            notes='%s', enabled=%d, status='%s' WHERE id=%d;
        ]], sqlite.quote(name), sqlite.quote(mac), sqlite.quote(ip), sqlite.quote(location),
            sqlite.quote(notes), enabled, sqlite.quote(status), id))
        return true, id
    end
    if kind == "builtin" then return false, "Cannot create builtin AP manually" end
    sqlite.execute(config.CONFIG_DB, string.format([[
        INSERT INTO access_points (name, kind, iface, mac, ip, location, status, enabled, created_at, notes)
        VALUES ('%s', 'lan', '', '%s', '%s', '%s', '%s', %d, %d, '%s');
    ]], sqlite.quote(name), sqlite.quote(mac), sqlite.quote(ip), sqlite.quote(location),
        sqlite.quote(status), enabled, os.time(), sqlite.quote(notes)))
    local row = sqlite.query_row(config.CONFIG_DB, "SELECT last_insert_rowid();")
    return true, tonumber(row and row[1])
end

function M.delete(id)
    id = tonumber(id)
    if not id then return false, "Invalid id" end
    local row = sqlite.query_row(config.CONFIG_DB, string.format(
        "SELECT kind FROM access_points WHERE id=%d;", id))
    if not row then return false, "Not found" end
    if row[1] == "builtin" then return false, "Cannot delete built-in radio AP" end
    pcall(function()
        sqlite.execute(config.ESP_DB, string.format("UPDATE esp_slots SET ap_id=0 WHERE ap_id=%d;", id))
    end)
    sqlite.execute(config.CONFIG_DB, string.format("DELETE FROM access_points WHERE id=%d;", id))
    return true
end

function M.bind_esp(esp_id, ap_id)
    esp_id = tonumber(esp_id)
    ap_id = tonumber(ap_id) or 0
    if not esp_id then return false, "ESP id required" end
    if ap_id > 0 then
        local ap = sqlite.query_row(config.CONFIG_DB, string.format(
            "SELECT id FROM access_points WHERE id=%d;", ap_id))
        if not ap then return false, "AP not found" end
    end
    pcall(function()
        sqlite.execute(config.ESP_DB, "ALTER TABLE esp_slots ADD COLUMN ap_id INTEGER DEFAULT 0;")
    end)
    sqlite.execute(config.ESP_DB, string.format(
        "UPDATE esp_slots SET ap_id=%d WHERE id=%d;", ap_id, esp_id))
    return true
end

local function day_start()
    local t = os.date("*t")
    t.hour, t.min, t.sec = 0, 0, 0
    return os.time(t)
end

local function count_radio_clients(iface_hint)
    -- best-effort: match iwinfo iface containing hint or all wlan
    local total = 0
    local p = io.popen("iwinfo 2>/dev/null | awk '/^wlan|^rai|^rax|^wl/{print $1}'")
    if not p then return 0 end
    local ifaces = {}
    for line in p:lines() do table.insert(ifaces, line) end
    p:close()
    for _, iface in ipairs(ifaces) do
        local use = true
        if iface_hint and iface_hint ~= "" then
            -- radio0 ~ first, radio1 ~ second roughly; also accept exact iface
            use = (iface == iface_hint) or iface:find(iface_hint, 1, true)
        end
        if use then
            local a = io.popen("iwinfo " .. iface .. " assoclist 2>/dev/null | grep -c ':'")
            if a then
                local n = tonumber(a:read("*a")) or 0
                a:close()
                total = total + n
            end
        end
    end
    return total
end

function M.dashboard_matrix()
    M.ensure_builtin_aps()
    local aps = M.list()
    local start = day_start()
    local now = os.time()
    local rows = {}
    local tot = { connected = 0, waiting = 0, sessions = 0, sales = 0 }

    for _, ap in ipairs(aps) do
        if ap.enabled == 1 then
            local esps = ap.esp
            if #esps == 0 then
                -- still show AP row with radio clients / zeros
                local connected = 0
                if ap.kind == "builtin" then
                    connected = count_radio_clients(ap.iface)
                end
                local waiting = 0
                local sessions = 0
                local sales = 0
                -- unassigned sessions/sales only on first builtin to avoid double count — skip for empty
                table.insert(rows, {
                    ap_id = ap.id, ap_name = ap.name, ap_kind = ap.kind,
                    esp_id = 0, esp_name = "—",
                    connected = connected, waiting = waiting, sessions = sessions, sales = sales
                })
                tot.connected = tot.connected + connected
            else
                for _, esp in ipairs(esps) do
                    local sid = esp.id
                    local sales_row = sqlite.query_row(config.SESSIONS_DB, string.format(
                        "SELECT COALESCE(SUM(amount),0) FROM sales WHERE sub_vendo_id=%d AND created_at>=%d;",
                        sid, start))
                    local sales = tonumber(sales_row and sales_row[1]) or 0
                    local sess_row = sqlite.query_row(config.SESSIONS_DB, string.format(
                        "SELECT COUNT(*) FROM sessions WHERE sub_vendo_id=%d AND ((active=1 AND session_end>%d) OR (paused=1 AND remaining>0));",
                        sid, now))
                    local sessions = tonumber(sess_row and sess_row[1]) or 0
                    local connected = sessions
                    if ap.kind == "builtin" and connected == 0 then
                        -- fall back share of radio clients for display when no sub_vendo tagging
                        connected = 0
                    end
                    local waiting = 0
                    if esp.status == "online" then
                        -- locked clients waiting on this ESP
                        local w = sqlite.query_row(config.ESP_DB, string.format(
                            "SELECT COUNT(*) FROM esp_slots WHERE id=%d AND locked_by IS NOT NULL AND locked_by!='' ;", sid))
                        waiting = tonumber(w and w[1]) or 0
                    end
                    table.insert(rows, {
                        ap_id = ap.id, ap_name = ap.name, ap_kind = ap.kind,
                        esp_id = sid, esp_name = esp.name or ("ESP #" .. tostring(sid)),
                        connected = connected, waiting = waiting, sessions = sessions, sales = sales,
                        esp_status = esp.status
                    })
                    tot.connected = tot.connected + connected
                    tot.waiting = tot.waiting + waiting
                    tot.sessions = tot.sessions + sessions
                    tot.sales = tot.sales + sales
                end
            end
        end
    end

    -- If no ESP-tagged sessions, add overall live session count into first builtin row for honest totals
    local live = sqlite.query_row(config.SESSIONS_DB, string.format(
        "SELECT COUNT(*) FROM sessions WHERE (active=1 AND session_end>%d) OR (paused=1 AND remaining>0);", now))
    local live_n = tonumber(live and live[1]) or 0
    if tot.sessions == 0 and live_n > 0 and #rows > 0 then
        rows[1].sessions = live_n
        rows[1].connected = math.max(rows[1].connected, live_n)
        tot.sessions = live_n
        tot.connected = math.max(tot.connected, live_n)
    end
    local sales_today = sqlite.query_row(config.SESSIONS_DB, string.format(
        "SELECT COALESCE(SUM(amount),0) FROM sales WHERE created_at>=%d;", start))
    local sales_n = tonumber(sales_today and sales_today[1]) or 0
    if tot.sales == 0 and sales_n > 0 and #rows > 0 then
        rows[1].sales = sales_n
        tot.sales = sales_n
    end

    return rows, tot
end

function M.probe_lan_status(ap)
    if ap.kind == "builtin" then
        return "online"
    end
    if ap.ip and ap.ip ~= "" then
        local f = io.popen("ping -c 1 -W 1 " .. ap.ip:gsub("[^%d%.]", "") .. " >/dev/null 2>&1; echo $?")
        if f then
            local code = (f:read("*a") or ""):match("(%d+)")
            f:close()
            if code == "0" then return "online" end
        end
    end
    if ap.mac and ap.mac ~= "" then
        local f = io.open("/proc/net/arp", "r")
        if f then
            local mac = ap.mac:lower()
            for line in f:lines() do
                if line:lower():find(mac, 1, true) then
                    f:close()
                    return "online"
                end
            end
            f:close()
        end
    end
    return "offline"
end

function M.refresh_statuses()
    for _, ap in ipairs(M.list()) do
        local st = M.probe_lan_status(ap)
        sqlite.execute(config.CONFIG_DB, string.format(
            "UPDATE access_points SET status='%s' WHERE id=%d;", sqlite.quote(st), ap.id))
    end
end

return M
