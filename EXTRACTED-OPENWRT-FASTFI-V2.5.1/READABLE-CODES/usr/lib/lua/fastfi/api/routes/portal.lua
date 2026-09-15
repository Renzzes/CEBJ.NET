
local config = require("fastfi.config")
local session_db = require("fastfi.db.sessions")
local config_db = require("fastfi.db.config")
local file_util = require("fastfi.util.file")
local json_util = require("fastfi.util.json")
local voucher_db = require("fastfi.db.vouchers")
local sqlite = require("fastfi.db.sqlite")
local response_formatter = require("fastfi.api.response")
local M = {}













local function auth_client(mac)
    os.execute(string.format(
        "(ndsctl deauth %s >/dev/null 2>&1; sleep 0.5; ndsctl auth %s >/dev/null 2>&1; sleep 1; " ..
        "/usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1) &", mac, mac))
end

local function deauth_client(mac)
    os.execute(string.format("(ndsctl deauth %s >/dev/null 2>&1) &", mac))
end

function M.check_device(params)
    local license_info = config_db.get_license_info()
    if license_info.license_status ~= "active" then
        return { status = "inactive", error = "unlicensed" }
    end

    local mac = (params["mac"] or ""):lower()
    local device_id = params["device_id"] or ""
    
    if (mac == "" and device_id == "") or (mac ~= "" and not require("fastfi.security").is_valid_mac(mac)) then
        return { error = "Invalid MAC and no device_id" }
    end
    
    local session = session_db.query_session(mac, device_id)
    local now = os.time()
    local time_left = 0
    local internet = 0
    
    
    if session and session.paused == 1 and session.remaining > 0 then
        time_left = session.remaining
        internet = 0
    elseif session and session.active == 1 and session.session_end > now then
        time_left = session.session_end - now
        internet = 1
    end
    
    
    local dl_mbps = 0
    local ul_mbps = 0
    
    if session and (session.dl_limit > 0 or session.ul_limit > 0) then
        
        dl_mbps = session.dl_limit
        ul_mbps = session.ul_limit
    else
        
        local spd = file_util.read(config.SPEED_CONF)
        if spd then
            local dl, ul = spd:match("^(%d+)|(%d+)")
            if dl and ul then
                dl_mbps = tonumber(dl) or 5
                ul_mbps = tonumber(ul) or 5
            end
        else
            dl_mbps = 5
            ul_mbps = 5
        end
    end
    
    local dl_kbps = math.floor(dl_mbps * 1000)
    local ul_kbps = math.floor(ul_mbps * 1000)
    
    local data_limit_mb = 0
    local data_remaining_mb = 0
    if session then
        data_limit_mb = session.data_limit_mb or 0
        if data_limit_mb > 0 then
            data_remaining_mb = math.max(0, data_limit_mb - (session.data_consumed_mb or 0))
        end
    end
    
    local remaining_pause_credits = 0
    if session then
        local effective_limit = 0
        if session.paused_limit and session.paused_limit > 0 then
            effective_limit = session.paused_limit
        else
            local file_util = require("fastfi.util.file")
            local pause_config = file_util.read("/etc/fastfi/pause_limit.conf") or ""
            local pause_limit = 0
            local limit_enabled = 0
            for line in pause_config:gmatch("[^\n]+") do
                local key, value = line:match("^([%w_]+)=(%d+)$")
                if key == "PAUSE_LIMIT" then pause_limit = tonumber(value) or 0
                elseif key == "ENABLED" then limit_enabled = tonumber(value) or 0 end
            end
            if limit_enabled == 1 then effective_limit = pause_limit end
        end
        if effective_limit > 0 then
            remaining_pause_credits = math.max(0, effective_limit - (session.pause_count or 0))
        end
    end
    
    
    
    
    local default_route = file_util.trim(file_util.execute("ip route show default 2>/dev/null"))
    local wan_status = (default_route and default_route ~= "") and "connected" or "disconnected"
    
    local insert_btn = 1
    local sqlite = require("fastfi.db.sqlite")
    local cfg_row = sqlite.query_row(config.CONFIG_DB, "SELECT hide_insert_no_internet, insert_timer, banner_text, enable_buy_data, enable_wipass FROM config LIMIT 1")
    if cfg_row and cfg_row[1] == "1" and wan_status == "disconnected" then
        insert_btn = 0
    end
    local insert_timer = tonumber(cfg_row and cfg_row[2]) or 60
    local banner_text = cfg_row and cfg_row[3]
    if not banner_text or banner_text == "" then
        banner_text = "Insert coin or enter voucher to start"
    end
    local buy_data_btn = tonumber(cfg_row and cfg_row[4]) or 1
    local voucher_btn = tonumber(cfg_row and cfg_row[5]) or 1


    
    local sub_vendo_info = nil

    
    
    
    
    
    
    
    local unit_id
    if session and session.device_id and session.device_id ~= ""
       and session.device_id ~= "null" and session.device_id ~= "undefined" then
        unit_id = session.device_id
    else
        unit_id = session_db.sanitize_device_id(device_id, params["client_id"], mac)
    end

    return {
        unit_id = unit_id,
        mac = mac,
        time = time_left,
        download = dl_kbps,
        upload = ul_kbps,
        internet = internet,
        data_limit_mb = data_limit_mb,
        data_remaining_mb = data_remaining_mb,
        paused_limit = remaining_pause_credits,
        reconnect = session and session.roamed and 1 or 0,
        fup_throttled = 0,
        session_end = session and session.session_end or 0,
        machine = {
            wan_status = wan_status,
            insert_btn = insert_btn,
            insert_timer = insert_timer,
            paused_btn = 1,
            wifi_rates_btn = 1,
            voucher_btn = voucher_btn,
            buy_data_btn = buy_data_btn,
            display_speed = 1,
            banner_text = banner_text,
            business_name = "FastFi PisoWiFi"
        },
        sub_vendo = sub_vendo_info
    }
end

function M.device_status(params)
    local license_info = config_db.get_license_info()
    
    return {
        status = license_info.license_status,
        plan = license_info.license_plan,
        expires = license_info.license_expires,
        device_id = config_db.get_device_id()
    }
end

function M.internet_status(params)
    
    local f = io.popen("ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && echo 'ok' || echo 'fail'")
    if not f then return { internet = false } end
    local result = f:read("*a")
    f:close()
    
    return { internet = (result:match("ok") ~= nil) }
end
















function M.get_mac(params)
    local ip = os.getenv("REMOTE_ADDR") or ""
    if ip == "" or not require("fastfi.security").is_valid_ip(ip) then
        return { mac = "", ip = ip }
    end

    local f = io.popen("awk -v ip='" .. ip .. "' '$1==ip && $4!=\"00:00:00:00:00:00\"{print $4; exit}' /proc/net/arp")
    if not f then return { mac = "", ip = ip } end
    local mac = f:read("*a")
    f:close()

    return {
        mac = (mac or ""):gsub("%s+", ""):lower(),
        ip = ip
    }
end

function M.session_status(params)
    local mac = (params["mac"] or ""):lower()
    local device_id = params["device_id"] or ""
    local session = session_db.query_session(mac, device_id)
    
    if not session then
        return { status = "inactive", active = 0, time_left = 0, remaining = 0 }
    end
    
    local now = os.time()
    local time_left = 0
    local status_str = "inactive"
    
    if session.paused == 1 then
        time_left = session.remaining
        status_str = "paused"
    elseif session.active == 1 and session.session_end > now then
        time_left = session.session_end - now
        status_str = "active"
    end
    
    local data_limit_mb = session.data_limit_mb or 0
    local data_consumed_mb = session.data_consumed_mb or 0
    local data_remaining_mb = data_limit_mb - data_consumed_mb
    if data_remaining_mb < 0 then data_remaining_mb = 0 end
    
    return {
        status = status_str,
        active = session.active,
        paused = session.paused,
        time_left = time_left,
        remaining = time_left,
        session_end = session.session_end,
        data_limit_mb = data_limit_mb,
        data_consumed_mb = data_consumed_mb,
        data_remaining_mb = data_remaining_mb
    }
end

function M.internet_check(params)
    local status = tonumber(params["status"])
    local device_id = params["device_id"]
    
    if status == nil then
        return M.internet_status(params)
    end
    
    local mac_info = M.get_mac(params)
    local mac = mac_info.mac
    
    if mac == "" then
        return { status = "error", message = "Could not identify device MAC" }
    end
    
    local session_db = require("fastfi.db.sessions")
    local session = session_db.query_session(mac, device_id)
    if not session then
        return { status = "error", message = "Session not found" }
    end
    
    local now = os.time()
    
    
    if status == 0 then
        if session.paused == 1 then
            return { status = "error", message = "Already paused" }
        end
        if session.session_end <= now then
            return { status = "error", message = "Session expired" }
        end
        
        
        local effective_limit = 0
        if session.paused_limit and session.paused_limit > 0 then
            effective_limit = session.paused_limit
        else
            local file_util = require("fastfi.util.file")
            local pause_config = file_util.read("/etc/fastfi/pause_limit.conf") or ""
            local pause_limit = 0
            local limit_enabled = 0
            
            for line in pause_config:gmatch("[^\n]+") do
                local key, value = line:match("^([%w_]+)=(%d+)$")
                if key == "PAUSE_LIMIT" then
                    pause_limit = tonumber(value) or 0
                elseif key == "ENABLED" then
                    limit_enabled = tonumber(value) or 0
                end
            end
            if limit_enabled == 1 then
                effective_limit = pause_limit
            end
        end
        
        if effective_limit > 0 then
            local current_count = session.pause_count or 0
            if current_count >= effective_limit then
                return { 
                    status = "error", 
                    message = string.format("Pause limit reached (%d/%d). You cannot pause anymore.", current_count, effective_limit)
                }
            end
        end
        
        local remaining = session.session_end - now
        session_db.update_session(mac, session.session_end, 1, 1, remaining, session.dl_limit, session.ul_limit)
        
        
        deauth_client(mac)

        return { status = "success", message = "Session Paused", paused = 1 }
        
    
    elseif status == 1 then
        if session.paused == 0 then
            return { status = "error", message = "Not paused" }
        end
        if session.remaining <= 0 then
            return { status = "error", message = "No time remaining" }
        end
        
        local new_end = now + session.remaining
        session_db.update_session(mac, new_end, 1, 0, session.remaining, session.dl_limit, session.ul_limit)
        
        
        auth_client(mac)

        return { status = "success", message = "Session Resumed", paused = 0 }
    end
    
    return { status = "error", message = "Invalid status parameter" }
end







local function classic_html(title, body)
    return string.format(
        '<!DOCTYPE html><html><head><meta charset="UTF-8">' ..
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">' ..
        '<title>%s</title>' ..
        '<style>body{background:#0f172a;color:#f8fafc;font-family:sans-serif;' ..
        'text-align:center;padding:40px;margin:0}h2{color:#3b82f6}' ..
        'a{color:#3b82f6}.b{max-width:440px;margin:0 auto;font-size:18px}</style>' ..
        '</head><body><div class="b">%s</div>' ..
        '<p style="margin-top:30px"><a href="http://10.0.0.1/">Open portal</a></p>' ..
        '</body></html>', title, body)
end


local function classic_respond(title, body)
    print("Content-Type: text/html")
    print("Cache-Control: no-store, no-cache, must-revalidate")
    print("")
    print(classic_html(title, body))
    return response_formatter.ALREADY_SENT
end

function M.classic(params)
    local mode = params["mode"] or "voucher"
    local mac_info = M.get_mac(params)
    local mac = (mac_info and mac_info.mac) or ""

    if mac == "" then
        return classic_respond("FastFi", "<h2>Could not identify your device</h2>" ..
            "<p>Please connect to the FastFi WiFi and try again.</p>")
    end

    local now = os.time()

    if mode == "voucher" then
        local code = (params["code"] or ""):upper()
        if code == "" then
            return classic_respond("FastFi", "<h2>Enter a voucher code</h2>" ..
                "<p>No voucher code was provided.</p>")
        end
        if now < 1704067200 then
            return classic_respond("FastFi", "<h2>System starting</h2>" ..
                "<p>Please wait a few seconds for the clock to sync, then try again.</p>")
        end
        
        
        local rate_key = voucher_db.rate_key(mac)
        local blocked_for = voucher_db.check_rate_limit(rate_key)
        if blocked_for then
            return classic_respond("FastFi", "<h2>Too many incorrect codes</h2>" ..
                string.format("<p>Please wait %d minute(s) and try again.</p>", math.ceil(blocked_for / 60)))
        end

        local success = voucher_db.redeem_voucher(code, mac)
        if not success then
            voucher_db.record_failure(rate_key)
            return classic_respond("FastFi", "<h2>Voucher invalid</h2>" ..
                "<p>The code is invalid, already used, or expired.</p>" ..
                "<p><a href='http://10.0.0.1/'>Try again</a></p>")
        end
        voucher_db.clear_failures(rate_key)
        local voucher = voucher_db.get_voucher(code)
        if not voucher then
            return classic_respond("FastFi", "<h2>Voucher error</h2>" ..
                "<p>Could not read voucher data.</p>")
        end
        local session_seconds = voucher.minutes * 60
        local session = session_db.query_session(mac, mac)
        local new_end
        if session and session.active == 1 and session.session_end > now then
            new_end = session.session_end + session_seconds
            session_db.update_session(mac, new_end, 1, 0, 0)
        elseif session then
            new_end = now + session_seconds
            session_db.update_session(mac, new_end, 1, 0, 0)
        else
            new_end = now + session_seconds
            session_db.create_session(mac, mac, new_end)
        end
        sqlite.execute(config.SESSIONS_DB, string.format(
            "INSERT INTO sales (mac_address, amount, coins, created_at) VALUES ('%s', %d, %d, %d);",
            sqlite.quote(mac), voucher.price or 0, voucher.price or 0, now))
        auth_client(mac)
        local mins = math.floor((new_end - now) / 60)
        return classic_respond("You're online", "<h2>You're online!</h2>" ..
            "<p>Voucher accepted. You have <b>" .. mins .. "</b> minutes.</p>" ..
            "<p>You can now browse the internet.</p>")

    elseif mode == "resume" then
        local session = session_db.query_session(mac, mac)
        if not session or session.paused ~= 1 then
            return classic_respond("FastFi", "<h2>No paused session</h2>" ..
                "<p>There is no paused time on this device to resume.</p>")
        end
        if session.remaining <= 0 then
            return classic_respond("FastFi", "<h2>No time remaining</h2>" ..
                "<p>Your paused time has run out.</p>")
        end
        local new_end = now + session.remaining
        session_db.update_session(mac, new_end, 1, 0, session.remaining)
        auth_client(mac)
        local mins = math.floor(session.remaining / 60)
        return classic_respond("Time resumed", "<h2>Time resumed</h2>" ..
            "<p>You have <b>" .. mins .. "</b> minutes. You can now browse.</p>")

    elseif mode == "online" then
        local session = session_db.query_session(mac, mac)
        if not session or (session.paused ~= 1 and not (session.active == 1 and session.session_end > now)) then
            return classic_respond("FastFi", "<h2>No active time</h2>" ..
                "<p>Insert coins or redeem a voucher to connect.</p>")
        end
        auth_client(mac)
        return classic_respond("Reconnected", "<h2>Reconnected</h2>" ..
            "<p>Your internet access has been refreshed. Try browsing.</p>")
    end

    return classic_respond("FastFi", "<h2>FastFi</h2><p>Unknown action.</p>")
end

function M.update_device(params)
    local mac = (params["mac"] or ""):lower()
    local time_seconds = tonumber(params["time"]) or 0
    local dl_limit = tonumber(params["download"]) or 0
    local ul_limit = tonumber(params["upload"]) or 0
    local added_data_limit_mb = tonumber(params["data_limit_mb"]) or 0
    local validity_minutes = tonumber(params["validity_minutes"]) or 0
    local added_paused_limit = tonumber(params["paused"]) or 0
    local coins_inserted = tonumber(params["coin"]) or 0

    if mac == "" or not require("fastfi.security").is_valid_mac(mac) then
        return { status = "error", message = "Invalid MAC address" }
    end

    
    
    
    
    
    local device_id = session_db.sanitize_device_id(params["device_id"], params["client_id"], mac)

    
    
    
    
    
    
    
    
    
    
    do
        local sqlite = require("fastfi.db.sqlite")
        local safe_mac = sqlite.quote(mac)

        local held_credit = nil
        local erow = sqlite.query_row(config.ESP_DB, string.format(
            "SELECT coin_credit FROM esp_slots WHERE locked_by='%s';", safe_mac))
        if erow then held_credit = tonumber(erow[1]) or 0 end

        if coins_inserted <= 0 or held_credit == nil or held_credit < coins_inserted then
            os.execute(string.format(
                "logger -t fastfi 'updateDevice refused for %s: claimed %d credit, slot holds %s'",
                mac, coins_inserted, tostring(held_credit)))
            return { status = "error", message = "No coin credit found for this device." }
        end
    end


    if time_seconds == 0 and added_data_limit_mb > 0 then
        if validity_minutes > 0 then
            time_seconds = validity_minutes * 60
        else
            
            time_seconds = 30 * 24 * 60 * 60
        end
    end
    
    
    local now = os.time()
    if now < 1704067200 then
        return { status = "error", message = "System starting. Please wait 10s for time sync..." }
    end
    
    local session = session_db.query_session(mac, device_id)

    
    
    
    if session and (session.device_id == "" or session.device_id == "null" or session.device_id == "undefined")
       and device_id ~= "" then
        sqlite.execute(config.SESSIONS_DB,
            string.format("UPDATE sessions SET device_id='%s' WHERE lower(trim(mac_address))='%s';",
                sqlite.quote(device_id), sqlite.quote(mac)))
        session.device_id = device_id
    end

    local sub_vendo_id = 0   

    
    local new_end = now + time_seconds
    if session then
        if session.active == 1 and session.session_end > now then
            new_end = session.session_end + time_seconds
        elseif session.paused == 1 and session.remaining > 0 then
            new_end = now + session.remaining + time_seconds
        end
    end

    
    if coins_inserted > 0 then
        local sqlite = require("fastfi.db.sqlite")
        local cfg = require("fastfi.config")
        sqlite.execute(cfg.SESSIONS_DB,
            string.format("INSERT INTO sales (mac_address, amount, coins, created_at, sub_vendo_id) VALUES ('%s', %d, %d, %d, %d);",
            sqlite.quote(mac), coins_inserted, coins_inserted, now, sub_vendo_id))
    end
    
    
    local final_validity = nil
    if validity_minutes > 0 then
        local sqlite = require("fastfi.db.sqlite")
        local cfg = require("fastfi.config")
        local row = sqlite.query_row(cfg.CONFIG_DB, "SELECT enable_validity FROM config LIMIT 1")
        if row and row[1] == "1" then
            local validity_seconds = validity_minutes * 60
            if session and session.validity_end and session.validity_end > now then
                final_validity = session.validity_end + validity_seconds
            else
                final_validity = now + validity_seconds
            end
        end
    end
    
    if session then
        local new_paused_limit = (session.paused_limit or 0) + added_paused_limit
        
        
        
        
        
        
        
        
        
        
        local base_limit    = session.data_limit_mb or 0
        local base_consumed = session.data_consumed_mb or 0
        if base_limit > 0 and base_consumed >= base_limit then
            base_limit = 0
            base_consumed = 0
        end
        local new_data_limit = base_limit + added_data_limit_mb
        local data_consumed  = base_consumed

        if not final_validity and session.validity_end and session.validity_end > 0 then
            final_validity = session.validity_end
        end

        session_db.update_session(mac, new_end, 1, 0, 0, dl_limit, ul_limit, new_data_limit, data_consumed, final_validity, new_paused_limit, sub_vendo_id)
    else
        
        session_db.create_session(device_id, mac, new_end, dl_limit, ul_limit, added_data_limit_mb, final_validity or 0, added_paused_limit, sub_vendo_id)
    end
    
    
    local sqlite = require("fastfi.db.sqlite")
    sqlite.execute(config.ESP_DB, string.format(
        "UPDATE esp_slots SET grace_until = %d, locked_by='', locked_at=0, coin_credit=0 WHERE locked_by='%s' OR locked_by='%s';",
        now + 10, sqlite.quote(mac), sqlite.quote(device_id)
    ))

    
    
    
    
    
    auth_client(mac)
    
    return { 
        result = "success",
        status = "ok", 
        message = "Session updated and authenticated",
        session_end = new_end,
        dl_limit = dl_limit,
        ul_limit = ul_limit
    }
end










function M.clear_credit(params)
    local sqlite = require("fastfi.db.sqlite")
    local ip = os.getenv("REMOTE_ADDR") or ""
    if ip == "" then
        return { status = "error", message = "Cannot determine client" }
    end

    
    local mac = nil
    local f = io.open("/proc/net/arp", "r")
    if f then
        for line in f:lines() do
            local lip, lmac = line:match("^(%S+)%s+%S+%s+%S+%s+(%S+)")
            if lip == ip and lmac and lmac ~= "00:00:00:00:00:00" then
                mac = lmac:lower()
                break
            end
        end
        f:close()
    end
    if not mac then
        return { status = "error", message = "Cannot determine client" }
    end

    local safe_mac = sqlite.quote(mac)
    sqlite.execute(config.ESP_DB, string.format(
        "UPDATE esp_slots SET locked_by='', locked_at=0, coin_credit=0 WHERE locked_by='%s';",
        safe_mac))

    return { status = "ok", message = "Credits cleared" }
end

return M
