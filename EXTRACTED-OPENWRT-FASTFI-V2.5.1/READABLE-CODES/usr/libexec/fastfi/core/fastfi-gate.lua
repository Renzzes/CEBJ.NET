#!/usr/bin/env lua



























local ok_sess, session_db = pcall(require, "fastfi.db.sessions")
local ok_sv, subvendo = pcall(require, "fastfi.db.subvendo")
local file_util = require("fastfi.util.file")

local function sh(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then return "" end
    local s = f:read("*a") or ""
    f:close()
    return s
end
local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end
local function uci_get(k) return trim(sh("uci -q get " .. k)) end
local function is_vlan(v)
    v = tonumber(v)
    return v and v >= 1 and v <= 4094
end


local function base_dev()
    local wan = uci_get("network.wan.device")
    local wan_base = wan ~= "" and (wan:match("^([^.]+)") or wan) or ""
    local p = io.popen("ls /sys/class/net/ 2>/dev/null")
    if p then
        for d in p:lines() do
            if d ~= "lo" and not d:match("^br%-") and not d:match("^tun")
               and not d:match("^wlan") and not d:match("^wl") and not d:match("%.[0-9]+")
               and d:match("^eth") and d ~= wan_base then
                p:close(); return d
            end
        end
        p:close()
    end
    if wan_base:match("^eth") then return wan_base end
    return "eth0"
end


local function ip_from_mac(target_mac)
    target_mac = (target_mac or ""):lower()
    if target_mac == "" then return nil end
    local f = io.open("/proc/net/arp", "r")
    if not f then return nil end
    f:read("*l")  
    for line in f:lines() do
        local ip, mac = line:match("^([%d%.]+)%s+0x%d+%s+0x%d+%s+([%a%d:]+)%s+")
        if mac and mac:lower() == target_mac then
            f:close(); return ip
        end
    end
    f:close()
    return nil
end


local function gated_interfaces()
    local dev = base_dev()
    local out = {}
    if not (ok_sv and subvendo) then return out end
    for _, sv in ipairs(subvendo.list_enabled()) do
        if sv.is_default ~= 1 and is_vlan(sv.vlan_id) then
            table.insert(out, {
                ifname = dev .. "." .. tostring(sv.vlan_id),
                vid = tonumber(sv.vlan_id),
                sv_id = sv.id,
            })
        end
    end
    return out
end

local ifaces = gated_interfaces()
if #ifaces == 0 then
    
    
    os.execute("nft delete table inet fastfi_captive 2>/dev/null")
    os.execute("logger -t fastfi-gate 'No sub-vendo interfaces; captive gate idle'")
    return
end



local authed = {}
local total_authed = 0
if ok_sess and session_db then
    local sessions = session_db.get_active_sessions()
    local now = os.time()
    for _, s in ipairs(sessions) do
        
        
        
        if ok_sv and subvendo and s.active == 1 and s.paused == 0
           and s.session_end > now and s.sub_vendo_id then
            local sv = subvendo.get(s.sub_vendo_id)
            if sv and sv.is_default ~= 1 and is_vlan(sv.vlan_id) then
                local ip = ip_from_mac(s.mac)
                if ip then
                    local vid = tonumber(sv.vlan_id)
                    authed[vid] = authed[vid] or {}
                    table.insert(authed[vid], ip)
                    total_authed = total_authed + 1
                end
            end
        end
    end
else
    os.execute("logger -t fastfi-gate 'sessions module unavailable; gate built with empty authed sets'")
end



local lines = {}
local function L(s) table.insert(lines, s) end
L("table inet fastfi_captive {")
L("    chain dstnat { type nat hook prerouting priority dstnat; policy accept; }")
L("    chain gate { type filter hook forward priority mangle; policy accept; }")
for _, ifc in ipairs(ifaces) do
    local setname = "authed_" .. tostring(ifc.vid)
    
    local elems = ""
    local ips = authed[ifc.vid]
    if ips and #ips > 0 then
        elems = " elements = { " .. table.concat(ips, ", ") .. " }"
    end
    L(string.format("    set %s { type ipv4_addr; flags timeout; timeout 1d;%s }",
        setname, elems))
    
    L(string.format(
        "    chain dstnat { iifname \"%s\" tcp dport 80 ip saddr != @%s dnat to 10.0.0.1:80 }",
        ifc.ifname, setname))
    
    L(string.format(
        "    chain gate { iifname \"%s\" ip saddr != @%s drop }",
        ifc.ifname, setname))
end
L("}")
local block = table.concat(lines, "\n")




local table_exists = sh("nft list table inet fastfi_captive 2>/dev/null") ~= ""
local script = (table_exists and "flush table inet fastfi_captive\n" or "") .. block

local tmp = "/tmp/fastfi-gate.nft"
file_util.write(tmp, script)
os.execute("nft -f " .. tmp .. " >/dev/null 2>&1")
os.execute("rm -f " .. tmp .. " 2>/dev/null")

os.execute(string.format(
    "logger -t fastfi-gate 'Captive gate rebuilt: %d interface(s), %d authed client(s)'",
    #ifaces, total_authed))