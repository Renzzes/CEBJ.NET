local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")
local M = {}

-- Normalize Wi‑Fi band preference for dual-band Ruijie profiles
function M.normalize_band(v)
    local s = tostring(v or "auto"):lower():gsub("%s+", "")
    if s == "2.4" or s == "2.4ghz" or s == "24" or s == "2g" then return "2.4" end
    if s == "5" or s == "5ghz" or s == "5g" then return "5" end
    return "auto"
end

-- Bandwidth profiles
function M.list_profiles()
    local rows = sqlite.query_list(config.CONFIG_DB,
        "SELECT id, name, down_kbps, up_kbps, enabled, created_at, band FROM bandwidth_profiles ORDER BY id ASC;") or {}
    local out = {}
    for _, r in ipairs(rows) do
        table.insert(out, {
            id = tonumber(r[1]), name = r[2], down_kbps = tonumber(r[3]) or 0,
            up_kbps = tonumber(r[4]) or 0, enabled = tonumber(r[5]) or 0,
            created_at = tonumber(r[6]) or 0, band = M.normalize_band(r[7])
        })
    end
    return out
end

function M.save_profile(p)
    local id = tonumber(p.id)
    local name = tostring(p.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false, "Name required" end
    local down = tonumber(p.down_kbps) or 0
    local up = tonumber(p.up_kbps) or 0
    local enabled = (tonumber(p.enabled) == 0) and 0 or 1
    local band = M.normalize_band(p.band)
    if id then
        sqlite.execute(config.CONFIG_DB, string.format(
            "UPDATE bandwidth_profiles SET name='%s', down_kbps=%d, up_kbps=%d, enabled=%d, band='%s' WHERE id=%d;",
            sqlite.quote(name), down, up, enabled, sqlite.quote(band), id))
        return true, id
    end
    sqlite.execute(config.CONFIG_DB, string.format(
        "INSERT INTO bandwidth_profiles (name, down_kbps, up_kbps, enabled, created_at, band) VALUES ('%s', %d, %d, %d, %d, '%s');",
        sqlite.quote(name), down, up, enabled, os.time(), sqlite.quote(band)))
    local row = sqlite.query_row(config.CONFIG_DB, "SELECT last_insert_rowid();")
    return true, tonumber(row and row[1])
end

function M.delete_profile(id)
    id = tonumber(id)
    if not id then return false end
    sqlite.execute(config.CONFIG_DB, string.format("UPDATE plans SET profile_id=NULL WHERE profile_id=%d;", id))
    sqlite.execute(config.CONFIG_DB, string.format("DELETE FROM bandwidth_profiles WHERE id=%d;", id))
    return true
end

function M.get_profile(id)
    id = tonumber(id)
    if not id then return nil end
    local r = sqlite.query_row(config.CONFIG_DB, string.format(
        "SELECT id, name, down_kbps, up_kbps, enabled, band FROM bandwidth_profiles WHERE id=%d;", id))
    if not r then return nil end
    return {
        id = tonumber(r[1]), name = r[2], down_kbps = tonumber(r[3]) or 0,
        up_kbps = tonumber(r[4]) or 0, enabled = tonumber(r[5]) or 0,
        band = M.normalize_band(r[6])
    }
end

-- Plans
function M.list_plans()
    local rows = sqlite.query_list(config.CONFIG_DB, [[
        SELECT p.id, p.name, p.price, p.duration_min, p.data_mb, p.profile_id, p.pause_limit, p.enabled, p.created_at,
               b.name, b.down_kbps, b.up_kbps
        FROM plans p LEFT JOIN bandwidth_profiles b ON b.id = p.profile_id
        ORDER BY p.id ASC;
    ]]) or {}
    local out = {}
    for _, r in ipairs(rows) do
        table.insert(out, {
            id = tonumber(r[1]), name = r[2], price = tonumber(r[3]) or 0,
            duration_min = tonumber(r[4]) or 0, data_mb = tonumber(r[5]) or 0,
            profile_id = tonumber(r[6]) or 0, pause_limit = tonumber(r[7]) or 0,
            enabled = tonumber(r[8]) or 0, created_at = tonumber(r[9]) or 0,
            profile_name = r[10], down_kbps = tonumber(r[11]) or 0, up_kbps = tonumber(r[12]) or 0
        })
    end
    return out
end

function M.get_plan(id)
    id = tonumber(id)
    if not id then return nil end
    for _, p in ipairs(M.list_plans()) do
        if p.id == id then return p end
    end
    return nil
end

function M.save_plan(p)
    local id = tonumber(p.id)
    local name = tostring(p.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false, "Name required" end
    local price = tonumber(p.price) or 0
    local duration = tonumber(p.duration_min) or 0
    local data_mb = tonumber(p.data_mb) or 0
    local profile_id = tonumber(p.profile_id) or 0
    local pause_limit = tonumber(p.pause_limit) or 0
    local enabled = (tonumber(p.enabled) == 0) and 0 or 1
    local profile_sql = (profile_id > 0) and tostring(profile_id) or "NULL"
    if id then
        sqlite.execute(config.CONFIG_DB, string.format(
            "UPDATE plans SET name='%s', price=%d, duration_min=%d, data_mb=%d, profile_id=%s, pause_limit=%d, enabled=%d WHERE id=%d;",
            sqlite.quote(name), price, duration, data_mb, profile_sql, pause_limit, enabled, id))
        return true, id
    end
    sqlite.execute(config.CONFIG_DB, string.format(
        "INSERT INTO plans (name, price, duration_min, data_mb, profile_id, pause_limit, enabled, created_at) VALUES ('%s', %d, %d, %d, %s, %d, %d, %d);",
        sqlite.quote(name), price, duration, data_mb, profile_sql, pause_limit, enabled, os.time()))
    local row = sqlite.query_row(config.CONFIG_DB, "SELECT last_insert_rowid();")
    return true, tonumber(row and row[1])
end

function M.delete_plan(id)
    id = tonumber(id)
    if not id then return false end
    sqlite.execute(config.CONFIG_DB, string.format("UPDATE plan_clients SET plan_id=NULL WHERE plan_id=%d;", id))
    sqlite.execute(config.CONFIG_DB, string.format("DELETE FROM plans WHERE id=%d;", id))
    return true
end

-- Plan clients / devices
function M.list_clients()
    local rows = sqlite.query_list(config.CONFIG_DB, [[
        SELECT c.id, c.name, c.contact, c.plan_id, c.notes, c.status, c.created_at, p.name
        FROM plan_clients c LEFT JOIN plans p ON p.id = c.plan_id
        ORDER BY c.id DESC;
    ]]) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local client = {
            id = tonumber(r[1]), name = r[2], contact = r[3] or "",
            plan_id = tonumber(r[4]) or 0, notes = r[5] or "", status = r[6] or "active",
            created_at = tonumber(r[7]) or 0, plan_name = r[8] or "", devices = {}
        }
        local devs = sqlite.query_list(config.CONFIG_DB, string.format(
            "SELECT id, mac, hostname, created_at FROM plan_devices WHERE client_id=%d;", client.id)) or {}
        for _, d in ipairs(devs) do
            table.insert(client.devices, {
                id = tonumber(d[1]), mac = d[2], hostname = d[3] or "", created_at = tonumber(d[4]) or 0
            })
        end
        table.insert(out, client)
    end
    return out
end

function M.save_client(p)
    local id = tonumber(p.id)
    local name = tostring(p.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false, "Name required" end
    local contact = tostring(p.contact or "")
    local notes = tostring(p.notes or "")
    local status = tostring(p.status or "active")
    local plan_id = tonumber(p.plan_id) or 0
    local plan_sql = (plan_id > 0) and tostring(plan_id) or "NULL"
    if id then
        sqlite.execute(config.CONFIG_DB, string.format(
            "UPDATE plan_clients SET name='%s', contact='%s', plan_id=%s, notes='%s', status='%s' WHERE id=%d;",
            sqlite.quote(name), sqlite.quote(contact), plan_sql, sqlite.quote(notes), sqlite.quote(status), id))
        return true, id
    end
    sqlite.execute(config.CONFIG_DB, string.format(
        "INSERT INTO plan_clients (name, contact, plan_id, notes, status, created_at) VALUES ('%s', '%s', %s, '%s', '%s', %d);",
        sqlite.quote(name), sqlite.quote(contact), plan_sql, sqlite.quote(notes), sqlite.quote(status), os.time()))
    local row = sqlite.query_row(config.CONFIG_DB, "SELECT last_insert_rowid();")
    return true, tonumber(row and row[1])
end

function M.delete_client(id)
    id = tonumber(id)
    if not id then return false end
    sqlite.execute(config.CONFIG_DB, string.format("DELETE FROM plan_devices WHERE client_id=%d;", id))
    sqlite.execute(config.CONFIG_DB, string.format("DELETE FROM plan_clients WHERE id=%d;", id))
    return true
end

function M.attach_device(client_id, mac, hostname)
    client_id = tonumber(client_id)
    mac = tostring(mac or ""):upper():gsub("%-", ":")
    if not client_id or not mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        return false, "Invalid client or MAC"
    end
    sqlite.execute(config.CONFIG_DB, string.format("DELETE FROM plan_devices WHERE mac='%s';", sqlite.quote(mac)))
    sqlite.execute(config.CONFIG_DB, string.format(
        "INSERT INTO plan_devices (client_id, mac, hostname, created_at) VALUES (%d, '%s', '%s', %d);",
        client_id, sqlite.quote(mac), sqlite.quote(hostname or ""), os.time()))
    return true
end

function M.detach_device(mac_or_id)
    local id = tonumber(mac_or_id)
    if id then
        sqlite.execute(config.CONFIG_DB, string.format("DELETE FROM plan_devices WHERE id=%d;", id))
        return true
    end
    local mac = tostring(mac_or_id or ""):upper()
    sqlite.execute(config.CONFIG_DB, string.format("DELETE FROM plan_devices WHERE mac='%s';", sqlite.quote(mac)))
    return true
end

return M
