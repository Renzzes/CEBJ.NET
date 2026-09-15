













local M = {}


function M.is_dsa()
    local p = io.popen("ls /sys/class/net/ 2>/dev/null")
    if p then
        for d in p:lines() do
            if d:match("^lan[0-9]+$") then p:close(); return true end
        end
        p:close()
    end
    return false
end


function M.lan_ports()
    local ports = {}
    local p = io.popen("ls /sys/class/net/ 2>/dev/null")
    if p then
        for d in p:lines() do
            if d:match("^lan[0-9]+$") then table.insert(ports, d) end
        end
        p:close()
    end
    table.sort(ports)
    return ports
end


function M.wan_port()
    if not M.is_dsa() then return nil end
    local p = io.popen("ls /sys/class/net/ 2>/dev/null")
    if p then
        for d in p:lines() do
            if d:match("^wan$") then p:close(); return "wan" end
        end
        p:close()
    end
    return "wan"
end







function M.heal_wan_device()
    if not M.is_dsa() then return false end
    local c = io.popen("uci -q get network.wan.device 2>/dev/null")
    local cur = c and c:read("*a") or ""
    if c then c:close() end
    cur = cur:gsub("%s+", "")
    if cur == "wan" then return false end
    
    
    if cur ~= "eth0" and not cur:match("^eth0%.") then return false end
    os.execute("uci set network.wan.device='wan'")
    os.execute("uci commit network 2>/dev/null")
    return true
end


local function current_br_lan_ports()
    local cur = {}
    local c = io.popen("uci -q get network.br_lan.ports 2>/dev/null")
    if c then
        for line in c:lines() do
            local v = line:gsub("%s+", "")
            if v ~= "" then cur[v] = true end
        end
        c:close()
    end
    return cur
end








function M.heal_br_lan()
    if not M.is_dsa() then return false end
    local want = M.lan_ports()
    if #want == 0 then return false end
    local cur = current_br_lan_ports()
    
    
    local broken = false
    for _, d in ipairs(want) do if not cur[d] then broken = true; break end end
    if not broken then
        for v in pairs(cur) do
            if v == "eth0" or v:match("^eth0%.") then broken = true; break end
        end
    end
    if not broken then return false end
    
    os.execute("uci -q delete network.br_lan.ports 2>/dev/null")
    for _, d in ipairs(want) do
        os.execute(string.format("uci add_list network.br_lan.ports='%s'", d))
    end
    os.execute("uci commit network 2>/dev/null")
    return true
end

return M
