


















local config     = require("fastfi.config")
local sqlite     = require("fastfi.db.sqlite")
local security   = require("fastfi.security")
local voucher_db = require("fastfi.db.vouchers")
local json_util  = require("fastfi.util.json")
local file_util  = require("fastfi.util.file")
local M = {}

local GCASH_BATCH = "gcash"
local ORDER_TTL_SECONDS = 15 * 60   











local FREEWINDOW_MINUTES      = 2     
local FREEWINDOW_COOLDOWN_SEC = 600   
local FREEWINDOW_DAILY_CAP    = 5     





local function ensure_config_columns()
    local cols = {
        "gcash_enabled INTEGER DEFAULT 0",
        "gcash_number TEXT DEFAULT ''",
        "gcash_qr TEXT DEFAULT ''",
        "gcash_app_secret TEXT DEFAULT ''",
        "gcash_voucher_expiry_days INTEGER DEFAULT 0",
        "gcash_freewindow_enabled INTEGER DEFAULT 1"
    }
    for _, col_def in ipairs(cols) do
        pcall(function()
            sqlite.execute(config.CONFIG_DB,
                "ALTER TABLE config ADD COLUMN " .. col_def .. ";")
        end)
    end
end



local function ensure_orders_table()
    sqlite.execute(config.GCASH_DB, [[
        CREATE TABLE IF NOT EXISTS gcash_orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_ref TEXT,
            amount_cents INTEGER NOT NULL,
            mobile TEXT NOT NULL,
            price INTEGER NOT NULL,
            minutes INTEGER NOT NULL,
            status TEXT DEFAULT 'pending',
            created_at INTEGER,
            claimed_at INTEGER DEFAULT 0,
            expires_at INTEGER
        );
    ]])
    pcall(function()
        sqlite.execute(config.GCASH_DB,
            "CREATE INDEX IF NOT EXISTS idx_gcash_amount ON gcash_orders(amount_cents);")
    end)
end

local function read_config()
    ensure_config_columns()
    local row = sqlite.query_row(config.CONFIG_DB,
        "SELECT gcash_enabled, gcash_number, gcash_qr, gcash_app_secret, gcash_voucher_expiry_days, gcash_freewindow_enabled FROM config LIMIT 1;")
    return {
        enabled             = (row and tonumber(row[1]) or 0) == 1,
        gcash_number        = (row and row[2]) or "",
        gcash_qr            = (row and row[3]) or "",
        gcash_app_secret    = (row and row[4]) or "",
        voucher_expiry_days = tonumber(row and row[5]) or 0,
        freewindow_enabled  = (row and tonumber(row[6]) or 1) == 1
    }
end


local function normalize_mobile(raw)
    if not raw then return nil end
    local digits = tostring(raw):gsub("%D", "")
    if digits:len() == 11 and digits:sub(1, 2) == "09" then return digits end
    if digits:len() == 12 and digits:sub(1, 2) == "63" then return "0" .. digits:sub(3) end
    if digits:len() == 10 and digits:sub(1, 1) == "9" then return "0" .. digits end
    return nil
end



local function generate_app_secret()
    local f = io.popen("openssl rand -hex 12 2>/dev/null")
    if f then
        local s = f:read("*a")
        f:close()
        s = file_util.trim(s)
        if #s >= 16 then return s end
    end
    
    return string.format("%x%x", os.time(), math.random(1, 2^31 - 1))
end





local function pool_inventory()
    local rows = sqlite.query_list(config.VOUCHER_DB, string.format(
        "SELECT price, minutes, status, COUNT(*) FROM vouchers WHERE batch='%s' GROUP BY price, minutes, status;",
        GCASH_BATCH))
    local by_price = {}
    for _, r in ipairs(rows) do
        local price = tonumber(r[1]) or 0
        local minutes = tonumber(r[2]) or 0
        local status = r[3] or "active"
        local count = tonumber(r[4]) or 0
        local entry = by_price[price]
        if not entry then
            entry = { price = price, minutes = minutes, total = 0, active = 0, redeemed = 0 }
            by_price[price] = entry
        end
        entry.total = entry.total + count
        if status == "active" then entry.active = entry.active + count
        elseif status == "used" then entry.redeemed = entry.redeemed + count end
    end
    local list = {}
    for _, v in pairs(by_price) do table.insert(list, v) end
    table.sort(list, function(a, b) return a.price < b.price end)
    return list
end





function M.get_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local cfg = read_config()
    return {
        status = "ok",
        enabled = cfg.enabled,
        gcash_number = cfg.gcash_number,
        gcash_qr = cfg.gcash_qr,
        has_secret = cfg.gcash_app_secret and #cfg.gcash_app_secret > 0,
        voucher_expiry_days = cfg.voucher_expiry_days,
        freewindow_enabled = cfg.freewindow_enabled,
        pool = pool_inventory()
    }
end

function M.set_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    ensure_config_columns()

    local enabled  = (params["enabled"] == "1" or params["enabled"] == "true") and 1 or 0
    local gcash_number = (params["gcash_number"] or ""):gsub("'", "")
    local gcash_qr = (params["gcash_qr"] or ""):gsub("'", "")
    local voucher_expiry_days = math.max(0, tonumber(params["voucher_expiry_days"]) or 0)
    local freewindow_enabled = (params["freewindow_enabled"] == "1" or params["freewindow_enabled"] == "true") and 1 or 0

    
    
    
    
    
    sqlite.execute(config.CONFIG_DB,
        "INSERT OR IGNORE INTO config (id) VALUES (1);")

    local res = sqlite.execute(config.CONFIG_DB, string.format(
        "UPDATE config SET gcash_enabled=%d, gcash_number='%s', gcash_qr='%s', gcash_voucher_expiry_days=%d, gcash_freewindow_enabled=%d WHERE id=1;",
        enabled, gcash_number, gcash_qr, voucher_expiry_days, freewindow_enabled))

    
    
    
    
    
    if type(res) == "string" and res:sub(1, 5) == "Error" then
        return { status = "error", message = "GCash save failed: " .. res }
    end
    if tonumber(res) ~= 1 then
        return { status = "error", message = "GCash save failed: config row not updated (got " .. tostring(res) .. " changes). DB may need re-init." }
    end

    return { status = "ok", message = "GCash settings saved." }
end


function M.public_config(params)
    local cfg = read_config()
    return {
        status = "ok",
        enabled = cfg.enabled,
        gcash_number = cfg.gcash_number,
        gcash_qr = cfg.gcash_qr
    }
end





function M.generate_pool(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local cfg = read_config()
    local count_per_rate = tonumber(params["count"]) or 20
    count_per_rate = math.min(math.max(count_per_rate, 1), 200)

    local rates = sqlite.query_list(config.CONFIG_DB,
        "SELECT price, minutes FROM coin_rates ORDER BY price ASC;")
    if not rates or #rates == 0 then
        return { status = "error", message = "No coin rates configured." }
    end

    local summary = {}
    for _, r in ipairs(rates) do
        local price = tonumber(r[1]) or 0
        local minutes = tonumber(r[2]) or 0
        if price > 0 and minutes > 0 then
            local minted = 0
            for _ = 1, count_per_rate do
                if voucher_db.mint_one(minutes, price, cfg.voucher_expiry_days or 0, GCASH_BATCH) then
                    minted = minted + 1
                end
            end
            table.insert(summary, { price = price, minutes = minutes, minted = minted })
        end
    end

    return {
        status = "ok",
        message = string.format("Generated %d codes per rate.", count_per_rate),
        count_per_rate = count_per_rate,
        summary = summary,
        pool = pool_inventory()
    }
end





function M.export_pool(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local rows = sqlite.query_list(config.VOUCHER_DB, string.format(
        "SELECT code, price, minutes FROM vouchers WHERE batch='%s' AND status='active' ORDER BY price ASC;",
        GCASH_BATCH))
    local by_price = {}
    for _, r in ipairs(rows) do
        local price = tonumber(r[2]) or 0
        local minutes = tonumber(r[3]) or 0
        local entry = by_price[price]
        if not entry then
            entry = { price = price, minutes = minutes, codes = {} }
            by_price[price] = entry
        end
        table.insert(entry.codes, r[1])
    end
    local packages = {}
    for _, v in pairs(by_price) do table.insert(packages, v) end
    table.sort(packages, function(a, b) return a.price < b.price end)

    return {
        status = "ok",
        generated_at = os.time(),
        gcash_number = read_config().gcash_number,
        packages = packages,
        total_codes = (function() local n = 0 for _, p in ipairs(packages) do n = n + #p.codes end return n end)()
    }
end







function M.upload_qr(params, req)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    if not req or not req.post_body or #req.post_body == 0 then
        return { status = "error", message = "Empty file upload" }
    end
    if #req.post_body > 2 * 1024 * 1024 then
        return { status = "error", message = "File too large. Max 2MB allowed." }
    end
    os.execute("mkdir -p /www/image 2>/dev/null")
    
    
    local f, err = io.open("/www/image/gcash-qr.png", "wb")
    if not f then
        return { status = "error", message = "Failed to write QR: " .. tostring(err) }
    end
    f:write(req.post_body)
    f:close()
    
    ensure_config_columns()
    sqlite.execute(config.CONFIG_DB,
        "UPDATE config SET gcash_qr='/image/gcash-qr.png' WHERE id=1;")
    return { status = "ok", message = "QR uploaded.", path = "/image/gcash-qr.png" }
end





function M.generate_secret(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local secret = generate_app_secret()
    ensure_config_columns()
    sqlite.execute(config.CONFIG_DB,
        string.format("UPDATE config SET gcash_app_secret='%s' WHERE id=1;",
            sqlite.quote(secret)))
    return { status = "ok", app_secret = secret,
        message = "New app secret generated. Type it into the companion app now — it is not shown again." }
end









function M.create_order(params)
    local cfg = read_config()
    if not cfg.enabled then
        return { status = "error", message = "GCash payments are not enabled." }
    end

    local price = tonumber(params["price"])
    if not price or price <= 0 then
        return { status = "error", message = "Invalid package price." }
    end

    
    local row = sqlite.query_row(config.CONFIG_DB,
        string.format("SELECT minutes FROM coin_rates WHERE price=%d ORDER BY id ASC LIMIT 1;",
            math.floor(price)))
    if not row then
        return { status = "error", message = "No package for that price." }
    end
    local minutes = tonumber(row[1]) or 0
    if minutes <= 0 then
        return { status = "error", message = "Invalid package." }
    end

    local mobile = normalize_mobile(params["mobile"])
    if not mobile then
        return { status = "error", message = "Enter a valid PH mobile (09XXXXXXXXX)." }
    end

    ensure_orders_table()
    local now = os.time()
    local price_int = math.floor(price)
    local amount_cents = price_int * 100

    
    pcall(function()
        sqlite.execute(config.GCASH_DB,
            string.format("DELETE FROM gcash_orders WHERE status='pending' AND expires_at<%d;", now))
    end)

    sqlite.execute(config.GCASH_DB, string.format(
        "INSERT INTO gcash_orders (order_ref, amount_cents, mobile, price, minutes, status, created_at, expires_at) " ..
        "VALUES ('FF-%d', %d, '%s', %d, %d, 'pending', %d, %d);",
        now, amount_cents, sqlite.quote(mobile), price_int, minutes, now, now + ORDER_TTL_SECONDS))

    
    local orow = sqlite.query_row(config.GCASH_DB,
        string.format("SELECT id FROM gcash_orders WHERE created_at=%d AND mobile='%s' ORDER BY id DESC LIMIT 1;",
            now, sqlite.quote(mobile)))
    local order_ref = "FF-" .. tostring(orow and orow[1] or now)
    if orow then
        sqlite.execute(config.GCASH_DB,
            string.format("UPDATE gcash_orders SET order_ref='FF-%d' WHERE id=%d;", orow[1], orow[1]))
    end

    return {
        status = "ok",
        order_ref = order_ref,
        amount = price_int,
        mobile = mobile,
        minutes = minutes,
        gcash_number = cfg.gcash_number,
        gcash_qr = cfg.gcash_qr,
        expires_at = now + ORDER_TTL_SECONDS
    }
end









function M.claim_by_amount(params)
    if not security.check_app_secret(params) then
        return { status = "error", message = "Unauthorized" }
    end
    local amount_cents = tonumber(params["amount_cents"])
    if not amount_cents then
        return { status = "error", message = "Missing amount_cents." }
    end
    amount_cents = math.floor(amount_cents)

    ensure_orders_table()
    local now = os.time()
    
    local row = sqlite.query_row(config.GCASH_DB, string.format(
        "SELECT id, mobile, minutes FROM gcash_orders " ..
        "WHERE amount_cents=%d AND status='pending' AND expires_at>=%d " ..
        "ORDER BY created_at ASC LIMIT 1;", amount_cents, now))
    if not row then
        return { status = "no_match" }
    end
    local oid, mobile, minutes = tonumber(row[1]), row[2], tonumber(row[3]) or 0
    sqlite.execute(config.GCASH_DB, string.format(
        "UPDATE gcash_orders SET status='claimed', claimed_at=%d WHERE id=%d;", now, oid))
    return { status = "ok", mobile = mobile, minutes = minutes }
end














local function get_mac_from_request()
    local ip = os.getenv("REMOTE_ADDR") or ""
    if ip == "" then return nil end
    local f = io.popen("awk -v ip='" .. ip .. "' '$1==ip{print $4}' /proc/net/arp")
    if not f then return nil end
    local mac = f:read("*a")
    f:close()
    mac = (mac or ""):gsub("%s+", ""):lower()
    if mac == "" or mac == "00:00:00:00:00:00" then return nil end
    return mac
end



local function has_active_session(mac)
    local now = os.time()
    local row = sqlite.query_row(config.SESSIONS_DB,
        string.format(
            "SELECT session_end, active, paused, remaining FROM sessions WHERE lower(trim(mac_address))='%s' LIMIT 1;",
            sqlite.quote(mac:lower())))
    if not row then return false end
    local session_end = tonumber(row[1]) or 0
    local active      = tonumber(row[2]) or 0
    local paused      = tonumber(row[3]) or 0
    local remaining   = tonumber(row[4]) or 0
    if active == 1 and session_end > now then return true end
    if paused == 1 and remaining > 0 then return true end
    return false
end



local function ensure_grants_table()
    sqlite.execute(config.SESSIONS_DB,
        [[CREATE TABLE IF NOT EXISTS gcash_freewindow_grants (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            mac        TEXT    NOT NULL,
            granted_at INTEGER NOT NULL,
            minutes    INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_freewindow_mac_ts ON gcash_freewindow_grants(mac, granted_at);]])
end


local function midnight_today()
    local t = os.date("*t")
    return os.time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
end

function M.freewindow(params)
    
    
    
    
    local function deny(reason, log_suffix)
        os.execute(string.format(
            "logger -t fastfi-gcash-freewindow 'denied %s to %s%s'",
            reason, mac or "(no-mac)", log_suffix or ""))
        return { status = "denied", reason = reason }
    end

    local cfg = read_config()
    if not cfg.freewindow_enabled then
        return deny("disabled")
    end

    local mac = get_mac_from_request()
    if not mac or not security.is_valid_mac(mac) then
        local saved = mac
        mac = nil
        return deny("no_mac", saved and (" (" .. saved .. ")") or "")
    end

    
    
    
    if has_active_session(mac) then
        return deny("already_connected")
    end

    ensure_grants_table()
    local safe_mac = sqlite.quote(mac:lower())
    local now      = os.time()

    
    local last_row = sqlite.query_row(config.SESSIONS_DB,
        string.format("SELECT MAX(granted_at) FROM gcash_freewindow_grants WHERE lower(trim(mac))='%s';", safe_mac))
    local last_grant = tonumber(last_row and last_row[1]) or 0
    if last_grant > 0 and (now - last_grant) < FREEWINDOW_COOLDOWN_SEC then
        local retry_in = FREEWINDOW_COOLDOWN_SEC - (now - last_grant)
        os.execute(string.format(
            "logger -t fastfi-gcash-freewindow 'denied cooldown to %s (retry_in %ds)'", mac, retry_in))
        return { status = "denied", reason = "cooldown", retry_in = retry_in }
    end

    
    local cap_row = sqlite.query_row(config.SESSIONS_DB,
        string.format("SELECT COUNT(*) FROM gcash_freewindow_grants WHERE lower(trim(mac))='%s' AND granted_at>=%d;",
            safe_mac, midnight_today()))
    local today_count = tonumber(cap_row and cap_row[1]) or 0
    if today_count >= FREEWINDOW_DAILY_CAP then
        return deny("daily_cap", string.format(" (%d/%d)", today_count, FREEWINDOW_DAILY_CAP))
    end

    
    if now < 1704067200 then
        return deny("time_not_synced")
    end

    
    
    
    local session_end = now + (FREEWINDOW_MINUTES * 60)
    local existing = sqlite.query_row(config.SESSIONS_DB,
        string.format("SELECT mac_address FROM sessions WHERE lower(trim(mac_address))='%s' LIMIT 1;", safe_mac))
    if existing then
        sqlite.execute(config.SESSIONS_DB, string.format(
            "UPDATE sessions SET session_end=%d, active=1, paused=0, remaining=0, updated_at=%d, data_limit_mb=0, data_consumed_mb=0 WHERE lower(trim(mac_address))='%s';",
            session_end, now, safe_mac))
    else
        sqlite.execute(config.SESSIONS_DB, string.format(
            "INSERT INTO sessions (device_id, mac_address, session_end, active, paused, remaining, updated_at, created_at, dl_limit, ul_limit, data_limit_mb, data_consumed_mb, validity_end, paused_limit) VALUES ('', '%s', %d, 1, 0, 0, %d, %d, 0, 0, 0, 0, 0, 0);",
            safe_mac, session_end, now, now))
    end

    sqlite.execute(config.SESSIONS_DB, string.format(
        "INSERT INTO gcash_freewindow_grants (mac, granted_at, minutes) VALUES ('%s', %d, %d);",
        safe_mac, now, FREEWINDOW_MINUTES))

    
    
    os.execute(string.format(
        "(ndsctl deauth %s >/dev/null 2>&1; sleep 0.3; ndsctl auth %s >/dev/null 2>&1; " ..
        "/usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1) &",
        mac, mac))

    os.execute(string.format(
        "logger -t fastfi-gcash-freewindow 'granted %dm free window to %s (expires %d)'",
        FREEWINDOW_MINUTES, mac, session_end))

    return { status = "ok", minutes = FREEWINDOW_MINUTES, session_end = session_end }
end

return M