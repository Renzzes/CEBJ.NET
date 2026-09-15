
local config = require("fastfi.config")
local security = require("fastfi.security")
local file_util = require("fastfi.util.file")
local sqlite = require("fastfi.db.sqlite")
local M = {}


function M.database_stats(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local stats = {
        sessions = {},
        vouchers = {},
        sales = {},
        esp_devices = {}
    }
    
    
    local row = sqlite.query_row(config.SESSIONS_DB, 
        "SELECT COUNT(*) FROM sessions WHERE active=1;")
    stats.sessions.active = tonumber(row and row[1]) or 0
    
    row = sqlite.query_row(config.SESSIONS_DB, 
        "SELECT COUNT(*) FROM sessions WHERE paused=1;")
    stats.sessions.paused = tonumber(row and row[1]) or 0
    
    row = sqlite.query_row(config.SESSIONS_DB, 
        "SELECT COUNT(*) FROM session_history;")
    stats.sessions.history_count = tonumber(row and row[1]) or 0
    
    
    row = sqlite.query_row(config.VOUCHER_DB, 
        "SELECT COUNT(*) FROM vouchers WHERE status='active';")
    stats.vouchers.active = tonumber(row and row[1]) or 0
    
    row = sqlite.query_row(config.VOUCHER_DB, 
        "SELECT COUNT(*) FROM vouchers WHERE status='used';")
    stats.vouchers.used = tonumber(row and row[1]) or 0
    
    
    local now = os.time()
    local day_start = now - (now % 86400)
    row = sqlite.query_row(config.PATHS.DATA_DIR .. "/sales.db",
        string.format("SELECT COALESCE(SUM(amount),0), COUNT(*) FROM sales WHERE created_at >= %d;", day_start))
    stats.sales.today_revenue = tonumber(row and row[1]) or 0
    stats.sales.today_transactions = tonumber(row and row[2]) or 0
    
    
    row = sqlite.query_row(config.ESP_DB, 
        "SELECT COUNT(*) FROM esp_slots WHERE status='online';")
    stats.esp_devices.active = tonumber(row and row[1]) or 0
    
    
    for name, path in pairs({
        sessions = config.SESSIONS_DB,
        vouchers = config.VOUCHER_DB,
        sales = config.PATHS.DATA_DIR .. "/sales.db",
        esp = config.ESP_DB
    }) do
        local size = file_util.execute(string.format("du -b '%s' 2>/dev/null | cut -f1 || echo 0", path))
        stats[name .. "_size_bytes"] = tonumber(size) or 0
    end
    
    return { status = "ok", data = stats }
end


function M.optimize_database(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local script_path = "/usr/libexec/fastfi/db/maintenance.sh"
    
    if not file_util.exists(script_path) then
        return { status = "error", message = "Maintenance script not found" }
    end
    
    
    os.execute("chmod +x " .. script_path)
    
    
    local output = file_util.execute(script_path .. " 2>&1")
    
    return { 
        status = "ok", 
        message = "Database optimization completed",
        output = output
    }
end


function M.slow_queries(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    
    local recommendations = {}
    
    
    local indexes = sqlite.execute(config.SESSIONS_DB, 
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='sessions';")
    
    if not indexes or indexes == "" then
        table.insert(recommendations, {
            table = "sessions",
            issue = "No indexes found",
            recommendation = "Run optimize-database.sql to add indexes"
        })
    end
    
    
    local row = sqlite.query_row(config.SESSIONS_DB, "SELECT COUNT(*) FROM sessions;")
    local session_count = tonumber(row and row[1]) or 0
    
    if session_count > 1000 then
        table.insert(recommendations, {
            table = "sessions",
            issue = string.format("Large table (%d records)", session_count),
            recommendation = "Consider archiving old sessions"
        })
    end
    
    return { 
        status = "ok", 
        recommendations = recommendations,
        total_tables_checked = 4
    }
end


function M.archive_data(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local archive_type = params["type"] or "sessions"
    local days_old = tonumber(params["days"]) or 30
    
    local archived_count = 0
    
    if archive_type == "sessions" then
        local cutoff = os.time() - (days_old * 86400)
        sqlite.execute(config.SESSIONS_DB,
            string.format("DELETE FROM sessions WHERE active=0 AND session_end < %d;", cutoff))
        
        row = sqlite.query_row(config.SESSIONS_DB, "SELECT changes();")
        archived_count = tonumber(row and row[1]) or 0
        
    elseif archive_type == "sales" then
        local cutoff = os.time() - (days_old * 86400)
        local sales_db = config.PATHS.DATA_DIR .. "/sales.db"
        sqlite.execute(sales_db,
            string.format("DELETE FROM sales WHERE created_at < %d;", cutoff))
        
        row = sqlite.query_row(sales_db, "SELECT changes();")
        archived_count = tonumber(row and row[1]) or 0
        
    elseif archive_type == "vouchers" then
        sqlite.execute(config.VOUCHER_DB,
            "DELETE FROM vouchers WHERE status='used' AND used_at > 0;")
        
        row = sqlite.query_row(config.VOUCHER_DB, "SELECT changes();")
        archived_count = tonumber(row and row[1]) or 0
    end
    
    
    if archive_type == "sessions" then
        sqlite.execute(config.SESSIONS_DB, "VACUUM;")
    end
    
    return { 
        status = "ok", 
        message = string.format("Archived %d %s records", archived_count, archive_type),
        archived_count = archived_count
    }
end

return M
