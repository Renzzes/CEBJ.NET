
local config = require("fastfi.config")
local file_util = require("fastfi.util.file")
local security = require("fastfi.security")
local sqlite = require("fastfi.db.sqlite")
local M = {}

function M.get_rates(params)
    
    local pause_config = file_util.read("/etc/fastfi/pause_limit.conf") or ""
    local pause_limit = 0
    local enabled = 1
    
    for line in pause_config:gmatch("[^\n]+") do
        local key, value = line:match("^([%w_]+)=(%d+)$")
        if key == "PAUSE_LIMIT" then
            pause_limit = tonumber(value) or 0
        elseif key == "ENABLED" then
            enabled = tonumber(value) or 1
        end
    end
    
    
    local rows = sqlite.query_list(config.CONFIG_DB, "SELECT price, minutes, download_mb, upload_mb, pause_limit, validity_minutes, data_limit_mb FROM coin_rates ORDER BY price ASC;")
    local rates = {}
    
    for _, row in ipairs(rows) do
        table.insert(rates, {
            price = tonumber(row[1]) or 0,
            time = (tonumber(row[2]) or 0) * 60, 
            download_mb = tonumber(row[3]) or 0,
            upload_mb = tonumber(row[4]) or 0,
            paused_limit = tonumber(row[5]) or 0,
            validity_minutes = tonumber(row[6]) or 0,
            data_limit_mb = tonumber(row[7]) or 0
        })
    end
    
    return { status = "ok", data = rates }
end

function M.save_rates(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local rates_json = params["rates"]
    if not rates_json then
        return { status = "error", message = "Missing rates data" }
    end
    
    
    local rates = {}
    for rate_str in rates_json:gmatch("{[^}]+}") do
        local price = tonumber(rate_str:match('"price"%s*:%s*(%d+)'))
        local time = tonumber(rate_str:match('"time"%s*:%s*(%d+)'))
        local download = tonumber(rate_str:match('"download_mb"%s*:%s*([%d%.]+)')) or 0
        local upload = tonumber(rate_str:match('"upload_mb"%s*:%s*([%d%.]+)')) or 0
        local paused_limit = tonumber(rate_str:match('"paused_limit"%s*:%s*(%d+)')) or 0
        local validity_minutes = tonumber(rate_str:match('"validity_minutes"%s*:%s*(%d+)')) or 0
        local data_limit_mb = tonumber(rate_str:match('"data_limit_mb"%s*:%s*(%d+)')) or 0
        
        if price and time then
            table.insert(rates, { 
                price = price, 
                minutes = math.floor(time / 60),
                download = download,
                upload = upload,
                paused_limit = paused_limit,
                validity_minutes = validity_minutes,
                data_limit_mb = data_limit_mb
            })
        end
    end
    
    
    sqlite.execute(config.CONFIG_DB, "BEGIN TRANSACTION;")
    sqlite.execute(config.CONFIG_DB, "DELETE FROM coin_rates;")
    
    for _, rate in ipairs(rates) do
        local query = string.format(
            "INSERT INTO coin_rates (price, minutes, download_mb, upload_mb, pause_limit, validity_minutes, data_limit_mb) VALUES (%d, %d, %d, %d, %d, %d, %d);",
            rate.price, rate.minutes, rate.download, rate.upload, rate.paused_limit, rate.validity_minutes, rate.data_limit_mb
        )
        sqlite.execute(config.CONFIG_DB, query)
    end
    sqlite.execute(config.CONFIG_DB, "COMMIT;")
    
    
    local f = io.open(config.RATES_FILE, "w")
    if f then
        for i, rate in ipairs(rates) do
            f:write(string.format("rate%d_peso=%d\n", i, rate.price))
            f:write(string.format("rate%d_time=%d\n", i, rate.minutes * 60))
            f:write(string.format("rate%d_download=%d\n", i, rate.download))
            f:write(string.format("rate%d_upload=%d\n", i, rate.upload))
            f:write(string.format("rate%d_pause_limit=%d\n", i, rate.paused_limit))
            f:write(string.format("rate%d_validity=%d\n", i, rate.validity_minutes))
            f:write(string.format("rate%d_data_limit=%d\n", i, rate.data_limit_mb))
        end
        f:close()
    end
    
    return { status = "ok", message = "Rates saved to database" }
end

function M.delete_all_rates(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    sqlite.execute(config.CONFIG_DB, "DELETE FROM coin_rates;")
    
    
    local f = io.open(config.RATES_FILE, "w")
    if f then f:close() end
    
    return { status = "ok", message = "All rates deleted" }
end

function M.get_pause_limit(params)
    local pause_config = file_util.read("/etc/fastfi/pause_limit.conf") or ""
    local pause_limit = 10
    local enabled = 1
    
    for line in pause_config:gmatch("[^\n]+") do
        local key, value = line:match("^([%w_]+)=(%d+)$")
        if key == "PAUSE_LIMIT" then
            pause_limit = tonumber(value) or 10
        elseif key == "ENABLED" then
            enabled = tonumber(value) or 1
        end
    end
    
    return {
        status = "ok",
        pause_limit = pause_limit,
        enabled = enabled
    }
end

function M.set_pause_limit(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local limit = tonumber(params["limit"])
    local enabled = tonumber(params["enabled"]) or 1
    
    if not limit or limit < 0 then
        return { status = "error", message = "Invalid limit" }
    end
    
    
    local f = io.open("/etc/fastfi/pause_limit.conf", "w")
    if not f then
        return { status = "error", message = "Failed to write config" }
    end
    
    f:write(string.format("PAUSE_LIMIT=%d\n", limit))
    f:write(string.format("ENABLED=%d\n", enabled))
    f:close()
    
    return { status = "ok", message = string.format("Pause limit set to %d", limit) }
end


local AUTOPAUSE_CONF = "/etc/fastfi/autopause.conf"

function M.handle_autopause_config(params, req)
    local method = req and req.method or "GET"

    if method == "POST" then
        
        if not security.check_admin_session() then
            return { status = "error", message = "Unauthorized" }
        end

        local enabled = tonumber(params["autopause_enabled"]) or 0
        local grace = tonumber(params["grace_period"]) or 60
        local resume = tonumber(params["auto_resume"]) or 1

        
        if grace < 10 then grace = 10 end
        if grace > 600 then grace = 600 end

        local f = io.open(AUTOPAUSE_CONF, "w")
        if not f then
            return { status = "error", message = "Failed to write autopause config" }
        end

        f:write(string.format("AUTOPAUSE_ENABLED=%d\n", enabled))
        f:write(string.format("AUTOPAUSE_GRACE_PERIOD=%d\n", grace))
        f:write(string.format("AUTOPAUSE_AUTO_RESUME=%d\n", resume))
        f:close()

        return { status = "ok", message = "Auto-pause config saved" }
    else
        
        local content = file_util.read(AUTOPAUSE_CONF) or ""
        local enabled = 0
        local grace = 60
        local resume = 1

        for line in content:gmatch("[^\n]+") do
            local key, value = line:match("^([%w_]+)=(%d+)$")
            if key == "AUTOPAUSE_ENABLED" then
                enabled = tonumber(value) or 0
            elseif key == "AUTOPAUSE_GRACE_PERIOD" then
                grace = tonumber(value) or 60
            elseif key == "AUTOPAUSE_AUTO_RESUME" then
                resume = tonumber(value) or 1
            end
        end

        return {
            status = "ok",
            autopause_enabled = enabled,
            grace_period = grace,
            auto_resume = resume
        }
    end
end

return M
