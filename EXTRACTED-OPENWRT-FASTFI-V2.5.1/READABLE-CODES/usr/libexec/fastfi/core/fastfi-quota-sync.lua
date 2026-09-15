#!/usr/bin/env lua



local lfs = require("lfs")
local json = require("cjson.safe")
local sqlite = require("fastfi.db.sqlite")
local session_db = require("fastfi.db.sessions")
local config = require("fastfi.config")

local SYNC_INTERVAL = 30
local DB_FLUSH_INTERVAL = 300 
local last_db_flush = os.time()



local memory_consumed = {}

local last_nft_counter = {}

local function log_msg(msg)
    os.execute(string.format("logger -t fastfi-quota '%s'", msg:gsub("'", "")))
end

local function flush_to_db()
    for mac, bytes in pairs(memory_consumed) do
        if bytes > 0 then
            local add_mb = math.floor(bytes / (1024 * 1024))
            if add_mb > 0 then
                
                sqlite.execute(config.SESSIONS_DB, string.format(
                    "UPDATE sessions SET data_consumed_mb = data_consumed_mb + %d WHERE lower(trim(mac_address)) = '%s'",
                    add_mb, sqlite.quote(mac)
                ))
                
                memory_consumed[mac] = bytes - (add_mb * 1024 * 1024)
            end
        end
    end
end

log_msg("Starting quota sync daemon...")

while true do
    local now = os.time()
    
    
    local f = io.popen("nft -j list chain inet fastfi_shaper accounting 2>/dev/null")
    if f then
        local out = f:read("*a")
        f:close()
        
        local data = json.decode(out)
        if data and data.nftables then
            local current_nft_counter = {}
            
            for _, item in ipairs(data.nftables) do
                if item.rule and item.rule.expr then
                    local mac = nil
                    local bytes = 0
                    
                    
                    for _, expr in ipairs(item.rule.expr) do
                        if expr.counter then
                            bytes = expr.counter.bytes or 0
                        elseif expr.match and expr.match.op == "==" then
                            
                        end
                    end
                    
                    
                    
                    if item.rule.comment then
                        local m = item.rule.comment:match("^mac:([%a%d:]+):")
                        if m then mac = m:lower() end
                    end
                    
                    if mac and bytes > 0 then
                        current_nft_counter[mac] = (current_nft_counter[mac] or 0) + bytes
                    end
                end
            end
            
            
            for mac, total_bytes in pairs(current_nft_counter) do
                local last_bytes = last_nft_counter[mac] or 0
                if total_bytes >= last_bytes then
                    local delta = total_bytes - last_bytes
                    memory_consumed[mac] = (memory_consumed[mac] or 0) + delta
                else
                    
                    memory_consumed[mac] = (memory_consumed[mac] or 0) + total_bytes
                end
                last_nft_counter[mac] = total_bytes
            end
            
            
            for mac in pairs(last_nft_counter) do
                if not current_nft_counter[mac] then
                    last_nft_counter[mac] = nil
                end
            end
        end
    end
    
    
    local sessions = session_db.get_active_sessions()
    for _, s in ipairs(sessions) do
        if s.data_limit_mb and s.data_limit_mb > 0 then
            local mem_bytes = memory_consumed[s.mac:lower()] or 0
            local mem_mb = math.floor(mem_bytes / (1024 * 1024))
            local total_consumed = (s.data_consumed_mb or 0) + mem_mb
            
            if total_consumed >= s.data_limit_mb then
                log_msg(string.format("Data limit reached for %s (%d MB / %d MB). Deauthenticating.", s.mac, total_consumed, s.data_limit_mb))
                
                sqlite.execute(config.SESSIONS_DB, string.format(
                    "UPDATE sessions SET data_consumed_mb = %d, active = 0 WHERE lower(trim(mac_address)) = '%s'",
                    total_consumed, sqlite.quote(s.mac:lower())
                ))
                memory_consumed[s.mac:lower()] = 0 
                
                
                os.execute(string.format("(ndsctl deauth %s >/dev/null 2>&1; /usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1) &", s.mac))
            end
        end
    end
    
    
    if now - last_db_flush >= DB_FLUSH_INTERVAL then
        flush_to_db()
        last_db_flush = now
    end
    
    os.execute("sleep " .. SYNC_INTERVAL)
end
