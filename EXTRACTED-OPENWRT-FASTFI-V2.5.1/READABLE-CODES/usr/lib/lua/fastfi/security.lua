
local config = require("fastfi.config")
local file_util = require("fastfi.util.file")
local M = {}


local SESSION_TTL = 3600  
local SESSION_COOKIE = config.SESSION_COOKIE_NAME


local function generate_token()
    
    local f = io.popen("openssl rand -hex 32 2>/dev/null")
    if f then
        local token = f:read("*a")
        f:close()
        token = file_util.trim(token)
        if #token > 0 then return token end
    end
    
    
    f = io.open("/dev/urandom", "rb")
    if not f then return nil end
    local bytes = f:read(32)
    f:close()
    if not bytes then return nil end
    
    
    local hex = ""
    for i=1,#bytes do
        hex = hex .. string.format("%02x", string.byte(bytes, i))
    end
    return hex
end


function M.create_session()
    os.execute("mkdir -p " .. config.SESSION_DIR .. " 2>/dev/null")
    
    local token = generate_token()
    if not token then return nil end
    
    local session_file = config.SESSION_DIR .. "/" .. token
    local now = os.time()
    local expiry = now + SESSION_TTL
    
    
    file_util.write(session_file, tostring(expiry))
    
    return token
end


function M.check_admin_session()
    
    local cookie_header = os.getenv("HTTP_COOKIE") or ""
    
    
    local token = cookie_header:match(SESSION_COOKIE .. "=([^;]+)")
    if not token then return false end
    
    
    local session_file = config.SESSION_DIR .. "/" .. token
    local content = file_util.read(session_file)
    
    if not content then return false end
    
    local expiry = tonumber(content)
    if not expiry then return false end
    
    
    local now = os.time()
    if now > expiry then
        os.remove(session_file)
        return false
    end
    
    
    
    if (expiry - now) < (SESSION_TTL - 300) then
        local tmp_path = session_file .. ".tmp." .. tostring(now) .. tostring(math.random(1000, 9999))
        local f = io.open(tmp_path, "w")
        if f then
            f:write(tostring(now + SESSION_TTL))
            f:close()
            os.rename(tmp_path, session_file)
        end
    end
    
    return true
end


function M.destroy_session()

    local cookie_header = os.getenv("HTTP_COOKIE") or ""
    local token = cookie_header:match(SESSION_COOKIE .. "=([^;]+)")

    if token then
        local session_file = config.SESSION_DIR .. "/" .. token
        os.remove(session_file)
    end
end


function M.verify_password(password)
    local pass_file = config.ADMIN_PASS_FILE
    local stored_password = file_util.read(pass_file)
    
    if not stored_password then 
        local msg = "Password file missing: " .. pass_file
        local f = io.open("/tmp/fastfi_security_err.log", "a")
        if f then
            f:write(os.date() .. " - " .. msg .. "\n")
            f:close()
        end
        return false, "System configuration error (Missing password file)"
    end
    
    stored_password = file_util.trim(stored_password)
    password = file_util.trim(password)
    
    local match = (password == stored_password)
    if not match then
        local log_msg = string.format("Mismatch. Input length: %d, Stored length: %d", #password, #stored_password)
        local f = io.open("/tmp/fastfi_security_err.log", "a")
        if f then
            f:write(os.date() .. " - " .. log_msg .. "\n")
            f:close()
        end
        return false, "Incorrect password"
    end
    
    return true
end


function M.change_password(new_password)
    local pass_file = config.ADMIN_PASS_FILE
    return file_util.write(pass_file, file_util.trim(new_password))
end


function M.is_valid_mac(mac)
    if not mac then return false end
    return mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil
end


function M.is_valid_ip(ip)
    if not ip then return false end
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return false end
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    return a <= 255 and b <= 255 and c <= 255 and d <= 255
end




function M.check_app_secret(params)
    local supplied = params and params["app_secret"] or ""
    if not supplied or supplied == "" then return false end

    local sqlite = require("fastfi.db.sqlite")
    
    pcall(function()
        sqlite.execute(config.CONFIG_DB, "ALTER TABLE config ADD COLUMN gcash_app_secret TEXT DEFAULT '';")
    end)
    local row = sqlite.query_row(config.CONFIG_DB,
        "SELECT gcash_app_secret FROM config LIMIT 1;")
    local stored = (row and row[1]) or ""
    if not stored or stored == "" then return false end

    
    if #supplied ~= #stored then return false end
    local diff = 0
    for i = 1, #stored do
        diff = diff + (string.byte(supplied, i) ~= string.byte(stored, i) and 1 or 0)
    end
    return diff == 0
end




function M.shell_quote(s)
    return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

return M
