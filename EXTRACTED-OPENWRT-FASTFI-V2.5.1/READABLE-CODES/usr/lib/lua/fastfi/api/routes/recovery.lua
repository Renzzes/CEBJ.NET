











local security  = require("fastfi.security")
local file_util = require("fastfi.util.file")
local config    = require("fastfi.config")
local sqlite    = require("fastfi.db.sqlite")
local M = {}

local DEFAULT_PASSWORD = "admin123"




local MUST_CHANGE_FLAG = "/etc/fastfi_pass_change_required"
local RATE_FILE_DIR    = "/tmp"
local MAX_ATTEMPTS     = 5
local LOCKOUT_SECONDS  = 900   





local function normalize(s)
    return (tostring(s or ""):upper():gsub("[^A-Z0-9]", ""))
end




local function rate_file()
    local ip = os.getenv("REMOTE_ADDR") or "unknown"
    return string.format("%s/fastfi_pwrecover_%s", RATE_FILE_DIR, ip:gsub("[^%d]", "_"))
end

local function read_attempts(path)
    local raw = file_util.read(path) or ""
    local count, last = raw:match("^(%d+)|(%d+)$")
    return tonumber(count) or 0, tonumber(last) or 0
end

function M.recover_admin_password(params)
    local now  = os.time()
    local path = rate_file()
    local attempts, last = read_attempts(path)

    if attempts >= MAX_ATTEMPTS and (now - last) < LOCKOUT_SECONDS then
        local wait = LOCKOUT_SECONDS - (now - last)
        return {
            status = "locked",
            message = string.format("Too many attempts. Try again in %d minute(s).",
                math.ceil(wait / 60))
        }
    end
    
    if attempts >= MAX_ATTEMPTS then attempts = 0 end

    local row = sqlite.query_row(config.CONFIG_DB,
        "SELECT license_key FROM config WHERE id=1;")
    local license = normalize(row and row[1])

    
    
    
    if #license < 8 then
        return {
            status = "error",
            message = "This device has no licence key, so password recovery is unavailable. Activate a licence first."
        }
    end

    local supplied = normalize(params["license_tail"])
    if #supplied < 8 then
        return { status = "invalid", message = "Enter the last two groups of your licence key (XXXX-XXXX)." }
    end

    if supplied:sub(-8) == license:sub(-8) then
        security.change_password(DEFAULT_PASSWORD)
        file_util.write(MUST_CHANGE_FLAG, tostring(now))
        os.remove(path)
        os.execute("logger -t fastfi-admin 'Admin password reset via licence-key recovery'")
        return {
            status = "reset",
            message = "Password reset. Log in with the default password, then set a new one.",
            default_password = DEFAULT_PASSWORD
        }
    end

    attempts = attempts + 1
    file_util.write(path, string.format("%d|%d", attempts, now))
    os.execute(string.format(
        "logger -t fastfi-admin 'Failed password recovery attempt (%d/%d)'", attempts, MAX_ATTEMPTS))

    local left = MAX_ATTEMPTS - attempts
    return {
        status = "invalid",
        message = (left > 0)
            and string.format("Incorrect. %d attempt(s) remaining.", left)
            or "Incorrect. Too many attempts — locked for 15 minutes."
    }
end



function M.must_change_password()
    return file_util.exists(MUST_CHANGE_FLAG)
end

function M.clear_must_change()
    os.remove(MUST_CHANGE_FLAG)
end

return M
