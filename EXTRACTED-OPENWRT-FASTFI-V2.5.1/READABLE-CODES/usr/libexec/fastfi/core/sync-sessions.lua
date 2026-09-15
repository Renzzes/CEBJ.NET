#!/usr/bin/env lua





local session_db = require("fastfi.db.sessions")
local os = require("os")


local nds_ready = false
for i = 1, 15 do
    local f = io.popen("ndsctl status 2>/dev/null | grep -c 'Managed interface'")
    local result = f and f:read("*a") or "0"
    if f then f:close() end
    if tonumber(result) and tonumber(result) > 0 then
        nds_ready = true
        break
    end
    os.execute("sleep 1")
end

if not nds_ready then
    os.execute("logger -t fastfi 'sync-sessions: NDS not ready after 15s, aborting'")
    return
end

local sessions = session_db.get_active_sessions()
local now = os.time()



if now < 1704067200 then
    os.execute("logger -t fastfi 'sync-sessions: System clock not synced (" .. now .. "), skipping session restoration.'")
    return
end


local connected_macs = {}
local f_iw = io.popen("iw dev 2>/dev/null | awk '/Interface/{print $2}' | xargs -I {} iw dev {} station dump 2>/dev/null | awk '/Station/{print tolower($2)}'")
if f_iw then
    for mac in f_iw:lines() do
        connected_macs[mac] = true
    end
    f_iw:close()
end

local count = 0
for _, s in ipairs(sessions) do
    if s.active == 1 and s.paused == 0 and s.session_end > now then
        local mac = s.mac:lower()
        
        if connected_macs[mac] then
            
            os.execute("ndsctl deauth " .. s.mac .. " >/dev/null 2>&1")
            os.execute("sleep 0.1")
            os.execute("ndsctl auth " .. s.mac .. " >/dev/null 2>&1")
            count = count + 1
        else
            os.execute("logger -t fastfi 'sync-sessions: Skipping restoration for " .. mac .. " (not on WiFi)'")
        end
    end
end

if count > 0 then
    
    os.execute("sleep 2")
    os.execute("(/usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1) &")
    os.execute("logger -t fastfi 'Re-authenticated " .. count .. " active sessions after nodogsplash restart'")
end
