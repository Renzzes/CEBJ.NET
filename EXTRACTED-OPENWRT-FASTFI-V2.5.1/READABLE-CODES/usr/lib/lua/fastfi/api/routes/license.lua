
local config_db = require("fastfi.db.config")
local sqlite = require("fastfi.db.sqlite")
local config = require("fastfi.config")
local security = require("fastfi.security")
local http_util = require("fastfi.util.http")
local file_util = require("fastfi.util.file")
local M = {}

function M.activate_license(params)
    local license_key = params["license_key"]
    if not license_key or license_key == "" then
        return { status = "error", message = "Missing license key" }
    end

    
    local device_id = config.MACHINE_ID
    if not device_id or device_id == "" then
        
        
        
        local h = io.popen(". /usr/libexec/fastfi/core/fastfi-machine-id.sh 2>/dev/null; fastfi_machine_id 2>/dev/null")
        device_id = h and h:read("*a") or ""
        if h then h:close() end
        device_id = (device_id or ""):gsub("%s+", ""):upper()
    end

    
    if not file_util.exists(config.DEVICE_KEY_FILE) then
        os.execute(string.format("mkdir -p %s && openssl rand -hex 32 > %s && chmod 600 %s",
            "/etc/fastfi", config.DEVICE_KEY_FILE, config.DEVICE_KEY_FILE))
    end

    local device_key = file_util.read(config.DEVICE_KEY_FILE) or ""

    
    local server_url = "https://fastfi.cloud/api/v1/device/activate"
    local json_body = string.format('{"device_id":"%s","license_key":"%s"}', device_id, license_key)

    
    local timestamp = tostring(os.time())
    local nonce_cmd = io.popen("openssl rand -hex 12")
    local nonce = nonce_cmd and nonce_cmd:read("*a") or ""
    if nonce_cmd then nonce_cmd:close() end
    nonce = nonce:gsub("%s+", "")

    local sign_data = device_id .. timestamp .. nonce .. json_body
    local sig_cmd = io.popen(string.format("printf '%s' | openssl dgst -sha256 -hmac '%s' -hex | awk '{print $2}'",
        sign_data, device_key))
    local signature = sig_cmd and sig_cmd:read("*a") or ""
    if sig_cmd then sig_cmd:close() end
    signature = signature:gsub("%s+", "")

    
    local response = http_util.post(server_url, json_body, {
        ["Content-Type"] = "application/json",
        ["x-device-id"] = device_id,
        ["x-timestamp"] = timestamp,
        ["x-nonce"] = nonce,
        ["x-signature"] = signature
    })

    if not response or (response.status_code ~= 200 and response.status_code ~= 409) then
        return {
            status = "inactive",
            plan = "-",
            expires = "-",
            license_key = "-",
            message = "Activation failed"
        }
    end

    
    local body = response.body or ""
    local srv_msg = body:match('"message"%s*:%s*"([^"]+)"') or body:match('"error"%s*:%s*"([^"]+)"')

    if response.status_code == 409 then
        if not srv_msg or (not srv_msg:lower():find("already bound") and not srv_msg:lower():find("already active")) then
            return {
                status = "inactive",
                plan = "-",
                expires = "-",
                license_key = "-",
                message = srv_msg or "Conflict: License already in use"
            }
        end
        
        
        
        
        
        
        
        
        local bound_device = body:match('"device_id"%s*:%s*"([^"]+)"') or ""
        bound_device = bound_device:gsub("%s+", ""):upper()
        local this_device = (device_id or ""):gsub("%s+", ""):upper()
        local msg_lower = (srv_msg or ""):lower()
        local bound_to_this = (bound_device ~= "" and bound_device == this_device)
            or msg_lower:find("this device") ~= nil
            or msg_lower:find("already active") ~= nil
        if not bound_to_this then
            return {
                status = "inactive",
                plan = "-",
                expires = "-",
                license_key = "-",
                message = "License is bound to another device — rebind required.",
                device_id = this_device,
                bound_device_id = bound_device
            }
        end
    end
    local resp_status = body:match('"status"%s*:%s*"([^"]+)"') or "inactive"

    
    if response.status_code == 409 and (resp_status == "error" or resp_status == "conflict" or resp_status == "inactive") then
        resp_status = "active"
    end
    local plan = body:match('"plan"%s*:%s*"([^"]+)"') or "-"
    local expires = body:match('"expires_at"%s*:%s*"([^"]+)"') or "-"

    
    file_util.write(config.LICENSE_FILE, body)

    
    if resp_status == "ok" or resp_status == "active" then
        sqlite.execute(config.CONFIG_DB,
            string.format([[UPDATE config SET
                license_status='active',
                license_key='%s'
            WHERE id=1;]],
            license_key))

        
        local verify = sqlite.query_row(config.CONFIG_DB, "SELECT license_status FROM config WHERE id=1;")
        if not verify or verify[1] ~= "active" then
            os.execute("logger -t fastfi 'WARNING: License DB write failed'")
        end
    end

    return {
        status = resp_status,
        plan = plan,
        expires = expires,
        license_key = license_key
    }
end

function M.get_license_status(params)
    
    local is_admin = security.check_admin_session()

    local db_info = config_db.get_license_info()

    local status = db_info.license_status

    
    local expires = db_info.expires_at or db_info.expires or "-"
    if expires == "-" and db_info.expires_at and db_info.expires_at ~= "-" then
        expires = db_info.expires_at
    end

    local result = {
        device_id = config.MACHINE_ID or "-",
        status = status or "inactive",
        plan = db_info.plan or "-",
        expires = expires
    }

    
    if is_admin and status == "active" and db_info.license_key then
        result.license_key = db_info.license_key
    end

    return result
end

function M.remove_license(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end

    local confirm = params["confirm"]
    if confirm ~= "1" then
        return { status = "error", message = "Confirmation required" }
    end

    
    sqlite.execute(config.CONFIG_DB, [[
        UPDATE config SET
            license_status='inactive',
            license_key='',
            plan_code='',
            expires_at=''
        WHERE id=1;
    ]])

    
    os.execute("rm -f " .. config.LICENSE_FILE)

    
    os.execute("rm -f /etc/fastfi_enrolled")

    os.execute("logger -t fastfi 'License removed by admin'")

    return { status = "ok", message = "License removed successfully" }
end










function M.recover_license(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end

    local rebind_key = (params["license_key"] or ""):gsub("^%s+", ""):gsub("%s+$", "")

    
    
    
    
    
    
    
    
    
    if rebind_key ~= "" then
        local r = M.activate_license({ license_key = rebind_key })
        local ok = r and (r.status == "ok" or r.status == "active")
        local device_id = (config.MACHINE_ID or ""):gsub("%s+", "")
        
        
        
        local safe_msg = (r and r.message or ""):gsub("['\"`$\\;|&<>]", "")
        os.execute("logger -t fastfi 'License rebind " .. (ok and "OK" or "FAILED") ..
            " device_id=" .. device_id .. " msg=" .. safe_msg .. "'")
        return {
            status = ok and "ok" or "error",
            message = (r and r.message) or "Rebind failed",
            license_status = ok and "active" or "inactive",
            license_key = rebind_key,
            plan = (r and r.plan) or "-",
            expires = (r and r.expires) or "-",
            device_id = device_id,
            rebind = true
        }
    end

    
    
    sqlite.execute(config.CONFIG_DB, "UPDATE config SET license_key='' WHERE id=1;")
    os.execute("rm -f " .. config.LICENSE_FILE .. " 2>/dev/null")

    
    
    
    
    
    local function wait_idle()
        for _ = 1, 12 do
            local f = io.popen("pgrep -f '/usr/libexec/fastfi/services/fastfi-report.sh' 2>/dev/null")
            local out = f and f:read("*a") or ""
            if f then f:close() end
            if out == nil or out == "" then return true end
            os.execute("sleep 1")
        end
        return false
    end

    wait_idle()
    local log = ""
    
    
    
    
    local report_cmd = "timeout 40 /usr/libexec/fastfi/services/fastfi-report.sh 2>&1"
    local tf = io.popen("command -v timeout 2>/dev/null")
    local has_timeout = tf and (tf:read("*a") or ""):match("%S")
    if tf then tf:close() end
    if not has_timeout then
        report_cmd = "/usr/libexec/fastfi/services/fastfi-report.sh 2>&1"
    end
    local f = io.popen(report_cmd)
    if f then
        log = f:read("*a") or ""
        f:close()
    end

    
    local row = sqlite.query_row(config.CONFIG_DB,
        "SELECT license_status, license_key, plan_code, expires_at FROM config WHERE id=1;")
    local status  = (row and row[1]) or "inactive"
    local key     = (row and row[2]) or ""
    local plan    = (row and row[3]) or ""
    local expires = (row and row[4]) or ""
    local recovered = (key ~= nil and key ~= "")
    local device_id = (config.MACHINE_ID or ""):gsub("%s+", "")
    local log_trim = (log or ""):gsub("^%s+", ""):gsub("%s+$", "")

    os.execute("logger -t fastfi 'License recovery requested by admin: " ..
        (recovered and "recovered " or "not found ") .. tostring(key) ..
        " device_id=" .. tostring(device_id) .. "'")

    local msg
    if recovered then
        msg = "License recovered from FastFi Cloud and bound to this device."
    elseif log_trim == "" then
        msg = "Recovery ran but the cloud report produced no output. Check internet/WAN connectivity and that the device can reach fastfi.cloud, then try again."
    else
        msg = "Recovery attempted, but no license is bound to this device on the cloud. " ..
              "Device sent device_id=\"" .. device_id .. "\". If the cloud bound this license " ..
              "under a different ID (e.g. an older MAC-derived ID), the binding must be migrated " ..
              "cloud-side to this device_id. Make sure the device is online and was previously activated, then try again."
    end

    return {
        status = recovered and "ok" or "error",
        message = msg,
        license_status = status,
        license_key = key,
        plan = plan,
        expires = expires,
        device_id = device_id,
        log = log,
        raw_report = log
    }
end

return M
