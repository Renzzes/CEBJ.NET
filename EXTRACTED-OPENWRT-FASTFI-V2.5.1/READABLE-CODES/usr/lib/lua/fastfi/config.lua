
local M = {}


local function detect_env()
    local os_target = package.config:sub(1,1)
    
    if os_target == '\\' then
        
        M.ENVIRONMENT = "development"
        M.BASE_DIR = "./data"
    else
        
        M.ENVIRONMENT = "production"
        M.BASE_DIR = "/"
    end
    
    
    os.execute("mkdir -p " .. (M.PATHS and M.PATHS.DATA_DIR or "/www/data") .. " 2>/dev/null")
    os.execute("mkdir -p " .. M.PATHS.RAM_DIR .. " 2>/dev/null")
    os.execute("mkdir -p " .. M.PATHS.SESSION_DIR .. " 2>/dev/null")
    os.execute("mkdir -p " .. M.PATHS.CONFIG_DIR .. " 2>/dev/null")
    
    
    
    
    
    
    
    
    
    
    

    local function is_blank_id(s)
        return (not s) or s == "" or (s:match("^0+$") ~= nil)
    end

    local function mac_to_id(addr)
        addr = (addr or ""):gsub(":", ""):gsub("%s+", ""):upper()
        if #addr == 12 and not is_blank_id(addr) then return addr end
        return nil
    end

    local function find_wired_mac()
        local candidates = {
            "/sys/class/net/eth0/address",
            "/sys/class/net/eth1/address",
            "/sys/class/net/eth2/address"
        }
        
        local p = io.popen("ls /sys/class/net/ 2>/dev/null")
        if p then
            for dev in p:lines() do
                if dev ~= "lo" and not dev:match("^br%-") and not dev:match("^tun")
                   and not dev:match("^wlan") and not dev:match("^wl") then
                    table.insert(candidates, "/sys/class/net/" .. dev .. "/address")
                end
            end
            p:close()
        end
        for _, path in ipairs(candidates) do
            local f = io.open(path, "r")
            if f then
                local id = mac_to_id(f:read("*a"))
                f:close()
                if id then return id end
            end
        end
        return nil
    end

    
    local function read_bin_hex(path, nbytes)
        local f = io.open(path, "rb")
        if not f then return nil end
        local data = f:read(nbytes or 16)
        f:close()
        if not data or data == "" then return nil end
        local hex = (data:gsub(".", function(c) return string.format("%02X", c:byte()) end))
        if is_blank_id(hex) then return nil end
        return hex
    end

    
    
    
    
    
    
    
    local function find_product_info_mac()
        
        
        local p = io.popen("awk -F: '/\"(product_info|product-info|productinfo)\"/{print $1; exit}' /proc/mtd 2>/dev/null")
        if not p then return nil end
        local mtd = (p:read("*a") or ""):gsub("%s+", "")
        p:close()
        if mtd == "" then return nil end
        local f = io.open("/dev/mtdblock" .. mtd:gsub("^mtd", ""), "rb")
        if not f then return nil end
        local data = f:read("*a")  
        f:close()
        if not data then return nil end
        local mac = data:match("ethaddr=([0-9A-Fa-f:]+)")
        if not mac then return nil end
        return mac_to_id(mac)  
    end

    
    
    
    
    
    
    
    
    
    local function find_factory_mac()
        
        
        local p = io.popen("awk -F: '/\"(factory|Factory|caldata|Caldata)\"/{print $1; exit}' /proc/mtd 2>/dev/null")
        if not p then return nil end
        local mtd = (p:read("*a") or ""):gsub("%s+", "")
        p:close()
        if mtd == "" then return nil end
        local f = io.open("/dev/mtdblock" .. mtd:gsub("^mtd", ""), "rb")
        if not f then return nil end
        f:seek("set", 4)
        local data = f:read(6)
        f:close()
        if not data or #data ~= 6 then return nil end
        local hex = (data:gsub(".", function(c) return string.format("%02X", c:byte()) end))
        if is_blank_id(hex) then return nil end
        return hex
    end

    local function find_stable_hw_id()

        local pimac = find_product_info_mac()
        if pimac and #pimac == 12 then return pimac end

        local fmac = find_factory_mac()
        if fmac and #fmac == 12 then return fmac end

        for _, p in ipairs({
            "/sys/bus/nvmem/devices/sunxi-sid0/nvmem",
            "/sys/bus/nvmem/devices/sunxi-sid/nvmem",
        }) do
            local id = read_bin_hex(p, 16)
            if id and #id >= 12 then return id end
        end
        
        local f = io.open("/sys/class/sunxi_info/chip_id", "r")
        if f then
            local id = (f:read("*a") or ""):gsub("%s+", ""):upper()
            f:close()
            if #id >= 12 and not is_blank_id(id) then return id end
        end
        
        f = io.open("/proc/cpuinfo", "r")
        if f then
            for line in f:lines() do
                local s = line:match("Serial%s*:%s*([0-9A-Fa-f]+)")
                if s then
                    s = s:upper()
                    if #s >= 12 and not is_blank_id(s) then
                        f:close()
                        return s
                    end
                end
            end
            f:close()
        end
        
        return find_wired_mac()
    end

    local id_file = (M.PATHS and M.PATHS.CONFIG_DIR or "/etc/fastfi") .. "/machine_id"
    local f_id = io.open(id_file, "r")
    if f_id then
        M.MACHINE_ID = (f_id:read("*a") or ""):gsub("%s+", ""):upper()
        f_id:close()
        
        if is_blank_id(M.MACHINE_ID) or #M.MACHINE_ID < 4 then
            M.MACHINE_ID = find_stable_hw_id() or "000000000000"
        end
    else
        
        local mid = find_stable_hw_id() or "000000000000"
        os.execute("mkdir -p /etc/fastfi")
        local f_save = io.open(id_file, "w")
        if f_save then
            f_save:write(mid)
            f_save:close()
        end
        M.MACHINE_ID = mid
    end
end


M.PATHS = {
    
    DATA_DIR = "/www/data",
    RAM_DIR = "/tmp/fastfi_state",
    
    
    SESSIONS_DB = "/www/data/sessions.db",
    CONFIG_DB = "/www/data/bindcode.db",
    VOUCHER_DB = "/www/data/vouchers.db",
    GCASH_DB = "/www/data/gcash.db",
    ESP_DB = "/www/data/esp_coinslot.db",
    
    
    CONFIG_DIR = "/etc/fastfi",
    ADMIN_PASS_FILE = "/etc/fastfi_admin_pass.conf",
    RATES_FILE = "/etc/fastfi_rates.conf",
    AUTO_PAUSE_FILE = "/etc/fastfi/autopause.conf",
    PAUSE_LIMIT_FILE = "/etc/fastfi/pause_limit.conf",
    RECOVERY_EMAIL_FILE = "/etc/fastfi/recovery_email.conf",

    DEVICE_KEY_FILE = "/etc/fastfi/device.key",
    LICENSE_FILE = "/etc/fastfi/license.json",
    
    
    LIBEXEC_DIR = "/usr/libexec/fastfi",
    CORE_LOOP = "/usr/libexec/fastfi/core/core-loop.sh",
    CAPTIVE_TRIGGER = "/usr/libexec/fastfi/core/captive-trigger.sh",
    
    
    BRANDING_BASE = "/etc/fastfi/branding/slot_",
    SPEED_CONF = "/etc/fastfi/client_speed",
    
    
    SESSION_DIR = "/www/data/admin_sessions",
    LOG_DIR = "/www/data/logs",
    SESSION_COOKIE_NAME = "fastfi_admin_session"
}


if package.config:sub(1,1) == '\\' then
    M.PATHS.DATA_DIR = "./data"
    M.PATHS.RAM_DIR = "./data/tmp_state"
    M.PATHS.SESSIONS_DB = "./data/sessions.db"
    M.PATHS.CONFIG_DB = "./data/bindcode.db"
    M.PATHS.VOUCHER_DB = "./data/vouchers.db"
    M.PATHS.GCASH_DB = "./data/gcash.db"
    M.PATHS.ESP_DB = "./data/esp_coinslot.db"
    M.PATHS.CONFIG_DIR = "./data/config"
    M.PATHS.RATES_FILE = "./data/rates.conf"
    M.PATHS.AUTO_PAUSE_FILE = "./data/autopause.conf"
    M.PATHS.PAUSE_LIMIT_FILE = "./data/pause_limit.conf"
    M.PATHS.RECOVERY_EMAIL_FILE = "./data/recovery_email.conf"

    M.PATHS.DEVICE_KEY_FILE = "./data/device.key"
    M.PATHS.LICENSE_FILE = "./data/license.json"
    M.PATHS.LIBEXEC_DIR = "./libexec"
    M.PATHS.CORE_LOOP = "./libexec/core/core-loop.sh"
    M.PATHS.CAPTIVE_TRIGGER = "./libexec/core/captive-trigger.sh"
    M.PATHS.BRANDING_BASE = "./data/branding_slot_"
    M.PATHS.SPEED_CONF = "./data/client_speed"
    M.PATHS.SESSION_DIR = "./data/sessions"
end


M.DATA_DIR = M.PATHS.DATA_DIR
M.RAM_DIR = M.PATHS.RAM_DIR
M.SESSIONS_DB = M.PATHS.SESSIONS_DB
M.CONFIG_DB = M.PATHS.CONFIG_DB
M.VOUCHER_DB = M.PATHS.VOUCHER_DB
M.GCASH_DB = M.PATHS.GCASH_DB
M.ESP_DB = M.PATHS.ESP_DB
M.BRANDING_BASE = M.PATHS.BRANDING_BASE
M.SPEED_CONF = M.PATHS.SPEED_CONF
M.SESSION_DIR = M.PATHS.SESSION_DIR
M.SESSION_COOKIE_NAME = M.PATHS.SESSION_COOKIE_NAME
M.ADMIN_PASS_FILE = M.PATHS.ADMIN_PASS_FILE
M.RATES_FILE = M.PATHS.RATES_FILE
M.AUTO_PAUSE_FILE = M.PATHS.AUTO_PAUSE_FILE
M.PAUSE_LIMIT_FILE = M.PATHS.PAUSE_LIMIT_FILE
M.RECOVERY_EMAIL_FILE = M.PATHS.RECOVERY_EMAIL_FILE

M.DEVICE_KEY_FILE = M.PATHS.DEVICE_KEY_FILE
M.LICENSE_FILE = M.PATHS.LICENSE_FILE
M.CONFIG_DIR = M.PATHS.CONFIG_DIR
M.LIBEXEC_DIR = M.PATHS.LIBEXEC_DIR
M.CORE_LOOP = M.PATHS.CORE_LOOP
M.CAPTIVE_TRIGGER = M.PATHS.CAPTIVE_TRIGGER


detect_env()

return M
