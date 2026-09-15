#!/usr/bin/env lua




local SESSIONS_DB = "/www/data/sessions.db"


local os_target = package.config:sub(1,1)
if os_target == '\\' then
    SESSIONS_DB = "./data/sessions.db"
end

local function execute_db(query)
    local safe_query = query:gsub('"', '\\"')
    local cmd = string.format('sqlite3 "%s" "%s" 2>/dev/null', SESSIONS_DB, safe_query)
    local handle = io.popen(cmd)
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()
    return result
end

local now = os.time()






local EXPIRY = "(paused=0 AND (session_end <= %d OR (validity_end > 0 AND validity_end <= %d))) OR (paused=1 AND validity_end > 0 AND validity_end <= %d)"
local expired = execute_db(string.format("SELECT device_id, mac_address FROM sessions WHERE active=1 AND (" .. EXPIRY .. ");", now, now, now))

if expired and expired ~= "" then
    local macs_to_deauth = {}
    for line in expired:gmatch("[^\r\n]+") do
        local dev_id, mac = line:match("^(.-)|(.*)$")
        if mac and mac ~= "" then
            table.insert(macs_to_deauth, mac)
        end
    end

    if #macs_to_deauth > 0 then
        
        execute_db(string.format("UPDATE sessions SET active=0, paused=0, remaining=0 WHERE active=1 AND (" .. EXPIRY .. ");", now, now, now))
        
        
        for _, mac in ipairs(macs_to_deauth) do
            os.execute("fastfi-qos.sh remove " .. mac .. " >/dev/null 2>&1")
            os.execute("ndsctl deauth " .. mac .. " >/dev/null 2>&1 &")
            
            local log_cmd = string.format("echo '%s - Deauthed MAC: %s (v5 natively)' >> /tmp/session-expiry.log", os.date('%Y-%m-%d %H:%M:%S'), mac)
            os.execute(log_cmd)
        end
    end
end


local success, cjson = pcall(require, "cjson")
local decode = success and cjson.decode or (require("fastfi.util.json")).decode
local file_util = require("fastfi.util.file")
local stats_str = file_util.read("/tmp/nds_stats.json")
if stats_str and stats_str ~= "" then
    local ok, stats = pcall(decode, stats_str)
    if ok and stats and stats.clients then
        execute_db("BEGIN TRANSACTION;")
        for mac, c in pairs(stats.clients) do
            local safe_mac = mac:lower():gsub('"', '')
            local dl = tonumber(c.download) or 0
            local ul = tonumber(c.upload) or 0
            if dl > 0 or ul > 0 then
                local consumed_mb = math.floor((dl + ul) / (1024 * 1024))
                execute_db(string.format("UPDATE sessions SET download=%d, upload=%d, data_consumed_mb=MAX(data_consumed_mb, %d) WHERE lower(mac_address)='%s' AND active=1;", dl, ul, consumed_mb, safe_mac))
            end
        end
        execute_db("COMMIT;")
    end
end


os.execute("find /usr/libexec/fastfi -type f \\( -name '*.sh' -o -name '*.lua' \\) -exec chmod +x {} + 2>/dev/null")
os.execute("chmod +x /etc/init.d/fastfi 2>/dev/null")
os.execute("chmod 0600 /etc/crontabs/root 2>/dev/null")
os.execute("if ! pgrep -f 'core-loop.sh' >/dev/null 2>&1; then /etc/init.d/fastfi start >/dev/null 2>&1; logger -t fastfi-watchdog 'Self-healed core-loop.sh and restarted fastfi service'; fi")
