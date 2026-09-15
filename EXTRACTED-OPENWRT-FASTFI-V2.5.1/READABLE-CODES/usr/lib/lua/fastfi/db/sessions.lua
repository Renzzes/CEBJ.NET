
local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")
local file_util = require("fastfi.util.file")
local M = {}








function M.sanitize_device_id(device_id, client_id, mac)
    local function is_placeholder(v)
        return v == nil or v == "" or v == "null" or v == "undefined"
    end
    if not is_placeholder(device_id) then
        return tostring(device_id):gsub("%s+", "")
    end
    if not is_placeholder(client_id) then
        return tostring(client_id):gsub("%s+", "")
    end
    if mac and mac ~= "" then
        return tostring(mac):lower()
    end
    
    math.randomseed(os.time() * 1000 + (math.floor(os.clock() * 1000) % 1000))
    math.random()
    return string.format("dev-%d-%d", os.time(), math.random(1000, 9999))
end

function M.query_session(mac, device_id)
    local safe_mac = sqlite.quote((mac or ""):lower())
    local row = nil
    
    
    local query = ""
    if device_id and device_id ~= "" and device_id ~= "null" and device_id ~= "undefined" then
        query = string.format("SELECT session_end, active, paused, remaining, mac_address, device_id, dl_limit, ul_limit, data_limit_mb, data_consumed_mb, validity_end, paused_limit, pause_count, sub_vendo_id FROM sessions WHERE device_id='%s' OR lower(trim(mac_address))='%s' ORDER BY session_end DESC LIMIT 1;",
            sqlite.quote(device_id), safe_mac)
    else
        query = string.format("SELECT session_end, active, paused, remaining, mac_address, device_id, dl_limit, ul_limit, data_limit_mb, data_consumed_mb, validity_end, paused_limit, pause_count, sub_vendo_id FROM sessions WHERE lower(trim(mac_address))='%s' ORDER BY session_end DESC LIMIT 1;",
            safe_mac)
    end

    row = sqlite.query_row(config.SESSIONS_DB, query)

    if not row then return nil end

    local session = {
        session_end = tonumber(row[1]) or 0,
        active = tonumber(row[2]) or 0,
        paused = tonumber(row[3]) or 0,
        remaining = tonumber(row[4]) or 0,
        mac_db = file_util.trim(row[5] or ""),
        device_id = file_util.trim(row[6] or ""),
        dl_limit = tonumber(row[7]) or 0,
        ul_limit = tonumber(row[8]) or 0,
        data_limit_mb = tonumber(row[9]) or 0,
        data_consumed_mb = tonumber(row[10]) or 0,
        validity_end = tonumber(row[11]) or 0,
        paused_limit = tonumber(row[12]) or 0,
        pause_count = tonumber(row[13]) or 0,
        sub_vendo_id = tonumber(row[14]) or 0
    }

    
    if mac and mac ~= "" and session.mac_db ~= "" and session.mac_db:lower() ~= mac:lower() then
        
        os.execute(string.format("ndsctl deauth %s >/dev/null 2>&1", session.mac_db))
        
        
        sqlite.execute(config.SESSIONS_DB, 
            string.format("DELETE FROM sessions WHERE lower(trim(mac_address))='%s' AND device_id != '%s';", 
            safe_mac, sqlite.quote(session.device_id)))

        
        sqlite.execute(config.SESSIONS_DB, 
            string.format("UPDATE sessions SET mac_address='%s' WHERE device_id='%s';", safe_mac, sqlite.quote(session.device_id)))
        
        session.mac_db = mac:lower()
        session.roamed = true 

        
        if session.active == 1 and session.session_end > os.time() and session.paused == 0 then
            os.execute(string.format("(ndsctl auth %s >/dev/null 2>&1; /usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1) &", mac))
        end
    end

    return session
end

function M.update_session(mac, session_end, active, paused, remaining, dl_limit, ul_limit, data_limit_mb, data_consumed_mb, validity_end, paused_limit, sub_vendo_id)
    local safe_mac = sqlite.quote((mac or ""):lower())
    local now = os.time()
    
    
    local current_session = M.query_session(mac, nil)
    local device_id = current_session and current_session.device_id or ""
    
    
    
    if device_id == "" or device_id == "null" or device_id == "undefined" then
        device_id = ""
    end
    local safe_div = sqlite.quote(device_id)
    
    
    if paused == 1 then
        
        if current_session and current_session.paused == 0 then
            
            M.log_session_event(device_id, mac, 'paused', remaining, session_end, 'Manual pause by admin', 'admin')
            
            
            if safe_div ~= "" then
                sqlite.execute(config.SESSIONS_DB,
                    string.format("UPDATE sessions SET last_paused_at=%d, pause_count=pause_count+1 WHERE device_id='%s';",
                        now, safe_div))
            else
                sqlite.execute(config.SESSIONS_DB,
                    string.format("UPDATE sessions SET last_paused_at=%d, pause_count=pause_count+1 WHERE lower(trim(mac_address))='%s';",
                        now, safe_mac))
            end
        end
    elseif paused == 0 then
        
        if current_session and current_session.paused == 1 then
            
            local pause_duration = now - (current_session.last_paused_at or now)
            M.log_session_event(device_id, mac, 'resumed', remaining, session_end, 'Session resumed after ' .. pause_duration .. 's pause', 'admin')
            
            
            if safe_div ~= "" then
                sqlite.execute(config.SESSIONS_DB,
                    string.format("UPDATE sessions SET total_paused_duration=total_paused_duration+%d WHERE device_id='%s';",
                        pause_duration, safe_div))
            else
                sqlite.execute(config.SESSIONS_DB,
                    string.format("UPDATE sessions SET total_paused_duration=total_paused_duration+%d WHERE lower(trim(mac_address))='%s';",
                        pause_duration, safe_mac))
            end
        end
    end
    
    
    local update_fields = string.format("session_end=%d, active=%d, paused=%d, remaining=%d, updated_at=%d", 
        session_end, active, paused, remaining, now)
    
    if dl_limit then
        update_fields = update_fields .. string.format(", dl_limit=%d", tonumber(dl_limit) or 0)
    end
    if ul_limit then
        update_fields = update_fields .. string.format(", ul_limit=%d", tonumber(ul_limit) or 0)
    end
    if data_limit_mb then
        update_fields = update_fields .. string.format(", data_limit_mb=%d", tonumber(data_limit_mb) or 0)
    end
    if data_consumed_mb then
        update_fields = update_fields .. string.format(", data_consumed_mb=%d", tonumber(data_consumed_mb) or 0)
    end
    
    if validity_end then
        update_fields = update_fields .. string.format(", validity_end=%d", tonumber(validity_end) or 0)
    end
    if paused_limit then
        update_fields = update_fields .. string.format(", paused_limit=%d", tonumber(paused_limit) or 0)
    end
    if sub_vendo_id then
        update_fields = update_fields .. string.format(", sub_vendo_id=%d", tonumber(sub_vendo_id) or 0)
    end

    if safe_div ~= "" and safe_div ~= "''" then
        sqlite.execute(config.SESSIONS_DB,
            string.format("UPDATE sessions SET %s WHERE device_id='%s';",
                update_fields, safe_div))
    else
        sqlite.execute(config.SESSIONS_DB,
            string.format("UPDATE sessions SET %s WHERE lower(trim(mac_address))='%s';",
                update_fields, safe_mac))
    end
end

function M.create_session(device_id, mac, session_end, dl_limit, ul_limit, data_limit_mb, validity_end, paused_limit, sub_vendo_id)
    local safe_div = sqlite.quote(device_id or "")
    local safe_mac = sqlite.quote((mac or ""):lower())
    local now = os.time()
    local dl = tonumber(dl_limit) or 0
    local ul = tonumber(ul_limit) or 0
    local d_limit = tonumber(data_limit_mb) or 0
    local v_end = tonumber(validity_end) or 0
    local p_limit = tonumber(paused_limit) or 0
    local sv_id = tonumber(sub_vendo_id) or 0

    
    sqlite.execute(config.SESSIONS_DB,
        string.format("INSERT OR REPLACE INTO sessions (device_id, mac_address, session_end, active, paused, remaining, updated_at, created_at, dl_limit, ul_limit, data_limit_mb, data_consumed_mb, validity_end, paused_limit, sub_vendo_id) VALUES ('%s', '%s', %d, 1, 0, 0, %d, %d, %d, %d, %d, 0, %d, %d, %d);",
            safe_div, safe_mac, session_end, now, now, dl, ul, d_limit, v_end, p_limit, sv_id))
    
    
    M.log_session_event(device_id, mac, 'created', 0, session_end, 'New session created', 'system')
end

function M.get_active_sessions()
    local now = os.time()
    local result = sqlite.execute(config.SESSIONS_DB,
        string.format("SELECT mac_address, session_end, active, paused, remaining, download, upload, dl_limit, ul_limit, validity_end, data_limit_mb, data_consumed_mb, paused_limit, sub_vendo_id FROM sessions WHERE (active=1 AND session_end > %d) OR (paused=1 AND remaining > 0) ORDER BY session_end DESC;", now))

    if not result or result == "" then return {} end

    local sessions = {}
    for line in result:gmatch("[^\n]+") do
        local fields = {}
        for token in string.gmatch(line, "[^|]+") do
            table.insert(fields, file_util.trim(token))
        end

        table.insert(sessions, {
            mac = fields[1] or "",
            session_end = tonumber(fields[2]) or 0,
            active = tonumber(fields[3]) or 0,
            paused = tonumber(fields[4]) or 0,
            remaining = tonumber(fields[5]) or 0,
            download = tonumber(fields[6]) or 0,
            upload = tonumber(fields[7]) or 0,
            dl_limit = tonumber(fields[8]) or 0,
            ul_limit = tonumber(fields[9]) or 0,
            validity_end = tonumber(fields[10]) or 0,
            data_limit_mb = tonumber(fields[11]) or 0,
            data_consumed_mb = tonumber(fields[12]) or 0,
            paused_limit = tonumber(fields[13]) or 0,
            sub_vendo_id = tonumber(fields[14]) or 0
        })
    end

    return sessions
end


function M.log_session_event(device_id, mac, event_type, remaining, session_end, reason, triggered_by)
    local safe_div = sqlite.quote(device_id or "")
    local safe_mac = sqlite.quote((mac or ""):lower())
    local now = os.time()
    local safe_reason = sqlite.quote(reason or "")
    local safe_trigger = sqlite.quote(triggered_by or "system")
    
    sqlite.execute(config.SESSIONS_DB,
        string.format("INSERT INTO session_history (device_id, mac_address, event_type, timestamp, remaining_seconds, session_end, reason, triggered_by) VALUES ('%s', '%s', '%s', %d, %d, %d, '%s', '%s');",
            safe_div, safe_mac, event_type, now, remaining or 0, session_end or 0, safe_reason, safe_trigger))
end


function M.get_session_history(device_id, mac, limit)
    limit = limit or 50
    local safe_div = sqlite.quote(device_id or "")
    local safe_mac = sqlite.quote((mac or ""):lower())
    
    local result = ""
    if safe_div ~= "" and safe_div ~= "''" then
        result = sqlite.execute(config.SESSIONS_DB,
            string.format("SELECT id, device_id, mac_address, event_type, timestamp, remaining_seconds, session_end, reason, triggered_by FROM session_history WHERE device_id='%s' ORDER BY timestamp DESC LIMIT %d;",
                safe_div, limit))
    elseif safe_mac ~= "" then
        result = sqlite.execute(config.SESSIONS_DB,
            string.format("SELECT id, device_id, mac_address, event_type, timestamp, remaining_seconds, session_end, reason, triggered_by FROM session_history WHERE lower(trim(mac_address))='%s' ORDER BY timestamp DESC LIMIT %d;",
                safe_mac, limit))
    end
    
    if not result or result == "" then return {} end
    
    local history = {}
    for line in result:gmatch("[^\n]+") do
        local fields = {}
        for token in string.gmatch(line, "[^|]+") do
            table.insert(fields, file_util.trim(token))
        end
        
        table.insert(history, {
            id = tonumber(fields[1]) or 0,
            device_id = fields[2] or "",
            mac = fields[3] or "",
            event_type = fields[4] or "",
            timestamp = tonumber(fields[5]) or 0,
            remaining = tonumber(fields[6]) or 0,
            session_end = tonumber(fields[7]) or 0,
            reason = fields[8] or "",
            triggered_by = fields[9] or "system"
        })
    end
    
    return history
end


function M.get_recent_events(limit)
    limit = limit or 100
    local result = sqlite.execute(config.SESSIONS_DB,
        string.format("SELECT id, device_id, mac_address, event_type, timestamp, remaining_seconds, reason, triggered_by FROM session_history ORDER BY timestamp DESC LIMIT %d;",
            limit))
    
    if not result or result == "" then return {} end
    
    local events = {}
    for line in result:gmatch("[^\n]+") do
        local fields = {}
        for token in string.gmatch(line, "[^|]+") do
            table.insert(fields, file_util.trim(token))
        end
        
        table.insert(events, {
            id = tonumber(fields[1]) or 0,
            device_id = fields[2] or "",
            mac = fields[3] or "",
            event_type = fields[4] or "",
            timestamp = tonumber(fields[5]) or 0,
            remaining = tonumber(fields[6]) or 0,
            reason = fields[7] or "",
            triggered_by = fields[8] or "system"
        })
    end
    
    return events
end

return M
