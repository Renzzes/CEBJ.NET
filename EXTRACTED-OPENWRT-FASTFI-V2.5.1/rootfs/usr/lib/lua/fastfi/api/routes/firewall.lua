
local config = require("fastfi.config")
local security = require("fastfi.security")
local file_util = require("fastfi.util.file")
local M = {}


function M.firewall_status(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local result = {
        status = "ok",
        rules_count = 0,
        dropped_packets = 0,
        rate_limiting = false,
        nat_active = false
    }
    
    
    local nft_output = file_util.execute("nft list ruleset 2>/dev/null | grep -c 'FastFi' || echo 0")
    result.rules_count = tonumber(nft_output) or 0
    
    
    local nat_check = file_util.execute("iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -c 'MASQUERADE.*10.0.0.0/24' || echo 0")
    result.nat_active = (tonumber(nat_check) or 0) > 0
    
    
    local rl_check = file_util.execute("iptables -t filter -L FORWARD -n -v 2>/dev/null | grep -c 'recent.*HOTSPOT_CONN' || echo 0")
    result.rate_limiting = (tonumber(rl_check) or 0) > 0
    
    
    local drops = file_util.execute("logread 2>/dev/null | grep -c 'FastFi-DROPPED' || echo 0")
    result.dropped_packets = tonumber(drops) or 0
    
    return result
end


function M.apply_firewall_enhanced(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local script_path = "/usr/libexec/fastfi/security/firewall-enhanced.sh"
    
    
    if not file_util.exists(script_path) then
        return { status = "error", message = "Enhanced firewall script not found" }
    end
    
    
    os.execute("chmod +x " .. script_path)
    
    
    local output = file_util.execute(script_path .. " 2>&1")
    
    return { 
        status = "ok", 
        message = "Enhanced firewall rules applied successfully",
        output = output
    }
end


function M.reset_firewall(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    
    os.execute("(/etc/init.d/firewall reload >/dev/null 2>&1; sleep 3; lua /usr/libexec/fastfi/core/sync-sessions.lua >/dev/null 2>&1) &")
    
    return { 
        status = "ok", 
        message = "Firewall reset to default configuration"
    }
end


function M.rate_limit_stats(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local stats = {
        hotspot_connections = {},
        ssh_attempts = {},
        dns_queries = {}
    }
    
    
    local conntrack = file_util.execute("(cat /proc/net/nf_conntrack 2>/dev/null | head -20) 2>/dev/null")
    
    
    local total_conns = file_util.execute("wc -l < /proc/net/nf_conntrack 2>/dev/null || echo 0")
    stats.total_connections = tonumber(total_conns) or 0
    
    return { status = "ok", data = stats }
end

return M
