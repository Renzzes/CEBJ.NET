






local security   = require("fastfi.security")
local file_util  = require("fastfi.util.file")
local session_db = require("fastfi.db.sessions")
local M = {}

local function sh(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then return "" end
    local s = f:read("*a") or ""
    f:close()
    return s
end
local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end
local function uci_get(k) return trim(sh("uci -q get " .. k)) end


local function sect_for_mac(mac)
    return "fastfistatic_" .. (mac or ""):lower():gsub(":", "")
end





function M.dhcp_leases(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end

    local data = file_util.read("/tmp/dhcp.leases") or ""
    local leases = {}
    for line in data:gmatch("[^\n]+") do
        local parts = {}
        for tok in line:gmatch("%S+") do table.insert(parts, tok) end
        if #parts >= 4 then
            local ts      = tonumber(parts[1]) or 0
            local mac     = parts[2]:lower()
            local ip      = parts[3]
            local host    = (parts[4] ~= "*" and parts[4] ~= "") and parts[4] or "*"
            table.insert(leases, { ts = ts, mac = mac, ip = ip, hostname = host })
        end
    end

    
    local active_macs = {}
    local ok_sess = pcall(function()
        for _, s in ipairs(session_db.get_active_sessions()) do
            active_macs[s.mac:lower()] = true
        end
    end)

    for _, l in ipairs(leases) do
        l.has_session = active_macs[l.mac] and true or false
    end

    return { status = "ok", leases = leases }
end


function M.dhcp_static_list(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local out = sh("uci -q show dhcp")
    local list = {}
    for sect in out:gmatch("dhcp%.(fastfistatic_%x+)=host") do
        local mac  = uci_get("dhcp." .. sect .. ".mac")
        local ip   = uci_get("dhcp." .. sect .. ".ip")
        local name = uci_get("dhcp." .. sect .. ".name")
        table.insert(list, { mac = mac:lower(), ip = ip, name = name })
    end
    
    table.sort(list, function(a, b) return (a.ip or "") < (b.ip or "") end)
    return { status = "ok", static = list }
end

function M.dhcp_static_add(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local mac   = trim((params["mac"] or ""):lower())
    local ip    = trim(params["ip"] or "")
    local name  = trim(params["name"] or "")

    if not security.is_valid_mac(mac) then
        return { status = "error", message = "Invalid MAC address" }
    end
    if ip ~= "" and not security.is_valid_ip(ip) then
        return { status = "error", message = "Invalid IP address" }
    end
    
    if name:match('[\'"%s`$|{}]') or #name > 40 then
        return { status = "error", message = "Invalid hostname" }
    end

    local sect = sect_for_mac(mac)
    os.execute(string.format("uci set dhcp.%s=host", sect))
    os.execute(string.format("uci set dhcp.%s.mac='%s'", sect, mac))
    if ip ~= "" then
        os.execute(string.format("uci set dhcp.%s.ip='%s'", sect, ip))
    else
        os.execute(string.format("uci -q delete dhcp.%s.ip 2>/dev/null", sect))
    end
    if name ~= "" then
        os.execute(string.format("uci set dhcp.%s.name='%s'", sect, name))
    else
        os.execute(string.format("uci -q delete dhcp.%s.name 2>/dev/null", sect))
    end
    os.execute("uci commit dhcp 2>/dev/null")
    os.execute("kill -HUP $(pgrep dnsmasq | head -1) 2>/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null")

    return { status = "ok", message = "Static lease saved." }
end

function M.dhcp_static_delete(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local mac = trim((params["mac"] or ""):lower())
    if not security.is_valid_mac(mac) then
        return { status = "error", message = "Invalid MAC address" }
    end
    local sect = sect_for_mac(mac)
    os.execute(string.format("uci -q delete dhcp.%s 2>/dev/null", sect))
    os.execute("uci commit dhcp 2>/dev/null")
    os.execute("kill -HUP $(pgrep dnsmasq | head -1) 2>/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null")
    return { status = "ok", message = "Static lease removed." }
end


local function parse_pools()
    local out = sh("uci -q show dhcp")
    
    local sects = {}
    for sect in out:gmatch("dhcp%.([%w_]+)=dhcp%s*\n") do
        table.insert(sects, sect)
    end
    local pools = {}
    for _, sect in ipairs(sects) do
        local iface = uci_get("dhcp." .. sect .. ".interface")
        table.insert(pools, {
            section    = sect,
            interface  = iface,
            start      = tonumber(uci_get("dhcp." .. sect .. ".start")) or 0,
            limit      = tonumber(uci_get("dhcp." .. sect .. ".limit")) or 0,
            leasetime  = uci_get("dhcp." .. sect .. ".leasetime"),
            is_subvendo = sect:match("^sv%d+$") ~= nil
        })
    end
    return pools
end

function M.dhcp_pools(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    return { status = "ok", pools = parse_pools() }
end

function M.dhcp_pool_save(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local sect = trim(params["section"] or "")
    
    if not sect:match("^[%w_]+$") then
        return { status = "error", message = "Invalid pool section" }
    end
    
    local stype = uci_get("dhcp." .. sect)  
    local raw = sh("uci -q show dhcp." .. sect)
    if raw == "" or not raw:match("=dhcp%s*\n") then
        return { status = "error", message = "Pool section not found" }
    end

    local start = tonumber(params["start"])
    local limit = tonumber(params["limit"])
    local leasetime = trim(params["leasetime"] or "")

    if not start or start < 1 then return { status = "error", message = "Start must be >= 1" } end
    if not limit or limit < 1 then return { status = "error", message = "Limit must be >= 1" } end
    if leasetime ~= "" and not leasetime:match("^[%dhms]+$") then
        return { status = "error", message = "Lease time format: e.g. 12h or 30m" }
    end

    os.execute(string.format("uci set dhcp.%s.start='%d'", sect, start))
    os.execute(string.format("uci set dhcp.%s.limit='%d'", sect, limit))
    if leasetime ~= "" then
        os.execute(string.format("uci set dhcp.%s.leasetime='%s'", sect, leasetime))
    end
    os.execute("uci commit dhcp 2>/dev/null")
    os.execute("kill -HUP $(pgrep dnsmasq | head -1) 2>/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null")

    local warn = ""
    if sect:match("^sv%d+$") then
        warn = " Note: this is a sub-vendo pool; the next Vendo Zones network apply will overwrite it."
    end
    return { status = "ok", message = "Pool saved." .. warn, pools = parse_pools() }
end

return M