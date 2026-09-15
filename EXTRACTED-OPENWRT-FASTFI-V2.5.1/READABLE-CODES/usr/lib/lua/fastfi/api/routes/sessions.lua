
local session_db = require("fastfi.db.sessions")
local security = require("fastfi.security")
local M = {}









local function nds_mac_present(mac)
    local f = io.popen("ndsctl json 2>/dev/null")
    if not f then return false end
    local out = f:read("*a") or ""
    f:close()
    return out:lower():find(mac:lower(), 1, true) ~= nil
end



local function grant_internet(session, mac)
    os.execute("ndsctl deauth " .. mac .. " >/dev/null 2>&1; sleep 0.3")
    os.execute("ndsctl auth " .. mac .. " >/dev/null 2>&1; sleep 0.5")
    local ok = nds_mac_present(mac)
    if not ok then
        os.execute("ndsctl auth " .. mac .. " >/dev/null 2>&1; sleep 0.5")
        ok = nds_mac_present(mac)
    end
    os.execute("/usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1")
    if not ok then
        os.execute(string.format("logger -t fastfi-sessions 'ndsctl auth FAILED for %s'", mac))
    end
    return ok
end


local function drop_internet(session, mac)
    os.execute("ndsctl deauth " .. mac .. " >/dev/null 2>&1")
end

function M.deauth_client(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local mac = (params["mac"] or ""):lower()
    if mac == "" or not security.is_valid_mac(mac) then
        return { status = "error", message = "Missing or invalid MAC" }
    end
    
    local now = os.time()
    session_db.update_session(mac, 0, 0, 0, 0)
    
    
    os.execute("(ndsctl deauth " .. mac .. " >/dev/null 2>&1) &")
    
    
    os.execute('for iface in $(iw dev | awk \'$1=="Interface"{print $2}\'); do iw dev "$iface" station del ' .. mac .. ' >/dev/null 2>&1; done')
    
    return { status = "ok", message = "Client deauthenticated" }
end

function M.extend_session(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local mac = (params["mac"] or ""):lower()
    local minutes = tonumber(params["minutes"]) or 0
    
    if mac == "" or not security.is_valid_mac(mac) then
        return { status = "error", message = "Missing or invalid MAC" }
    end
    
    if minutes <= 0 then
        return { status = "error", message = "Invalid minutes" }
    end
    
    
    local session = session_db.query_session(mac, nil)
    local now = os.time()
    local new_end = 0
    local is_new_session = false
    local device_id = ""
    
    
    if session then
        device_id = session.device_id or mac  
        local current_end = session.session_end
        if session.paused == 1 then
            new_end = now + session.remaining + (minutes * 60)
        else
            new_end = (current_end > now and current_end or now) + (minutes * 60)
        end
        
        
        session_db.update_session(mac, new_end, 1, 0, new_end - now)
    else
        
        device_id = mac  
        new_end = now + (minutes * 60)
        session_db.create_session(device_id, mac, new_end)
        is_new_session = true
    end
    
    
    
    
    grant_internet(session, mac)

    return { status = "ok", message = "Session extended", new_end = new_end, device_id = device_id }
end

function M.update_client(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local mac = (params["mac"] or ""):lower()
    local remaining = tonumber(params["remaining"]) or 0
    local paused = tonumber(params["paused"]) or 0
    
    local dl_limit = tonumber(params["dl_limit"])
    local ul_limit = tonumber(params["ul_limit"])
    local data_limit_mb = tonumber(params["data_limit_mb"])
    local paused_limit = tonumber(params["paused_limit"])
    
    if mac == "" or not security.is_valid_mac(mac) then
        return { status = "error", message = "Missing or invalid MAC" }
    end
    
    local now = os.time()
    local new_end = now + remaining
    
    
    local session = session_db.query_session(mac, nil)
    
    
    if paused == 1 then
        local effective_limit = 0
        if session and session.paused_limit and session.paused_limit > 0 then
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
            local current_count = session and session.pause_count or 0
            if current_count >= effective_limit then
                return { 
                    status = "error", 
                    message = string.format("Pause limit reached (%d/%d). This client cannot pause anymore.", current_count, effective_limit)
                }
            end
        end
    end
    
    
    session_db.update_session(mac, new_end, 1, paused, remaining, dl_limit, ul_limit, data_limit_mb, nil, nil, paused_limit)
    
    if paused == 1 then
        
        
        drop_internet(session, mac)
    else
        
        grant_internet(session, mac)
    end

    return { status = "ok", message = "Client updated", new_end = new_end, paused = paused }
end

function M.session_history(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local mac = (params["mac"] or ""):lower()
    if mac ~= "" and not security.is_valid_mac(mac) then
        return { status = "error", message = "Invalid MAC format" }
    end
    local device_id = params["device_id"] or ""
    local limit = tonumber(params["limit"]) or 50
    
    local history = {}
    
    if mac ~= "" or device_id ~= "" then
        
        history = session_db.get_session_history(device_id, mac, limit)
    else
        
        history = session_db.get_recent_events(limit)
    end
    
    
    for _, event in ipairs(history) do
        event.formatted_time = os.date("%Y-%m-%d %H:%M:%S", event.timestamp)
    end
    
    return { status = "ok", data = history, count = #history }
end

return M
