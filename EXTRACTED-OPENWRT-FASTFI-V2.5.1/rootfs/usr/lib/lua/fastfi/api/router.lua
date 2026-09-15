
local request_parser = require("fastfi.api.request")
local response_formatter = require("fastfi.api.response")
local security = require("fastfi.security")
local json_util = require("fastfi.util.json")


local portal_routes = require("fastfi.api.routes.portal")
local session_routes = require("fastfi.api.routes.sessions")
local dashboard_routes = require("fastfi.api.routes.dashboard")
local voucher_routes = require("fastfi.api.routes.vouchers")
local esp_routes = require("fastfi.api.routes.esp")
local admin_routes = require("fastfi.api.routes.admin")
local client_routes = require("fastfi.api.routes.clients")
local rate_routes = require("fastfi.api.routes.rates")
local license_routes = require("fastfi.api.routes.license")
local esp_license_routes = require("fastfi.api.routes.esp_license")
local recovery_routes = require("fastfi.api.routes.recovery")
local ops_routes = require("fastfi.api.routes.ops")
local firewall_routes = require("fastfi.api.routes.firewall")
local database_routes = require("fastfi.api.routes.database")
local ok_dhcp, dhcp_routes = pcall(require, "fastfi.api.routes.dhcp")
if not ok_dhcp then
    io.stderr:write("[WARN] dhcp module failed to load: " .. tostring(dhcp_routes) .. "\n")
    dhcp_routes = {}
end
local ok_sh, shield_routes = pcall(require, "fastfi.api.routes.shield")
if not ok_sh then
    io.stderr:write("[WARN] shield module failed to load: " .. tostring(shield_routes) .. "\n")
    shield_routes = {}
end
local ok_gc, gcash_routes = pcall(require, "fastfi.api.routes.gcash")
if not ok_gc then
    io.stderr:write("[WARN] gcash module failed to load: " .. tostring(gcash_routes) .. "\n")
    gcash_routes = {}
end
local ok_plans, plans_routes = pcall(require, "fastfi.api.routes.plans")
if not ok_plans then
    io.stderr:write("[WARN] plans module failed to load: " .. tostring(plans_routes) .. "\n")
    plans_routes = {}
end
local ok_dev, devices_routes = pcall(require, "fastfi.api.routes.devices")
if not ok_dev then
    io.stderr:write("[WARN] devices module failed to load: " .. tostring(devices_routes) .. "\n")
    devices_routes = {}
end
local ok_ext, ext_routes = pcall(require, "fastfi.api.routes.ext")
if not ok_ext then
    io.stderr:write("[WARN] ext module failed to load: " .. tostring(ext_routes) .. "\n")
    ext_routes = {}
end
local ok_ap, ap_routes = pcall(require, "fastfi.api.routes.access_points")
if not ok_ap then
    io.stderr:write("[WARN] access_points module failed to load: " .. tostring(ap_routes) .. "\n")
    ap_routes = {}
end
local ok_ts, ts_routes = pcall(require, "fastfi.api.routes.tailscale")
if not ok_ts then
    io.stderr:write("[WARN] tailscale module failed to load: " .. tostring(ts_routes) .. "\n")
    ts_routes = {}
end

local M = {}


local routes = {
    
    checkDevice = portal_routes.check_device,
    device_status = portal_routes.device_status,
    internet_status = portal_routes.internet_status,
    getMac = portal_routes.get_mac,
    session_status = portal_routes.session_status,
    internet = portal_routes.internet_check,
    updateDevice = portal_routes.update_device,
    voucher = voucher_routes.redeem,
    clearcredit = portal_routes.clear_credit,
    terminate = portal_routes.terminate,
    classic = portal_routes.classic,
    
    
    client_deauth = session_routes.deauth_client,
    extend_session = session_routes.extend_session,
    client_update = session_routes.update_client,
    session_history = session_routes.session_history,
    
    
    system_status = dashboard_routes.system_status,
    
    
    insertcoin = esp_routes.insert_coin,
    lockcoin = esp_routes.lock_coin,
    fetchcoin = esp_routes.fetch_coin,
    register_esp_slot = esp_routes.register_esp_slot,
    esp_status = esp_routes.esp_status,
    check_coin_lock = esp_routes.check_coin_lock,
    unlockcoin = esp_routes.unlock_coin,
    
    
    list_esp_devices = esp_routes.list_esp_devices,
    add_esp_device = esp_routes.add_esp_device,
    delete_esp_device = esp_routes.delete_esp_device,
    rename_esp_slot = esp_routes.rename_esp_slot,
    
    
    esp_license_list = esp_license_routes.list,
    esp_license_add = esp_license_routes.add,
    esp_license_remove = esp_license_routes.remove,
    esp_license_bind = esp_license_routes.bind,
    esp_license_unbind = esp_license_routes.unbind,
    esp_license_free = esp_license_routes.free,
    esp_license_release = esp_license_routes.release,
    esp_detect = esp_license_routes.detect,
    
    
    admin_login = admin_routes.login,
    admin_logout = admin_routes.logout,
    change_password = admin_routes.change_password,
    recover_admin_password = recovery_routes.recover_admin_password,
    session_info = admin_routes.session_info,
    
    
    live_sessions = client_routes.live_sessions,
    client_list = client_routes.client_list,
    client_list_unauth = client_routes.client_list_unauth,
    
    
    rates = rate_routes.get_rates,
    save_rates = rate_routes.save_rates,
    delete_all_rates = rate_routes.delete_all_rates,
    pause_limit = rate_routes.get_pause_limit,
    set_pause_limit = rate_routes.set_pause_limit,
    autopause_config = rate_routes.handle_autopause_config,
    
    
    generate_vouchers = voucher_routes.generate,
    list_vouchers = voucher_routes.list_vouchers,
    delete_vouchers = voucher_routes.delete_vouchers,
    export_vouchers = voucher_routes.export_vouchers,
    
    
    license_activate = license_routes.activate_license,
    license_status = license_routes.get_license_status,
    remove_license = license_routes.remove_license,
    recover_license = license_routes.recover_license,
    
    
    
    
    reboot = ops_routes.reboot,
    get_ssid = ops_routes.get_ssid,
    set_ssid = ops_routes.set_ssid,
    wan_status = ops_routes.wan_status,
    save_speed_limit = ops_routes.save_speed_limit,
    get_tethering = ops_routes.get_tethering_config,
    set_tethering = ops_routes.set_tethering_config,
    get_validity = ops_routes.get_validity_config,
    set_validity = ops_routes.set_validity_config,
    get_data = ops_routes.get_data_config,
    set_data = ops_routes.set_data_config,
    get_hide_insert = ops_routes.get_hide_insert_config,
    set_hide_insert = ops_routes.set_hide_insert_config,
    get_buy_data = ops_routes.get_buy_data_config,
    set_buy_data = ops_routes.set_buy_data_config,
    get_wipass = ops_routes.get_wipass_config,
    set_wipass = ops_routes.set_wipass_config,
    get_insert_config = ops_routes.get_insert_config,
    set_insert_config = ops_routes.set_insert_config,

    upload_banner = ops_routes.upload_banner,
    upload_audio = ops_routes.upload_audio,
    restore_default_banner = ops_routes.restore_default_banner,
    get_portal_media = ops_routes.get_portal_media,
    get_esp_wifi = ops_routes.get_esp_wifi,
    set_esp_wifi = ops_routes.set_esp_wifi,

    sales_data = ops_routes.sales_data,
    sales_history = ops_routes.sales_history,
    sales_totals = ops_routes.sales_totals,
    delete_sales = ops_routes.delete_sales,
    wan_apply = ops_routes.wan_apply,
    wan_sqm_apply = ops_routes.wan_sqm_apply,
    remote_access = ts_routes.status or ops_routes.remote_access_status,
    remote_access_connect = ts_routes.up or ops_routes.remote_access_connect,
    remote_access_disconnect = ts_routes.down or ops_routes.remote_access_disconnect,
    remote_access_enroll = ts_routes.up or ops_routes.remote_access_enroll,
    tailscale_status = ts_routes.status,
    tailscale_install = ts_routes.install,
    tailscale_up = ts_routes.up,
    tailscale_down = ts_routes.down,
    check_update = ops_routes.check_update,
    update_progress = ops_routes.update_progress,
    proceed_update = ops_routes.proceed_update,
    upload_firmware = ops_routes.upload_firmware,
    flash_firmware = ops_routes.flash_firmware,
    upload_oem_firmware = ops_routes.upload_oem_firmware,
    validate_oem_firmware = ops_routes.validate_oem_firmware,
    cancel_oem_firmware = ops_routes.cancel_oem_firmware,
    flash_oem_firmware = ops_routes.flash_oem_firmware,

    
    backup_now = ops_routes.backup_now,
    list_backups = ops_routes.list_backups,
    restore_backup = ops_routes.restore_backup,
    delete_backup = ops_routes.delete_backup,
    rollback_status = ops_routes.rollback_status,
    
    
    firewall_status = firewall_routes.firewall_status,
    apply_firewall_enhanced = firewall_routes.apply_firewall_enhanced,
    reset_firewall = firewall_routes.reset_firewall,
    rate_limit_stats = firewall_routes.rate_limit_stats,
    
    
    database_stats = database_routes.database_stats,
    optimize_database = database_routes.optimize_database,
    slow_queries = database_routes.slow_queries,
    archive_data = database_routes.archive_data,



    
    dhcp_leases          = dhcp_routes.dhcp_leases,
    dhcp_static_list     = dhcp_routes.dhcp_static_list,
    dhcp_static_add      = dhcp_routes.dhcp_static_add,
    dhcp_static_delete   = dhcp_routes.dhcp_static_delete,
    dhcp_pools           = dhcp_routes.dhcp_pools,
    dhcp_pool_save       = dhcp_routes.dhcp_pool_save,

    
    shield_status            = shield_routes.shield_status,
    shield_get_lists        = shield_routes.shield_get_lists,
    shield_add_blocked      = shield_routes.shield_add_blocked,
    shield_remove_blocked   = shield_routes.shield_remove_blocked,
    shield_add_allowed      = shield_routes.shield_add_allowed,
    shield_remove_allowed   = shield_routes.shield_remove_allowed,
    shield_toggle_starlink  = shield_routes.shield_toggle_starlink,
    shield_toggle_force_dns = shield_routes.shield_toggle_force_dns,
    shield_toggle_doh       = shield_routes.shield_toggle_doh,
    shield_toggle_quic      = shield_routes.shield_toggle_quic,
    shield_apply            = shield_routes.shield_apply,
    shield_starlink_sync_now = shield_routes.shield_starlink_sync_now,

    
    
    gcash_config_get    = gcash_routes.get_config,
    gcash_config_set    = gcash_routes.set_config,
    gcash_generate_pool = gcash_routes.generate_pool,
    gcash_export_pool   = gcash_routes.export_pool,
    gcash_public_config = gcash_routes.public_config,
    gcash_upload_qr     = gcash_routes.upload_qr,
    gcash_generate_secret = gcash_routes.generate_secret,
    gcash_order         = gcash_routes.create_order,
    gcash_claim_by_amount = gcash_routes.claim_by_amount,
    gcash_freewindow    = gcash_routes.freewindow,

    -- Plans / profiles / clients
    list_profiles = plans_routes.list_profiles,
    save_profile = plans_routes.save_profile,
    delete_profile = plans_routes.delete_profile,
    list_plans = plans_routes.list_plans,
    save_plan = plans_routes.save_plan,
    delete_plan = plans_routes.delete_plan,
    list_plan_clients = plans_routes.list_plan_clients,
    save_plan_client = plans_routes.save_plan_client,
    delete_plan_client = plans_routes.delete_plan_client,
    attach_plan_device = plans_routes.attach_plan_device,
    detach_plan_device = plans_routes.detach_plan_device,
    activate_plan = plans_routes.activate_plan,

    -- Devices / MAC block / waiting
    list_devices = devices_routes.list_devices,
    list_mac_blocks = devices_routes.list_mac_blocks,
    block_mac = devices_routes.block_mac,
    unblock_mac = devices_routes.unblock_mac,
    waiting_queue = devices_routes.waiting_queue,

    -- Ext: users, branding, radio, reports, pricing
    list_admin_users = ext_routes.list_admin_users,
    create_admin_user = ext_routes.create_admin_user,
    delete_admin_user = ext_routes.delete_admin_user,
    get_role_permissions = ext_routes.get_role_permissions,
    set_role_permissions = ext_routes.set_role_permissions,
    activity_feed = ext_routes.activity_feed,
    audit_feed = ext_routes.audit_feed,
    get_branding = ext_routes.get_branding,
    set_branding = ext_routes.set_branding,
    upload_logo = ext_routes.upload_logo,
    clear_logo = ext_routes.clear_logo,
    radio_status = ext_routes.radio_status,
    radio_restart = ext_routes.radio_restart,
    sales_by_vendo = ext_routes.sales_by_vendo,
    reports_summary = ext_routes.reports_summary,
    sms_test = ext_routes.sms_test,
    pricing_hub = ext_routes.pricing_hub,

    -- Access Points + redesigned dashboard overview
    list_access_points = ap_routes.list_access_points,
    save_access_point = ap_routes.save_access_point,
    delete_access_point = ap_routes.delete_access_point,
    bind_esp_to_ap = ap_routes.bind_esp_to_ap,
    dashboard_overview = ap_routes.dashboard_overview

}

local public_routes = {
    checkDevice = true,
    device_status = true,
    internet_status = true,
    getMac = true,
    session_status = true,
    internet = true,
    updateDevice = true,
    voucher = true,
    clearcredit = true,
    terminate = true,
    classic = true,
    insertcoin = true,
    lockcoin = true,
    fetchcoin = true,
    register_esp_slot = true,
    esp_status = true,
    admin_login = true,
    recover_admin_password = true,
    license_activate = true,
    rates = true,
    check_coin_lock = true,
    unlockcoin = true,
    list_esp_devices = true,


    
    
    gcash_public_config = true,
    gcash_order = true,
    gcash_claim_by_amount = true,
    gcash_freewindow = true,
    get_branding = true,
    get_portal_media = true

}


function M.dispatch()
    local req = request_parser.parse()
    
    if not req.action then
        response_formatter.send(response_formatter.error("Missing action parameter"))
        return
    end
    
    
    if not public_routes[req.action] then
        if not security.check_admin_session() then
            response_formatter.send({
                status = "error",
                message = "Unauthorized. Please log in.",
                code = 401
            })
            return
        end
    end

    
    local client_transaction_routes = {
        updateDevice = true,
        voucher = true,
        lockcoin = true,
        insertcoin = true,
        gcash_order = true,
        gcash_freewindow = true,
        classic = true
    }

    if client_transaction_routes[req.action] then
        local config_db_helper = require("fastfi.db.config")
        local lic = config_db_helper.get_license_info()
        if lic.license_status ~= "active" then
            response_formatter.send({
                status = "error",
                message = "System inactive. A valid license is required to connect.",
                license_status = "inactive"
            })
            return
        end
    end
    
    
    local handler = routes[req.action]
    
    if handler then
        local ok, result = pcall(handler, req.params, req)
        
        if not ok then
            response_formatter.send(response_formatter.error("Internal error: " .. tostring(result)))
            return
        end
        
        response_formatter.send(result)
    else
        
        response_formatter.send({
            status = "error",
            message = "API Route Not Found: " .. tostring(req.action),
            code = 404
        })
    end
end

return M
