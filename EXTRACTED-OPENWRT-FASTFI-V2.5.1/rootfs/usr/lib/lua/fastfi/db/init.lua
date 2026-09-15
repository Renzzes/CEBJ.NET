
local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")

local M = {}

function M.init()
    
    
    
    
    
    
    
    
    
    
    local CURRENT_VERSION = 36
    local config_db = config.CONFIG_DB
    
    
    
    local db_ver = 0
    local success, res = pcall(function() 
        local row = sqlite.query_row(config_db, "SELECT value FROM sys_config WHERE key='schema_version';")
        return tonumber(row and row[1]) or 0
    end)
    if success then db_ver = res end
    
    if db_ver >= CURRENT_VERSION then
        return true
    end

    
    
    sqlite.execute(config_db, "CREATE TABLE IF NOT EXISTS sys_config (key TEXT PRIMARY KEY, value TEXT);")

    
    sqlite.execute(config.CONFIG_DB, [[
        CREATE TABLE IF NOT EXISTS config (
            id INTEGER PRIMARY KEY,
            license_key TEXT,
            license_status TEXT DEFAULT 'inactive',
            expires_at TEXT,
            plan_code TEXT,
            anti_tethering INTEGER DEFAULT 1,
            hide_insert_no_internet INTEGER DEFAULT 0,
            last_report_id INTEGER DEFAULT 0,
            insert_timer INTEGER DEFAULT 60,
            insert_spam_limit INTEGER DEFAULT 5,
            wifi_public_ssid TEXT DEFAULT 'KonekSik-Fi PisoWiFi',
            wifi_private_ssid TEXT DEFAULT 'KonekSik-Fi-Private',
            wifi_private_pass TEXT DEFAULT '12345678',
            enable_validity INTEGER DEFAULT 0,
            enable_data_allocation INTEGER DEFAULT 0,
            wan_mode TEXT DEFAULT 'standard',
            vlan_id INTEGER,
            outdoor_vlan_id INTEGER,
            banner_text TEXT DEFAULT 'Insert coin or enter voucher to start',
            enable_buy_data INTEGER DEFAULT 1,
            enable_wipass INTEGER DEFAULT 1,
            -- GCash e-payment (code-pool model). MUST exist from first boot:
            -- gcash.lua's lazy ensure_config_columns adds them too, but if that
            -- ALTER ever fails on-device (its pcall swallows the error), every
            -- GCash config save silently no-ops and the enable toggle reverts
            -- to off. Defining them here guarantees they're present.
            gcash_enabled INTEGER DEFAULT 0,
            gcash_number TEXT DEFAULT '',
            gcash_qr TEXT DEFAULT '',
            gcash_app_secret TEXT DEFAULT '',
            gcash_voucher_expiry_days INTEGER DEFAULT 0,
            -- GCash grant-first free browsing window (default ON): when 1,
            -- unauthenticated captive-portal clients may claim a short free
            -- internet window to open the GCash app and pay before they have a
            -- session. Minutes/cooldown/cap are hardcoded in routes/gcash.lua.
            -- Must exist from first boot — same reason as the other gcash columns
            -- (see gcash-toggle-reverts-columns).
            gcash_freewindow_enabled INTEGER DEFAULT 1
        );
        INSERT OR IGNORE INTO config (id, anti_tethering, last_report_id, wan_mode, vlan_id, outdoor_vlan_id) VALUES (1, 1, 0, 'standard', NULL, NULL);

        
        CREATE TABLE IF NOT EXISTS coin_rates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            price INTEGER NOT NULL,
            minutes INTEGER NOT NULL,
            download_mb INTEGER DEFAULT 0,
            upload_mb INTEGER DEFAULT 0,
            pause_limit INTEGER DEFAULT 0,
            validity_minutes INTEGER DEFAULT 0,
            data_limit_mb INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
    ]])

    
    sqlite.execute(config.SESSIONS_DB, [[
        CREATE TABLE IF NOT EXISTS sessions (
            mac_address TEXT PRIMARY KEY,
            session_end INTEGER DEFAULT 0,
            download INTEGER DEFAULT 0,
            upload INTEGER DEFAULT 0,
            active INTEGER DEFAULT 1,
            paused INTEGER DEFAULT 0,
            remaining INTEGER DEFAULT 0,
            device_id TEXT DEFAULT '',
            dl_limit INTEGER DEFAULT 0,
            ul_limit INTEGER DEFAULT 0,
            created_at INTEGER DEFAULT 0,
            updated_at INTEGER DEFAULT 0,
            last_paused_at INTEGER DEFAULT 0,
            pause_count INTEGER DEFAULT 0,
            total_paused_duration INTEGER DEFAULT 0,
            validity_end INTEGER DEFAULT 0,
            data_limit_mb INTEGER DEFAULT 0,
            data_consumed_mb INTEGER DEFAULT 0,
            paused_limit INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS session_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT,
            mac_address TEXT,
            event_type TEXT,
            timestamp INTEGER,
            remaining_seconds INTEGER,
            session_end INTEGER,
            reason TEXT,
            triggered_by TEXT
        );
        CREATE TABLE IF NOT EXISTS sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mac_address TEXT,
            amount INTEGER,
            coins INTEGER,
            created_at INTEGER,
            batch_id TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_sessions_mac_active ON sessions(mac_address, active);
        CREATE INDEX IF NOT EXISTS idx_sessions_device_id ON sessions(device_id);
        CREATE INDEX IF NOT EXISTS idx_sales_created ON sales(created_at);
    ]])

    
    sqlite.execute(config.ESP_DB, [[
        CREATE TABLE IF NOT EXISTS esp_slots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            slot_name TEXT,
            slot_mac TEXT UNIQUE,
            router_mac TEXT,
            status TEXT DEFAULT 'offline',
            license_status TEXT DEFAULT 'unlicensed',
            license_key TEXT,
            last_seen INTEGER,
            locked_by TEXT,
            locked_at INTEGER DEFAULT 0,
            coin_credit INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS esp_licenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            license_key TEXT UNIQUE,
            status TEXT DEFAULT 'available',
            used_slot_id INTEGER,
            used_at TEXT,
            router_mac TEXT
        );
        CREATE TABLE IF NOT EXISTS coin_spam (
            client_mac TEXT PRIMARY KEY,
            fail_count INTEGER DEFAULT 0,
            last_attempt INTEGER DEFAULT 0,
            blocked_until INTEGER DEFAULT 0
        );
    ]])

    
    local free_lic_row = sqlite.query_row(config.ESP_DB, "SELECT COUNT(*) FROM esp_licenses WHERE license_key='FASTFI-FREE-ESP';")
    if tonumber(free_lic_row and free_lic_row[1]) == 0 then
        sqlite.execute(config.ESP_DB, "INSERT INTO esp_licenses (license_key, status) VALUES ('FASTFI-FREE-ESP', 'available');")
    end

    
    local legacy_free = sqlite.query_row(config.ESP_DB, "SELECT id FROM esp_slots WHERE license_status='free' AND (license_key IS NULL OR license_key = '');")
    if legacy_free and legacy_free[1] then
        local slot_id = legacy_free[1]
        sqlite.execute(config.ESP_DB, string.format("UPDATE esp_slots SET license_key='FASTFI-FREE-ESP' WHERE id=%d;", slot_id))
        sqlite.execute(config.ESP_DB, string.format("UPDATE esp_licenses SET status='used', used_slot_id=%d, used_at=datetime('now') WHERE license_key='FASTFI-FREE-ESP' AND status='available';", slot_id))
    end

    
    local function add_col(db, table, col, type)
        pcall(function() sqlite.execute(db, string.format("ALTER TABLE %s ADD COLUMN %s %s;", table, col, type)) end)
    end

    add_col(config.CONFIG_DB, "config", "enable_validity", "INTEGER DEFAULT 0")
    add_col(config.CONFIG_DB, "config", "enable_data_allocation", "INTEGER DEFAULT 0")
    add_col(config.CONFIG_DB, "config", "wan_mode", "TEXT DEFAULT 'standard'")
    add_col(config.CONFIG_DB, "config", "vlan_id", "INTEGER")
    add_col(config.CONFIG_DB, "config", "outdoor_vlan_id", "INTEGER")

    add_col(config.CONFIG_DB, "config", "insert_timer", "INTEGER DEFAULT 60")
    add_col(config.CONFIG_DB, "config", "insert_spam_limit", "INTEGER DEFAULT 5")
    
    
    add_col(config.CONFIG_DB, "config", "gcash_enabled", "INTEGER DEFAULT 0")
    add_col(config.CONFIG_DB, "config", "gcash_number", "TEXT DEFAULT ''")
    add_col(config.CONFIG_DB, "config", "gcash_qr", "TEXT DEFAULT ''")
    add_col(config.CONFIG_DB, "config", "gcash_app_secret", "TEXT DEFAULT ''")
    add_col(config.CONFIG_DB, "config", "gcash_voucher_expiry_days", "INTEGER DEFAULT 0")
    add_col(config.CONFIG_DB, "config", "gcash_freewindow_enabled", "INTEGER DEFAULT 1")
    add_col(config.SESSIONS_DB, "sessions", "validity_end", "INTEGER DEFAULT 0")
    add_col(config.SESSIONS_DB, "sessions", "paused_limit", "INTEGER DEFAULT 0")
    add_col(config.SESSIONS_DB, "sales", "coins", "INTEGER DEFAULT 0")
    add_col(config.SESSIONS_DB, "sales", "batch_id", "TEXT")
    add_col(config.ESP_DB, "esp_slots", "coin_credit", "INTEGER DEFAULT 0")
    add_col(config.ESP_DB, "esp_licenses", "grace_used", "INTEGER DEFAULT 0")
    add_col(config.ESP_DB, "esp_licenses", "grace_max", "INTEGER DEFAULT 3")
    add_col(config.ESP_DB, "esp_licenses", "live_mac", "TEXT")
    add_col(config.ESP_DB, "esp_licenses", "license_id", "TEXT")
    add_col(config.ESP_DB, "esp_licenses", "source", "TEXT DEFAULT 'koneksk'")

    
    add_col(config.SESSIONS_DB, "sessions", "sub_vendo_id", "INTEGER DEFAULT 0")
    add_col(config.SESSIONS_DB, "sales", "sub_vendo_id", "INTEGER DEFAULT 0")

    
    
    
    local old_vlan = sqlite.query_row(config.CONFIG_DB, "SELECT wan_mode, vlan_id, outdoor_vlan_id FROM config LIMIT 1;")
    if old_vlan then
        local old_mode = old_vlan[1] or "standard"
        local old_wan_vlan = old_vlan[2]
        local old_ap_vlan = old_vlan[3]
        if old_mode == "vlan" and old_ap_vlan and old_ap_vlan ~= "" then
            
            sqlite.execute(config.CONFIG_DB, string.format(
                "UPDATE config SET vlan_id=%s, outdoor_vlan_id=NULL WHERE id=1;",
                sqlite.quote(tostring(old_ap_vlan))))
            print(string.format("[KonekSik-Fi] Migrated old VLAN config: AP VLAN now %s, WAN fixed to eth0.1", tostring(old_ap_vlan)))
        end
    end

    
    local count_row = sqlite.query_row(config.CONFIG_DB, "SELECT COUNT(*) FROM coin_rates;")
    if tonumber(count_row and count_row[1]) == 0 then
        sqlite.execute(config.CONFIG_DB, [[
            INSERT INTO coin_rates (price, minutes, validity_minutes) VALUES (1, 5, 0);
            INSERT INTO coin_rates (price, minutes, validity_minutes) VALUES (5, 30, 0);
            INSERT INTO coin_rates (price, minutes, validity_minutes) VALUES (10, 60, 0);
            INSERT INTO coin_rates (price, minutes, validity_minutes) VALUES (20, 120, 0);
        ]])
    end

    


    
    

    
    
    
    
    pcall(function()
        sqlite.execute(config.CONFIG_DB,
            "ALTER TABLE config ADD COLUMN banner_text TEXT DEFAULT 'Insert coin or enter voucher to start';")
    end)

    pcall(function()
        sqlite.execute(config.CONFIG_DB,
            "ALTER TABLE config ADD COLUMN enable_buy_data INTEGER DEFAULT 1;")
    end)

    pcall(function()
        sqlite.execute(config.CONFIG_DB,
            "ALTER TABLE config ADD COLUMN enable_wipass INTEGER DEFAULT 1;")
    end)


    
    
    
    
    

    


    
    pcall(function()
        local row = sqlite.query_row(config.ESP_DB, "SELECT id FROM esp_slots WHERE slot_mac='gpio-coinslot';")
        if row and row[1] then
            local slot_id = tonumber(row[1])
            sqlite.execute(config.ESP_DB, string.format(
                "UPDATE esp_licenses SET status='available', used_slot_id=NULL, used_at=NULL WHERE used_slot_id=%d;", slot_id))
        end
        sqlite.execute(config.ESP_DB, "DELETE FROM esp_slots WHERE slot_mac='gpio-coinslot';")
    end)

    
    
    
    sqlite.execute(config.ESP_DB, "UPDATE esp_licenses SET router_mac = UPPER(router_mac) WHERE router_mac IS NOT NULL;")
    sqlite.execute(config.ESP_DB, "UPDATE esp_slots SET router_mac = UPPER(router_mac) WHERE router_mac IS NOT NULL;")

    
    
    
    
    
    
    sqlite.execute(config.ESP_DB,
        "UPDATE esp_licenses SET status='available', used_slot_id=NULL, used_at=NULL " ..
        "WHERE status='used' AND used_slot_id IS NOT NULL " ..
        "AND used_slot_id NOT IN (SELECT id FROM esp_slots);")

    
    
    
    
    
    
    pcall(function()
        sqlite.execute(config.SESSIONS_DB, "DROP TABLE IF EXISTS chat_messages;")
        sqlite.execute(config.SESSIONS_DB, "DROP TABLE IF EXISTS chat_conversations;")
        sqlite.execute(config.SESSIONS_DB, "DROP TABLE IF EXISTS chat_rate;")
        sqlite.execute(config.SESSIONS_DB, "VACUUM;")
    end)

    
    
    
    
    pcall(function()
        sqlite.execute(config.CONFIG_DB, "DROP TABLE IF EXISTS points;")
        sqlite.execute(config.CONFIG_DB, "DROP TABLE IF EXISTS points_log;")
        sqlite.execute(config.CONFIG_DB, "DROP TABLE IF EXISTS wheel_segments;")
        sqlite.execute(config.CONFIG_DB, "DROP TABLE IF EXISTS spin_history;")
    end)

    -- v30–v35: KonekSik-inspired feature tables
    sqlite.execute(config.CONFIG_DB, [[
        CREATE TABLE IF NOT EXISTS bandwidth_profiles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            down_kbps INTEGER DEFAULT 0,
            up_kbps INTEGER DEFAULT 0,
            enabled INTEGER DEFAULT 1,
            created_at INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS plans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            price INTEGER DEFAULT 0,
            duration_min INTEGER DEFAULT 0,
            data_mb INTEGER DEFAULT 0,
            profile_id INTEGER,
            pause_limit INTEGER DEFAULT 0,
            enabled INTEGER DEFAULT 1,
            created_at INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS plan_clients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            contact TEXT DEFAULT '',
            plan_id INTEGER,
            notes TEXT DEFAULT '',
            status TEXT DEFAULT 'active',
            created_at INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS plan_devices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_id INTEGER NOT NULL,
            mac TEXT NOT NULL,
            hostname TEXT DEFAULT '',
            created_at INTEGER DEFAULT 0,
            UNIQUE(mac)
        );
        CREATE TABLE IF NOT EXISTS mac_blocklist (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mac TEXT NOT NULL UNIQUE,
            reason TEXT DEFAULT '',
            blocked_at INTEGER DEFAULT 0,
            blocked_by TEXT DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS admin_users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            role TEXT DEFAULT 'owner',
            created_at INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER DEFAULT 0,
            username TEXT DEFAULT '',
            action TEXT DEFAULT '',
            detail TEXT DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS activity_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER DEFAULT 0,
            type TEXT DEFAULT 'info',
            title TEXT DEFAULT '',
            body TEXT DEFAULT ''
        );
    ]])
    add_col(config.CONFIG_DB, "config", "login_logo", "TEXT DEFAULT ''")
    add_col(config.CONFIG_DB, "config", "nav_logo", "TEXT DEFAULT ''")
    add_col(config.CONFIG_DB, "config", "portal_logo", "TEXT DEFAULT ''")
    add_col(config.CONFIG_DB, "config", "shop_name", "TEXT DEFAULT 'KonekSik-Fi'")
    -- Rebrand legacy default shop name
    pcall(function()
        sqlite.execute(config.CONFIG_DB,
            "UPDATE config SET shop_name='KonekSik-Fi' WHERE shop_name IS NULL OR shop_name='' OR shop_name='FastFi';")
        sqlite.execute(config.CONFIG_DB,
            "UPDATE config SET wifi_public_ssid='KonekSik-Fi PisoWiFi' WHERE wifi_public_ssid='FastFi PisoWiFi';")
        sqlite.execute(config.CONFIG_DB,
            "UPDATE config SET wifi_private_ssid='KonekSik-Fi-Private' WHERE wifi_private_ssid='FastFi-Private';")
    end)
    add_col(config.CONFIG_DB, "config", "voucher_template_note", "TEXT DEFAULT ''")
    add_col(config.CONFIG_DB, "config", "backup_schedule_enabled", "INTEGER DEFAULT 0")
    add_col(config.CONFIG_DB, "config", "sms_enabled", "INTEGER DEFAULT 0")
    add_col(config.CONFIG_DB, "config", "sms_provider", "TEXT DEFAULT 'none'")
    add_col(config.CONFIG_DB, "config", "sms_endpoint", "TEXT DEFAULT ''")
    add_col(config.SESSIONS_DB, "sessions", "plan_id", "INTEGER DEFAULT 0")
    add_col(config.SESSIONS_DB, "sessions", "profile_id", "INTEGER DEFAULT 0")
    add_col(config.SESSIONS_DB, "sessions", "plan_client_id", "INTEGER DEFAULT 0")
    -- Dual-band preference per bandwidth profile: auto | 2.4 | 5
    add_col(config.CONFIG_DB, "bandwidth_profiles", "band", "TEXT DEFAULT 'auto'")
    add_col(config.SESSIONS_DB, "sessions", "band", "TEXT DEFAULT 'auto'")

    -- Seed default bandwidth profiles / plans if empty
    local bp_count = sqlite.query_row(config.CONFIG_DB, "SELECT COUNT(*) FROM bandwidth_profiles;")
    if tonumber(bp_count and bp_count[1]) == 0 then
        local now = os.time()
        sqlite.execute(config.CONFIG_DB, string.format([[
            INSERT INTO bandwidth_profiles (name, down_kbps, up_kbps, enabled, created_at, band) VALUES
            ('Basic', 5120, 2048, 1, %d, 'auto'),
            ('Standard', 10240, 5120, 1, %d, 'auto'),
            ('VIP', 20480, 10240, 1, %d, '5');
        ]], now, now, now))
    end
    local plan_count = sqlite.query_row(config.CONFIG_DB, "SELECT COUNT(*) FROM plans;")
    if tonumber(plan_count and plan_count[1]) == 0 then
        local now = os.time()
        sqlite.execute(config.CONFIG_DB, string.format([[
            INSERT INTO plans (name, price, duration_min, data_mb, profile_id, pause_limit, enabled, created_at) VALUES
            ('Day Pass', 50, 1440, 0, 2, 3, 1, %d),
            ('Weekly', 250, 10080, 0, 2, 5, 1, %d),
            ('Monthly', 800, 43200, 0, 3, 10, 1, %d);
        ]], now, now, now))
    end

    -- Migrate legacy password file into admin_users
    pcall(function()
        local users = require("fastfi.db.users")
        users.ensure_default_admin()
    end)

    -- v36: Access Points (built-in radios + LAN coverage APs) + ESP bind
    sqlite.execute(config.CONFIG_DB, [[
        CREATE TABLE IF NOT EXISTS access_points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            kind TEXT DEFAULT 'lan',
            iface TEXT DEFAULT '',
            mac TEXT DEFAULT '',
            ip TEXT DEFAULT '',
            location TEXT DEFAULT '',
            status TEXT DEFAULT 'unknown',
            enabled INTEGER DEFAULT 1,
            created_at INTEGER DEFAULT 0,
            notes TEXT DEFAULT ''
        );
    ]])
    add_col(config.ESP_DB, "esp_slots", "ap_id", "INTEGER DEFAULT 0")
    pcall(function()
        local ap_db = require("fastfi.db.access_points")
        ap_db.ensure_builtin_aps()
    end)

    sqlite.execute(config_db, string.format("INSERT OR REPLACE INTO sys_config (key, value) VALUES ('schema_version', '%d');", CURRENT_VERSION))

    
    
    
    local default_vlan_file = "/etc/fastfi/vlan_default.sql"
    local vf = io.open(default_vlan_file, "r")
    if vf then
        local sql = vf:read("*a")
        vf:close()
        if sql and sql:match("%S") then
            local ok, err = pcall(function() sqlite.execute(config_db, sql) end)
            if not ok then
                
                print(string.format("[KonekSik-Fi] WARNING: vlan_default.sql failed: %s", tostring(err)))
            else
                print("[KonekSik-Fi] Applied factory VLAN default from /etc/fastfi/vlan_default.sql")
            end
        end
    end

    
    
    
    
    

    return true
end

return M
