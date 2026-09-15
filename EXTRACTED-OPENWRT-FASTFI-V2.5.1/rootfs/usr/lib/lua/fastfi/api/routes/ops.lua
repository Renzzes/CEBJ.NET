
local security = require("fastfi.security")
local file_util = require("fastfi.util.file")
local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")
local config_db = require("fastfi.db.config")
local M = {}

function M.reboot(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    
    os.execute("sync")
    
    
    os.execute("(sleep 1 && reboot) &")
    
    return { status = "ok", message = "Rebooting..." }
end

function M.get_ssid(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    
    local ssid24_cmd = io.popen("uci get wireless.@wifi-iface[0].ssid 2>/dev/null")
    local ssid24 = ssid24_cmd and ssid24_cmd:read("*a") or ""
    if ssid24_cmd then ssid24_cmd:close() end
    ssid24 = ssid24:gsub("%s+", "")
    
    local ssid5_cmd = io.popen("uci get wireless.@wifi-iface[1].ssid 2>/dev/null")
    local ssid5 = ssid5_cmd and ssid5_cmd:read("*a") or ""
    if ssid5_cmd then ssid5_cmd:close() end
    ssid5 = ssid5:gsub("%s+", "")
    
    return {
        status = "ok",
        ssid24 = ssid24 ~= "" and ssid24 or "KonekSik-Fi-2.4G",
        ssid5 = ssid5 ~= "" and ssid5 or "KonekSik-Fi-5G"
    }
end

function M.set_ssid(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local ssid24 = params["ssid24"] or ""
    local ssid5 = params["ssid5"] or ""
    
    
    if ssid24:match('["\\$`{|}]') then
        return { status = "error", message = "Invalid characters in 2.4GHz SSID" }
    end
    if ssid5:match('["\\$`{|}]') then
        return { status = "error", message = "Invalid characters in 5GHz SSID" }
    end
    
    
    ssid24 = ssid24:sub(1, 32)
    ssid5 = ssid5:sub(1, 32)
    
    
    os.execute(string.format("uci set wireless.@wifi-iface[0].ssid=%s", security.shell_quote(ssid24)))
    os.execute(string.format("uci set wireless.@wifi-iface[1].ssid=%s", security.shell_quote(ssid5)))
    
    local commit_result = os.execute("uci commit wireless 2>/dev/null")
    
    if commit_result == 0 then
        
        os.execute("(wifi reload >/dev/null 2>&1; sleep 2; " ..
            "iptables -t nat -C POSTROUTING -s 10.0.0.0/24 -o wan -j MASQUERADE 2>/dev/null || " ..
            "iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o wan -j MASQUERADE; " ..
            "/usr/libexec/fastfi/core/nds-reauth.sh) &")
        return { status = "ok", message = "SSIDs updated successfully" }
    else
        return { status = "error", message = "Failed to apply WiFi settings" }
    end
end



function M.get_esp_wifi(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end

    
    local function uci_get(key)
        local cmd = io.popen("uci get " .. key .. " 2>/dev/null")
        local val = cmd and cmd:read("*a") or ""
        if cmd then cmd:close() end
        return val:gsub("%s+", "")
    end

    local ssid = uci_get("wireless.espwifi.ssid")
    local key = uci_get("wireless.espwifi.key")
    local disabled = uci_get("wireless.espwifi.disabled")

    return {
        status = "ok",
        esp_ssid = ssid,
        esp_password = key,
        enabled = (disabled ~= "1" and ssid ~= "")
    }
end

function M.set_esp_wifi(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end

    local ssid = params["ssid"] or ""
    local password = params["password"] or ""

    if ssid == "" then
        return { status = "error", message = "SSID is required" }
    end

    
    if ssid:match('[\'\"\\$`{|}]') then
        return { status = "error", message = "Invalid characters in SSID" }
    end

    
    if password ~= "" then
        if #password < 8 or #password > 63 then
            return { status = "error", message = "Password must be 8-63 characters for WPA2" }
        end
        if password:match('[\'\"\\$`{|}]') then
            return { status = "error", message = "Invalid characters in password" }
        end
    end

    
    ssid = ssid:sub(1, 32)

    
    
    local exists_cmd = io.popen("uci -q get wireless.espwifi.ssid 2>/dev/null")
    local exists = exists_cmd and exists_cmd:read("*a") or ""
    if exists_cmd then exists_cmd:close() end
    exists = exists:gsub("%s+", "")

    if exists == "" then
        
        os.execute("uci set wireless.espwifi=wifi-iface")
        os.execute("uci set wireless.espwifi.device='radio0'")
        os.execute("uci set wireless.espwifi.mode='ap'")
        os.execute("uci set wireless.espwifi.network='lan'")
        os.execute("uci set wireless.espwifi.hidden='1'")
    end

    
    os.execute(string.format("uci set wireless.espwifi.ssid=%s", security.shell_quote(ssid)))
    os.execute("uci set wireless.espwifi.disabled='0'")

    if password ~= "" then
        os.execute("uci set wireless.espwifi.encryption='psk2'")
        os.execute(string.format("uci set wireless.espwifi.key=%s", security.shell_quote(password)))
    else
        os.execute("uci set wireless.espwifi.encryption='none'")
        os.execute("uci delete wireless.espwifi.key 2>/dev/null")
    end

    local commit_result = os.execute("uci commit wireless 2>/dev/null")

    
    local db_ssid = ssid:gsub("'", "''")
    local db_pass = password:gsub("'", "''")
    os.execute(string.format(
        "sqlite3 /www/data/bindcode.db \"UPDATE config SET wifi_private_ssid='%s', wifi_private_pass='%s' WHERE id=1;\"",
        db_ssid, db_pass
    ))

    if commit_result == 0 then
        
        os.execute("(wifi reload >/dev/null 2>&1) &")
        return { status = "ok", message = "ESP WiFi saved and applied!" }
    else
        return { status = "error", message = "Failed to apply ESP WiFi settings" }
    end
end




local function get_sqm_iface()
    
    local pp = io.popen("uci -q get network.wan.proto 2>/dev/null")
    if pp then
        local pr = (pp:read("*a") or ""):gsub("%s+", "")
        pp:close()
        if pr == "pppoe" then return "pppoe-wan" end
    end
    
    local f = io.popen("uci -q show sqm 2>/dev/null | grep '=queue' | head -1 | cut -d. -f2 | cut -d= -f1")
    if f then
        local iface = f:read("*a")
        f:close()
        iface = (iface or ""):gsub("%s+", "")
        if #iface > 0 then return iface end
    end
    
    local w = io.popen("uci -q get network.wan.device 2>/dev/null || uci -q get network.wan.ifname 2>/dev/null")
    if w then
        local dev = w:read("*a")
        w:close()
        dev = (dev or ""):gsub("%s+", "")
        if #dev > 0 then return dev end
    end
    
    return "eth1"
end



function M.wan_status(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end

    
    local remote_addr = os.getenv("REMOTE_ADDR") or ""
    local route_check = io.popen(string.format("ip route get %s 2>/dev/null", remote_addr))
    local is_lan = "false"
    if route_check then
        local out = route_check:read("*a")
        route_check:close()
        if out and (out:match("br%-hotspot") or out:match("br%-lan")) then
            is_lan = "true"
        end
    end

    if is_lan ~= "true" then
        return { lan = false }
    end

    
    local proto_cmd = io.popen("uci get network.wan.proto 2>/dev/null")
    local proto = proto_cmd and proto_cmd:read("*a") or "unknown"
    if proto_cmd then proto_cmd:close() end
    proto = proto:gsub("%s+", "")

    
    local ip_cmd = io.popen("ifstatus wan 2>/dev/null | jsonfilter -e '@[\"ipv4-address\"][0].address'")
    local ip = ip_cmd and ip_cmd:read("*a") or "none"
    if ip_cmd then ip_cmd:close() end
    ip = ip:gsub("%s+", "")
    
    
    local sqm_enabled = "0"
    local sqm_dl = 0
    local sqm_ul = 0
    local active_iface = "wan"

    
    local raw_sqm = ""
    local f_sqm = io.popen("/sbin/uci -q show sqm")
    if f_sqm then
        raw_sqm = f_sqm:read("*a")
        f_sqm:close()
    end

    
    local priority_ifaces = {"wan", "eth1", "eth0", get_sqm_iface()}
    
    
    for _, target in ipairs(priority_ifaces) do
        if target and target ~= "" then
            
            local en_pat = "sqm%." .. target .. "%.enabled=['\"]?([%w]+)['\"]?"
            local en_val = raw_sqm:match(en_pat)
            
            if en_val == "1" or en_val == "on" or en_val == "true" or en_val == "enabled" then
                sqm_enabled = "1"
                active_iface = target
                
                
                sqm_dl = tonumber(raw_sqm:match("sqm%." .. target .. "%.download=['\"]?(%d+)['\"]?")) or 0
                sqm_ul = tonumber(raw_sqm:match("sqm%." .. target .. "%.upload=['\"]?(%d+)['\"]?")) or 0
                break 
            end
        end
    end

    
    if sqm_dl == 0 or sqm_ul == 0 then
        for _, target in ipairs(priority_ifaces) do
            if target and target ~= "" then
                local d = tonumber(raw_sqm:match("sqm%." .. target .. "%.download=['\"]?(%d+)['\"]?")) or 0
                local u = tonumber(raw_sqm:match("sqm%." .. target .. "%.upload=['\"]?(%d+)['\"]?")) or 0
                if d > 0 and sqm_dl == 0 then sqm_dl = d end
                if u > 0 and sqm_ul == 0 then sqm_ul = u end
            end
        end
    end

    
    local def_dl = 5
    local def_ul = 5
    local speed_file = file_util.read("/etc/fastfi/client_speed")
    if speed_file then
        def_dl, def_ul = speed_file:match("^(%d+)|(%d+)$")
        def_dl = tonumber(def_dl) or 5
        def_ul = tonumber(def_ul) or 5
    end

    
    local raw_cmd = io.popen(string.format("uci -q show sqm.%s", active_iface))
    local raw_out = raw_cmd and raw_cmd:read("*a") or "no-config"
    if raw_cmd then raw_cmd:close() end

    
    local vlan_row = sqlite.query_row(config.CONFIG_DB, "SELECT wan_mode, vlan_id FROM config LIMIT 1;")
    local wan_mode = vlan_row and vlan_row[1] or "standard"
    local vlan_id = tonumber(vlan_row and vlan_row[2])

    
    
    
    
    
    
    local pppoe_installed = (os.execute("opkg list-installed 2>/dev/null | grep -q '^ppp-mod-pppoe '") == 0
        and os.execute("opkg list-installed 2>/dev/null | grep -q '^kmod-pppoe '") == 0)
    local wan_username = ""
    local wan_mtu = ""
    if proto == "pppoe" then
        local u = io.popen("uci -q get network.wan.username 2>/dev/null")
        if u then wan_username = (u:read("*a") or ""):gsub("%s+", ""); u:close() end
        local m = io.popen("uci -q get network.wan.mtu 2>/dev/null")
        if m then wan_mtu = (m:read("*a") or ""):gsub("%s+", ""); m:close() end
    end

    return {
        lan = true,
        proto = proto,
        wan_mode = wan_mode,
        vlan_id = vlan_id,
        pppoe_installed = pppoe_installed,
        wan_username = wan_username,
        wan_mtu = wan_mtu,
        sqm_enabled = sqm_enabled,
        sqm_status = sqm_enabled,
        sqm_iface = active_iface,
        sqm_dl = tonumber(sqm_dl) or 0,
        sqm_ul = tonumber(sqm_ul) or 0,
        def_dl = def_dl,
        def_ul = def_ul,
        ip = ip,
        debug_raw = raw_out
    }
end

function M.wan_sqm_apply(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local enabled = params["enabled"] or "0"
    local download = tonumber(params["download"])
    local upload = tonumber(params["upload"])
    
    
    if enabled ~= "0" and enabled ~= "1" then
        return { status = "error", message = "enabled must be 0 or 1" }
    end
    if enabled == "1" and (not download or download < 100) then
        return { status = "error", message = "Download speed must be at least 100 Kbps" }
    end
    if enabled == "1" and (not upload or upload < 100) then
        return { status = "error", message = "Upload speed must be at least 100 Kbps" }
    end
    
    
    local iface_name = get_sqm_iface()
    local cmd = string.format("/bin/sh /usr/libexec/fastfi/core/sqm-apply.sh '%s' '%d' '%d' '%s'", 
        enabled, download or 0, upload or 0, iface_name)
    
    os.execute(cmd)
    
    return {
        status = "ok",
        message = enabled == "1"
            and string.format("SQM enabled on %s: %d/%d Kbps (CAKE)", iface_name, download, upload)
            or "SQM disabled"
    }
end

function M.upload_banner(params, req)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    if not req or not req.post_body or #req.post_body == 0 then
        return { status = "error", message = "Empty file upload" }
    end
    
    
    if #req.post_body > 5 * 1024 * 1024 then
        return { status = "error", message = "File too large. Max 5MB allowed." }
    end
    
    local target_file = "/www/image/banner.jpg"
    
    
    os.execute("mkdir -p /www/image 2>/dev/null")
    
    local ok = file_util.write(target_file, req.post_body)
    if ok then
        -- Marker distinguishes custom upload from factory Default-Banner.png
        file_util.write("/www/image/.custom_banner", "1")
        return { status = "ok", message = "Banner uploaded successfully!", custom = 1 }
    else
        return { status = "error", message = "Failed to write file to storage" }
    end
end

function M.restore_default_banner(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end

    os.execute("rm -f /www/image/.custom_banner /www/image/banner.jpg 2>/dev/null")
    -- Ensure factory default asset is present for portal + admin preview
    local default_src = "/www/image/Default-Banner.png"
    local f = io.open(default_src, "rb")
    if not f then
        f = io.open("/www/Default-Banner.png", "rb")
        if f then
            local data = f:read("*a")
            f:close()
            os.execute("mkdir -p /www/image 2>/dev/null")
            file_util.write(default_src, data or "")
        end
    else
        f:close()
    end

    return {
        status = "ok",
        message = "Restored Default-Banner.png",
        custom = 0,
        default_banner_url = "/image/Default-Banner.png"
    }
end

--- Public: captive portal + admin read banner/music paths (FastFi-aligned).
function M.get_portal_media(params)
    local now = tostring(os.time())
    local has_custom_banner = file_util.exists("/www/image/.custom_banner")
        and file_util.exists("/www/image/banner.jpg")

    local default_banner = "/image/Default-Banner.png"
    if not file_util.exists("/www/image/Default-Banner.png") then
        if file_util.exists("/www/Default-Banner.png") then
            default_banner = "/Default-Banner.png"
        end
    end

    local banner_url = default_banner .. "?t=" .. now
    if has_custom_banner then
        banner_url = "/image/banner.jpg?t=" .. now
    end

    local function pick_audio(abs_path, url_path, local_fallback)
        if file_util.exists(abs_path) then
            return url_path .. "?t=" .. now, true
        end
        return local_fallback, false
    end

    local bg_url, has_bg = pick_audio("/www/audio/insert.mp3", "/audio/insert.mp3", "bg_music.mp3")
    local coin_url = select(1, pick_audio("/www/audio/coin.mp3", "/audio/coin.mp3", "coin.mp3"))
    local success_url = select(1, pick_audio("/www/audio/success.mp3", "/audio/success.mp3", "success.mp3"))

    local banner_text = "Insert coin or enter voucher to start"
    local row = sqlite.query_row(config.CONFIG_DB, "SELECT banner_text FROM config LIMIT 1")
    if row and row[1] and row[1] ~= "" then
        banner_text = row[1]
    end

    local shop_name = ""
    local brand = sqlite.query_row(config.CONFIG_DB, "SELECT shop_name FROM config LIMIT 1")
    if brand and brand[1] then shop_name = brand[1] end

    return {
        status = "ok",
        has_custom_banner = has_custom_banner and 1 or 0,
        banner_url = banner_url,
        default_banner_url = default_banner,
        has_custom_music = has_bg and 1 or 0,
        music_url = bg_url,
        bg_music_url = bg_url,
        coin_url = coin_url,
        success_url = success_url,
        banner_text = banner_text,
        shop_name = shop_name,
        brand_name = (shop_name ~= "" and shop_name) or "KonekSik-fi"
    }
end

function M.upload_audio(params, req)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    if not req or not req.post_body or #req.post_body == 0 then
        return { status = "error", message = "Empty file upload" }
    end
    
    
    if #req.post_body > 3 * 1024 * 1024 then
        return { status = "error", message = "File too large. Max 3MB allowed." }
    end
    
    local audio_type = params["type"] or "bg"
    local filename = "insert.mp3"
    
    if audio_type == "coin" then
        filename = "coin.mp3"
    elseif audio_type == "success" then
        filename = "success.mp3"
    end
    
    local target_file = "/www/audio/" .. filename
    
    
    os.execute("mkdir -p /www/audio 2>/dev/null")
    
    local ok = file_util.write(target_file, req.post_body)
    if ok then
        return { status = "ok", message = "Audio uploaded successfully!" }
    else
        return { status = "error", message = "Failed to write file to storage" }
    end
end

function M.wan_apply(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end

    local proto = params["proto"]
    if not proto or proto == "" then
        return { status = "error", message = "Protocol required" }
    end
    
    
    if proto ~= "dhcp" and proto ~= "static" and proto ~= "pppoe" then
        return { status = "error", message = "Invalid protocol" }
    end

    
    local vlan_row = sqlite.query_row(config.CONFIG_DB, "SELECT wan_mode, vlan_id FROM config LIMIT 1;")
    local wan_mode = vlan_row and vlan_row[1] or "standard"
    local vlan_id = tonumber(vlan_row and vlan_row[2])

    
    local wan_base = "eth0"
    local f = io.popen("uci -q get network.wan.device 2>/dev/null || echo ''")
    local current_dev = f and f:read("*a") or ""
    if f then f:close() end
    current_dev = current_dev:gsub("%s+", "")
    if current_dev ~= "" then
        
        wan_base = current_dev:match("^([^.]+)") or current_dev
    else
        
        local p = io.popen("ls /sys/class/net/ 2>/dev/null")
        if p then
            for dev in p:lines() do
                if dev ~= "lo" and not dev:match("^br%-") and not dev:match("^tun")
                   and not dev:match("^wlan") and not dev:match("^wl") and not dev:match("%.[0-9]+") then
                    if dev:match("^eth") then
                        wan_base = dev
                        break
                    end
                end
            end
            p:close()
        end
    end

    
    
    
    local wan_dev = wan_base
    local br_lan_port = nil

    
    
    
    
    
    
    
    local net_util = require("fastfi.util.network")
    local is_dsa = net_util.is_dsa()

    
    
    
    
    
    
    if is_dsa then
        wan_dev = net_util.wan_port() or "wan"
    end

    if wan_mode == "vlan" and vlan_id then
        br_lan_port = wan_base .. "." .. vlan_id
    else
        
        
        
        if not is_dsa then
            local p = io.popen("ls /sys/class/net/ 2>/dev/null")
            if p then
                for dev in p:lines() do
                    if dev ~= "lo" and not dev:match("^br%-") and not dev:match("^tun")
                       and not dev:match("^wlan") and not dev:match("^wl") and not dev:match("%.[0-9]+") then
                        if dev ~= wan_base and dev:match("^eth") then
                            br_lan_port = dev
                            break
                        end
                    end
                end
                p:close()
            end
        end
    end

    os.execute(string.format("uci set network.wan.device=%s", security.shell_quote(wan_dev)))

    
    os.execute("uci -q delete network.outdoor 2>/dev/null")

    
    os.execute("uci set network.br_lan=device")
    os.execute("uci set network.br_lan.name='br-lan'")
    os.execute("uci set network.br_lan.type='bridge'")
    os.execute("uci set network.lan.device='br-lan'")

    
    
    
    if not is_dsa then
        if br_lan_port then
            os.execute(string.format("uci set network.br_lan.ports=%s", security.shell_quote(br_lan_port)))
        else
            os.execute("uci set network.br_lan.ports=''")
        end
    end
    

    
    
    
    
    if proto == "pppoe" then
        os.execute("uci -q delete network.wan.ipaddr 2>/dev/null")
        os.execute("uci -q delete network.wan.netmask 2>/dev/null")
        os.execute("uci -q delete network.wan.gateway 2>/dev/null")
        os.execute("uci -q delete network.wan.dns 2>/dev/null")
    else
        os.execute("uci -q delete network.wan.username 2>/dev/null")
        os.execute("uci -q delete network.wan.password 2>/dev/null")
        os.execute("uci -q delete network.wan.mtu 2>/dev/null")
        os.execute("uci -q delete network.wan.peerdns 2>/dev/null")
        os.execute("uci -q delete network.wan.ipv6 2>/dev/null")
    end

    
    
    
    
    
    
    
    if proto == "pppoe" then
        local function has_pkg(pkg)
            return os.execute("opkg list-installed 2>/dev/null | grep -q '^" .. pkg .. " '") == 0
        end
        
        
        
        
        
        
        
        
        local pkgs_ok = has_pkg("ppp-mod-pppoe") and has_pkg("kmod-pppoe")
        if not pkgs_ok then
            
            
            os.execute("sed -i 's|https://|http://|g' /etc/opkg/distfeeds.conf 2>/dev/null")
            os.execute("opkg update >/dev/null 2>&1")
            os.execute("opkg install ppp ppp-mod-pppoe kmod-pppoe >/dev/null 2>&1")
            pkgs_ok = has_pkg("ppp-mod-pppoe") and has_pkg("kmod-pppoe")
        end
        os.execute("modprobe pppoe 2>/dev/null || true")
        
        local module_loaded = (os.execute("test -d /sys/module/pppoe 2>/dev/null") == 0)
        if not (pkgs_ok and module_loaded) then
            return { status = "error",
                message = "Could not install PPPoE support. The router needs ppp, ppp-mod-pppoe and kmod-pppoe; the kernel module often fails to install via opkg if this box's kernel doesn't match the package repo. Make sure the router is online via DHCP and retry, or reflash the latest firmware image (which bakes the packages in)." }
        end
    end

    os.execute(string.format("uci set network.wan.proto=%s", security.shell_quote(proto)))

    if proto == "static" then
        local ip = params["ipaddr"]
        local netmask = params["netmask"]
        local gateway = params["gateway"]
        local dns = params["dns"]
        
        
        
        local function valid_dns_list(s)
            local saw = false
            for tok in tostring(s):gmatch("%S+") do
                saw = true
                if not security.is_valid_ip(tok) then return false end
            end
            return saw
        end
        if ip and not security.is_valid_ip(ip) then
            return { status = "error", message = "Invalid WAN IP address" }
        end
        if netmask and not security.is_valid_ip(netmask) then
            return { status = "error", message = "Invalid WAN netmask" }
        end
        if gateway and not security.is_valid_ip(gateway) then
            return { status = "error", message = "Invalid WAN gateway" }
        end
        if dns and not valid_dns_list(dns) then
            return { status = "error", message = "Invalid WAN DNS server" }
        end
        if ip then os.execute(string.format("uci set network.wan.ipaddr=%s", security.shell_quote(ip))) end
        if netmask then os.execute(string.format("uci set network.wan.netmask=%s", security.shell_quote(netmask))) end
        if gateway then os.execute(string.format("uci set network.wan.gateway=%s", security.shell_quote(gateway))) end
        if dns then os.execute(string.format("uci set network.wan.dns=%s", security.shell_quote(dns))) end
    elseif proto == "pppoe" then
        local user = params["user"] or ""
        local pass = params["pass"] or ""
        local mtu = params["mtu"] or "1492"
        
        
        if user:match("['\"`$|;]") or pass:match("['\"`$|;]") then
            return { status = "error", message = "Invalid characters in PPPoE username or password" }
        end
        local mtu_n = tonumber(mtu)
        if not mtu_n or mtu_n < 576 or mtu_n > 1500 then
            return { status = "error", message = "MTU must be between 576 and 1500" }
        end
        if user ~= "" then os.execute(string.format("uci set network.wan.username=%s", security.shell_quote(user))) end
        if pass ~= "" then os.execute(string.format("uci set network.wan.password=%s", security.shell_quote(pass))) end
        os.execute(string.format("uci set network.wan.mtu='%d'", mtu_n))
        os.execute("uci set network.wan.peerdns='1'")
        os.execute("uci set network.wan.ipv6='0'")
    end

    
    
    
    
    
    net_util.heal_br_lan()
    net_util.heal_wan_device()

    local commit_result = os.execute("uci commit network 2>/dev/null")

    if commit_result == 0 then
        local actual_wan_dev = "wan"
        local w = io.popen("uci -q get network.wan.device 2>/dev/null || echo 'wan'")
        if w then actual_wan_dev = w:read("*a"):gsub("%s+", ""); w:close() end
        
        
        
        local masq_dev = actual_wan_dev
        if proto == "pppoe" then masq_dev = "pppoe-wan" end
        
        os.execute("(sleep 1 && /etc/init.d/network restart; sleep 2; " ..
            "/etc/init.d/dnsmasq restart 2>/dev/null; " ..
            "iptables -t nat -C POSTROUTING -s 10.0.0.0/24 -o " .. masq_dev .. " -j MASQUERADE 2>/dev/null || " ..
            "iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o " .. masq_dev .. " -j MASQUERADE; " ..
            "/usr/libexec/fastfi/core/nds-reauth.sh) &")
        return { status = "ok", message = "WAN settings applied. Restarting network..." }
    else
        return { status = "error", message = "Failed to apply WAN settings" }
    end
end

function M.sales_totals(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local db = config.SESSIONS_DB
    local now = os.time()
    
    
    local h = tonumber(os.date("%H")) or 0
    local m = tonumber(os.date("%M")) or 0
    local s = tonumber(os.date("%S")) or 0
    local seconds_since_midnight = h * 3600 + m * 60 + s
    local day_start = now - seconds_since_midnight
    local row = sqlite.query_row(db, string.format("SELECT COALESCE(SUM(amount),0) FROM sales WHERE created_at >= %d;", day_start))
    local daily_total = tonumber(row and row[1]) or 0
    
    
    local week_start = day_start - (6 * 86400)
    row = sqlite.query_row(db, string.format("SELECT COALESCE(SUM(amount),0) FROM sales WHERE created_at >= %d;", week_start))
    local weekly_total = tonumber(row and row[1]) or 0
    
    
    local year = tonumber(os.date("%Y")) or 2024
    local month = tonumber(os.date("%m")) or 1
    local month_start = os.time{year=year, month=month, day=1, hour=0, min=0, sec=0}
    row = sqlite.query_row(db, string.format("SELECT COALESCE(SUM(amount),0) FROM sales WHERE created_at >= %d;", month_start))
    local monthly_total = tonumber(row and row[1]) or 0
    
    
    row = sqlite.query_row(db, "SELECT COALESCE(SUM(amount),0) FROM sales;")
    local total_all = tonumber(row and row[1]) or 0
    
    return {
        status = "ok",
        daily = daily_total,
        weekly = weekly_total,
        monthly = monthly_total,
        total = total_all
    }
end

function M.delete_sales(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local cmd = params["cmd"]
    local db = config.SESSIONS_DB
    
    if cmd == "delete_day" then
        local date_str = params["date"]
        if not date_str then return { status = "error", message = "Missing date" } end
        local y, m, d = date_str:match("(%d+)-(%d+)-(%d+)")
        if not y then return { status = "error", message = "Invalid date format" } end
        
        local start_ts = os.time{year=y, month=m, day=d, hour=0, min=0, sec=0}
        local end_ts = start_ts + 86399
        sqlite.execute(db, string.format("DELETE FROM sales WHERE created_at >= %d AND created_at <= %d;", start_ts, end_ts))
        
    elseif cmd == "delete_range" then
        local start_str = params["date_start"]
        local end_str = params["date_end"]
        if not start_str or not end_str then return { status = "error", message = "Missing dates" } end
        
        local sy, sm, sd = start_str:match("(%d+)-(%d+)-(%d+)")
        local ey, em, ed = end_str:match("(%d+)-(%d+)-(%d+)")
        
        if not sy or not ey then return { status = "error", message = "Invalid date format" } end
        
        local start_ts = os.time{year=sy, month=sm, day=sd, hour=0, min=0, sec=0}
        local end_ts = os.time{year=ey, month=em, day=ed, hour=23, min=59, sec=59}
        sqlite.execute(db, string.format("DELETE FROM sales WHERE created_at >= %d AND created_at <= %d;", start_ts, end_ts))
        
    elseif cmd == "clear_monthly" then
        local year = tonumber(os.date("%Y")) or 2024
        local month = tonumber(os.date("%m")) or 1
        local start_ts = os.time{year=year, month=month, day=1, hour=0, min=0, sec=0}
        sqlite.execute(db, string.format("DELETE FROM sales WHERE created_at >= %d;", start_ts))
        
    elseif cmd == "clear_all" then
        sqlite.execute(db, "DELETE FROM sales;")
        sqlite.execute(db, "DELETE FROM esp_transactions;")
    else
        return { status = "error", message = "Invalid command" }
    end
    
    return { status = "ok", message = "Sales records deleted" }
end

function M.sales_data(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local filter = params["filter"] or "week"
    local db = config.SESSIONS_DB
    local now = os.time()
    
    if filter == "day" then
        
        local h = tonumber(os.date("%H")) or 0
        local m = tonumber(os.date("%M")) or 0
        local s = tonumber(os.date("%S")) or 0
        local seconds_since_midnight = h * 3600 + m * 60 + s
        local day_start = now - seconds_since_midnight
        
        local labels = {}
        local data = {}
        
        for i = 0, 23 do
            local hour_start = day_start + i * 3600
            local hour_end = hour_start + 3599
            
            local row = sqlite.query_row(db,
                string.format("SELECT COALESCE(SUM(amount),0) FROM sales WHERE created_at >= %d AND created_at <= %d;",
                    hour_start, hour_end))
            local val = tonumber(row and row[1]) or 0
            
            table.insert(labels, string.format("%02d:00", i))
            table.insert(data, val)
        end
        
        return { labels = labels, data = data }
        
    elseif filter == "month" then
        
        local year = tonumber(os.date("%Y")) or 2024
        local month = tonumber(os.date("%m")) or 1
        local days_in_month = os.date("*t", os.time{year=year, month=month+1, day=0}).day
        
        local labels = {}
        local data = {}
        
        for day = 1, days_in_month do
            local day_start = os.time{year=year, month=month, day=day, hour=0, min=0, sec=0}
            local day_end = day_start + 86399
            
            local row = sqlite.query_row(db,
                string.format("SELECT COALESCE(SUM(amount),0) FROM sales WHERE created_at >= %d AND created_at <= %d;",
                    day_start, day_end))
            local val = tonumber(row and row[1]) or 0
            
            table.insert(labels, tostring(day))
            table.insert(data, val)
        end
        
        return { labels = labels, data = data }
        
    elseif filter == "week" then
        
        local labels = {}
        local data = {}
        
        local h = tonumber(os.date("%H")) or 0
        local m = tonumber(os.date("%M")) or 0
        local s = tonumber(os.date("%S")) or 0
        local seconds_since_midnight = h * 3600 + m * 60 + s
        local today_start = now - seconds_since_midnight
        
        for i = 6, 0, -1 do
            local day_start = today_start - (i * 86400)
            local day_date = os.date("%Y-%m-%d", day_start)
            local day_end = day_start + 86399
            
            local row = sqlite.query_row(db,
                string.format("SELECT COALESCE(SUM(amount),0) FROM sales WHERE created_at >= %d AND created_at <= %d;",
                    day_start, day_end))
            local val = tonumber(row and row[1]) or 0
            
            table.insert(labels, day_date)
            table.insert(data, val)
        end
        
        return { labels = labels, data = data }
    else
        return { status = "error", message = "Invalid filter" }
    end
end

function M.remote_access_status(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end

    
    
    
    
    
    
    local device_online = 0
    local uh = io.popen("pidof uhttpd >/dev/null 2>&1 && echo 1 || echo 0")
    if uh then device_online = tonumber(uh:read("*a") or "0") or 0; uh:close() end

    
    
    local openvpn_running = 0
    local ov = io.popen("pgrep -x openvpn >/dev/null 2>&1 && echo 1 || echo 0")
    if ov then openvpn_running = tonumber(ov:read("*a") or "0") or 0; ov:close() end

    local vpn_ip = ""
    if openvpn_running == 1 then
        local ip_cmd = io.popen("ip -4 addr show tun0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}'")
        if ip_cmd then
            vpn_ip = (ip_cmd:read("*a") or ""):gsub("%s+", "")
            ip_cmd:close()
        end
    end

    local gw_ok = 0
    if vpn_ip ~= "" then
        local pg = io.popen("ping -c 1 -W 2 10.8.0.1 >/dev/null 2>&1 && echo 1 || echo 0")
        if pg then gw_ok = tonumber(pg:read("*a") or "0") or 0; pg:close() end
    end

    local tunnel_up = (openvpn_running == 1 and vpn_ip ~= "" and gw_ok == 1) and 1 or 0

    
    
    local tunnel_state = "down"
    if tunnel_up == 1 then
        tunnel_state = "connected"
    elseif openvpn_running == 1 then
        tunnel_state = "reconnecting"
    end

    
    
    local enrolled = file_util.exists("/etc/fastfi_enrolled")
    local remote_url = ""
    if enrolled then
        local enroll_file = file_util.read("/etc/fastfi_enrolled")
        if enroll_file then
            remote_url = enroll_file:gsub("%s+", "")
            if not remote_url:match("/admin%.html$") then
                remote_url = remote_url .. "/admin.html"
            end
        end
    end

    local token_pending = file_util.exists("/etc/fastfi_remote_token") and 1 or 0

    local enroll_error = ""
    if file_util.exists("/tmp/fastfi_enroll_error") then
        enroll_error = file_util.read("/tmp/fastfi_enroll_error") or ""
        os.execute("rm -f /tmp/fastfi_enroll_error")
    end

    return {
        
        device_online = device_online,
        tunnel_up = tunnel_up,
        tunnel_state = tunnel_state,
        openvpn_running = openvpn_running,
        
        vpn_connected = tunnel_up,
        vpn_ip = vpn_ip,
        remote_url = remote_url,
        enrolled = enrolled,
        token_pending = token_pending,
        enroll_error = enroll_error
    }
end

function M.remote_access_connect(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    
    
    local inet = file_util.execute("ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && echo 1 || echo 0")
    if tonumber(inet) ~= 1 then
        return { status = "error", message = "No internet connection. VPN requires internet to establish a tunnel." }
    end
    
    
    local ca_exists = file_util.execute("[ -s /etc/openvpn/fastfi-ca.crt ] && echo 1 || echo 0")
    if tonumber(ca_exists) ~= 1 then
        
        os.execute("mkdir -p /etc/openvpn")
        os.execute("curl --max-time 10 -s -o /etc/openvpn/fastfi-ca.crt https://fastfi.cloud/api/v1/admin/vpn/ca 2>/dev/null")
        ca_exists = file_util.execute("[ -s /etc/openvpn/fastfi-ca.crt ] && echo 1 || echo 0")
        if tonumber(ca_exists) ~= 1 then
            os.execute("rm -f /etc/openvpn/fastfi-ca.crt")
            return { status = "error", message = "Cannot download VPN certificate from fastfi.cloud. The server may be unreachable or the VPN CA endpoint is not configured." }
        end
    end
    
    
    
    
    
    os.execute("touch /etc/fastfi_vpn_enabled")
    
    
    os.execute("(/usr/libexec/fastfi/services/fastfi-vpn.sh >/dev/null 2>&1) &")
    
    
    local wait_count = 0
    local vpn_ready = 0
    
    while wait_count < 45 do
        os.execute("sleep 1")
        local ip_cmd = io.popen("ip -4 addr show tun0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}'")
        local vpn_ip = ip_cmd and ip_cmd:read("*a") or ""
        if ip_cmd then ip_cmd:close() end
        vpn_ip = vpn_ip:gsub("%s+", "")
        
        if vpn_ip ~= "" then
            vpn_ready = 1
            break
        end
        wait_count = wait_count + 1
    end
    
    if vpn_ready == 1 then
        return { status = "ok", message = "VPN connection established" }
    else
        
        local log_output = file_util.execute("logread 2>/dev/null | grep 'fastfi-vpn' | tail -3")
        local detail = ""
        if log_output and log_output ~= "" then
            detail = " Last log: " .. log_output:gsub("\n", " | ")
        end
        return { status = "error", message = "VPN failed to establish after 45s. The VPN server (147.93.158.194:1194) may be down or not accepting this device's credentials." .. detail }
    end
end

function M.remote_access_disconnect(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    
    os.remove("/etc/fastfi_vpn_enabled")
    
    
    local pid_file = "/var/run/fastfi-vpn.pid"
    local pid = file_util.read(pid_file)
    if pid then
        pid = pid:gsub("%s+", "")
        os.execute(string.format("kill %s 2>/dev/null", pid))
        os.remove(pid_file)
    end
    
    
    os.execute("pkill -f openvpn 2>/dev/null")
    
    return { status = "ok", message = "VPN disconnected" }
end

function M.remote_access_enroll(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local token = params.token
    if not token or token == "" then
        return { status = "error", message = "Token is required" }
    end
    
    
    file_util.write("/etc/fastfi_remote_token", token)
    
    
    os.execute("(/usr/libexec/fastfi/services/fastfi-vpn.sh >/dev/null 2>&1) &")
    
    return { status = "ok", message = "Enrolling device..." }
end

function M.get_tethering_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    local row = sqlite.query_row(config_db, "SELECT anti_tethering FROM config LIMIT 1")
    
    local enabled = false
    if row and tonumber(row[1]) == 1 then
        enabled = true
    end
    
    return { status = "ok", enabled = enabled }
end

function M.set_tethering_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local enabled = params.enabled == "true" or params.enabled == "1"
    local val = enabled and 1 or 0
    
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    sqlite.execute(config_db, "UPDATE config SET anti_tethering=" .. val)
    
    if enabled then
        os.execute("sh /usr/libexec/fastfi/core/fastfi-antitether.sh enable")
    else
        os.execute("sh /usr/libexec/fastfi/core/fastfi-antitether.sh disable")
    end
    
    return { status = "ok", enabled = enabled }
end

function M.get_validity_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    local row = sqlite.query_row(config_db, "SELECT enable_validity FROM config LIMIT 1")
    
    local enabled = false
    if row and tonumber(row[1]) == 1 then
        enabled = true
    end
    
    return { status = "ok", enabled = enabled }
end

function M.set_validity_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local enabled = params.enabled == "true" or params.enabled == "1"
    local val = enabled and 1 or 0
    
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    sqlite.execute(config_db, "UPDATE config SET enable_validity=" .. val)
    
    return { status = "ok", enabled = enabled }
end

function M.get_data_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    local row = sqlite.query_row(config_db, "SELECT enable_data_allocation FROM config LIMIT 1")
    
    local enabled = false
    if row and tonumber(row[1]) == 1 then
        enabled = true
    end
    
    return { status = "ok", enabled = enabled }
end

function M.set_data_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local enabled = params.enabled == "true" or params.enabled == "1"
    local val = enabled and 1 or 0
    
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    sqlite.execute(config_db, "UPDATE config SET enable_data_allocation=" .. val)
    
    return { status = "ok", enabled = enabled }
end

function M.get_hide_insert_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    local row = sqlite.query_row(config_db, "SELECT hide_insert_no_internet FROM config LIMIT 1")
    
    local enabled = false
    if row and tonumber(row[1]) == 1 then
        enabled = true
    end
    
    return { status = "ok", enabled = enabled }
end

function M.set_hide_insert_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local enabled = params.enabled == "true" or params.enabled == "1"
    local val = enabled and 1 or 0
    
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    sqlite.execute(config_db, "UPDATE config SET hide_insert_no_internet=" .. val)
    
    return { status = "ok", enabled = enabled }
end

function M.get_buy_data_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    local row = sqlite.query_row(config_db, "SELECT enable_buy_data FROM config LIMIT 1")
    local enabled = true
    if row and tonumber(row[1]) == 0 then
        enabled = false
    end
    return { status = "ok", enabled = enabled }
end

function M.set_buy_data_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local enabled = params.enabled == "true" or params.enabled == "1"
    local val = enabled and 1 or 0
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    sqlite.execute(config_db, "UPDATE config SET enable_buy_data=" .. val)
    return { status = "ok", enabled = enabled }
end

function M.get_wipass_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    local row = sqlite.query_row(config_db, "SELECT enable_wipass FROM config LIMIT 1")
    local enabled = true
    if row and tonumber(row[1]) == 0 then
        enabled = false
    end
    return { status = "ok", enabled = enabled }
end

function M.set_wipass_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local enabled = params.enabled == "true" or params.enabled == "1"
    local val = enabled and 1 or 0
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    sqlite.execute(config_db, "UPDATE config SET enable_wipass=" .. val)
    return { status = "ok", enabled = enabled }
end


function M.get_insert_config(params)
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    local row = sqlite.query_row(config_db, "SELECT insert_timer, insert_spam_limit, banner_text FROM config LIMIT 1")
    
    return {
        status = "ok",
        insert_timer = tonumber(row and row[1]) or 60,
        insert_spam_limit = tonumber(row and row[2]) or 5,
        banner_text = row and row[3] or "Insert coin or enter voucher to start"
    }
end

function M.set_insert_config(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local timer = tonumber(params["insert_timer"]) or 60
    local spam_limit = tonumber(params["insert_spam_limit"]) or 5
    local banner_text = params["banner_text"] or "Insert coin or enter voucher to start"
    
    
    if timer < 10 then timer = 10 end
    if timer > 300 then timer = 300 end
    if spam_limit < 1 then spam_limit = 1 end
    if spam_limit > 50 then spam_limit = 50 end
    
    local config_db = require("fastfi.config").CONFIG_DB
    local sqlite = require("fastfi.db.sqlite")
    sqlite.execute(config_db, string.format(
        "UPDATE config SET insert_timer=%d, insert_spam_limit=%d, banner_text='%s'", 
        timer, spam_limit, sqlite.quote(banner_text)))
    
    return { 
        status = "ok", 
        insert_timer = timer, 
        insert_spam_limit = spam_limit,
        banner_text = banner_text
    }
end

function M.save_speed_limit(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local dl_mbps = tonumber(params["dl"]) or 5
    local ul_mbps = tonumber(params["ul"]) or 5
    
    
    local speed_content = string.format("%d|%d", dl_mbps, ul_mbps)
    file_util.write("/etc/fastfi/client_speed", speed_content)
    
    
    os.execute("(/usr/bin/env lua /usr/libexec/fastfi/core/fastfi-shaper.lua >/dev/null 2>&1) &")
    
    return { status = "success", message = "Speed limits saved and instantly applied!" }
end

function M.sales_history(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local limit = tonumber(params["limit"]) or 100
    local offset = tonumber(params["offset"]) or 0
    local db = config.SESSIONS_DB

    
    
    
    
    local function day_start_ts(str)
        if not str or str == "" then return nil end
        local y, m, d = str:match("(%d+)-(%d+)-(%d+)")
        if not y then return false end
        return os.time{year = y, month = m, day = d, hour = 0, min = 0, sec = 0}
    end
    local function day_end_ts(str)
        if not str or str == "" then return nil end
        local y, m, d = str:match("(%d+)-(%d+)-(%d+)")
        if not y then return false end
        return os.time{year = y, month = m, day = d, hour = 23, min = 59, sec = 59}
    end

    local start_ts = day_start_ts(params["date_start"])
    local end_ts   = day_end_ts(params["date_end"])
    if start_ts == false or end_ts == false then
        return { status = "error", message = "Invalid date format (expected YYYY-MM-DD)" }
    end
    if start_ts and end_ts and start_ts > end_ts then
        return { status = "error", message = "Start date must not be after end date" }
    end

    local where, range_where = "", ""
    if start_ts and end_ts then
        where = string.format(" WHERE s.created_at >= %d AND s.created_at <= %d", start_ts, end_ts)
        range_where = string.format(" WHERE created_at >= %d AND created_at <= %d", start_ts, end_ts)
    elseif start_ts then
        where = string.format(" WHERE s.created_at >= %d", start_ts)
        range_where = string.format(" WHERE created_at >= %d", start_ts)
    elseif end_ts then
        where = string.format(" WHERE s.created_at <= %d", end_ts)
        range_where = string.format(" WHERE created_at <= %d", end_ts)
    end

    
    
    
    
    local q = string.format([[
        SELECT
            s.id,
            s.mac_address,
            s.amount,
            s.coins,
            s.created_at,
            sess.device_id,
            sess.session_end,
            sess.dl_limit,
            sess.ul_limit,
            sess.pause_count
        FROM sales s
        LEFT JOIN sessions sess ON s.mac_address = sess.mac_address%s
        ORDER BY s.created_at DESC
        LIMIT %d OFFSET %d;
    ]], where, limit, offset)
    local rows = sqlite.query_list(db, q)

    if not rows then rows = {} end

    
    
    local total_row = sqlite.query_row(db,
        string.format("SELECT COALESCE(SUM(amount),0), COUNT(*) FROM sales%s;", range_where))

    return {
        status = "success",
        data = rows,
        range_total = tonumber(total_row and total_row[1]) or 0,
        range_count = tonumber(total_row and total_row[2]) or 0
    }
end

function M.remove_license(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    config_db.revoke_license()
    return { status = "ok", message = "License removed successfully. Service deactivated." }
end



function M.check_update(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local handle = io.popen("sh /usr/libexec/fastfi/core/fastfi-ota.sh check 2>&1")
    local result = handle:read("*a")
    handle:close()
    
    local status = result:match("STATUS=(%w+)")
    if status == "AVAILABLE" then
        local version = result:match("VERSION=([%d%.]+)")
        local url = result:match("URL=(%S+)")
        local asset = result:match("ASSET=(%S+)") or "update.tar.gz"
        
        if url and asset then
            
            os.execute("mkdir -p /tmp")
            file_util.write("/tmp/_ota_url", url)
            
            
            os.execute("echo '['$(date '+%Y-%m-%d %H:%M:%S')'] Initializing download...' > /tmp/fw_progress.log && chmod 666 /tmp/fw_progress.log")
            
            
            
            os.execute(string.format(
                "(sh /usr/libexec/fastfi/core/fastfi-ota.sh download '%s' '%s' >> /tmp/fw_progress.log 2>&1) &",
                url, asset))
            
            
            os.execute("sleep 0.2")
            
            return { status = "available", version = version, asset = asset }
        end
    elseif status == "UPTODATE" then
        return { status = "uptodate" }
    else
        
        local err = result:match("FATAL: (.-)\n") 
                 or result:match("Error: (.-)\n") 
                 or "Update check failed"
        return { status = "error", message = err }
    end
end

function M.update_progress(params)
    local content = file_util.read("/tmp/fw_progress.log") or ""
    return { status = "ok", progress = content }
end

function M.proceed_update(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end

    
    
    
    
    
    os.execute("echo '['$(date '+%Y-%m-%d %H:%M:%S')'] Applying update (may take a minute, then the router reboots)...' >> /tmp/fw_progress.log")
    os.execute("sh /usr/libexec/fastfi/core/fastfi-ota.sh apply >> /tmp/fw_progress.log 2>&1 </dev/null &")

    return { status = "ok", message = "Applying update... Router will reboot." }
end

-- Stage a .bin for sysupgrade (KonekSik overlay or stock Ruijie image)
function M.upload_firmware(params, req)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    if not req or not req.post_body or #req.post_body == 0 then
        return { status = "error", message = "Empty firmware upload" }
    end
    if #req.post_body < 1024 * 100 then
        return { status = "error", message = "File too small to be a firmware image" }
    end
    if #req.post_body > 64 * 1024 * 1024 then
        return { status = "error", message = "File too large (max 64MB)" }
    end
    local target = "/tmp/koneksik_fw_upload.bin"
    local ok = file_util.write(target, req.post_body)
    if not ok then
        return { status = "error", message = "Failed to stage firmware in /tmp" }
    end
    local size = #req.post_body
    return {
        status = "ok",
        message = "Firmware staged",
        path = target,
        size = size,
        size_mb = math.floor(size / 1024 / 1024 * 10) / 10
    }
end

function M.flash_firmware(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local confirm = tostring(params.confirm_stock or params.confirm or "")
    if confirm ~= "1" and confirm ~= "true" and confirm ~= "yes" then
        return { status = "error", message = "Confirm stock/flash acknowledgement required" }
    end
    local target = "/tmp/koneksik_fw_upload.bin"
    local f = io.open(target, "rb")
    if not f then
        return { status = "error", message = "No staged firmware. Upload a .bin first." }
    end
    f:close()
    -- Keep config when flashing OpenWrt-family images; stock Ruijie may ignore -n
    os.execute("echo '['$(date '+%Y-%m-%d %H:%M:%S')'] Flashing staged firmware via sysupgrade...' >> /tmp/fw_progress.log")
    os.execute("(sleep 2; sysupgrade -n /tmp/koneksik_fw_upload.bin >> /tmp/fw_progress.log 2>&1) &")
    return {
        status = "ok",
        message = "Flashing started. Router will reboot. Stock Ruijie images restore the original Ruijie web UI."
    }
end

-- ============================================================
-- PATH B — OEM ReyeeOS restore (independent of sysupgrade PATH A)
-- Existing upload_firmware / flash_firmware above are FROZEN.
-- ============================================================

function M.upload_oem_firmware(params, req)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local oem = require("fastfi.oem_reyee")
    if not req or not req.post_body or #req.post_body == 0 then
        return { status = "error", message = "Empty OEM firmware upload" }
    end
    if #req.post_body < 1024 * 100 then
        return { status = "error", message = "File too small" }
    end
    if #req.post_body > 32 * 1024 * 1024 then
        return { status = "error", message = "File too large (max 32MB)" }
    end
    oem.clear()
    local paths = oem.paths()
    local ok = file_util.write(paths.upload, req.post_body)
    if not ok then
        return { status = "error", message = "Failed to stage OEM firmware in /tmp" }
    end
    os.execute(string.format(
        "echo '[OEM] '$(date '+%%Y-%%m-%%d %%H:%%M:%%S')' Upload received (%d bytes)' >> /tmp/fw_progress.log",
        #req.post_body))
    local report = oem.validate_staged()
    if not report.ok then
        return {
            status = "error",
            message = (report.errors and report.errors[1]) or "OEM validation failed",
            report = report
        }
    end
    return {
        status = "ok",
        message = report.message or "OEM firmware validated",
        report = report
    }
end

function M.validate_oem_firmware(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local oem = require("fastfi.oem_reyee")
    local report = oem.validate_staged()
    if not report.ok then
        return {
            status = "error",
            message = (report.errors and report.errors[1]) or "OEM validation failed",
            report = report
        }
    end
    return { status = "ok", message = "OEM validation PASS", report = report }
end

function M.cancel_oem_firmware(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local oem = require("fastfi.oem_reyee")
    oem.clear()
    return { status = "ok", message = "OEM staging cancelled" }
end

function M.flash_oem_firmware(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local confirm = tostring(params.confirm_oem or "")
    if confirm ~= "1" and confirm ~= "true" and confirm ~= "yes" then
        return { status = "error", message = "Confirm OEM installation acknowledgement required" }
    end
    local token = tostring(params.confirm_token or "")
    local oem = require("fastfi.oem_reyee")
    local ok, msg = oem.flash(token)
    if not ok then
        return { status = "error", message = msg }
    end
    return { status = "ok", message = msg }
end

local BACKUP_DIR = "/www/data/backups"
local BACKUP_SCRIPT = "/usr/libexec/fastfi/core/fastfi-backup.sh"



local function safe_backup_name(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:match("[/\\]") or name:match("%.%.") then return nil end
    if name:match("[`'\"$;%|%&<>|]") then return nil end
    if not name:match("^fastfi[%w%.%-]*%.tar%.gz$") then return nil end
    return name
end


local function list_snapshots()
    local out = {}
    local h = io.popen(BACKUP_SCRIPT .. " list 2>/dev/null")
    if not h then return out end
    local text = h:read("*a") or ""
    h:close()
    for line in text:gmatch("[^\r\n]+") do
        local size, name = line:match("^(%S+)%s+(fastfi[%w%.%-]*%.tar%.gz)$")
        if name then
            table.insert(out, { name = name, size = size })
        end
    end
    return out
end

function M.backup_now(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    
    
    local mode = (params["mode"] == "full") and "full" or "config"
    
    
    
    
    
    
    local h = io.popen(BACKUP_SCRIPT .. " backup " .. mode .. " 2>&1")
    if not h then
        return { status = "error", message = "Failed to run backup tool." }
    end
    local raw = h:read("*a") or ""
    h:close()
    local out = ""
    for line in raw:gmatch("[^\r\n]+") do
        if line and line:match("%S") then out = line end
    end
    out = out:gsub("^%s+", ""):gsub("%s+$", "")
    if out == "" then
        return { status = "error", message = "Backup produced no output. The rootfs may be full — free space or expand the rootfs, then retry." }
    end
    
    if out:match("^/www/data/backups/fastfi[%w%.%-]*%.tar%.gz$") then
        return { status = "ok", message = "Backup created.", backup = out, list = list_snapshots() }
    end
    return { status = "error", message = out }
end

function M.list_backups(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    return { status = "ok", list = list_snapshots() }
end

function M.restore_backup(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local name = safe_backup_name(params["backup"])
    if not name then
        return { status = "error", message = "Invalid backup name." }
    end
    local path = BACKUP_DIR .. "/" .. name
    if not file_util.exists(path) then
        return { status = "error", message = "Backup file not found." }
    end
    
    os.execute(string.format("cp %s /tmp/_backup.sh && chmod +x /tmp/_backup.sh", BACKUP_SCRIPT))
    local rc = os.execute(string.format("sh /tmp/_backup.sh restore '%s' >/dev/null 2>&1", path))
    os.execute("rm -f /tmp/_backup.sh")
    if rc ~= 0 then
        return { status = "error", message = "Restore failed. See system log." }
    end
    return { status = "ok", message = "Configuration restored. Reboot the router to apply it." }
end

function M.delete_backup(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local name = safe_backup_name(params["backup"])
    if not name then
        return { status = "error", message = "Invalid backup name." }
    end
    local path = BACKUP_DIR .. "/" .. name
    if not file_util.exists(path) then
        return { status = "error", message = "Backup file not found." }
    end
    os.remove(path)
    return { status = "ok", message = "Backup deleted.", list = list_snapshots() }
end

function M.rollback_status(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    
    local armed = file_util.exists("/etc/fastfi/ota_pending")
    local info = { armed = armed, backup = "", version = "" }
    if armed then
        local raw = file_util.read("/etc/fastfi/ota_pending") or ""
        info.backup  = (raw:match("BACKUP=(%S+)") or "")
        info.version = (raw:match("VERSION=(%S+)") or "")
    end
    return { status = "ok", rollback = info, list = list_snapshots() }
end

return M
