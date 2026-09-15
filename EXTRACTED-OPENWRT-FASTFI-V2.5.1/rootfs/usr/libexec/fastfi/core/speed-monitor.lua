#!/usr/bin/env lua
local file_util = require("fastfi.util.file")
local json = require("fastfi.util.json")


local success, cjson = pcall(require, "cjson")
local decode = success and cjson.decode or json.decode
local encode = success and cjson.encode or json.encode

os.execute("ndsctl json > /tmp/nds_clients.json 2>/dev/null")
local current_str = file_util.read("/tmp/nds_clients.json")
if not current_str or current_str == "" then return end

local ok, current = pcall(decode, current_str)
if not ok or not current or not current.clients then return end

local prev_str = file_util.read("/tmp/nds_speed_cache.json") or "{}"
local _, prev = pcall(decode, prev_str)
prev = prev or {}

local now = os.time()
local prev_time = prev._time or now
local time_diff = now - prev_time
if time_diff <= 0 then time_diff = 1 end


local stats = {}
local new_cache = { _time = now }

for mac, c in pairs(current.clients) do
    mac = mac:lower()
    local dl_bytes = tonumber(c.downloaded) or 0
    local ul_bytes = tonumber(c.uploaded) or 0
    
    local dl_rate = 0
    local ul_rate = 0
    
    if prev[mac] then
        local p_dl = prev[mac].dl or 0
        local p_ul = prev[mac].ul or 0
        
        local diff_dl = (dl_bytes >= p_dl) and (dl_bytes - p_dl) or dl_bytes
        local diff_ul = (ul_bytes >= p_ul) and (ul_bytes - p_ul) or ul_bytes
        
        dl_rate = math.floor(diff_dl / time_diff)
        ul_rate = math.floor(diff_ul / time_diff)
        
        new_cache[mac] = { dl = dl_bytes, ul = ul_bytes }
    else
        new_cache[mac] = { dl = dl_bytes, ul = ul_bytes }
    end
    
    stats[mac] = {
        download = dl_bytes,
        upload = ul_bytes,
        dl_rate = dl_rate,
        ul_rate = ul_rate
    }
end

file_util.write("/tmp/nds_speed_cache.json", encode(new_cache))
file_util.write("/tmp/nds_stats.json", encode({ clients = stats }))










local data_macs_over_limit = {}
local mac_bytes = {}


local nft_handle = io.popen('nft list chain inet fastfi_shaper accounting 2>/dev/null')
if nft_handle then
    for line in nft_handle:lines() do
        if line:find("comment") then
            local bytes_str = line:match("bytes (%d+)")
            local mac_addr = line:match("mac:([%x:]+):")
            local direction = line:match(":(%a+)\"")
            
            if bytes_str and mac_addr and direction then
                local bytes = tonumber(bytes_str) or 0
                mac_addr = mac_addr:lower()
                
                if not mac_bytes[mac_addr] then
                    mac_bytes[mac_addr] = { up = 0, down = 0 }
                end
                
                if direction == "up" then
                    mac_bytes[mac_addr].up = bytes
                elseif direction == "down" then
                    mac_bytes[mac_addr].down = bytes
                end
            end
        end
    end
    nft_handle:close()
    
    
    for mac, data in pairs(mac_bytes) do
        local total_bytes = data.down + data.up
        local consumed_mb = math.floor(total_bytes / (1024 * 1024))
        
        if consumed_mb > 0 then
            os.execute(string.format(
                'sqlite3 /www/data/sessions.db "UPDATE sessions SET data_consumed_mb=%d WHERE lower(trim(mac_address))=\'%s\' AND active=1;" 2>/dev/null',
                consumed_mb, mac))
        end
    end
end


local data_check = io.popen('sqlite3 /www/data/sessions.db "SELECT mac_address, data_limit_mb, data_consumed_mb FROM sessions WHERE active=1 AND data_limit_mb > 0 AND data_consumed_mb >= data_limit_mb;" 2>/dev/null')
if data_check then
    for line in data_check:lines() do
        local d_mac, d_limit, d_consumed = line:match("^([^|]+)|(%d+)|(%d+)$")
        if d_mac and d_mac ~= "" then
            table.insert(data_macs_over_limit, d_mac:lower())
            os.execute(string.format("echo '%s - Data Limit Exceeded: %s (consumed %sMB / limit %sMB)' >> /tmp/session-expiry.log",
                os.date('%Y-%m-%d %H:%M:%S'), d_mac, d_consumed or "?", d_limit or "?"))
        end
    end
    data_check:close()
end

if #data_macs_over_limit > 0 then
    for _, mac in ipairs(data_macs_over_limit) do
        os.execute(string.format(
            'sqlite3 /www/data/sessions.db "UPDATE sessions SET active=0, paused=0, remaining=0 WHERE lower(trim(mac_address))=\'%s\';" 2>/dev/null', mac))
        os.execute("ndsctl deauth " .. mac .. " >/dev/null 2>&1")
        os.execute(string.format("logger -t fastfi 'Data limit exceeded for %s - session terminated'", mac))
    end
    os.execute("/usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1 &")
end



local expired_handle = io.popen(string.format('sqlite3 /www/data/sessions.db "SELECT mac_address FROM sessions WHERE active=1 AND (session_end <= %d OR (validity_end > 0 AND validity_end <= %d));" 2>/dev/null', now, now))
if expired_handle then
    local macs_to_kill = {}
    for line in expired_handle:lines() do
        local mac = line:match("^([^|]+)$")
        if mac and mac ~= "" then
            table.insert(macs_to_kill, mac:lower())
        end
    end
    expired_handle:close()

    if #macs_to_kill > 0 then
        os.execute(string.format('sqlite3 /www/data/sessions.db "UPDATE sessions SET active=0, paused=0, remaining=0 WHERE active=1 AND (session_end <= %d OR (validity_end > 0 AND validity_end <= %d));" 2>/dev/null', now, now))
        for _, mac in ipairs(macs_to_kill) do
            os.execute("ndsctl deauth " .. mac .. " >/dev/null 2>&1")
            os.execute(string.format("echo '%s - Deauthed MAC: %s (Time/Validity Exhausted via speed-monitor)' >> /tmp/session-expiry.log", os.date('%Y-%m-%d %H:%M:%S'), mac))
        end
        os.execute("/usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1 &")
    end
end
