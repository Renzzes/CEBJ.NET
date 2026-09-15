local plans_db = require("fastfi.db.plans")
local security = require("fastfi.security")
local activity = require("fastfi.db.activity")
local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")
local M = {}

local function sess_user()
    local s = security.get_session_user()
    return (s and s.username) or "admin"
end

-- Profiles
function M.list_profiles(params)
    return { status = "ok", data = plans_db.list_profiles() }
end

function M.save_profile(params)
    local ok, id_or_err = plans_db.save_profile(params)
    if not ok then return { status = "error", message = id_or_err or "Save failed" } end
    activity.add("info", "Bandwidth profile saved", tostring(params.name or id_or_err))
    return { status = "ok", id = id_or_err }
end

function M.delete_profile(params)
    if not plans_db.delete_profile(params.id) then
        return { status = "error", message = "Delete failed" }
    end
    return { status = "ok" }
end

-- Plans
function M.list_plans(params)
    return { status = "ok", data = plans_db.list_plans() }
end

function M.save_plan(params)
    local ok, id_or_err = plans_db.save_plan(params)
    if not ok then return { status = "error", message = id_or_err or "Save failed" } end
    activity.add("info", "Plan saved", tostring(params.name or id_or_err))
    pcall(function() require("fastfi.db.users").audit(sess_user(), "plan_save", tostring(params.name)) end)
    return { status = "ok", id = id_or_err }
end

function M.delete_plan(params)
    plans_db.delete_plan(params.id)
    return { status = "ok" }
end

-- Clients
function M.list_plan_clients(params)
    return { status = "ok", data = plans_db.list_clients() }
end

function M.save_plan_client(params)
    local ok, id_or_err = plans_db.save_client(params)
    if not ok then return { status = "error", message = id_or_err or "Save failed" } end
    return { status = "ok", id = id_or_err }
end

function M.delete_plan_client(params)
    plans_db.delete_client(params.id)
    return { status = "ok" }
end

function M.attach_plan_device(params)
    local ok, err = plans_db.attach_device(params.client_id, params.mac, params.hostname)
    if not ok then return { status = "error", message = err } end
    return { status = "ok" }
end

function M.detach_plan_device(params)
    plans_db.detach_device(params.id or params.mac)
    return { status = "ok" }
end

local function apply_shaper(mac, down_kbps, up_kbps)
    mac = tostring(mac or ""):upper()
    os.execute(string.format("mkdir -p %s 2>/dev/null", config.SPEED_CONF))
    local conf = string.format("%s/%s", config.SPEED_CONF, mac:gsub(":", ""))
    local f = io.open(conf, "w")
    if f then
        f:write(string.format("DOWNLOAD=%d\nUPLOAD=%d\n", tonumber(down_kbps) or 0, tonumber(up_kbps) or 0))
        f:close()
    end
    pcall(function()
        os.execute("/usr/bin/lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1 &")
    end)
end

-- Best-effort: if profile prefers 2.4 or 5 only, deauth the MAC from the other band
-- so the phone reconnects on the allowed radio (Auto = no kick).
local function apply_band_preference(mac, band)
    band = plans_db.normalize_band(band)
    if band == "auto" then return end
    mac = tostring(mac or ""):upper()
    local want24 = (band == "2.4")
    local ifaces = io.popen("iwinfo 2>/dev/null | awk '/^wlan|^rai|^rax|^wl/{print $1}'")
    if not ifaces then return end
    for iface in ifaces:lines() do
        iface = tostring(iface):gsub("%s+", "")
        if iface ~= "" then
            local info = io.popen("iwinfo " .. iface .. " info 2>/dev/null")
            local iface_band = "auto"
            if info then
                local blob = info:read("*a") or ""
                info:close()
                if blob:match("2%.4") or blob:match("2GHz") then iface_band = "2.4"
                elseif blob:match("5%.") or blob:match("5GHz") then iface_band = "5" end
            end
            local assoc = io.popen("iwinfo " .. iface .. " assoclist 2>/dev/null")
            local found = false
            if assoc then
                for al in assoc:lines() do
                    if al:upper():find(mac, 1, true) then found = true break end
                end
                assoc:close()
            end
            if found and iface_band ~= "auto" then
                local allowed = (want24 and iface_band == "2.4") or ((not want24) and iface_band == "5")
                if not allowed then
                    os.execute(string.format(
                        "ubus call hostapd.%s del_client '{\"addr\":\"%s\",\"reason\":5,\"deauth\":true,\"ban_time\":0}' >/dev/null 2>&1",
                        iface, mac))
                    os.execute(string.format(
                        "hostapd_cli -i %s deauthenticate %s >/dev/null 2>&1", iface, mac))
                end
            end
        end
    end
    ifaces:close()
end

function M.activate_plan(params)
    local plan_id = tonumber(params.plan_id)
    local mac = tostring(params.mac or ""):upper():gsub("%-", ":")
    if not plan_id or not mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        return { status = "error", message = "plan_id and mac required" }
    end
    local plan = plans_db.get_plan(plan_id)
    if not plan or plan.enabled == 0 then
        return { status = "error", message = "Plan not found or disabled" }
    end
    local now = os.time()
    local duration = (tonumber(plan.duration_min) or 0) * 60
    local session_end = now + duration
    local client_id = tonumber(params.client_id) or 0
    local pause_limit = tonumber(plan.pause_limit) or 0
    local data_mb = tonumber(plan.data_mb) or 0
    local profile_id = tonumber(plan.profile_id) or 0
    local band = "auto"
    local prof = nil
    if profile_id > 0 then
        prof = plans_db.get_profile(profile_id)
        if prof then band = plans_db.normalize_band(prof.band) end
    end

    sqlite.execute(config.SESSIONS_DB, string.format(
        "DELETE FROM sessions WHERE mac_address='%s';", sqlite.quote(mac)))
    sqlite.execute(config.SESSIONS_DB, string.format([[
        INSERT INTO sessions (mac_address, session_end, remaining, active, paused, created_at, updated_at,
            paused_limit, data_limit_mb, plan_id, profile_id, plan_client_id, band)
        VALUES ('%s', %d, %d, 1, 0, %d, %d, %d, %d, %d, %d, %d, '%s');
    ]], sqlite.quote(mac), session_end, duration, now, now, pause_limit, data_mb, plan_id, profile_id, client_id, sqlite.quote(band)))

    if prof then
        apply_shaper(mac, prof.down_kbps, prof.up_kbps)
        pcall(apply_band_preference, mac, band)
    end

    -- grant captive access best-effort
    pcall(function()
        os.execute(string.format("%s %s >/dev/null 2>&1 &", config.CAPTIVE_TRIGGER, mac))
    end)

    activity.add("success", "Plan activated", plan.name .. " → " .. mac .. " [" .. band .. "]")
    pcall(function() require("fastfi.db.users").audit(sess_user(), "activate_plan", plan.name .. " " .. mac) end)

    return { status = "ok", session_end = session_end, remaining = duration, plan = plan, band = band }
end

return M
