






local security = require("fastfi.security")
local shield   = require("fastfi.db.shield")
local file_util = require("fastfi.util.file")
local M = {}

local function bg(cmd)
    os.execute("(sleep 0.3; " .. cmd .. " >/dev/null 2>&1) &")
end
local function bg_engine() bg("/usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shield.lua") end
local function bg_sync()   bg("/usr/bin/env lua /usr/libexec/fastfi/core/fastfi-starlink-sync.lua") end

local function admin_guard()
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    return nil
end

local function read_ts(path)
    local s = file_util.read(path)
    if not s then return 0 end
    
    
    
    return tonumber((s:gsub("%s+", ""))) or 0
end




local function dnsmasq_confdir_ok()
    local f = io.popen("grep -rsq 'conf-dir=/etc/dnsmasq.d' /var/etc/dnsmasq.conf.* 2>/dev/null && echo yes")
    if not f then return false end
    local out = f:read("*a") or ""
    f:close()
    return out:find("yes", 1, true) ~= nil
end



local function nft_set_count(setname)
    local f = io.popen("nft -j list set inet fastfi_shield " .. setname .. " 2>/dev/null")
    if not f then return 0 end
    local out = f:read("*a") or ""
    f:close()
    
    if out == "" then
        local f2 = io.popen("nft list set inet fastfi_shield " .. setname .. " 2>/dev/null")
        if not f2 then return 0 end
        local txt = f2:read("*a") or ""
        f2:close()
        local elems = txt:match("elements%s*=%s*{%s*(.-)%s*}")
        if not elems or elems == "" then return 0 end
        local n = 0
        for _ in elems:gmatch(",") do n = n + 1 end
        return n + 1
    end
    
    local n = 0
    for _ in out:gmatch('"elem"') do n = n + 1 end
    return n
end

function M.shield_status(params)
    local err = admin_guard(); if err then return err end
    local cfg = shield.read_config()
    local blocked  = shield.read_list("blocked_domains")
    local allowed  = shield.read_list("allowed_domains")
    local starlink = shield.read_list("starlink_domains")
    local doh     = shield.get_doh_domains()

    local protection_active = (cfg.starlink_enabled == 1) or (cfg.force_dns_enabled == 1)
        or (cfg.doh_block_enabled == 1) or (cfg.quic_block_enabled == 1) or (#blocked > 0)

    return {
        status = "ok",
        config = cfg,
        counts = {
            blocked  = #blocked,
            allowed  = #allowed,
            starlink = #starlink,
            doh      = #doh
        },
        protection_active = protection_active,
        last_apply = read_ts("/etc/fastfi/security/.last_apply"),
        last_sync   = read_ts("/etc/fastfi/security/.last_sync"),
        starlink_ip_count = nft_set_count("fastfi_starlink_ips"),
        
        dnsmasq_confdir_ok = dnsmasq_confdir_ok(),
        block_conf_present = file_util.exists("/etc/dnsmasq.d/fastfi-block.conf")
    }
end

function M.shield_get_lists(params)
    local err = admin_guard(); if err then return err end
    return {
        status = "ok",
        blocked  = shield.read_list("blocked_domains"),
        allowed  = shield.read_list("allowed_domains"),
        starlink = shield.read_list("starlink_domains"),
        doh      = shield.get_doh_domains()
    }
end


local function add_remove(list_name, params, op)
    local err = admin_guard(); if err then return err end
    
    
    local domains = shield.parse_domains(params["domain"] or "")
    if #domains == 0 then
        return { status = "error",
                 message = "Invalid domain. Enter a hostname like facebook.com (http://, paths, wildcards, and ports are auto-stripped)." }
    end
    local new_list, any_changed
    for _, d in ipairs(domains) do
        if op == "add" then
            local lst, changed = shield.add_domain(list_name, d)
            if lst then new_list, any_changed = lst, (any_changed or changed) end
        else
            local lst, changed = shield.remove_domain(list_name, d)
            new_list = lst or new_list
            any_changed = any_changed or changed
        end
    end
    if any_changed then bg_engine() end
    return {
        status = "ok",
        message = any_changed and "Saved." or "No change.",
        list = new_list or shield.read_list(list_name)
    }
end

function M.shield_add_blocked(params)    return add_remove("blocked_domains", params, "add") end
function M.shield_remove_blocked(params) return add_remove("blocked_domains", params, "remove") end
function M.shield_add_allowed(params)    return add_remove("allowed_domains", params, "add") end
function M.shield_remove_allowed(params) return add_remove("allowed_domains", params, "remove") end


local function toggle(key, params)
    local err = admin_guard(); if err then return err end
    local on = (params["enabled"] == "1" or params["enabled"] == "true")
    local cfg = shield.set_toggle(key, on and 1 or 0)
    bg_engine()
    
    
    if key == "starlink_enabled" and on then bg_sync() end
    return { status = "ok", config = cfg }
end

function M.shield_toggle_starlink(params)  return toggle("starlink_enabled", params) end
function M.shield_toggle_force_dns(params) return toggle("force_dns_enabled", params) end
function M.shield_toggle_doh(params)       return toggle("doh_block_enabled", params) end
function M.shield_toggle_quic(params)      return toggle("quic_block_enabled", params) end



function M.shield_apply(params)
    local err = admin_guard(); if err then return err end
    bg_engine()
    return { status = "ok", message = "Re-applying shield rules..." }
end


function M.shield_starlink_sync_now(params)
    local err = admin_guard(); if err then return err end
    bg_sync()
    return { status = "ok", message = "Resolving Starlink IPs in the background..." }
end

return M