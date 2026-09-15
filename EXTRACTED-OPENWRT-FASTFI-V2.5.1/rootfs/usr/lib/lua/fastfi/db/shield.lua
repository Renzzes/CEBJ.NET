





local config    = require("fastfi.config")
local json_util = require("fastfi.util.json")
local file_util = require("fastfi.util.file")
local M = {}

SECURITY_DIR = (config.CONFIG_DIR or "/etc/fastfi") .. "/security"
CONF_DIR     = "/etc/dnsmasq.d"







M.DEFAULT_STARLINK_DOMAINS = {
    "starlink.com",
    "dns.starlink.com",
    "gateway.starlink.com",
    "graph.starlink.com",
    "prod.starlink.com",
    "sqa.starlink.com",
    "stats.starlink.com",
    "cloud.starlink.com",
    "dishy-data.starlink.com",
    "customer.starlink.com",
}





M.DEFAULT_DOH_DOMAINS = {
    "dns.google",
    "cloudflare-dns.com",
    "mozilla.cloudflare-dns.com",
}





local DEFAULT_CONFIG = {
    starlink_enabled   = 0,
    force_dns_enabled  = 0,
    doh_block_enabled  = 0,
    quic_block_enabled = 0,
}


local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end



local function atomic_write(path, content)
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "w")
    if not f then return false, err end
    f:write(content)
    f:close()
    if os.rename(tmp, path) then return true end
    
    
    os.remove(tmp)
    return file_util.write(path, content)
end





function M.is_valid_domain(d)
    if not d or type(d) ~= "string" then return false end
    d = trim(d):lower()
    if d == "" or #d > 253 then return false end
    if d:match("^%d+%.%d+%.%d+%.%d+$") then return false end 
    if d:match("%.%.") then return false end                
    if d:match("%.+$") then return false end                 
    for label in d:gmatch("[^.]+") do
        if label == "" or #label > 63 then return false end
        
        
        
        
        if not (label:match("^[a-z0-9]$") or
                label:match("^[a-z0-9][a-z0-9-]*[a-z0-9]$")) then return false end
    end
    return true
end

local function normalize_domain(d)
    return trim(tostring(d or "")):lower():gsub("%.+$", "")
end






function M.parse_domains(raw)
    local out, seen = {}, {}
    if type(raw) ~= "string" then return out end
    for token in raw:gmatch("[^%s,;]+") do
        local d = token
        d = d:gsub("^%a+://", "")   
        d = d:gsub("^//", "")        
        d = d:gsub("^%*%.", "")      
        d = d:gsub("^@%.?", "")      
        d = d:gsub("[/?#:].*$", "")  
        d = normalize_domain(d)
        if d ~= "" and M.is_valid_domain(d) and not seen[d] then
            seen[d] = true
            table.insert(out, d)
        end
    end
    return out
end



local function clean_list(arr)
    local seen, out = {}, {}
    if type(arr) ~= "table" then return out end
    
    
    for _, v in ipairs(arr) do
        local d = normalize_domain(v)
        if M.is_valid_domain(d) and not seen[d] then
            seen[d] = true
            table.insert(out, d)
        end
    end
    return out
end



local function list_path(name) return SECURITY_DIR .. "/" .. name .. ".json" end

function M.read_list(name)
    local raw = file_util.read(list_path(name))
    if not raw or raw == "" then return {} end
    local ok, data = pcall(json_util.decode, raw)
    if not ok or type(data) ~= "table" then return {} end
    return clean_list(data)
end

function M.write_list(name, arr)
    local clean = clean_list(arr)
    os.execute("mkdir -p " .. SECURITY_DIR .. " 2>/dev/null")
    return atomic_write(list_path(name), json_util.encode(clean))
end



function M.add_domain(name, domain)
    local d = normalize_domain(domain)
    if not M.is_valid_domain(d) then return nil, "Invalid domain" end
    local list = M.read_list(name)
    for _, x in ipairs(list) do
        if x == d then return list, false end 
    end
    table.insert(list, d)
    M.write_list(name, list)
    return list, true
end

function M.remove_domain(name, domain)
    local d = normalize_domain(domain)
    local list = M.read_list(name)
    local out, changed = {}, false
    for _, x in ipairs(list) do
        if x == d then
            changed = true
        else
            table.insert(out, x)
        end
    end
    if changed then M.write_list(name, out) end
    return out, changed
end


local function config_path() return SECURITY_DIR .. "/shield_config.json" end

function M.read_config()
    local cfg = {}
    for k, v in pairs(DEFAULT_CONFIG) do cfg[k] = v end
    local raw = file_util.read(config_path())
    if raw and raw ~= "" then
        local ok, data = pcall(json_util.decode, raw)
        if ok and type(data) == "table" then
            for _, key in ipairs({"starlink_enabled", "force_dns_enabled",
                                  "doh_block_enabled", "quic_block_enabled"}) do
                if data[key] ~= nil then
                    cfg[key] = (tonumber(data[key]) == 1) and 1 or 0
                end
            end
        end
    end
    return cfg
end

function M.write_config(cfg)
    local clean = {}
    for _, key in ipairs({"starlink_enabled", "force_dns_enabled",
                          "doh_block_enabled", "quic_block_enabled"}) do
        clean[key] = (tonumber(cfg and cfg[key]) == 1) and 1 or 0
    end
    os.execute("mkdir -p " .. SECURITY_DIR .. " 2>/dev/null")
    return atomic_write(config_path(), json_util.encode(clean))
end


function M.set_toggle(key, on)
    local cfg = M.read_config()
    cfg[key] = (on == true or on == 1 or on == "1" or on == "true") and 1 or 0
    M.write_config(cfg)
    return cfg
end

function M.get_doh_domains() return M.read_list("doh_domains") end









function M.is_subdomain(child, parent)
    child, parent = normalize_domain(child), normalize_domain(parent)
    if child == "" or parent == "" then return false end
    if child == parent then return true end
    return child:sub(-(#parent + 1)) == "." .. parent
end





function M.is_overridden(domain, allowed_list)
    domain = normalize_domain(domain)
    for _, a in ipairs(allowed_list or {}) do
        if M.is_subdomain(domain, a) then return true end
    end
    return false
end





function M.overrides_needed(allowed_list, blocked_set)
    local out = {}
    for _, a in ipairs(allowed_list or {}) do
        local needs = false
        for _, b in ipairs(blocked_set or {}) do
            if M.is_subdomain(a, b) and a ~= b then needs = true; break end
        end
        if needs then table.insert(out, a) end
    end
    return out
end





function M.self_seed()
    os.execute("mkdir -p " .. SECURITY_DIR .. " " .. CONF_DIR .. " 2>/dev/null")

    
    if not file_util.exists(list_path("starlink_domains")) then
        M.write_list("starlink_domains", M.DEFAULT_STARLINK_DOMAINS)
    end
    
    if not file_util.exists(list_path("blocked_domains")) then
        M.write_list("blocked_domains", {})
    end
    if not file_util.exists(list_path("allowed_domains")) then
        M.write_list("allowed_domains", {})
    end
    
    if not file_util.exists(list_path("doh_domains")) then
        M.write_list("doh_domains", M.DEFAULT_DOH_DOMAINS)
    end
    
    if not file_util.exists(config_path()) then
        M.write_config(DEFAULT_CONFIG)
    end

    
    
    
    
    local function uci_get(k)
        local f = io.popen("uci -q get " .. k .. " 2>/dev/null")
        if not f then return "" end
        local s = f:read("*a") or ""
        f:close()
        return (s:gsub("%s+", ""))
    end
    local cur = uci_get("dhcp.@dnsmasq[0].confdir")
    if cur ~= CONF_DIR then
        
        
        os.execute("uci -q delete dhcp.@dnsmasq[0].confdir 2>/dev/null")
        os.execute(string.format("uci add_list dhcp.@dnsmasq[0].confdir='%s'", CONF_DIR))
        os.execute("uci commit dhcp 2>/dev/null")
    end
end

return M