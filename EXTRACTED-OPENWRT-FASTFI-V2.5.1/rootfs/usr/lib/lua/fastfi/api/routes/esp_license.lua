-- KonekSik offline ESP licensing (no FastFi cloud pool).
-- License IDs come from esp-license-provisioner (Ed25519-signed blob on the ESP).
-- Rules: one live MAC per license; max 3 grace board replacements.

local sqlite = require("fastfi.db.sqlite")
local config = require("fastfi.config")
local security = require("fastfi.security")

local M = {}

local GRACE_MAX = 3

local function ensure_schema()
    pcall(function()
        sqlite.execute(config.ESP_DB, "ALTER TABLE esp_licenses ADD COLUMN grace_used INTEGER DEFAULT 0;")
    end)
    pcall(function()
        sqlite.execute(config.ESP_DB, "ALTER TABLE esp_licenses ADD COLUMN grace_max INTEGER DEFAULT 3;")
    end)
    pcall(function()
        sqlite.execute(config.ESP_DB, "ALTER TABLE esp_licenses ADD COLUMN live_mac TEXT;")
    end)
    pcall(function()
        sqlite.execute(config.ESP_DB, "ALTER TABLE esp_licenses ADD COLUMN license_id TEXT;")
    end)
    pcall(function()
        sqlite.execute(config.ESP_DB, "ALTER TABLE esp_licenses ADD COLUMN source TEXT DEFAULT 'koneksk';")
    end)
end

local function norm_mac(mac)
    mac = string.upper(tostring(mac or ""):gsub("%s+", ""))
    mac = mac:gsub("-", ":"):gsub("%.", ":")
    return mac
end

local function norm_lic(id)
    return string.upper(tostring(id or ""):gsub("%s+", ""))
end

local function is_ksk_license(id)
    id = norm_lic(id)
    if id == "" then return false end
    if id == "FASTFI-FREE-ESP" then return false end
    -- KSK-… from provisioner, or legacy ESP-… accepted offline as import
    return id:match("^KSK%-") ~= nil or id:match("^ESP%-") ~= nil or #id >= 8
end

--- List licensed devices (replaces cloud "pool")
function M.list(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    ensure_schema()

    local list = sqlite.query_list(config.ESP_DB, [[
        SELECT l.id,
               COALESCE(NULLIF(l.license_id,''), l.license_key) AS lid,
               l.status, l.used_at, l.live_mac,
               COALESCE(l.grace_used,0), COALESCE(l.grace_max,3),
               s.slot_name, s.slot_mac, s.status, s.license_status
        FROM esp_licenses l
        LEFT JOIN esp_slots s ON l.used_slot_id = s.id
        WHERE COALESCE(l.license_key,'') != 'FASTFI-FREE-ESP'
        ORDER BY l.id DESC;
    ]])

    local licenses = {}
    for _, row in ipairs(list or {}) do
        table.insert(licenses, {
            id = row[1],
            license_id = row[2] or "",
            license_key = row[2] or "",
            status = row[3] or "available",
            used_at = row[4],
            live_mac = row[5] or "",
            grace_used = tonumber(row[6]) or 0,
            grace_max = tonumber(row[7]) or GRACE_MAX,
            grace_left = math.max(0, (tonumber(row[7]) or GRACE_MAX) - (tonumber(row[6]) or 0)),
            slot_name = row[8],
            slot_mac = row[9],
            esp_status = row[10],
            license_status = row[11],
        })
    end
    return { status = "ok", data = licenses, licenses = licenses }
end

--- Import / register a KSK license id into the router DB (offline; no cloud)
function M.add(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    ensure_schema()

    local key = norm_lic(params["key"] or params["license_id"] or "")
    if key == "" then
        return { status = "error", message = "Missing license ID" }
    end
    if not is_ksk_license(key) then
        return { status = "error", message = "Invalid license ID (use KSK-… from Flasher)" }
    end

    local exists = sqlite.query_row(config.ESP_DB,
        string.format("SELECT id FROM esp_licenses WHERE license_key='%s' OR license_id='%s';",
            sqlite.quote(key), sqlite.quote(key)))
    if exists and exists[1] then
        return { status = "ok", message = "License already registered", id = exists[1] }
    end

    local router_mac = config.MACHINE_ID
    sqlite.execute(config.ESP_DB, string.format(
        "INSERT INTO esp_licenses (license_key, license_id, status, router_mac, grace_used, grace_max, source) VALUES ('%s','%s','available','%s',0,%d,'koneksk');",
        sqlite.quote(key), sqlite.quote(key), sqlite.quote(router_mac), GRACE_MAX))

    return { status = "ok", message = "ESP32 license registered (offline)" }
end

function M.remove(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local id = params["id"]
    if not id then
        return { status = "error", message = "Missing license ID" }
    end
    sqlite.execute(config.ESP_DB, string.format(
        "DELETE FROM esp_licenses WHERE id='%s' AND status='available';", sqlite.quote(tostring(id))))
    return { status = "ok", message = "License removed" }
end

--- Core: detect/bind ESP by MAC + license_id (auto + button share this)
function M.detect(params)
    if not security.check_admin_session() then
        -- ESP auto-register may call without admin session via register_esp_slot
        if not params or params._from_register ~= true then
            return { status = "error", message = "Unauthorized" }
        end
    end
    ensure_schema()

    local mac = norm_mac(params["mac"] or params["esp_mac"] or "")
    local license_id = norm_lic(params["license_id"] or params["key"] or params["license_key"] or "")
    local name = params["name"] or params["esp_name"] or ("ESP " .. mac:sub(-8))

    if mac == "" or not mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        return { status = "error", message = "Valid ESP MAC required (AA:BB:CC:DD:EE:FF)" }
    end
    if license_id == "" or not is_ksk_license(license_id) then
        return { status = "error", message = "Valid KSK license ID required" }
    end

    local router_mac = config.MACHINE_ID
    local now = os.time()

    -- Ensure license row
    local lic = sqlite.query_row(config.ESP_DB, string.format(
        "SELECT id, status, COALESCE(grace_used,0), COALESCE(grace_max,%d), live_mac, used_slot_id FROM esp_licenses WHERE license_key='%s' OR license_id='%s';",
        GRACE_MAX, sqlite.quote(license_id), sqlite.quote(license_id)))

    if not lic or not lic[1] then
        sqlite.execute(config.ESP_DB, string.format(
            "INSERT INTO esp_licenses (license_key, license_id, status, router_mac, grace_used, grace_max, source) VALUES ('%s','%s','available','%s',0,%d,'koneksk');",
            sqlite.quote(license_id), sqlite.quote(license_id), sqlite.quote(router_mac), GRACE_MAX))
        lic = sqlite.query_row(config.ESP_DB, string.format(
            "SELECT id, status, COALESCE(grace_used,0), COALESCE(grace_max,%d), live_mac, used_slot_id FROM esp_licenses WHERE license_key='%s';",
            GRACE_MAX, sqlite.quote(license_id)))
    end

    local lic_id = lic[1]
    local grace_used = tonumber(lic[3]) or 0
    local grace_max = tonumber(lic[4]) or GRACE_MAX
    local live_mac = norm_mac(lic[5] or "")

    local grace_event = false
    if live_mac ~= "" and live_mac ~= mac then
        -- Replacement board under same license
        if grace_used >= grace_max then
            return {
                status = "error",
                message = "Grace limit reached (3/3). Buy a new license from the seller.",
                grace_used = grace_used,
                grace_max = grace_max,
            }
        end
        grace_used = grace_used + 1
        grace_event = true
        -- Drop old live MAC slot
        sqlite.execute(config.ESP_DB, string.format(
            "UPDATE esp_slots SET license_status='inactive_replaced', license_key=NULL, status='offline' WHERE UPPER(slot_mac)='%s';",
            sqlite.quote(live_mac)))
    end

    -- Upsert slot for this MAC
    local slot = sqlite.query_row(config.ESP_DB, string.format(
        "SELECT id FROM esp_slots WHERE UPPER(slot_mac)='%s';", sqlite.quote(mac)))
    local slot_id
    if slot and slot[1] then
        slot_id = tonumber(slot[1])
        sqlite.execute(config.ESP_DB, string.format(
            "UPDATE esp_slots SET slot_name='%s', status='online', license_status='licensed', license_key='%s', last_seen=%d, router_mac='%s' WHERE id=%d;",
            sqlite.quote(name), sqlite.quote(license_id), now, sqlite.quote(router_mac), slot_id))
    else
        sqlite.execute(config.ESP_DB, string.format(
            "INSERT INTO esp_slots (slot_name, slot_mac, router_mac, status, license_status, license_key, last_seen) VALUES ('%s','%s','%s','online','licensed','%s',%d);",
            sqlite.quote(name), sqlite.quote(mac), sqlite.quote(router_mac), sqlite.quote(license_id), now))
        local id_row = sqlite.query_row(config.ESP_DB, "SELECT last_insert_rowid();")
        slot_id = tonumber(id_row and id_row[1]) or 0
    end

    sqlite.execute(config.ESP_DB, string.format(
        "UPDATE esp_licenses SET status='used', used_slot_id=%d, used_at=datetime('now'), router_mac='%s', live_mac='%s', license_id='%s', grace_used=%d, grace_max=%d WHERE id=%d;",
        slot_id, sqlite.quote(router_mac), sqlite.quote(mac), sqlite.quote(license_id), grace_used, grace_max, lic_id))

    return {
        status = "ok",
        message = grace_event
            and string.format("ESP32 detected — grace %d/%d used; Insert Coin active", grace_used, grace_max)
            or "ESP32 detected and licensed — Insert Coin active",
        slot_id = slot_id,
        license_id = license_id,
        live_mac = mac,
        grace_used = grace_used,
        grace_max = grace_max,
        grace_left = math.max(0, grace_max - grace_used),
        licensed = true,
    }
end

-- Compatibility shims (old Admin buttons)
function M.bind(params)
    params = params or {}
    -- Old UI passed esp_id only and pulled next pool key — now require license_id
    if params["license_id"] or params["key"] then
        if params["esp_id"] and not params["mac"] then
            local row = sqlite.query_row(config.ESP_DB, string.format(
                "SELECT slot_mac FROM esp_slots WHERE id='%s';", sqlite.quote(tostring(params["esp_id"]))))
            if row then params["mac"] = row[1] end
        end
        return M.detect(params)
    end
    return { status = "error", message = "Use Detect ESP32 with MAC + License ID" }
end

function M.unbind(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    local esp_id = params["esp_id"]
    if not esp_id then
        return { status = "error", message = "Missing ESP ID" }
    end
    local slot = sqlite.query_row(config.ESP_DB, string.format(
        "SELECT license_key, slot_mac FROM esp_slots WHERE id='%s';", sqlite.quote(tostring(esp_id))))
    if slot and slot[1] and slot[1] ~= "" then
        sqlite.execute(config.ESP_DB, string.format(
            "UPDATE esp_licenses SET status='available', used_slot_id=NULL, live_mac=NULL WHERE license_key='%s' OR license_id='%s';",
            sqlite.quote(slot[1]), sqlite.quote(slot[1])))
    end
    sqlite.execute(config.ESP_DB, string.format(
        "UPDATE esp_slots SET license_status='unlicensed', license_key=NULL WHERE id='%s';",
        sqlite.quote(tostring(esp_id))))
    return { status = "ok", message = "ESP unbound" }
end

function M.free(params)
    -- Replaced by grace Detect flow — keep no-op friendly message
    return {
        status = "error",
        message = "Free License is removed. Flash the same sealed license onto a new ESP (buyer flasher), then Detect ESP32 (grace ≤ 3).",
    }
end

function M.release(params)
    return M.remove(params)
end

return M
