
local security = require("fastfi.security")
local M = {}

function M.login(params)
    local password = params["password"]
    local username = params["username"] or "admin"
    
    if not password or password == "" then
        return { status = "fail", message = "Missing password" }
    end
    
    password = require("fastfi.util.file").trim(password)
    username = require("fastfi.util.file").trim(username)
    
    
    local success, err_msg, user = security.verify_password(password, username)
    if not success then
        
        os.execute("sleep 1")
        return { status = "fail", message = err_msg or "Invalid password" }
    end
    
    user = user or { username = username, role = "owner" }
    local token = security.create_session(user.username, user.role)
    
    if not token then
        return { status = "fail", message = "Session creation failed" }
    end
    
    
    local cookie_header = "Set-Cookie: " .. require("fastfi.config").SESSION_COOKIE_NAME .. "=" .. token .. "; Path=/; Max-Age=31536000; HttpOnly; SameSite=Strict"
    
    
    
    local ok_rec, recovery = pcall(require, "fastfi.api.routes.recovery")
    local must_change = (ok_rec and recovery and recovery.must_change_password
                         and recovery.must_change_password()) or false

    pcall(function()
        local users = require("fastfi.db.users")
        users.audit(user.username, "login", "Admin login OK")
        local activity = require("fastfi.db.activity")
        activity.add("info", "Admin login", user.username .. " signed in")
    end)

    return { 
        status = "ok", 
        message = "Login successful",
        username = user.username,
        role = user.role,
        must_change_password = must_change,
        _headers = { cookie_header }
    }
end

function M.logout(params)
    
    local sess = security.get_session_user()
    if sess then
        pcall(function()
            require("fastfi.db.users").audit(sess.username, "logout", "Admin logout")
        end)
    end
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

    local sess = security.get_session_user() or { username = "admin" }
    local target = params["username"] or sess.username
    -- staff can only change own password; owner can change any
    if sess.role ~= "owner" and target ~= sess.username then
        return { status = "error", message = "Forbidden" }
    end
    
    local success = security.change_password(new_pass, target)
    
    if success then
        
        local ok_rec, recovery = pcall(require, "fastfi.api.routes.recovery")
        if ok_rec and recovery and recovery.clear_must_change then
            recovery.clear_must_change()
        end
        pcall(function()
            require("fastfi.db.users").audit(sess.username, "change_password", "Changed password for " .. tostring(target))
        end)
        os.execute("logger -t fastfi-admin 'Admin password changed successfully'")
        return { status = "ok", message = "Password changed successfully" }
    else
        os.execute("logger -t fastfi-admin 'Failed to change admin password'")
        return { status = "error", message = "Failed to change password" }
    end
end

function M.session_info(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized", code = 401 }
    end
    local sess = security.get_session_user() or { username = "admin", role = "owner" }
    return { status = "ok", username = sess.username, role = sess.role }
end

return M
