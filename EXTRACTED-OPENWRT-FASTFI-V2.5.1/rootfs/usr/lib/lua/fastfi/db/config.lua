
local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")
local file_util = require("fastfi.util.file")
local M = {}

function M.get_license_info()
    local row = sqlite.query_row(config.CONFIG_DB, "SELECT license_key, license_status, expires_at, plan_code FROM config LIMIT 1;")
    
    local key = row and row[1] or ""
    local status = row and row[2] or "inactive"
    
    local plan = (row and row[4] and row[4] ~= "") and row[4] or "-"
    local expires = (row and row[3] and row[3] ~= "") and row[3] or "-"
    
    
    if (plan == "-" or expires == "-") and file_util.exists(config.LICENSE_FILE) then
        local json_data = file_util.read(config.LICENSE_FILE)
        if json_data and json_data ~= "" then
            if plan == "-" then
                local p = json_data:match('"plan"%s*:%s*"([^"]+)"')
                if p then plan = p end
            end
            
            if expires == "-" then
                local e = json_data:match('"expires_at"%s*:%s*"([^"]+)"')
                if not e then
                    e = json_data:match('"expires"%s*:%s*"([^"]+)"')
                end
                if e then expires = e end
            end
        end
    end
    
    
    if status ~= "active" and status ~= "revoked" and key ~= "" and expires ~= "-" then
        status = "active"
    end
    
    
    if expires == "revoked" or status == "revoked" then
        status = "inactive"
        expires = "-"
    end
    
    return {
        license_key = key,
        license_status = status,
        plan = plan,
        expires = expires,
        expires_at = expires
    }
end

function M.get_device_id()
    
    
    
    return config.MACHINE_ID or nil
end

function M.revoke_license()
    sqlite.execute(M.CONFIG_DB or config.CONFIG_DB, "UPDATE config SET license_key='', license_status='inactive', plan_code='', expires_at='' WHERE id=1;")
    os.execute("rm -f " .. (M.LICENSE_FILE or config.LICENSE_FILE))
    return true
end

return M
