
local session_db = require("fastfi.db.sessions")
local file_util = require("fastfi.util.file")
local security = require("fastfi.security")




local function sanitize_hostname(h)
    if not h or h == "" or h == "*" then return "Unknown Device" end
    h = h:gsub("[^%w%.%-_]", "")
    if #h == 0 then return "Unknown Device" end
    if #h > 32 then h = h:sub(1, 32) end
    return h
end

local M = {}

function M.live_sessions(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local sessions = session_db.get_active_sessions()
    local now = os.time()
    local result = {}
    
    
    local arp_data = file_util.read("/proc/net/arp") or ""
    local arp_map = {}
    for line in arp_data:gmatch("[^\n]+") do
        local ip, mac = line:match("^(%S+)%s+%S+%s+%S+%s+(%S+)")
        if ip and mac then
            arp_map[mac:lower()] = ip
        end
    end
    
    for _, s in ipairs(sessions) do
        if s.session_end > now then
            local remaining = s.session_end - now
            local ip = arp_map[s.mac:lower()] or "unknown"
            
            table.insert(result, {
                mac = s.mac,
                ip = ip,
                remaining = remaining,
                download = s.data_consumed_mb or 0,
                upload = 0,
                active = s.active,
                paused = s.paused
            })
        end
    end
    
    return { status = "ok", data = result }
end

function M.client_list(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local sessions = session_db.get_active_sessions()
    local now = os.time()
    local result = {}
    
    
    local dhcp_data = file_util.read("/tmp/dhcp.leases") or ""
    local dhcp_map = {}
    for line in dhcp_data:gmatch("[^\n]+") do
        local parts = {}
        for part in line:gmatch("%S+") do
            table.insert(parts, part)
        end
        if #parts >= 4 then
            local mac = parts[2]:lower()
            dhcp_map[mac] = {
                ip = parts[3],
                hostname = sanitize_hostname(parts[4])
            }
        end
    end
    
    local json = require("fastfi.util.json")
    local nds_cache = file_util.read("/tmp/nds_stats.json") or "{}"
    local nds_data = {}
    local success, parsed = pcall(json.decode, nds_cache)
    if success and parsed and parsed.clients then
        nds_data = parsed.clients
    end
    
    
    local added_macs = {}
    
    
    for _, s in ipairs(sessions) do
        added_macs[s.mac:lower()] = true
        
        local remaining = 0
        if s.paused == 1 then
            remaining = s.remaining or 0
        else
            remaining = math.max(0, s.session_end - now)
        end
        
        
        local days = math.floor(remaining / 86400)
        local hours = math.floor((remaining % 86400) / 3600)
        local mins = math.floor((remaining % 3600) / 60)
        local secs = math.floor(remaining % 60)
        
        local formatted = ""
        if days > 0 then
            formatted = string.format("%dd %dh %dm %ds", days, hours, mins, secs)
        elseif hours > 0 then
            formatted = string.format("%dh %dm %ds", hours, mins, secs)
        else
            formatted = string.format("%dm %ds", mins, secs)
        end
        
        local dhcp_info = dhcp_map[s.mac:lower()] or {}
        local nds_client = nds_data[s.mac:lower()] or {}
        
        local validity_formatted = "No Expiry"
        if s.validity_end and s.validity_end > 0 then
            local v_rem = math.max(0, s.validity_end - now)
            if v_rem == 0 then
                validity_formatted = "Expired"
            else
                local vd = math.floor(v_rem / 86400)
                local vh = math.floor((v_rem % 86400) / 3600)
                local vm = math.floor((v_rem % 3600) / 60)
                if vd > 0 then
                    validity_formatted = string.format("%dd %dh", vd, vh)
                elseif vh > 0 then
                    validity_formatted = string.format("%dh %dm", vh, vm)
                else
                    validity_formatted = string.format("%dm", vm)
                end
            end
        end
        
        table.insert(result, {
            mac = s.mac,
            ip = dhcp_info.ip or s.ip or "-",
            hostname = dhcp_info.hostname or s.hostname or "Unknown Device",
            remaining = remaining,
            formatted = formatted,
            validity_end = s.validity_end or 0,
            validity_formatted = validity_formatted,
            download = s.data_consumed_mb or 0,
            upload = 0, 
            dl_rate = nds_client.dl_rate or 0,
            ul_rate = nds_client.ul_rate or 0,
            active = s.active,
            paused = s.paused,
            whitelisted = false,
            dl_limit = s.dl_limit,
            ul_limit = s.ul_limit,
            paused_limit = s.paused_limit,
            data_limit_mb = s.data_limit_mb
        })
    end
    
    return { status = "ok", data = result }
end

function M.client_list_unauth(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    
    local arp_data = file_util.read("/proc/net/arp") or ""
    local sessions = session_db.get_active_sessions()
    local now = os.time()
    
    
    local auth_macs = {}
    for _, s in ipairs(sessions) do
        auth_macs[s.mac:lower()] = true
    end
    
    local arp_lines = {}
    for line in arp_data:gmatch("[^\n]+") do
        table.insert(arp_lines, line)
    end
    
    
    local dhcp_data = file_util.read("/tmp/dhcp.leases") or ""
    local dhcp_map = {}
    for line in dhcp_data:gmatch("[^\n]+") do
        local parts = {}
        for part in line:gmatch("%S+") do
            table.insert(parts, part)
        end
        if #parts >= 4 then
            local mac = parts[2]:lower()
            dhcp_map[mac] = {
                ip = parts[3],
                hostname = sanitize_hostname(parts[4])
            }
        end
    end
    
    local result = {}
    for line in arp_data:gmatch("[^\n]+") do
        local ip, mac = line:match("^(%S+)%s+%S+%s+%S+%s+(%S+)")
        if ip and mac then
            mac = mac:lower()
            
            if not auth_macs[mac] and mac ~= "type" and mac ~= "address" and mac ~= "00:00:00:00:00:00" then
                local dhcp_info = dhcp_map[mac] or {}
                table.insert(result, {
                    mac = mac,
                    ip = dhcp_info.ip or ip,
                    hostname = dhcp_info.hostname or "Unknown Device",
                    status = "unauthenticated"
                })
            end
        end
    end
    
    return { status = "ok", data = result }
end

return M
