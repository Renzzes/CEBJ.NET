local devices_db = require("fastfi.db.devices")
local security = require("fastfi.security")
local activity = require("fastfi.db.activity")
local M = {}

function M.list_devices(params)
    return { status = "ok", data = devices_db.collect_devices() }
end

function M.list_mac_blocks(params)
    return { status = "ok", data = devices_db.list_blocks() }
end

function M.block_mac(params)
    local sess = security.get_session_user() or { username = "admin" }
    local ok, err = devices_db.block(params.mac, params.reason, sess.username)
    if not ok then return { status = "error", message = err } end
    activity.add("warning", "Device blocked", tostring(params.mac) .. " — " .. tostring(params.reason or ""))
    pcall(function() require("fastfi.db.users").audit(sess.username, "mac_block", tostring(params.mac)) end)
    return { status = "ok" }
end

function M.unblock_mac(params)
    devices_db.unblock(params.id or params.mac)
    activity.add("info", "Device unblocked", tostring(params.mac or params.id))
    return { status = "ok" }
end

function M.waiting_queue(params)
    local all = devices_db.collect_devices()
    local waiting = {}
    for _, d in ipairs(all) do
        if d.auth == "unauthenticated" and d.status == "online" and not d.blocked then
            table.insert(waiting, d)
        end
    end
    return { status = "ok", data = waiting }
end

return M
