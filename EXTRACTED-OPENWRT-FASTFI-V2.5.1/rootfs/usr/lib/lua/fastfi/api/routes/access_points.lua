local ap_db = require("fastfi.db.access_points")
local activity = require("fastfi.db.activity")
local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")
local file_util = require("fastfi.util.file")
local M = {}

function M.list_access_points(params)
    ap_db.refresh_statuses()
    return { status = "ok", data = ap_db.list() }
end

function M.save_access_point(params)
    local ok, id_or_err = ap_db.save(params)
    if not ok then return { status = "error", message = id_or_err } end
    activity.add("info", "Access Point saved", tostring(params.name or id_or_err))
    return { status = "ok", id = id_or_err }
end

function M.delete_access_point(params)
    local ok, err = ap_db.delete(params.id)
    if not ok then return { status = "error", message = err } end
    return { status = "ok" }
end

function M.bind_esp_to_ap(params)
    local ok, err = ap_db.bind_esp(params.esp_id, params.ap_id)
    if not ok then return { status = "error", message = err } end
    activity.add("info", "ESP bound to AP", "ESP " .. tostring(params.esp_id) .. " → AP " .. tostring(params.ap_id))
    return { status = "ok" }
end

local function read_mem_cpu()
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
    local mem_pct = math.floor(((memtotal - memavail) / memtotal) * 100)
    local cpu = 0
    local top_f = io.popen("top -n1 2>/dev/null")
    if top_f then
        local out = top_f:read("*a") or ""
        top_f:close()
        local idle = out:match("CPU:.-([%d%.]+)%%%s+idle")
        if idle then cpu = math.floor(100 - tonumber(idle)) end
    end
    local uf = io.open("/proc/uptime", "r")
    local uptime = uf and tonumber((uf:read("*a") or ""):match("^(%S+)")) or 0
    if uf then uf:close() end
    return mem_pct, cpu, uptime, memtotal, memavail
end

local function storage_slices()
    local total_kb, used_kb = 0, 0
    local df = io.popen("df -k /overlay 2>/dev/null | tail -1")
    if not df then df = io.popen("df -k / 2>/dev/null | tail -1") end
    if df then
        local line = df:read("*a") or ""
        df:close()
        local total, used = line:match("%S+%s+(%d+)%s+(%d+)")
        total_kb = tonumber(total) or 0
        used_kb = tonumber(used) or 0
    end
    local total_mb = total_kb / 1024
    local used_mb = used_kb / 1024
    local data_mb = 0
    local du = io.popen("du -sk /www/data 2>/dev/null")
    if du then
        data_mb = (tonumber((du:read("*a") or ""):match("(%d+)")) or 0) / 1024
        du:close()
    end
    local admin_mb = math.max(0, used_mb - data_mb) * 0.35
    local other_mb = math.max(0, used_mb - data_mb - admin_mb)
    return {
        storageTotalMb = math.floor(total_mb * 10) / 10,
        storageLive = true,
        temperature = nil,
        storageSlices = {
            { label = "Admin & portal", mb = math.floor(admin_mb * 10) / 10, color = "#7F2D37" },
            { label = "Data / DBs", mb = math.floor(data_mb * 10) / 10, color = "#2563eb" },
            { label = "System / other", mb = math.floor(other_mb * 10) / 10, color = "#64748b" },
        }
    }
end

local function wan_up()
    local f = io.popen("cat /sys/class/net/wan/operstate 2>/dev/null || cat /sys/class/net/eth0.1/operstate 2>/dev/null || cat /sys/class/net/eth0/operstate 2>/dev/null")
    if not f then return false end
    local s = file_util.trim(f:read("*a") or "")
    f:close()
    return s == "up"
end

function M.dashboard_overview(params)
    local rows, tot = ap_db.dashboard_matrix()
    local mem_pct, cpu, uptime = read_mem_cpu()
    local storage = storage_slices()
    local version = "2.5.1"
    local vf = io.open("/www/version.txt", "r")
    if vf then version = file_util.trim(vf:read("*a") or version); vf:close() end
    local openwrt = "OpenWrt"
    local orf = io.open("/etc/openwrt_release", "r")
    if orf then
        local txt = orf:read("*a") or ""
        orf:close()
        openwrt = txt:match("DISTRIB_DESCRIPTION='([^']+)'") or txt:match('DISTRIB_DESCRIPTION="([^"]+)"') or openwrt
    end

    local now = os.time()
    local recent = {}
    local srows = sqlite.query_list(config.SESSIONS_DB, string.format([[
        SELECT mac_address, session_end, remaining, active, paused, sub_vendo_id
        FROM sessions ORDER BY updated_at DESC LIMIT 8;
    ]])) or {}
    -- updated_at may not sort if missing — fallback
    if #srows == 0 then
        srows = sqlite.query_list(config.SESSIONS_DB,
            "SELECT mac_address, session_end, remaining, active, paused, sub_vendo_id FROM sessions LIMIT 8;") or {}
    end
    for _, s in ipairs(srows) do
        local rem = tonumber(s[3]) or 0
        local end_ts = tonumber(s[2]) or 0
        if rem <= 0 and end_ts > now then rem = end_ts - now end
        local st = "expired"
        if tonumber(s[5]) == 1 then st = "paused"
        elseif tonumber(s[4]) == 1 and rem > 0 then st = "active" end
        table.insert(recent, {
            mac = s[1], remaining = rem, status = st, sub_vendo_id = tonumber(s[6]) or 0
        })
    end

    local connected_users = {}
    local ok_dev, devices_db = pcall(require, "fastfi.db.devices")
    if ok_dev then
        for _, d in ipairs(devices_db.collect_devices()) do
            if d.auth == "authenticated" and d.status ~= "blocked" then
                table.insert(connected_users, d)
            end
        end
    end

    local aps = ap_db.list()
    local ap_online = 0
    for _, a in ipairs(aps) do
        if a.status == "online" and a.enabled == 1 then ap_online = ap_online + 1 end
    end

    local internet = wan_up() and "online" or "offline"
    local t = os.date("*t")
    local week_ago = now - 7 * 86400
    local sales_week = sqlite.query_row(config.SESSIONS_DB, string.format(
        "SELECT COALESCE(SUM(amount),0) FROM sales WHERE created_at>=%d;", week_ago))
    local month_start = os.time({ year = t.year, month = t.month, day = 1, hour = 0, min = 0, sec = 0 })
    local sales_month = sqlite.query_row(config.SESSIONS_DB, string.format(
        "SELECT COALESCE(SUM(amount),0) FROM sales WHERE created_at>=%d;", month_start))

    return {
        status = "ok",
        kpis = {
            sales_today = tot.sales,
            sales_week = tonumber(sales_week and sales_week[1]) or 0,
            sales_month = tonumber(sales_month and sales_month[1]) or 0,
            connected = tot.connected,
            sessions = tot.sessions,
            waiting = tot.waiting
        },
        per_ap_esp = rows,
        totals = tot,
        network_status = {
            internet = internet,
            ruijie = "online",
            wifi = (ap_online > 0) and "online" or "degraded",
            access_points = string.format("%d/%d online", ap_online, #aps),
            latency_ms = nil,
            packet_loss = nil
        },
        ruijie = {
            model = "RG-EW1200G Pro",
            firmware = openwrt,
            fastfi_version = version,
            uptime = uptime,
            connection = "connected",
            cpu = cpu,
            memory = mem_pct,
            storageTotalMb = storage.storageTotalMb,
            storageLive = storage.storageLive,
            temperature = storage.temperature,
            storageSlices = storage.storageSlices
        },
        recent_sessions = recent,
        connected_users = connected_users,
        access_points = aps
    }
end

return M
