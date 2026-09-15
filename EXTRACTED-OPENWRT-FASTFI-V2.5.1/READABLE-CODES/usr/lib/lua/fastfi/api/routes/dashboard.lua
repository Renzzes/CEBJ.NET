
local session_db = require("fastfi.db.sessions")
local config_db = require("fastfi.db.config")
local sqlite = require("fastfi.db.sqlite")
local config = require("fastfi.config")
local file_util = require("fastfi.util.file")
local M = {}

function M.system_status(params)
    
    local memtotal, memavail = 1, 0
    local mf = io.open("/proc/meminfo", "r")
    if mf then
        for line in mf:lines() do
            local t = line:match("^MemTotal:%s*(%d+)")
            local a = line:match("^MemAvailable:%s*(%d+)")
            if t then memtotal = tonumber(t) end
            if a then memavail = tonumber(a) end
        end
        mf:close()
    end
    
    local used = memtotal - memavail
    local r_per = math.floor((used / memtotal) * 100)
    
    local uf = io.open("/proc/uptime", "r")
    local uptime_sec = uf and tonumber(uf:read("*a"):match("^(%S+)")) or 0
    if uf then uf:close() end
    
    local lf = io.open("/proc/loadavg", "r")
    local load = lf and lf:read("*a"):match("^(%S+)") or "0.00"
    if lf then lf:close() end
    
    
    local cpu_usage = "N/A"
    local top_f = io.popen("top -n1 2>/dev/null")
    if top_f then
        local top_out = top_f:read("*a")
        top_f:close()
        local idle = top_out:match("CPU:.-([%d%.]+)%%%s+idle")
        if idle then
            cpu_usage = tostring(math.floor(100 - tonumber(idle)))
        end
    end
    
    
    local hostname = "FastFi Router"
    if file_util.exists("/tmp/sysinfo/model") then
        hostname = file_util.trim(file_util.read("/tmp/sysinfo/model") or "FastFi Router")
    elseif file_util.exists("/tmp/sysinfo/board_name") then
        hostname = file_util.trim(file_util.read("/tmp/sysinfo/board_name") or "FastFi Router")
    else
        local hf = io.popen("uname -n 2>/dev/null")
        if hf then
            hostname = file_util.trim(hf:read("*a") or "FastFi Router")
            hf:close()
        end
    end

    
    local storage_total, storage_used, storage_percent = "0M", "0M", 0
    local df_out = io.popen("df -h / 2>/dev/null | tail -1")
    if df_out then
        local df_line = file_util.trim(df_out:read("*a") or "")
        df_out:close()
        local size, used_s, avail, pct = df_line:match("(%S+)%s+(%S+)%s+(%S+)%s+(%d+)%%")
        if size and used_s and pct then
            storage_total = size
            storage_used = used_s
            storage_percent = tonumber(pct)
        end
    end

    
    local rx_bytes, tx_bytes = 0, 0
    local wan_iface = file_util.trim(file_util.execute("ip route show default 2>/dev/null | awk 'NR==1 {print $5}'"))
    if not wan_iface or wan_iface == "" then wan_iface = "wan" end

    local net_dev = file_util.read("/proc/net/dev")
    if net_dev then
        for line in net_dev:gmatch("[^\n]+") do
            if line:match("^%s*" .. wan_iface .. ":") then
                local stats = line:match(":([%d%s]+)")
                if stats then
                    local fields = {}
                    for num in stats:gmatch("%d+") do
                        table.insert(fields, tonumber(num))
                    end
                    if #fields >= 10 then
                        rx_bytes = fields[1] or 0
                        tx_bytes = fields[9] or 0
                    end
                end
                break
            end
        end
    end

    
    local db = config.SESSIONS_DB
    local now = os.time()
    
    
    local h = tonumber(os.date("%H")) or 0
    local m = tonumber(os.date("%M")) or 0
    local s = tonumber(os.date("%S")) or 0
    local seconds_since_midnight = h * 3600 + m * 60 + s
    local day_start = now - seconds_since_midnight
    
    
    local d = tonumber(os.date("%d")) or 1
    local seconds_since_month_start = (d - 1) * 86400 + seconds_since_midnight
    local month_start = now - seconds_since_month_start

    local row_today = sqlite.query_row(db, string.format("SELECT COALESCE(SUM(amount),0) FROM sales WHERE created_at >= %d;", day_start))
    local sales_today = tonumber(row_today and row_today[1]) or 0
    
    local row_month = sqlite.query_row(db, string.format("SELECT COALESCE(SUM(amount),0) FROM sales WHERE created_at >= %d;", month_start))
    local sales_month = tonumber(row_month and row_month[1]) or 0

    
    local sessions = session_db.get_active_sessions()
    local c_live = 0
    local c_tot = #sessions
    for _, sess in ipairs(sessions) do
        if sess.session_end > now then
            c_live = c_live + 1
        end
    end
    
    
    local license_info = config_db.get_license_info()
    local lic_valid = license_info.license_valid
    if lic_valid == nil then lic_valid = true end 

    
    local p_status = file_util.execute("pgrep uhttpd >/dev/null 2>&1 && echo 'running' || echo 'stopped'")
    local n_status = file_util.execute("ndsctl status >/dev/null 2>&1 && echo 'running' || echo 'stopped'")
    local f_status = file_util.execute("(nft list chain inet fw4 forward_hotspot >/dev/null 2>&1 || iptables -t nat -L POSTROUTING 2>/dev/null | grep -q '10.0.0.0/24') && echo 'active' || echo 'inactive'")

    return {
        hostname = hostname,
        storage_total = storage_total,
        storage_used = storage_used,
        storage_percent = storage_percent,
        rx_bytes = rx_bytes,
        tx_bytes = tx_bytes,
        sales_today = sales_today,
        sales_month = sales_month,
        uptime = uptime_sec,
        ram_percent = r_per,
        ram_used = math.floor(used / 1024),
        ram_total = math.floor(memtotal / 1024),
        cpu_temp = "No Sensor",
        cpu_usage = cpu_usage,
        load = load,
        current_clients = c_live,
        total_clients = c_tot,
        license_key = license_info.license_key,
        license_status = license_info.license_status,
        
        portal_status = file_util.trim(p_status),
        nds_status = file_util.trim(n_status),
        firewall_status = file_util.trim(f_status),
        license_valid = lic_valid
    }
end

return M
