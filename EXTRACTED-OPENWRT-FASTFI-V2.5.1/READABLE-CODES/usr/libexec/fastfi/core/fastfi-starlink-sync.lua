#!/usr/bin/env lua















local ok_sh, shield = pcall(require, "fastfi.db.shield")
local file_util = require("fastfi.util.file")

local function sh(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then return "" end
    local s = f:read("*a") or ""
    f:close()
    return s
end
local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local CACHE_FILE = "/etc/fastfi/security/starlink_ips.cache"
local LAST_SYNC  = "/etc/fastfi/security/.last_sync"
local MAX_IPS    = 500
local UPSTREAM   = "1.1.1.1"



local function table_exists()
    return sh("nft list table inet fastfi_shield") ~= ""
end


local function resolve(domain)
    local ips = {}
    local out = sh(string.format("nslookup %s %s", domain, UPSTREAM))
    
    
    local seen_server = false
    for ip in out:gmatch("Address%s*1?:%s*([%d%.]+)") do
        if not seen_server then
            seen_server = true 
        else
            table.insert(ips, ip)
        end
    end
    
    local seen, out_ips = {}, {}
    for _, ip in ipairs(ips) do
        if ip:match("^%d+%.%d+%.%d+%.%d+$") and not seen[ip] then
            seen[ip] = true
            table.insert(out_ips, ip)
        end
    end
    return out_ips
end

if not ok_sh or not shield then
    os.execute("logger -t fastfi-starlink-sync 'shield db module unavailable; aborting'")
    return
end

local cfg = shield.read_config()
local starlink_on = cfg.starlink_enabled == 1


os.execute("mkdir -p /etc/fastfi/security 2>/dev/null")

if not starlink_on or not table_exists() then
    
    if table_exists() then
        os.execute("nft flush set inet fastfi_shield fastfi_starlink_ips 2>/dev/null")
    end
    file_util.write(LAST_SYNC, os.time() .. "\n")
    os.execute("logger -t fastfi-starlink-sync 'Starlink off (or table absent); set flushed'")
    return
end

local domains = shield.read_list("starlink_domains")
local all_ips, seen = {}, {}
for _, d in ipairs(domains) do
    for _, ip in ipairs(resolve(d)) do
        if not seen[ip] then
            seen[ip] = true
            table.insert(all_ips, ip)
            if #all_ips >= MAX_IPS then break end
        end
    end
    if #all_ips >= MAX_IPS then break end
end


local lines = {}
local function L(s) table.insert(lines, s) end
L("flush set inet fastfi_shield fastfi_starlink_ips")
if #all_ips > 0 then
    
    
    for i = 1, #all_ips, 64 do
        local chunk = {}
        for j = i, math.min(i + 63, #all_ips) do
            table.insert(chunk, all_ips[j])
        end
        L(string.format("add element inet fastfi_shield fastfi_starlink_ips { %s }",
            table.concat(chunk, ", ")))
    end
end
local script = table.concat(lines, "\n")

local tmp = "/tmp/fastfi-starlink-sync.nft"
file_util.write(tmp, script)
os.execute("nft -f " .. tmp .. " >/dev/null 2>&1")
os.execute("rm -f " .. tmp .. " 2>/dev/null")


file_util.write(CACHE_FILE, table.concat(all_ips, "\n") .. "\n")
file_util.write(LAST_SYNC, os.time() .. "\n")

os.execute(string.format(
    "logger -t fastfi-starlink-sync 'Resolved %d Starlink IP(s) across %d domain(s)'",
    #all_ips, #domains))