
local esp_db = require("fastfi.db.esp")
local config_db = require("fastfi.db.config")
local sqlite = require("fastfi.db.sqlite")
local config = require("fastfi.config")
local security = require("fastfi.security")
local M = {}













function M.lock_coin(params)
    local slot_mac = sqlite.quote((params["slot_mac"] or ""):lower())
    local client_mac = sqlite.quote((params["mac"] or ""):lower())

    
    
    
    
    
    
    
    
    
    
    local raw_mac = (params["mac"] or ""):lower()
    if raw_mac == "" then
        local ip = os.getenv("REMOTE_ADDR") or ""
        if ip ~= "" and security.is_valid_ip(ip) then
            local f = io.popen("awk -v ip='" .. ip ..
                "' '$1==ip && $4!=\"00:00:00:00:00:00\"{print $4; exit}' /proc/net/arp 2>/dev/null")
            if f then
                raw_mac = (f:read("*a") or ""):gsub("%s+", ""):lower()
                f:close()
            end
        end
    end
    
    
    local client_ident = raw_mac
    if client_ident == "" then client_ident = (params["device_id"] or ""):lower() end

    if slot_mac == "" then
        return { status = "error", message = "Missing slot_mac" }
    end

    
    if client_mac ~= "" then
        local now = os.time()

        
        local limit_row = sqlite.query_row(config.CONFIG_DB,
            "SELECT insert_spam_limit FROM config LIMIT 1")
        local spam_limit = tonumber(limit_row and limit_row[1]) or 5

        
        local spam_row = sqlite.query_row(config.ESP_DB,
            string.format("SELECT fail_count, blocked_until FROM coin_spam WHERE client_mac='%s';", client_mac))

        if spam_row then
            local fail_count = tonumber(spam_row[1]) or 0
            local blocked_until = tonumber(spam_row[2]) or 0

            
            if blocked_until > now then
                local remaining = blocked_until - now
                return { status = "error", message = "Rate limited. Try again in " .. remaining .. "s", blocked = true, cooldown = remaining }
            end

            
            if fail_count >= spam_limit then
                local block_time = now + 300
                sqlite.execute(config.ESP_DB,
                    string.format("UPDATE coin_spam SET blocked_until=%d, fail_count=0 WHERE client_mac='%s';",
                        block_time, client_mac))
                return { status = "error", message = "Too many empty attempts. Blocked for 5 minutes.", blocked = true, cooldown = 300 }
            end
        end

        
        sqlite.execute(config.ESP_DB,
            string.format("INSERT INTO coin_spam (client_mac, fail_count, last_attempt) VALUES ('%s', 1, %d) ON CONFLICT(client_mac) DO UPDATE SET fail_count = fail_count + 1, last_attempt = %d;",
                client_mac, now, now))
    end

    if slot_mac == "local" or slot_mac == "" then
        return { status = "error", message = "Built-in coin slot not supported on this device" }
    end

    
    local row = sqlite.query_row(config.ESP_DB,
        string.format("SELECT id, status, license_status, locked_by FROM esp_slots WHERE LOWER(slot_mac)='%s';", slot_mac))

    if not row then
        return { status = "error", message = "Slot not found" }
    end

    local slot_id = row[1]
    local slot_status = row[2] or "offline"
    local license_status = row[3] or "unlicensed"
    local locked_by = row[4] or ""

    if license_status ~= "free" and license_status ~= "licensed" then
        return { status = "error", message = "Slot not licensed" }
    end

    
    if locked_by ~= "" then
        local lock_row = sqlite.query_row(config.ESP_DB,
            string.format("SELECT locked_at FROM esp_slots WHERE id='%s';", slot_id))
        local locked_at = tonumber(lock_row and lock_row[1]) or 0
        local now_ts = os.time()

        
        
        
        
        local requesting_client = sqlite.quote(client_ident)
        if client_ident ~= "" and locked_by == requesting_client then
            
            sqlite.execute(config.ESP_DB,
                string.format("UPDATE esp_slots SET locked_at=%d WHERE id='%s';", now_ts, slot_id))
            local credit_row = sqlite.query_row(config.ESP_DB,
                string.format("SELECT coin_credit FROM esp_slots WHERE id='%s';", slot_id))
            local existing_coins = tonumber(credit_row and credit_row[1]) or 0
            return { status = "ok", message = "Slot re-locked", slot_id = slot_id, coin = existing_coins }
        end

        if (now_ts - locked_at) < 120 then
            return { status = "error", message = "Coin slot is busy" }
        end
    end

    
    local now = os.time()
    local client_id = (client_ident ~= "" and client_ident) or "client"
    sqlite.execute(config.ESP_DB,
        string.format("UPDATE esp_slots SET locked_by='%s', locked_at=%d, coin_credit=0 WHERE id='%s';",
            sqlite.quote(client_id), now, slot_id))


    return { status = "ok", message = "Slot locked", slot_id = slot_id }
end



function M.fetch_coin(params)
    local slot_mac = (params["slot_mac"] or ""):lower()

    if slot_mac == "local" or slot_mac == "" then
        return { coin = 0 }
    end

    local safe_mac = sqlite.quote(slot_mac)
    local sql = string.format("SELECT coin_credit FROM esp_slots WHERE LOWER(slot_mac)='%s';", safe_mac)
    local row = sqlite.query_row(config.ESP_DB, sql)

    local coins = tonumber(row and row[1]) or 0
    return { 
        coin = coins
    }
end



function M.insert_coin(params)
    local slot_mac = sqlite.quote((params["mac"] or ""):lower())
    local pulses = tonumber(params["pulses"]) or 0

    if slot_mac == "" then
        return { success = false, error = "no_slot" }
    end

    
    local slot_info = esp_db.get_slot_by_mac(slot_mac)

    if not slot_info then
        return { success = false, error = "Slot not registered" }
    end

    if slot_info.license_status ~= "free" and slot_info.license_status ~= "licensed" then
        return { success = false, error = "license_required", slot_id = slot_info.id }
    end

    
    esp_db.update_slot_last_seen(slot_info.id)

    
    local total_coins = esp_db.increment_credit(slot_mac, pulses)

    return {
        success = true,
        coin = total_coins
    }
end

function M.list_esp_devices(params)
    
    
    local now = os.time()
    sqlite.execute(config.ESP_DB,
        string.format("UPDATE esp_slots SET status='offline' WHERE last_seen < %d AND status='online';",
            now - 60))
    
    
    
    
    
    
    
    
    
    local router_mac = config.MACHINE_ID
    
    local license_info = config_db.get_license_info()
    
    
    pcall(function()
        sqlite.execute(config.ESP_DB, "ALTER TABLE esp_slots ADD COLUMN ap_id INTEGER DEFAULT 0;")
    end)
    local esp_list = sqlite.query_list(config.ESP_DB,
        "SELECT id, slot_name, slot_mac, status, license_status, license_key, last_seen, COALESCE(ap_id,0) FROM esp_slots ORDER BY id;")
    
    local esp_devices = {}
    for _, row in ipairs(esp_list) do
        table.insert(esp_devices, {
            id = row[1],
            slot_name = row[2] or "",
            slot_mac = row[3] or "",
            status = row[4] or "offline",
            license_status = row[5] or "unlicensed",
            license_key = row[6] or "",
            license_id = row[6] or "",
            last_seen = tonumber(row[7]) or 0,
            ap_id = tonumber(row[8]) or 0
        })
    end
    
    
    local available_row = sqlite.query_row(config.ESP_DB,
        "SELECT COUNT(*) FROM esp_licenses WHERE status='available' AND COALESCE(license_key,'') != 'FASTFI-FREE-ESP';")
    local used_row = sqlite.query_row(config.ESP_DB,
        "SELECT COUNT(*) FROM esp_licenses WHERE status='used' AND COALESCE(license_key,'') != 'FASTFI-FREE-ESP';")
    
    local total_row = sqlite.query_row(config.ESP_DB, "SELECT COUNT(*) FROM esp_slots;")
    local licensed_row = sqlite.query_row(config.ESP_DB,
        "SELECT COUNT(*) FROM esp_slots WHERE license_status='licensed' OR license_status='free';")
    
    return {
        router_mac = router_mac,
        router_license_status = license_info.license_status,
        router_license_key = "***REDACTED***",
        total_esp_slots = tonumber(total_row and total_row[1]) or 0,
        available_licenses = tonumber(available_row and available_row[1]) or 0,
        used_licenses = tonumber(used_row and used_row[1]) or 0,
        licensed_esp_count = tonumber(licensed_row and licensed_row[1]) or 0,
        esp_devices = esp_devices
    }
end

function M.add_esp_device(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local esp_name = params["esp_name"]
    local esp_mac = (params["esp_mac"] or ""):lower()
    local esp_ip = params["esp_ip"] or ""
    
    if not esp_name or not esp_mac or esp_mac == "" then
        return { status = "error", message = "Missing ESP name or MAC address" }
    end
    
    
    
    
    
    
    
    
    
    local router_mac = config.MACHINE_ID
    
    local license_info = config_db.get_license_info()
    
    
    local exists = sqlite.execute(config.ESP_DB,
        string.format("SELECT id FROM esp_slots WHERE slot_mac='%s';", esp_mac))
    
    if exists and exists ~= "" then
        return { status = "error", message = "ESP MAC address already registered" }
    end
    
    
    local count_row = sqlite.query_row(config.ESP_DB, "SELECT COUNT(*) FROM esp_slots;")
    local esp_count = tonumber(count_row and count_row[1]) or 0
    local slot_num = esp_count + 1
    
    
    local license_status = "unlicensed"
    local license_key = ""
    
    
    local free_lic = sqlite.query_row(config.ESP_DB, "SELECT id FROM esp_licenses WHERE license_key='FASTFI-FREE-ESP' AND status='available';")
    if free_lic and free_lic[1] then
        license_status = "free"
        license_key = "FASTFI-FREE-ESP"
    end
    
    
    sqlite.execute(config.ESP_DB,
        string.format("INSERT INTO esp_slots (slot_name, slot_mac, router_mac, status, license_status, license_key) VALUES ('%s', '%s', '%s', 'online', '%s', '%s');",
            esp_name, esp_mac, router_mac, license_status, license_key))
    
    local slot_id_row = sqlite.query_row(config.ESP_DB, "SELECT last_insert_rowid();")
    local slot_id = tonumber(slot_id_row and slot_id_row[1]) or 0
    
    
    if license_key == "FASTFI-FREE-ESP" then
        sqlite.execute(config.ESP_DB, 
            string.format("UPDATE esp_licenses SET status='used', used_slot_id=%d, used_at=datetime('now'), router_mac='%s' WHERE license_key='FASTFI-FREE-ESP';",
                slot_id, router_mac))
    end
    
    return {
        status = "ok",
        message = "ESP device added",
        slot_id = slot_id,
        slot_number = slot_num,
        license_status = license_status
    }
end

function M.delete_esp_device(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end

    local slot_id = params["slot_id"]
    if not slot_id then
        return { status = "error", message = "Missing slot_id" }
    end

    local safe_id = sqlite.quote(tostring(slot_id))

    
    
    
    
    
    
    
    
    local slot = sqlite.query_row(config.ESP_DB,
        string.format("SELECT license_key FROM esp_slots WHERE id='%s';", safe_id))
    if slot and slot[1] and slot[1] ~= "" then
        sqlite.execute(config.ESP_DB,
            string.format("UPDATE esp_licenses SET status='available', used_slot_id=NULL, used_at=NULL WHERE license_key='%s';",
                sqlite.quote(slot[1])))
    end

    sqlite.execute(config.ESP_DB,
        string.format("DELETE FROM esp_slots WHERE id='%s';", safe_id))

    return { status = "ok", message = "ESP device deleted" }
end

function M.rename_esp_slot(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local slot_id = params["slot_id"]
    local new_name = params["slot_name"]
    
    if not slot_id or not new_name then
        return { status = "error", message = "Missing slot_id or slot_name" }
    end
    
    sqlite.execute(config.ESP_DB,
        string.format("UPDATE esp_slots SET slot_name='%s' WHERE id='%s';", new_name, slot_id))
    
    return { status = "ok", message = "ESP slot renamed" }
end


function M.register_esp_slot(params)
    local esp_mac = string.upper(tostring(params["mac"] or ""):gsub("%s+", ""))
    esp_mac = esp_mac:gsub("-", ":")
    local esp_name = params["name"] or "New ESP32"
    local license_id = string.upper(tostring(params["license_id"] or params["license_key"] or ""):gsub("%s+", ""))

    if esp_mac == "" then
        return { licensed = false, error = "missing_mac" }
    end

    -- Auto-detect path: ESP (or Admin) sends license_id with MAC
    if license_id ~= "" and license_id ~= "FASTFI-FREE-ESP" then
        local esp_license = require("fastfi.api.routes.esp_license")
        local det = esp_license.detect({
            mac = esp_mac,
            license_id = license_id,
            name = esp_name,
            _from_register = true,
        })
        if det.status == "ok" then
            return {
                licensed = true,
                license_key = license_id,
                license_id = license_id,
                slot_number = det.slot_id,
                status = "ok",
                grace_used = det.grace_used,
                grace_max = det.grace_max,
                message = det.message,
            }
        end
        return {
            licensed = false,
            status = "error",
            error = det.message or "detect_failed",
            message = det.message,
            grace_used = det.grace_used,
            grace_max = det.grace_max,
        }
    end

    local router_mac = config.MACHINE_ID
    local row = sqlite.query_row(config.ESP_DB,
        string.format("SELECT id, license_status, license_key FROM esp_slots WHERE UPPER(slot_mac)='%s';", esp_mac))

    local license_status, license_key, slot_id

    if row then
        slot_id = tonumber(row[1]) or 1
        license_status = row[2]
        license_key = row[3]
        local now = os.time()
        sqlite.execute(config.ESP_DB,
            string.format("UPDATE esp_slots SET status='online', last_seen=%d WHERE UPPER(slot_mac)='%s';",
                now, esp_mac))
    else
        -- No auto free FastFi slot — must present KSK license_id
        license_status = "unlicensed"
        license_key = ""
        local now = os.time()
        local count_row = sqlite.query_row(config.ESP_DB, "SELECT COUNT(*) FROM esp_slots;")
        local esp_count = tonumber(count_row and count_row[1]) or 0
        local final_name = esp_name ~= "New ESP32" and esp_name or ("ESP32 #" .. (esp_count + 1))

        sqlite.execute(config.ESP_DB,
            string.format("INSERT INTO esp_slots (slot_name, slot_mac, router_mac, status, license_status, license_key, last_seen) VALUES ('%s', '%s', '%s', 'online', '%s', '%s', %d);",
                sqlite.quote(final_name), esp_mac, router_mac, license_status, license_key, now))

        local id_row = sqlite.query_row(config.ESP_DB, "SELECT last_insert_rowid();")
        slot_id = tonumber(id_row and id_row[1]) or (esp_count + 1)
    end

    local is_licensed = (license_status == "free" or license_status == "licensed")

    return {
        licensed = is_licensed,
        license_key = license_key,
        license_id = license_key,
        slot_number = slot_id,
        status = "ok",
        message = is_licensed and "ok" or "ESP online but unlicensed — Detect with KSK license ID to activate Insert Coin",
    }
end


function M.esp_status(params)
    local esp_mac = (params["mac"] or ""):lower()
    local status = params["status"] or "online"
    
    if esp_mac == "" then
        return { status = "error", message = "missing_mac" }
    end
    
    local now = os.time()
    
    
    if not _G.ESP_GRACE_CHECKED then
        sqlite.execute(config.ESP_DB, "ALTER TABLE esp_slots ADD COLUMN grace_until INTEGER DEFAULT 0;")
        _G.ESP_GRACE_CHECKED = true
    end
    
    
    sqlite.execute(config.ESP_DB,
        string.format("UPDATE esp_slots SET status='%s', last_seen=%d WHERE slot_mac='%s';",
            sqlite.quote(status), now, esp_mac))
            
    
    local lock_row = sqlite.query_row(config.ESP_DB,
        string.format("SELECT locked_by, locked_at, grace_until FROM esp_slots WHERE slot_mac='%s';", esp_mac))
    
    local is_locked = false
    if lock_row then
        local locked_by = lock_row[1] or ""
        local locked_at = tonumber(lock_row[2]) or 0
        local grace_until = tonumber(lock_row[3]) or 0
        
        
        if locked_by ~= "" then
            
            local timer_row = sqlite.query_row(config.CONFIG_DB, "SELECT insert_timer FROM config LIMIT 1;")
            local insert_timer = tonumber(timer_row and timer_row[1]) or 60
            
            if (now - locked_at) < insert_timer then
                is_locked = true
            end
        end
        
        
        if grace_until > now then
            is_locked = true
        end
    end
            
    return { 
        status = "ok",
        relay = is_locked and 1 or 0
    }
end


function M.check_coin_lock(params)
    local client_mac = sqlite.quote((params["mac"] or ""):lower())
    if client_mac == "" then
        return { locked = false }
    end

    
    local slot_mac = ""
    local coin_credit = 0
    local locked_at = 0
    
    local row = sqlite.query_row(config.ESP_DB,
        string.format("SELECT slot_mac, coin_credit, locked_at FROM esp_slots WHERE locked_by='%s';", client_mac))
    if row then
        slot_mac = row[1] or ""
        coin_credit = tonumber(row[2]) or 0
        locked_at = tonumber(row[3]) or 0
    end

    if slot_mac == "" or locked_at == 0 then
        return { locked = false }
    end

    
    local timer_row = sqlite.query_row(config.CONFIG_DB, "SELECT insert_timer FROM config LIMIT 1;")
    local insert_timer = tonumber(timer_row and timer_row[1]) or 60

    
    local now = os.time()
    if (now - locked_at) >= (insert_timer + 10) then
        return { locked = false }
    end

    local elapsed = now - locked_at
    local remaining = math.max(0, insert_timer - elapsed)

    return {
        locked = true,
        slot_mac = slot_mac,
        coin = coin_credit,
        locked_at = locked_at,
        remaining_timer = remaining,
        insert_timer = insert_timer
    }
end


function M.unlock_coin(params)
    local slot_mac = (params["slot_mac"] or ""):lower()
    if slot_mac == "" then
        return { status = "error", message = "Missing slot_mac" }
    end

    if slot_mac == "local" then
        return { status = "ok", message = "Slot unlocked" }
    end

    local safe_mac = sqlite.quote(slot_mac)
    
    local clear_result = sqlite.execute(config.ESP_DB,
        string.format("UPDATE esp_slots SET locked_by='', locked_at=0, coin_credit=0 WHERE LOWER(slot_mac)='%s';", safe_mac))

    return { status = "ok", message = "Slot unlocked" }
end

return M
