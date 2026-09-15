#!/usr/bin/env lua



local file_util = require("fastfi.util.file")
local session_db = require("fastfi.db.sessions")
local ok_sv, subvendo = pcall(require, "fastfi.db.subvendo")


local hotspot_iface = "br-lan"

local speed_content = file_util.read("/etc/fastfi/client_speed") or "5|5"
local dl_mbps, ul_mbps = speed_content:match("^(%d+)|(%d+)$")
dl_mbps = tonumber(dl_mbps) or 0
ul_mbps = tonumber(ul_mbps) or 0



local function ex(cmd)
    os.execute(cmd .. " >/dev/null 2>&1")
end


local function get_ip_from_mac(target_mac)
    target_mac = target_mac:lower()
    local f = io.open("/proc/net/arp", "r")
    if not f then return nil end
    
    
    f:read("*l")
    
    for line in f:lines() do
        
        local ip, mac = line:match("^([%d%.]+)%s+0x%d+%s+0x%d+%s+([%a%d:]+)%s+.*" .. hotspot_iface:gsub("%-", "%%-"))
        if not mac then
            
            ip, mac = line:match("^([%d%.]+)%s+0x%d+%s+0x%d+%s+([%a%d:]+)%s+")
        end
        
        if mac and mac:lower() == target_mac then
            f:close()
            return ip
        end
    end
    f:close()
    
    
    local f_nds = io.popen("ndsctl json 2>/dev/null")
    if f_nds then
        local content = f_nds:read("*a")
        f_nds:close()
        
        local ip = content:match('"' .. target_mac .. '".-ip":%s*"([%d%.]+)"')
        if ip then return ip end
    end

    
    
    
    
    
    local fl = io.open("/tmp/dhcp.leases", "r")
    if fl then
        for line in fl:lines() do
            
            local lmac, lip = line:match("^%S+%s+(%S+)%s+(%S+)")
            if lmac and lmac:lower() == target_mac then
                fl:close()
                return lip
            end
        end
        fl:close()
    end

    return nil
end


ex("tc qdisc del dev " .. hotspot_iface .. " root")
ex("nft delete table inet fastfi_shaper")


os.execute("sleep 0.5")


local sessions = session_db.get_active_sessions()
local now = os.time()







local sv_speed = {}
local sv_default = {}
if ok_sv and subvendo then
    for _, sv in ipairs(subvendo.list_all()) do
        sv_speed[sv.id] = { down = tonumber(sv.speed_down) or 0,
                            up   = tonumber(sv.speed_up)   or 0 }
        sv_default[sv.id] = (sv.is_default == 1)
    end
end


local has_any_session_limits = false
for _, s in ipairs(sessions) do
    if s.active == 1 and s.paused == 0 and s.session_end > now then
        local z = sv_speed[s.sub_vendo_id or 0]
        local zdl = z and z.down or 0
        local zul = z and z.up or 0
        if (s.dl_limit and s.dl_limit > 0) or (s.ul_limit and s.ul_limit > 0)
           or (s.data_limit_mb and s.data_limit_mb > 0) or zdl > 0 or zul > 0 then
            has_any_session_limits = true
            break
        end
    end
end

if dl_mbps <= 0 and ul_mbps <= 0 and not has_any_session_limits then
    os.execute("logger -t fastfi-shaper 'Speed limits disabled (no active limits)'")
    return
end


ex("nft add table inet fastfi_shaper")
ex("nft add chain inet fastfi_shaper upload '{ type filter hook forward priority 0 ; policy accept ; }'")
ex("nft add chain inet fastfi_shaper accounting '{ type filter hook forward priority 1 ; policy accept ; }'")


ex("tc qdisc add dev " .. hotspot_iface .. " root handle 1: htb default 1000")
ex("tc class add dev " .. hotspot_iface .. " parent 1: classid 1:1 htb rate 1000mbit ceil 1000mbit")
ex("tc class add dev " .. hotspot_iface .. " parent 1:1 classid 1:1000 htb rate 1000mbit ceil 1000mbit")





ex("tc qdisc add dev " .. hotspot_iface .. " parent 1:1000 handle 1000: fq_codel")

local class_id = 10
local applied_count = 0

for _, s in ipairs(sessions) do
    if s.active == 1 and s.paused == 0 and s.session_end > now then
        local mac = s.mac:lower()
        local ip = get_ip_from_mac(mac)

        
        local z = sv_speed[s.sub_vendo_id or 0]
        local zdl = z and z.down or 0
        local zul = z and z.up or 0
        
        
        
        local is_subvendo_client = (sv_default[s.sub_vendo_id or 0] == false)

        
        local s_dl_mbps = (s.dl_limit and s.dl_limit > 0) and s.dl_limit
                       or (zdl > 0 and zdl)
                       or (dl_mbps > 0 and dl_mbps or nil)
        local s_ul_mbps = (s.ul_limit and s.ul_limit > 0) and s.ul_limit
                       or (zul > 0 and zul)
                       or (ul_mbps > 0 and ul_mbps or nil)

        if ip then
            
            
            if s_dl_mbps then
                if is_subvendo_client then
                    local s_dl_kbytes = math.floor(s_dl_mbps * 125 * 1.05)
                    ex(string.format("nft add rule inet fastfi_shaper upload ip daddr %s limit rate over %d kbytes/second drop", ip, s_dl_kbytes))
                else
                    local s_dl_kbit = math.floor(s_dl_mbps * 1100) .. "kbit"
                    ex(string.format("tc class add dev " .. hotspot_iface .. " parent 1:1 classid 1:%d htb rate %s ceil %s burst 64k cburst 64k", class_id, s_dl_kbit, s_dl_kbit))
                    ex(string.format("tc qdisc add dev " .. hotspot_iface .. " parent 1:%d handle %d: fq_codel", class_id, class_id))
                    ex(string.format("tc filter add dev " .. hotspot_iface .. " protocol ip parent 1:0 u32 match ip dst %s flowid 1:%d", ip, class_id))
                end
            end

            
            if s_ul_mbps then
                local s_ul_kbytes = math.floor(s_ul_mbps * 125 * 1.05)
                ex(string.format("nft add rule inet fastfi_shaper upload ip saddr %s limit rate over %d kbytes/second drop", ip, s_ul_kbytes))
            end

            
            
            ex(string.format("nft add rule inet fastfi_shaper accounting ip saddr %s counter comment \\\"mac:%s:up\\\"", ip, mac))
            ex(string.format("nft add rule inet fastfi_shaper accounting ip daddr %s counter comment \\\"mac:%s:down\\\"", ip, mac))

            applied_count = applied_count + 1
            class_id = class_id + 1
        else
            os.execute(string.format("logger -t fastfi-shaper 'WARNING: Could not resolve IP for %s - shaping skipped'", mac))
        end
    end
end

os.execute(string.format("logger -t fastfi-shaper 'Applied custom speed limits to %d active clients'", applied_count))
