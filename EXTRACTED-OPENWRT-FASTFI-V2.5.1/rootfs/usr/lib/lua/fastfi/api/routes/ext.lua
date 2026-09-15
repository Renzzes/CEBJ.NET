local users = require("fastfi.db.users")
local security = require("fastfi.security")
local activity = require("fastfi.db.activity")
local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")
local file_util = require("fastfi.util.file")
local json_util = require("fastfi.util.json")
local M = {}

local function require_owner()
    if not security.check_admin_session() then return false, "Unauthorized" end
    if not security.require_owner() then return false, "Owner role required" end
    return true
end

function M.list_admin_users(params)
    local ok, err = require_owner()
    if not ok then return { status = "error", message = err } end
    return { status = "ok", data = users.list_users() }
end

function M.create_admin_user(params)
    local ok, err = require_owner()
    if not ok then return { status = "error", message = err } end
    local success, msg = users.create_user(params.username, params.password, params.role)
    if not success then return { status = "error", message = msg } end
    local sess = security.get_session_user()
    users.audit(sess and sess.username or "owner", "user_create", tostring(params.username))
    activity.add("info", "Operator added", tostring(params.username))
    return { status = "ok" }
end

function M.delete_admin_user(params)
    local ok, err = require_owner()
    if not ok then return { status = "error", message = err } end
    local success, msg = users.delete_user(params.id)
    if not success then return { status = "error", message = msg } end
    return { status = "ok" }
end

function M.activity_feed(params)
    return { status = "ok", data = activity.list(tonumber(params.limit) or 50) }
end

function M.audit_feed(params)
    local ok, err = require_owner()
    if not ok then return { status = "error", message = err } end
    return { status = "ok", data = activity.list_audit(tonumber(params.limit) or 50) }
end

function M.get_branding(params)
    local row = sqlite.query_row(config.CONFIG_DB,
        "SELECT login_logo, nav_logo, portal_logo, shop_name, voucher_template_note, backup_schedule_enabled, sms_enabled, sms_provider, sms_endpoint FROM config LIMIT 1;")
    return {
        status = "ok",
        login_logo = (row and row[1]) or "",
        nav_logo = (row and row[2]) or "",
        portal_logo = (row and row[3]) or "",
        shop_name = (row and row[4]) or "KonekSik-Fi",
        voucher_template_note = (row and row[5]) or "",
        backup_schedule_enabled = tonumber(row and row[6]) or 0,
        sms_enabled = tonumber(row and row[7]) or 0,
        sms_provider = (row and row[8]) or "none",
        sms_endpoint = (row and row[9]) or ""
    }
end

function M.set_branding(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local shop = tostring(params.shop_name or "KonekSik-Fi")
    local note = tostring(params.voucher_template_note or "")
    local sched = (tonumber(params.backup_schedule_enabled) == 1) and 1 or 0
    local sms_en = (tonumber(params.sms_enabled) == 1) and 1 or 0
    local sms_prov = tostring(params.sms_provider or "none")
    local sms_ep = tostring(params.sms_endpoint or "")
    sqlite.execute(config.CONFIG_DB, string.format(
        "UPDATE config SET shop_name='%s', voucher_template_note='%s', backup_schedule_enabled=%d, sms_enabled=%d, sms_provider='%s', sms_endpoint='%s' WHERE id=1;",
        sqlite.quote(shop), sqlite.quote(note), sched, sms_en, sqlite.quote(sms_prov), sqlite.quote(sms_ep)))
    return { status = "ok" }
end

function M.upload_logo(params, req)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local kind = tostring(params.kind or "login")
    if kind ~= "login" and kind ~= "nav" and kind ~= "portal" then
        return { status = "error", message = "Invalid kind" }
    end
    if not req or not req.post_body or #req.post_body == 0 then
        return { status = "error", message = "Empty file upload" }
    end
    if #req.post_body > 2 * 1024 * 1024 then
        return { status = "error", message = "File too large (max 2MB)" }
    end
    os.execute("mkdir -p /www/data/branding /www/image/branding 2>/dev/null")
    local filename = kind .. "_logo.png"
    local path = "/www/image/branding/" .. filename
    if not file_util.write(path, req.post_body) then
        return { status = "error", message = "Write failed" }
    end
    local col = kind .. "_logo"
    local url = "/image/branding/" .. filename .. "?t=" .. tostring(os.time())
    sqlite.execute(config.CONFIG_DB, string.format(
        "UPDATE config SET %s='%s' WHERE id=1;", col, sqlite.quote(url)))
    activity.add("info", "Branding updated", kind .. " logo")
    return { status = "ok", url = url }
end

function M.clear_logo(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local kind = tostring(params.kind or "login")
    local col = kind .. "_logo"
    sqlite.execute(config.CONFIG_DB, string.format("UPDATE config SET %s='' WHERE id=1;", col))
    return { status = "ok" }
end

function M.radio_status(params)
    local radios = {}
    local p = io.popen("uci show wireless 2>/dev/null | grep '=wifi-device\\|=wifi-iface'")
    -- prefer iwinfo inventory
    local iw = io.popen("iwinfo 2>/dev/null")
    if iw then
        local current = nil
        for line in iw:lines() do
            local iface = line:match("^(%S+)%s+ESSID:")
            if iface then
                current = { iface = iface, ssid = "", channel = "", signal = "", clients = 0, band = "", txpower = "" }
                local ssid = line:match('ESSID:%s*"(.-)"')
                current.ssid = ssid or ""
                table.insert(radios, current)
            elseif current then
                local ch = line:match("Channel:%s*(%d+)")
                if ch then current.channel = ch end
                local tp = line:match("Tx%-Power:%s*(%d+)")
                if tp then current.txpower = tp end
                local mode = line:match("Mode:%s*(%S+)")
                if mode then current.mode = mode end
                if line:match("2%.4") or line:match("2GHz") then current.band = "2.4 GHz" end
                if line:match("5%.") or line:match("5GHz") then current.band = "5 GHz" end
            end
        end
        iw:close()
    end
    for _, r in ipairs(radios) do
        local a = io.popen("iwinfo " .. r.iface .. " assoclist 2>/dev/null | grep -c ':'")
        if a then
            local n = a:read("*a")
            a:close()
            r.clients = tonumber(n) or 0
        end
    end
    if p then p:close() end
    return { status = "ok", data = radios }
end

function M.radio_restart(params)
    if not security.require_owner() then
        return { status = "error", message = "Owner role required" }
    end
    local iface = tostring(params.iface or "")
    if iface ~= "" and iface:match("^[%w%.%-_]+$") then
        os.execute("wifi down " .. iface .. " >/dev/null 2>&1; sleep 1; wifi up " .. iface .. " >/dev/null 2>&1 &")
    else
        os.execute("wifi down >/dev/null 2>&1; sleep 1; wifi >/dev/null 2>&1 &")
    end
    activity.add("warning", "Radio restart", iface ~= "" and iface or "all")
    return { status = "ok", message = "Radio restart triggered" }
end

function M.sales_by_vendo(params)
    local rows = sqlite.query_list(config.SESSIONS_DB, [[
        SELECT COALESCE(sub_vendo_id, 0) as sid, SUM(amount), COUNT(*), SUM(coins)
        FROM sales GROUP BY COALESCE(sub_vendo_id, 0) ORDER BY sid;
    ]]) or {}
    local out = {}
    for _, r in ipairs(rows) do
        table.insert(out, {
            sub_vendo_id = tonumber(r[1]) or 0,
            amount = tonumber(r[2]) or 0,
            count = tonumber(r[3]) or 0,
            coins = tonumber(r[4]) or 0
        })
    end
    return { status = "ok", data = out }
end

function M.reports_summary(params)
    local period = tostring(params.period or "day")
    local now = os.time()
    local start = now - 86400
    if period == "week" then start = now - 7 * 86400
    elseif period == "month" then start = now - 30 * 86400 end
    local sales = sqlite.query_row(config.SESSIONS_DB, string.format(
        "SELECT COALESCE(SUM(amount),0), COUNT(*) FROM sales WHERE created_at >= %d;", start))
    local sessions = sqlite.query_row(config.SESSIONS_DB,
        "SELECT COUNT(*) FROM sessions WHERE active=1;")
    return {
        status = "ok",
        period = period,
        sales_total = tonumber(sales and sales[1]) or 0,
        sales_count = tonumber(sales and sales[2]) or 0,
        active_sessions = tonumber(sessions and sessions[1]) or 0,
        generated_at = now
    }
end

function M.sms_test(params)
    -- no-op provider stub
    local row = sqlite.query_row(config.CONFIG_DB, "SELECT sms_enabled, sms_provider FROM config LIMIT 1;")
    local enabled = tonumber(row and row[1]) or 0
    if enabled ~= 1 then
        return { status = "ok", message = "SMS disabled (stub)", sent = false }
    end
    return { status = "ok", message = "SMS provider stub — no message sent", sent = false, provider = row and row[2] }
end

function M.pricing_hub(params)
    local rates = {}
    local rrows = sqlite.query_list(config.CONFIG_DB,
        "SELECT id, price, minutes, download_mb, upload_mb, pause_limit, data_limit_mb FROM coin_rates ORDER BY price ASC;") or {}
    for _, r in ipairs(rrows) do
        table.insert(rates, {
            id = r[1], price = r[2], minutes = r[3], download_mb = r[4], upload_mb = r[5],
            pause_limit = r[6], data_limit_mb = r[7]
        })
    end
    local plans_db = require("fastfi.db.plans")
    return { status = "ok", rates = rates, plans = plans_db.list_plans(), profiles = plans_db.list_profiles() }
end

-- Role permission matrix (editable checkboxes in Operators UI)
local ROLE_PERM_FILE = (config.PATHS and config.PATHS.CONFIG_DIR or "/etc/fastfi") .. "/role_permissions.json"

local DEFAULT_ROLE_PERMS = {
    view_dashboard = { owner = true, admin = true, staff = true, viewer = true },
    manage_sessions = { owner = true, admin = true, staff = true, viewer = false },
    edit_rates = { owner = true, admin = true, staff = true, viewer = false },
    network = { owner = true, admin = true, staff = false, viewer = false },
    operators = { owner = true, admin = false, staff = false, viewer = false },
    ota = { owner = true, admin = true, staff = false, viewer = false },
    branding = { owner = true, admin = true, staff = false, viewer = false },
}

local function normalize_role_perms(raw)
    local function as_bool(v, fallback)
        if v == nil then return fallback end
        return (v == true or v == 1 or v == "1" or v == "true")
    end
    local out = {}
    for key, defaults in pairs(DEFAULT_ROLE_PERMS) do
        local row = (type(raw) == "table" and type(raw[key]) == "table") and raw[key] or {}
        out[key] = {
            owner = true,
            admin = as_bool(row.admin, defaults.admin),
            staff = as_bool(row.staff, defaults.staff),
            viewer = as_bool(row.viewer, defaults.viewer),
        }
    end
    return out
end

local function load_role_perms()
    local raw = file_util.read(ROLE_PERM_FILE)
    if not raw or raw == "" then
        return normalize_role_perms(nil)
    end
    local ok, decoded = pcall(json_util.decode, raw)
    if not ok or type(decoded) ~= "table" then
        return normalize_role_perms(nil)
    end
    return normalize_role_perms(decoded)
end

function M.get_role_permissions(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    return { status = "ok", data = load_role_perms(), defaults = DEFAULT_ROLE_PERMS }
end

function M.set_role_permissions(params)
    local ok, err = require_owner()
    if not ok then return { status = "error", message = err } end
    local incoming = params.permissions or params.data or params
    if type(incoming) ~= "table" then
        return { status = "error", message = "Invalid permissions payload" }
    end
    -- Accept either { permissions: { ... } } or flat map
    if incoming.permissions and type(incoming.permissions) == "table" then
        incoming = incoming.permissions
    end
    local normalized = normalize_role_perms(incoming)
    file_util.write(ROLE_PERM_FILE, json_util.encode(normalized))
    local sess = security.get_session_user()
    users.audit(sess and sess.username or "owner", "role_permissions_update", "matrix saved")
    return { status = "ok", data = normalized }
end

return M
