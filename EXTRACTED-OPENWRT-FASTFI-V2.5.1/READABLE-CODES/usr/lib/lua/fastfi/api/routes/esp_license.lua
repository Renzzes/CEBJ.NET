
local sqlite = require("fastfi.db.sqlite")
local config = require("fastfi.config")
local security = require("fastfi.security")

local http_util = require("fastfi.util.http")
local file_util = require("fastfi.util.file")

local M = {}



function M.list(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local router_mac = config.MACHINE_ID
    
    
    local query = string.format([[
        SELECT l.id, l.license_key, l.status, l.used_at, s.slot_name, s.slot_mac 
        FROM esp_licenses l
        LEFT JOIN esp_slots s ON l.used_slot_id = s.id
        WHERE l.router_mac = '%s' OR l.router_mac IS NULL
        ORDER BY l.id DESC;
    ]], router_mac)
    
    local list = sqlite.query_list(config.ESP_DB, query)
    local licenses = {}
    
    for _, row in ipairs(list) do
        table.insert(licenses, {
            id = row[1],
            license_key = row[2],
            status = row[3] or "available",
            used_at = row[4],
            slot_name = row[5],
            slot_mac = row[6]
        })
    end
    
    return licenses
end

function M.add(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local key = params["key"]
    if not key or key == "" then
        return { status = "error", message = "Missing license key" }
    end
    
    
    local is_free = (key == "FASTFI-FREE-ESP")
    local is_valid_format = key:match("^ESP%-[A-Z0-9]+%-[A-Z0-9]+%-[A-Z0-9]+%-[A-Z0-9]+$")
    
    if not is_free and not is_valid_format then
        return { status = "error", message = "Invalid key format. ESP licenses must follow the format: ESP-XXXX-XXXX-XXXX-XXXX" }
    end

    local safe_key = sqlite.quote(key)
    local router_mac = config.MACHINE_ID
    
    
    if is_free then
        
    else
        
        local server_url = "https://fastfi.cloud/api/v1/device/report"
        local device_id = config.MACHINE_ID
        
        
        local main_lic = sqlite.query_row("/www/data/bindcode.db", "SELECT license_key FROM config WHERE id=1;")
        local main_key = (main_lic and main_lic[1]) or ""
        
        local json_body = string.format('{"device_id":"%s","license_key":"%s","uptime":0,"esp_keys":["%s"]}', device_id, main_key, key)
        
        local response = http_util.post(server_url, json_body, {
            ["Content-Type"] = "application/json"
        })
        
        
        local f_log = io.open("/tmp/esp_license_debug.log", "a")
        if f_log then
            local log_body = response and response.body or "NO_RESPONSE"
            local log_code = response and response.status_code or "ERROR"
            f_log:write(string.format("[%s] Key: %s | Code: %s | Body: %s\n", 
                os.date(), key, log_code, log_body))
            f_log:close()
        end
        
        if not response or not response.status_code then
            return { status = "error", message = "Could not connect to license server. Check internet connection." }
        end
        
        
        local body = response.body or ""
        local srv_msg = body:match('"message"%s*:%s*"([^"]+)"') or body:match('"error"%s*:%s*"([^"]+)"') or ""
        local is_success = false
        
        if response.status_code == 200 then
            
            
            local key_pattern = '"license_key"%s*:%s*"' .. key:gsub("%-", "%%-") .. '"'
            local block_start = body:find(key_pattern)
            
            if block_start then
                
                local block = body:sub(block_start, block_start + 150)
                local esp_status = block:match('"status"%s*:%s*"([^"]+)"')
                
                
                
                if esp_status == "active" or esp_status == "unused" or esp_status == "valid" then
                    is_success = true
                elseif esp_status == "not_bound" then
                    srv_msg = "ESP key is not bound to your router's license. Please bind it to this router in the FastFi Cloud Dashboard first."
                else
                    srv_msg = "ESP license key is " .. tostring(esp_status)
                end
            else
                local top_status = body:match('"status"%s*:%s*"([^"]+)"')
                if top_status == "ok" or top_status == "license_recovery" then
                    
                    
                    is_success = true
                else
                    srv_msg = srv_msg ~= "" and srv_msg or "Failed to verify ESP key via telemetry."
                end
            end
        else
            srv_msg = "Server returned " .. tostring(response.status_code) .. ": " .. srv_msg
        end
                          
        if not is_success then
            local detail = srv_msg ~= "" and (": " .. srv_msg) or ""
            return { status = "error", message = "License rejected by server" .. detail }
        end
    end
    
    
    local exists = sqlite.query_row(config.ESP_DB, 
        string.format("SELECT id FROM esp_licenses WHERE license_key='%s';", safe_key))
        
    if exists and exists[1] then
        return { status = "error", message = "License key already added to pool" }
    end
    
    
    sqlite.execute(config.ESP_DB, 
        string.format("INSERT INTO esp_licenses (license_key, status, router_mac) VALUES ('%s', 'available', '%s');", 
            safe_key, router_mac))
            
    return { status = "ok", message = "License verified and added to pool successfully" }
end

function M.remove(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local id = params["id"]
    if not id then
        return { status = "error", message = "Missing license ID" }
    end
    
    
    sqlite.execute(config.ESP_DB, 
        string.format("DELETE FROM esp_licenses WHERE id='%s' AND status='available';", sqlite.quote(tostring(id))))
        
    return { status = "ok", message = "License removed from pool" }
end

function M.bind(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local esp_id = params["esp_id"]
    if not esp_id then
        return { status = "error", message = "Missing ESP ID" }
    end
    
    local router_mac = config.MACHINE_ID
    
    
    local slot = sqlite.query_row(config.ESP_DB, 
        string.format("SELECT id, license_status FROM esp_slots WHERE id='%s';", sqlite.quote(tostring(esp_id))))
        
    if not slot or not slot[1] then
        return { status = "error", message = "ESP slot not found" }
    end
    
    if slot[2] == "free" or slot[2] == "licensed" then
        return { status = "error", message = "ESP slot already has a license" }
    end
    
    
    local license = sqlite.query_row(config.ESP_DB, 
        string.format("SELECT id, license_key FROM esp_licenses WHERE (router_mac='%s' OR router_mac IS NULL) AND status='available' LIMIT 1;", router_mac))
        
    if not license or not license[1] then
        return { status = "error", message = "No available licenses in pool. Please add one first." }
    end
    
    local lic_id = license[1]
    local lic_key = license[2]
    
    
    sqlite.execute(config.ESP_DB, 
        string.format("UPDATE esp_licenses SET status='used', used_slot_id='%s', used_at=datetime('now'), router_mac='%s' WHERE id='%s';", 
            sqlite.quote(tostring(esp_id)), router_mac, lic_id))
            
    sqlite.execute(config.ESP_DB, 
        string.format("UPDATE esp_slots SET license_status='licensed', license_key='%s' WHERE id='%s';", 
            sqlite.quote(lic_key), sqlite.quote(tostring(esp_id))))
            
    return { status = "ok", message = "License successfully bound to ESP slot" }
end

function M.unbind(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local esp_id = params["esp_id"]
    if not esp_id then
        return { status = "error", message = "Missing ESP ID" }
    end
    
    
    local slot = sqlite.query_row(config.ESP_DB, 
        string.format("SELECT license_key FROM esp_slots WHERE id='%s';", sqlite.quote(tostring(esp_id))))
        
    if slot and slot[1] and slot[1] ~= "" then
        local lic_key = slot[1]
        
        local new_status = "available"
        
        sqlite.execute(config.ESP_DB, 
            string.format("UPDATE esp_licenses SET status='%s', used_slot_id=NULL, used_at=NULL WHERE license_key='%s';", 
                new_status, sqlite.quote(lic_key)))
    end
    
    
    sqlite.execute(config.ESP_DB, 
        string.format("UPDATE esp_slots SET license_status='unlicensed', license_key=NULL WHERE id='%s';", sqlite.quote(tostring(esp_id))))
        
    return { status = "ok", message = "ESP unbound and license blocked" }
end

function M.free(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local esp_id = params["esp_id"]
    if not esp_id then
        return { status = "error", message = "Missing ESP ID" }
    end
    
    
    local slot = sqlite.query_row(config.ESP_DB, 
        string.format("SELECT status, license_key FROM esp_slots WHERE id='%s';", sqlite.quote(tostring(esp_id))))
        
    if not slot or not slot[1] then
        return { status = "error", message = "ESP slot not found" }
    end
    
    
    if slot[2] and slot[2] ~= "" then
        sqlite.execute(config.ESP_DB, 
            string.format("UPDATE esp_licenses SET status='available', used_slot_id=NULL, used_at=NULL WHERE license_key='%s';", sqlite.quote(slot[2])))
    end
    
    
    sqlite.execute(config.ESP_DB,
        string.format("UPDATE esp_slots SET license_status='inactive_replaced', license_key=NULL WHERE id='%s';", sqlite.quote(tostring(esp_id))))

    return { status = "ok", message = "License successfully freed back to pool" }
end









function M.release(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end

    local id = params["id"]
    if not id then
        return { status = "error", message = "Missing license id" }
    end

    local safe_id = sqlite.quote(tostring(id))

    
    
    local row = sqlite.query_row(config.ESP_DB,
        string.format("SELECT status FROM esp_licenses WHERE id='%s';", safe_id))
    if not row or not row[1] then
        return { status = "error", message = "License not found" }
    end
    if row[1] ~= "used" then
        return { status = "error", message = "License is not currently in use" }
    end

    sqlite.execute(config.ESP_DB,
        string.format("UPDATE esp_licenses SET status='available', used_slot_id=NULL, used_at=NULL WHERE id='%s';", safe_id))

    return { status = "ok", message = "License released back to pool" }
end

return M
