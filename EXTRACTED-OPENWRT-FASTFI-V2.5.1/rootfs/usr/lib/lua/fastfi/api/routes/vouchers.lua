
local voucher_db = require("fastfi.db.vouchers")
local session_db = require("fastfi.db.sessions")
local sqlite = require("fastfi.db.sqlite")
local config = require("fastfi.config")
local security = require("fastfi.security")
local M = {}

function M.redeem(params)
    local code = (params["code"] or ""):upper()
    local mac = (params["mac"] or ""):lower()
    if mac ~= "" and not security.is_valid_mac(mac) then
        return { status = "error", message = "Invalid MAC address" }
    end
    local device_id = params["device_id"] or ""
    
    if code == "" then
        return { status = "error", message = "Missing voucher code" }
    end

    
    local now = os.time()
    if now < 1704067200 then
        return { status = "error", message = "System starting. Please wait 10s for time sync..." }
    end
    
    
    
    
    local rate_key = voucher_db.rate_key(mac)
    local blocked_for = voucher_db.check_rate_limit(rate_key)
    if blocked_for then
        return { status = "error",
                 message = string.format("Too many incorrect codes. Try again in %d minute(s).",
                                         math.ceil(blocked_for / 60)),
                 blocked = true, cooldown = blocked_for }
    end

    local success = voucher_db.redeem_voucher(code, mac)

    if not success then
        voucher_db.record_failure(rate_key)
        return { status = "error", message = "Voucher invalid, used, or expired." }
    end

    voucher_db.clear_failures(rate_key)
    
    
    local voucher = voucher_db.get_voucher(code)
    if not voucher then
        return { status = "error", message = "Voucher data error" }
    end
    
    local session_seconds = voucher.minutes * 60
    
    
    
    
    
    local target_id = session_db.sanitize_device_id(device_id, params["client_id"], mac)
    
    
    local session = session_db.query_session(mac, target_id)
    local new_end = 0
    
    if session then
        
        if session.active == 1 and session.session_end > now then
            
            new_end = session.session_end + session_seconds
        else
            
            new_end = now + session_seconds
        end
        
        session_db.update_session(mac, new_end, 1, 0, 0)
    else
        
        new_end = now + session_seconds
        session_db.create_session(target_id, mac, new_end)
    end
    
    
    local sale_sql = string.format("INSERT INTO sales (mac_address, amount, coins, created_at) VALUES ('%s', %d, %d, %d);",
        sqlite.quote(mac), voucher.price, voucher.price, now)
    sqlite.execute(config.SESSIONS_DB, sale_sql)


    os.execute(string.format("(ndsctl deauth %s >/dev/null 2>&1; sleep 0.3; ndsctl auth %s >/dev/null 2>&1; /usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1) &", mac, mac))
    
    return {
        status = "ok",
        message = "Voucher applied successfully",
        remaining = math.max(0, new_end - now)
    }
end

function M.generate(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local count = tonumber(params["count"]) or 1
    local price = tonumber(params["price"]) or 10
    local minutes = tonumber(params["minutes"]) or 60
    local expiry_days = tonumber(params["expiry"]) or 365
    local batch = params["batch"] or os.date("%Y%m%d-%H%M%S")


    count = math.min(math.max(count, 1), 100)
    price = math.min(price, 10000)
    minutes = math.min(minutes, 525600)  
    expiry_days = math.max(0, math.min(expiry_days, 3650))

    local now = os.time()
    
    
    
    local expires_date = (expiry_days > 0)
        and os.date("%Y-%m-%d", now + expiry_days * 86400)
        or "Never"

    local vouchers = {}
    for _ = 1, count do
        local code = voucher_db.mint_one(minutes, price, expiry_days, batch)
        if code then
            table.insert(vouchers, {
                code = code,
                minutes = minutes,
                price = price,
                expires = expires_date,
                batch = batch
            })
        end
    end

    return {
        status = "ok",
        vouchers = vouchers,
        batch = batch,
        generated_count = #vouchers,
        requested_count = count
    }
end

function M.export_vouchers(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local batch = params["batch"]
    local format = params["format"] or "csv"  
    
    local where_sql = ""
    if batch then
        where_sql = string.format(" WHERE batch='%s'", batch)
    end
    
    local rows = sqlite.query_list(config.VOUCHER_DB,
        string.format("SELECT code, minutes, price, created_at, expires_at, status, batch FROM vouchers%s ORDER BY created_at DESC;",
            where_sql))
    
    if format == "json" then
        local vouchers = {}
        for _, row in ipairs(rows) do
            table.insert(vouchers, {
                code = row[1],
                minutes = tonumber(row[2]) or 0,
                price = tonumber(row[3]) or 0,
                created_at = tonumber(row[4]) or 0,
                expires_at = tonumber(row[5]) or 0,
                status = row[6] or "unknown",
                batch = row[7] or ""
            })
        end
        return { status = "ok", data = vouchers, count = #vouchers }
    elseif format == "csv" then
        local csv = "Code,Minutes,Price,Created,Expires,Status,Batch\n"
        for _, row in ipairs(rows) do
            local created = os.date("%Y-%m-%d %H:%M:%S", tonumber(row[4]) or 0)
            local expires = os.date("%Y-%m-%d", tonumber(row[5]) or 0)
            csv = csv .. string.format("%s,%d,%d,%s,%s,%s,%s\n",
                row[1], tonumber(row[2]) or 0, tonumber(row[3]) or 0,
                created, expires, row[6] or "unknown", row[7] or "")
        end
        return { status = "ok", format = "csv", data = csv, count = #rows }
    else
        
        local text = ""
        for _, row in ipairs(rows) do
            text = text .. row[1] .. "\n"
        end
        return { status = "ok", format = "text", data = text, count = #rows }
    end
end

function M.list_vouchers(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local limit = tonumber(params["limit"]) or 100
    local offset = tonumber(params["offset"]) or 0
    local status_filter = params["status"]  
    local batch_filter = params["batch"]
    
    
    local where_clauses = {}
    if status_filter and status_filter ~= "all" then
        if status_filter == "expired" then
            
            
            table.insert(where_clauses, string.format("status='active' AND expires_at > 0 AND expires_at < %d", os.time()))
        else
            table.insert(where_clauses, string.format("status='%s'", status_filter))
        end
    end
    if batch_filter then
        table.insert(where_clauses, string.format("batch='%s'", batch_filter))
    end
    
    local where_sql = ""
    if #where_clauses > 0 then
        where_sql = " WHERE " .. table.concat(where_clauses, " AND ")
    end
    
    
    local count_row = sqlite.query_row(config.VOUCHER_DB,
        string.format("SELECT COUNT(*) FROM vouchers%s;", where_sql))
    local total = tonumber(count_row and count_row[1]) or 0
    
    
    local rows = sqlite.query_list(config.VOUCHER_DB,
        string.format("SELECT code, minutes, price, created_at, expires_at, used_by, status, batch FROM vouchers%s ORDER BY created_at DESC LIMIT %d OFFSET %d;",
            where_sql, limit, offset))
    
    local vouchers = {}
    for _, row in ipairs(rows) do
        table.insert(vouchers, {
            code = row[1],
            minutes = tonumber(row[2]) or 0,
            price = tonumber(row[3]) or 0,
            created_at = tonumber(row[4]) or 0,
            expires_at = tonumber(row[5]) or 0,
            used_by = row[6] or "",
            status = row[7] or "unknown",
            batch = row[8] or ""
        })
    end
    
    return {
        status = "ok",
        total = total,
        count = #vouchers,
        vouchers = vouchers
    }
end

function M.delete_vouchers(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local action = params["cmd"] or params["action"]
    local batch = params["batch"]
    
    if action == "delete_batch" and batch then
        local count_row = sqlite.query_row(config.VOUCHER_DB,
            string.format("SELECT COUNT(*) FROM vouchers WHERE batch='%s';", batch))
        local count = tonumber(count_row and count_row[1]) or 0
        
        sqlite.execute(config.VOUCHER_DB,
            string.format("DELETE FROM vouchers WHERE batch='%s';", batch))
        
        return { status = "ok", message = string.format("Deleted %d vouchers from batch %s", count, batch) }
        
    elseif action == "delete_used" then
        local count_row = sqlite.query_row(config.VOUCHER_DB,
            "SELECT COUNT(*) FROM vouchers WHERE status='used';")
        local count = tonumber(count_row and count_row[1]) or 0
        
        sqlite.execute(config.VOUCHER_DB, "DELETE FROM vouchers WHERE status='used';")
        
        return { status = "ok", message = string.format("Deleted %d used vouchers", count) }
        
    elseif action == "delete_expired" then
        local now = os.time()
        
        
        local count_row = sqlite.query_row(config.VOUCHER_DB,
            string.format("SELECT COUNT(*) FROM vouchers WHERE status='active' AND expires_at > 0 AND expires_at < %d;", now))
        local count = tonumber(count_row and count_row[1]) or 0

        sqlite.execute(config.VOUCHER_DB,
            string.format("DELETE FROM vouchers WHERE status='active' AND expires_at > 0 AND expires_at < %d;", now))
        
        return { status = "ok", message = string.format("Deleted %d expired vouchers", count) }
        
    elseif action == "delete_all" then
        local count_row = sqlite.query_row(config.VOUCHER_DB, "SELECT COUNT(*) FROM vouchers;")
        local count = tonumber(count_row and count_row[1]) or 0
        
        sqlite.execute(config.VOUCHER_DB, "DELETE FROM vouchers;")
        
        return { status = "ok", message = string.format("Deleted %d vouchers", count) }
        
    elseif action == "list_batches" then
        local rows = sqlite.query_list(config.VOUCHER_DB,
            "SELECT batch, COUNT(*) as count FROM vouchers WHERE batch IS NOT NULL AND batch != '' GROUP BY batch ORDER BY count DESC;")
        
        local batches = {}
        for _, row in ipairs(rows) do
            table.insert(batches, { batch = row[1], count = tonumber(row[2]) or 0 })
        end
        
        return { status = "ok", batches = batches }
    else
        return { status = "error", message = "Invalid action" }
    end
end

return M
