-- KonekSik-Fi: on-demand Tailscale remote Admin (replaces FastFi OpenVPN cloud).
local security = require("fastfi.security")
local file_util = require("fastfi.util.file")

local M = {}

local SCRIPT = "/usr/libexec/fastfi/services/fastfi-tailscale.sh"

local function decode_json(raw)
    if not raw or raw == "" then
        return nil
    end
    local ok, cjson = pcall(require, "cjson.safe")
    if ok and cjson and cjson.decode then
        local obj = cjson.decode(raw)
        if type(obj) == "table" then
            return obj
        end
    end
    return nil
end

local function run(args)
    local cmd = SCRIPT .. " " .. (args or "status") .. " 2>/dev/null"
    local out = file_util.execute(cmd)
    local obj = decode_json(out)
    if obj then
        obj.provider = "tailscale"
        if not obj.status then
            obj.status = "ok"
        end
        return obj
    end
    return {
        status = "error",
        provider = "tailscale",
        message = "Tailscale helper failed",
        raw = out or ""
    }
end

function M.status(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    return run("status")
end

function M.install(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    return run("install")
end

function M.up(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local key = tostring(params.auth_key or params.authkey or params.token or "")
    key = key:gsub("^%s+", ""):gsub("%s+$", "")
    if key ~= "" then
        local safe = key:gsub("'", "'\\''")
        return run(string.format("up '%s'", safe))
    end
    return run("up")
end

function M.down(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    return run("down")
end

-- Compatibility aliases used by older Admin JS action names
function M.remote_access_status(params)
    return M.status(params)
end

function M.remote_access_connect(params)
    return M.up(params)
end

function M.remote_access_disconnect(params)
    return M.down(params)
end

function M.remote_access_enroll(params)
    return M.up(params)
end

return M
