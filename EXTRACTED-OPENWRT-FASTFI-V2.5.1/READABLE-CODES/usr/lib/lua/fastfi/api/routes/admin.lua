
local security = require("fastfi.security")
local json_util = require("fastfi.util.json")
local M = {}

function M.login(params)
    local password = params["password"]
    
    if not password or password == "" then
        return { status = "fail", message = "Missing password" }
    end
    
    password = require("fastfi.util.file").trim(password)
    
    
    local success, err_msg = security.verify_password(password)
    if not success then
        
        os.execute("sleep 1")
        return { status = "fail", message = err_msg or "Invalid password" }
    end
    
    
    local token = security.create_session()
    
    if not token then
        return { status = "fail", message = "Session creation failed" }
    end
    
    
    local cookie_header = "Set-Cookie: " .. require("fastfi.config").SESSION_COOKIE_NAME .. "=" .. token .. "; Path=/; Max-Age=31536000; HttpOnly; SameSite=Strict"
    
    
    
    local ok_rec, recovery = pcall(require, "fastfi.api.routes.recovery")
    local must_change = (ok_rec and recovery and recovery.must_change_password
                         and recovery.must_change_password()) or false

    return { 
        status = "ok", 
        message = "Login successful",
        must_change_password = must_change,
        _headers = { cookie_header }
    }
end

function M.logout(params)
    
    security.destroy_session()
    
    return { status = "ok", message = "Logged out" }
end

function M.change_password(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local new_pass = params["new_password"]
    if not new_pass or new_pass == "" then
        return { status = "error", message = "Missing new password" }
    end
    
    local success = security.change_password(new_pass)
    
    if success then
        
        local ok_rec, recovery = pcall(require, "fastfi.api.routes.recovery")
        if ok_rec and recovery and recovery.clear_must_change then
            recovery.clear_must_change()
        end
        os.execute("logger -t fastfi-admin 'Admin password changed successfully'")
        return { status = "ok", message = "Password changed successfully" }
    else
        os.execute("logger -t fastfi-admin 'Failed to change admin password'")
        return { status = "error", message = "Failed to change password" }
    end
end

return M
