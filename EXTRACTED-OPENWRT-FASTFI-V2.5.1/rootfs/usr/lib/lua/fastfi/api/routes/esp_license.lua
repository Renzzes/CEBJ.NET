-- KonekSik offline ESP licensing (no FastFi cloud pool).
-- License IDs come from esp-license-provisioner (Ed25519-signed blob on the ESP).
-- Rules: one live MAC per license on this router. No grace-based replacement.
-- Legacy grace_used / grace_max columns remain for schema and .ksk parse compat.

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
    pcall(function()
        sqlite.execute(config.ESP_DB, "ALTER TABLE esp_licenses ADD COLUMN license_hash TEXT;")
    end)
    pcall(function()
        sqlite.execute(config.ESP_DB, "ALTER TABLE esp_licenses ADD COLUMN ksk_verified INTEGER DEFAULT 0;")
    end)
    pcall(function()
        sqlite.execute(config.ESP_DB, "ALTER TABLE esp_licenses ADD COLUMN ksk_ever_bound INTEGER DEFAULT 0;")
    end)
    pcall(function()
        sqlite.execute(config.ESP_DB, "ALTER TABLE esp_licenses ADD COLUMN last_live_mac TEXT;")
    end)
    pcall(function()
        sqlite.execute(config.ESP_DB, "ALTER TABLE esp_licenses ADD COLUMN signed_ksk TEXT;")
    end)
    local bind = require("fastfi.license.ksk_bind")
    pcall(function()
        sqlite.execute(config.ESP_DB, bind.LEGACY_EVER_BOUND_SQL)
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

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local s = f:read("*a") or ""
    f:close()
    return s
end

--- Collect LAN ESP MAC candidates (DHCP + ARP + recent esp_slots).
--- Owner does not need to type MAC; License ID stays manual on Detect.
function M.scan(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    ensure_schema()

    local now = os.time()
    local router_mac = norm_mac(config.MACHINE_ID or "")
    local seen = {}
    local candidates = {}

    local function add_cand(mac, source, ip, hostname, score)
        mac = norm_mac(mac)
        if mac == "" or not mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then return end
        if router_mac ~= "" and mac == router_mac then return end
        -- Skip multicast / locally-invalid
        local first = tonumber(mac:sub(1, 2), 16) or 0
        if (first % 2) == 1 then return end -- multicast bit
        if seen[mac] then
            -- bump score / enrich
            for _, c in ipairs(candidates) do
                if c.mac == mac then
                    c.score = math.max(c.score or 0, score or 0)
                    if ip and (not c.ip or c.ip == "") then c.ip = ip end
                    if hostname and (not c.hostname or c.hostname == "" or c.hostname == "*") then
                        c.hostname = hostname
                    end
                    if source and c.source and c.source:find(source, 1, true) == nil then
                        c.source = c.source .. "+" .. source
                    end
                    return
                end
            end
            return
        end
        seen[mac] = true
        -- Already licensed live?
        local lic = sqlite.query_row(config.ESP_DB, string.format(
            "SELECT license_status FROM esp_slots WHERE UPPER(slot_mac)='%s';", sqlite.quote(mac)))
        local license_status = (lic and lic[1]) or "unknown"
        table.insert(candidates, {
            mac = mac,
            source = source or "lan",
            ip = ip or "",
            hostname = hostname or "",
            license_status = license_status,
            score = score or 0,
        })
    end

    -- 1) Recent ESP slots that heartbeated / registered (best signal)
    local rows = sqlite.query_list(config.ESP_DB, string.format([[
        SELECT slot_mac, status, license_status, COALESCE(last_seen,0), slot_name
        FROM esp_slots
        WHERE COALESCE(last_seen,0) >= %d
          AND COALESCE(slot_mac,'') != ''
          AND COALESCE(slot_mac,'') != 'gpio-coinslot'
        ORDER BY last_seen DESC;
    ]], now - 600))
    for _, row in ipairs(rows or {}) do
        local mac = row[1]
        local st = tostring(row[2] or "")
        local ls = tostring(row[3] or "")
        local score = 50
        if ls == "unlicensed" or ls == "" then score = score + 40 end
        if st == "online" then score = score + 20 end
        if ls == "inactive_replaced" then score = score - 80 end
        add_cand(mac, "esp_slot", "", row[5] or "", score)
    end

    local function is_espressif_oui(mac)
        -- Chip / STA / W5500 (we stamp W5500 with WIFI_STA MAC) — Espressif OUIs
        local u = string.upper(tostring(mac or ""))
        local prefs = {
            "A4:CB:8F", "A4:CF:12", "24:0A:C4", "30:AE:A4", "84:F3:EB",
            "AC:67:B2", "BC:DD:C2", "CC:50:E3", "98:F4:AB", "24:6F:28",
            "3C:71:BF", "40:F5:20", "48:55:19", "4C:EB:D6", "58:BF:25",
            "7C:9E:BD", "8C:AA:B5", "94:B9:7E", "A0:20:A6", "B4:E6:2D",
            "C4:4F:33", "C8:2B:96", "D8:A0:1D", "DC:4F:22", "E0:5A:1B",
            "E8:68:E7", "EC:FA:BC", "F4:CF:A2", "FC:F5:C4",
        }
        for _, p in ipairs(prefs) do
            if u:sub(1, #p) == p then return true end
        end
        return false
    end

    -- 2) DHCP leases (W5500 / WiFi STA both get a lease from Ruijie)
    local leases = read_file("/tmp/dhcp.leases")
    for line in leases:gmatch("[^\n]+") do
        local parts = {}
        for tok in line:gmatch("%S+") do table.insert(parts, tok) end
        if #parts >= 4 then
            local mac = parts[2]
            local ip = parts[3]
            local host = parts[4] or ""
            local score = 20
            local hl = string.lower(host)
            if hl:find("esp", 1, true) or hl:find("ksk", 1, true) or hl:find("w5500", 1, true)
                or hl:find("espressif", 1, true) then
                score = score + 35
            end
            if is_espressif_oui(mac) then
                score = score + 80  -- real ESP chip / stamped W5500 MAC
            else
                score = score - 25 -- PC / phone / random LAN (false Detect)
            end
            add_cand(mac, "dhcp", ip, host, score)
        end
    end

    -- 3) ARP table (devices that talked to the router recently)
    local arp = read_file("/proc/net/arp")
    for line in arp:gmatch("[^\n]+") do
        if not line:match("^IP") then
            local ip, mac = line:match("^(%S+)%s+%S+%s+%S+%s+(%S+)")
            if mac and mac ~= "00:00:00:00:00:00" then
                local score = 10
                if is_espressif_oui(mac) then score = score + 70 else score = score - 20 end
                add_cand(mac, "arp", ip, "", score)
            end
        end
    end

    table.sort(candidates, function(a, b)
        return (a.score or 0) > (b.score or 0)
    end)

    -- Prefer not-yet-licensed for Detect
    local best = nil
    for _, c in ipairs(candidates) do
        if c.license_status ~= "licensed" and c.license_status ~= "free"
            and c.license_status ~= "inactive_replaced" then
            best = c
            break
        end
    end
    if not best and #candidates > 0 then
        best = candidates[1]
    end

    return {
        status = "ok",
        message = (#candidates == 0)
            and "No ESP/LAN devices found — plug Ethernet, power the ESP, wait for DHCP, then retry"
            or string.format("Found %d candidate(s)", #candidates),
        candidates = candidates,
        suggested_mac = best and best.mac or "",
        count = #candidates,
    }
end

--- Resolve MAC when Admin left it blank (License ID still required).
local function resolve_mac_if_empty(params)
    local mac = norm_mac(params["mac"] or params["esp_mac"] or "")
    if mac ~= "" and mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        return mac, nil
    end
    local scan = M.scan(params)
    if scan.status ~= "ok" then
        return "", scan
    end
    if not scan.suggested_mac or scan.suggested_mac == "" then
        return "", {
            status = "error",
            message = "Could not auto-detect ESP MAC. Plug ESP LAN into Ruijie, wait ~10s, or type MAC manually.",
            candidates = scan.candidates or {},
        }
    end
    -- Multiple strong unlicensed candidates → ask Admin to pick
    local strong = 0
    for _, c in ipairs(scan.candidates or {}) do
        if (c.score or 0) >= 40 and c.license_status ~= "licensed" and c.license_status ~= "inactive_replaced" then
            strong = strong + 1
        end
    end
    if strong > 1 then
        return "", {
            status = "need_pick",
            message = "Multiple ESP/LAN devices found — pick the ESP MAC, then Detect again",
            candidates = scan.candidates,
            suggested_mac = scan.suggested_mac,
        }
    end
    params["mac"] = scan.suggested_mac
    return scan.suggested_mac, nil
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
               s.slot_name, s.slot_mac, s.status, s.license_status,
               COALESCE(l.ksk_ever_bound,0),
               CASE WHEN l.signed_ksk IS NOT NULL AND TRIM(l.signed_ksk)!='' THEN 1 ELSE 0 END
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
            ksk_ever_bound = tonumber(row[12]) or 0,
            -- Flag only — never send the signed payload to the Admin table.
            has_signed_ksk = (tonumber(row[13]) or 0) == 1,
            signed_ksk = ((tonumber(row[13]) or 0) == 1) and "1" or "",
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
    ensure_schema()
    local id = params["id"]
    if not id then
        return { status = "error", message = "Missing license row id" }
    end
    local row = sqlite.query_row(config.ESP_DB, string.format(
        "SELECT status, COALESCE(grace_used,0), COALESCE(ksk_ever_bound,0), " ..
        "CASE WHEN signed_ksk IS NOT NULL AND TRIM(signed_ksk)!='' THEN 1 ELSE 0 END " ..
        "FROM esp_licenses WHERE id='%s';",
        sqlite.quote(tostring(id))))
    if not row then
        return { status = "error", message = "License not found" }
    end
    local status = tostring(row[1] or "")
    local grace_used = tonumber(row[2]) or 0
    local ever_bound = tonumber(row[3]) or 0
    local has_signed = tonumber(row[4]) or 0
    if status ~= "available" then
        return {
            status = "error",
            message = "Only unused available license registrations can be removed. Use Unbind/Del on a live ESP instead.",
            code = "REMOVE_NOT_AVAILABLE",
        }
    end
    -- Preserve replacement history: never delete rows that were bound or hold a signed KSK.
    if grace_used > 0 or ever_bound > 0 or has_signed > 0 then
        return {
            status = "error",
            message = "This license has binding history. Remove is blocked so grace history is preserved.",
            code = "REMOVE_HISTORY_PRESERVED",
        }
    end
    sqlite.execute(config.ESP_DB, string.format(
        "DELETE FROM esp_licenses WHERE id='%s' AND status='available' " ..
        "AND COALESCE(grace_used,0)=0 AND COALESCE(ksk_ever_bound,0)=0 " ..
        "AND (signed_ksk IS NULL OR TRIM(signed_ksk)='');",
        sqlite.quote(tostring(id))))
    return { status = "ok", message = "Unused license registration removed" }
end

local function detect_user_message(code, fallback)
    if code == "MISSING_SIGNED_KSK" then
        return "Invalid KSK input. Please load the signed .ksk license file."
    elseif code == "INVALID_FORMAT" then
        return "Invalid KSK license: the signed license data is malformed."
    elseif code == "INVALID_SIGNATURE" then
        return "KSK signature verification failed."
    elseif code == "INVALID_IDENTITY" then
        return "ESP identity does not match this KSK."
    elseif code == "EXPIRED" then
        return "KSK license has expired."
    elseif code == "ROUTER_DEVICE_MISMATCH" then
        return "This KSK is bound to another Router Device ID."
    elseif code == "INVALID_TYPE" then
        return "Invalid KSK license type."
    elseif code == "INVALID_ID" then
        return "Invalid KSK license: the signed license data is malformed."
    end
    return fallback or "KSK verify failed"
end

local function unwrap_bundle_ksk(params)
    local json = require("fastfi.util.json")
    local raw = params.ksk
    if type(raw) == "string" and raw:find("{", 1, true) then
        local ok, obj = pcall(json.decode, raw)
        if ok and type(obj) == "table" and obj.type == "ksk_replacement_bundle"
            and type(obj.license) == "table" and type(obj.license.sig_b64) == "string" then
            -- Re-encode license object for prepare(). Verifier uses canonical form.
            params.ksk = json.encode(obj.license)
            params.ksk_b64 = nil
            params.ksk_b64url = nil
        end
    end
    return params
end

--- Shared prep for Admin verify/bind. Returns (params, verdict_or_err).
--- verdict_or_err has .code; VALID means cryptographic prepare succeeded.
local function admin_prepare_ksk(params)
    params = params or {}
    local function pasted(v)
        return type(v) == "string" and v:gsub("%s+", "") ~= ""
    end
    if pasted(params.ksk_paste) or pasted(params.pasted_ksk) or pasted(params.ksk_text) or pasted(params.manual_ksk) then
        return params, {
            status = "error",
            message = "Signed KSK file required.",
            code = "MANUAL_KSK_REJECTED",
        }
    end
    params = unwrap_bundle_ksk(params)

    local has_ksk = (type(params.ksk) == "string" and params.ksk:find("{", 1, true))
        or (type(params.ksk_b64) == "string" and params.ksk_b64 ~= "")
        or (type(params.ksk_b64url) == "string" and params.ksk_b64url ~= "")
    if not has_ksk then
        local lid = tostring(params.license_id or params.key or ""):gsub("%s+", "")
        if lid ~= "" then
            os.execute("logger -t fastfi-ksk 'reject bare license_id without signed KSK' >/dev/null 2>&1")
        end
        return params, {
            status = "error",
            message = detect_user_message("MISSING_SIGNED_KSK"),
            code = "MISSING_SIGNED_KSK",
        }
    end

    if params._from_register ~= true then
        local mac = norm_mac(params["mac"] or params["esp_mac"] or "")
        if mac == "" and type(params.ksk) == "string" and params.ksk:find("{", 1, true) then
            local json = require("fastfi.util.json")
            local ok, obj = pcall(json.decode, params.ksk)
            if ok and type(obj) == "table" then
                if obj.type == "ksk_replacement_bundle" and type(obj.license) == "table" then
                    obj = obj.license
                end
                if obj.mac and tostring(obj.mac) ~= "" then
                    params["mac"] = norm_mac(obj.mac)
                    mac = params["mac"]
                end
                if (not params["chip_id"] or params["chip_id"] == "") and obj.chip_id then
                    params["chip_id"] = obj.chip_id
                end
            end
        end
        if mac == "" then
            local resolved, scan_err = resolve_mac_if_empty(params)
            if scan_err and scan_err.status == "need_pick" then
                return params, scan_err
            end
            if resolved and resolved ~= "" then
                params["mac"] = resolved
            end
        end
    end

    local ksk = require("fastfi.license.ksk_verify")
    local verdict = ksk.prepare(params, os.time())
    if verdict.code ~= "VALID" then
        ksk.log_failure(verdict)
        return params, {
            status = "error",
            message = detect_user_message(verdict.code, verdict.message),
            code = verdict.code,
        }
    end
    return params, verdict
end

local function lookup_existing_license(license_id)
    ensure_schema()
    local lid = norm_lic(license_id)
    if lid == "" then return nil end
    local row = sqlite.query_row(config.ESP_DB, string.format(
        "SELECT id, status, COALESCE(live_mac,''), COALESCE(grace_used,0), COALESCE(grace_max,%d), " ..
        "COALESCE(ksk_ever_bound,0), COALESCE(last_live_mac,''), used_slot_id, " ..
        "CASE WHEN signed_ksk IS NOT NULL AND TRIM(signed_ksk)!='' THEN 1 ELSE 0 END " ..
        "FROM esp_licenses WHERE license_key='%s' OR license_id='%s' LIMIT 1;",
        GRACE_MAX, sqlite.quote(lid), sqlite.quote(lid)))
    if not row then return nil end
    return {
        id = row[1],
        status = row[2] or "",
        live_mac = norm_mac(row[3] or ""),
        grace_used = tonumber(row[4]) or 0,
        grace_max = tonumber(row[5]) or GRACE_MAX,
        ksk_ever_bound = tonumber(row[6]) or 0,
        last_live_mac = norm_mac(row[7] or ""),
        used_slot_id = row[8],
        has_signed_ksk = (tonumber(row[9]) or 0) == 1,
        license_id = lid,
    }
end

--- Compatibility check only. NO database mutation.
--- Legacy grace_* fields are reported for older UIs; they do not authorize bind.
function M.verify(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    params = params or {}
    local _, verdict = admin_prepare_ksk(params)
    if verdict.status == "need_pick" then
        return verdict
    end
    if verdict.code ~= "VALID" then
        return {
            status = "error",
            message = verdict.message or detect_user_message(verdict.code),
            code = verdict.code,
        }
    end

    local existing = lookup_existing_license(verdict.license_id)
    local detected_mac = norm_mac(verdict.mac or "")
    local state = "READY_TO_BIND"
    local message = "ESP32 License Compatibility Verified"
    if existing then
        local live = existing.live_mac
        local last = existing.last_live_mac or ""
        if live ~= "" and live == detected_mac and (existing.status == "used" or existing.status == "active") then
            state = "ALREADY_BOUND_SAME"
            message = "License already exists and is already bound to this ESP."
        elseif live ~= "" and live ~= detected_mac then
            state = "ALREADY_BOUND_OTHER"
            message = "License already exists and is currently bound to another ESP. A second ESP cannot inherit it."
        elseif (existing.has_signed_ksk or existing.ksk_ever_bound > 0) and last ~= "" and last ~= detected_mac then
            state = "REPLACEMENT_DENIED"
            message = "This license was bound to a different ESP. Unbind does not transfer it; buy a new license."
        elseif existing.has_signed_ksk or existing.ksk_ever_bound > 0 then
            state = "EXISTS_UNBOUND"
            message = "License already exists on this router."
        else
            state = "EXISTS_PLACEHOLDER"
            message = "A placeholder license ID exists. Binding will use the signed KSK."
        end
    end

    local json = require("fastfi.util.json")
    local plan, expires_at, grace_max = "", 0, GRACE_MAX
    if type(params.ksk) == "string" then
        local ok, obj = pcall(json.decode, params.ksk)
        if ok and type(obj) == "table" then
            plan = tostring(obj.plan or "")
            expires_at = tonumber(obj.expires_at) or 0
            grace_max = tonumber(obj.grace_max) or GRACE_MAX
        end
    end

    return {
        status = "ok",
        code = state,
        message = message,
        verified = true,
        ready_to_bind = (state == "READY_TO_BIND" or state == "EXISTS_UNBOUND" or state == "EXISTS_PLACEHOLDER"),
        already_bound = (state == "ALREADY_BOUND_SAME"),
        license_id = verdict.license_id,
        mac = detected_mac,
        chip_id = params.chip_id or "",
        plan = plan,
        expires_at = expires_at,
        grace_max = grace_max,
        router_device_id = verdict.router_device_id or "",
        signature = "valid",
        identity = "matched",
        expiry = (expires_at > 0 and "timed") or "never",
        existing = existing,
        current_live_mac = existing and existing.live_mac or "",
        detected_mac = detected_mac,
        grace_used = existing and existing.grace_used or 0,
    }
end

--- Core: verify the signed KSK, then bind. is_ksk_license() is not the trust boundary.
--- A bare license_id cannot create or update a licensed binding.
function M.detect(params)
    if not security.check_admin_session() then
        -- ESP auto-register may call without admin session via register_esp_slot
        if not params or params._from_register ~= true then
            return { status = "error", message = "Unauthorized" }
        end
    end
    params = params or {}
    local prepared, verdict = admin_prepare_ksk(params)
    params = prepared
    if verdict.status == "need_pick" then
        return verdict
    end
    if verdict.code ~= "VALID" then
        return {
            status = "error",
            message = verdict.message or detect_user_message(verdict.code),
            code = verdict.code,
        }
    end

    ensure_schema()

    local bind = require("fastfi.license.ksk_bind")
    local name = params["name"] or params["esp_name"] or ("ESP " .. verdict.mac:sub(-8))
    return bind.commit(config.ESP_DB, {
        license_id = verdict.license_id,
        mac = verdict.mac,
        hash = verdict.license_hash,
        signed_ksk = verdict.raw or "",
        name = name,
        router_mac = config.MACHINE_ID,
        now = os.time(),
    }, M._test_db)
end

-- Compatibility shims (old Admin buttons)
function M.bind(params)
    -- Bind always re-runs full signed-KSK detect/commit. Never trust ID alone.
    params = params or {}
    if params["esp_id"] and not params["mac"] then
        local row = sqlite.query_row(config.ESP_DB, string.format(
            "SELECT slot_mac FROM esp_slots WHERE id='%s';", sqlite.quote(tostring(params["esp_id"]))))
        if row then params["mac"] = row[1] end
    end
    local has_ksk = (type(params.ksk) == "string" and params.ksk:find("{", 1, true))
        or (type(params.ksk_b64) == "string" and params.ksk_b64 ~= "")
        or (type(params.ksk_b64url) == "string" and params.ksk_b64url ~= "")
    if not has_ksk then
        return {
            status = "error",
            message = "Use Detect / Bind ESP32 with the signed .ksk license",
            code = "MISSING_SIGNED_KSK",
        }
    end
    return M.detect(params)
end

-- exec(sql) optional: when provided (sqlite.transaction), all writes share one txn.
local function run_sql(exec, sql)
    if exec then
        exec(sql)
    else
        sqlite.execute(config.ESP_DB, sql)
    end
end

local function unbind_license_row(license_key, exec)
    if not license_key or license_key == "" then return end
    run_sql(exec, string.format(
        "UPDATE esp_licenses SET status='unbound', used_slot_id=NULL, " ..
        "last_live_mac=CASE WHEN live_mac IS NOT NULL AND TRIM(live_mac)!='' THEN live_mac ELSE last_live_mac END, " ..
        "live_mac=NULL, ksk_ever_bound=1 WHERE license_key='%s' OR license_id='%s';",
        sqlite.quote(license_key), sqlite.quote(license_key)))
end

-- Clear every slot demonstrably tied to this license. Signed .ksk stays on the
-- license row; ksk_now rejects credit without a live_mac binding.
local function clear_slots_for_license(license_key, live_mac, last_live_mac, exec)
    if not license_key or license_key == "" then return 0 end
    local key = sqlite.quote(license_key)
    local cleared = 0
    run_sql(exec, string.format(
        "UPDATE esp_slots SET license_status='unlicensed', license_key=NULL " ..
        "WHERE license_key='%s' OR license_key='%s';",
        key, key))
    cleared = cleared + 1
    local function clear_mac(mac)
        mac = tostring(mac or ""):upper():gsub("%s+", "")
        if mac == "" then return end
        local safe = sqlite.quote(mac)
        run_sql(exec, string.format(
            "UPDATE esp_slots SET license_status='unlicensed', license_key=NULL " ..
            "WHERE UPPER(slot_mac)='%s' AND (license_key='%s' OR license_key='%s' OR " ..
            "license_key IS NULL OR TRIM(COALESCE(license_key,''))='');",
            safe, key, key))
    end
    clear_mac(live_mac)
    clear_mac(last_live_mac)
    return cleared
end

local function license_snapshot(license_id)
    if not license_id or license_id == "" then return nil end
    local safe = sqlite.quote(license_id)
    local row = sqlite.query_row(config.ESP_DB, string.format(
        "SELECT license_key, license_id, COALESCE(live_mac,''), COALESCE(last_live_mac,''), used_slot_id " ..
        "FROM esp_licenses WHERE license_key='%s' OR license_id='%s' LIMIT 1;",
        safe, safe))
    if not row then return nil end
    return {
        license_key = row[1] or license_id,
        license_id = row[2] or license_id,
        live_mac = row[3] or "",
        last_live_mac = row[4] or "",
        used_slot_id = row[5],
    }
end

function M.unbind(params)
    if not security.check_admin_session() then
        return { status = "error", message = "Unauthorized" }
    end
    ensure_schema()
    local esp_id = params["esp_id"]
    local license_id = norm_lic(params["license_id"] or params["key"] or "")
    local snap = nil

    if not esp_id and license_id ~= "" then
        snap = license_snapshot(license_id)
        if not snap then
            return { status = "error", message = "License not found" }
        end
        -- used_slot_id may be null or stale; clear by license key + live/last MAC.
        local key = snap.license_key or license_id
        local ok_txn, txn_err = sqlite.transaction(config.ESP_DB, function(exec)
            clear_slots_for_license(key, snap.live_mac, snap.last_live_mac, exec)
            unbind_license_row(key, exec)
        end)
        if not ok_txn then
            return {
                status = "error",
                code = "DATABASE_ERROR",
                message = "Unbind failed; no changes were kept. " .. tostring(txn_err or "database error"),
                license_id = snap.license_id or license_id,
            }
        end
        os.execute("logger -t fastfi-ksk 'KSK unbound: live binding cleared; signed KSK retained' >/dev/null 2>&1")
        return {
            status = "ok",
            message = "ESP unbound",
            license_id = snap.license_id or license_id,
            slots_cleared = true,
        }
    end

    if not esp_id then
        return { status = "error", message = "Missing ESP ID or License ID" }
    end
    local slot = sqlite.query_row(config.ESP_DB, string.format(
        "SELECT license_key, slot_mac FROM esp_slots WHERE id='%s';", sqlite.quote(tostring(esp_id))))
    local key = (slot and slot[1] and slot[1] ~= "") and slot[1] or license_id
    if key == "" then
        sqlite.execute(config.ESP_DB, string.format(
            "UPDATE esp_slots SET license_status='unlicensed', license_key=NULL WHERE id='%s';",
            sqlite.quote(tostring(esp_id))))
        return { status = "ok", message = "ESP unbound" }
    end
    snap = license_snapshot(key)
    local ok_txn, txn_err = sqlite.transaction(config.ESP_DB, function(exec)
        clear_slots_for_license(
            key,
            snap and snap.live_mac or "",
            snap and snap.last_live_mac or (slot and slot[2]) or "",
            exec)
        unbind_license_row(key, exec)
        exec(string.format(
            "UPDATE esp_slots SET license_status='unlicensed', license_key=NULL WHERE id='%s';",
            sqlite.quote(tostring(esp_id))))
    end)
    if not ok_txn then
        return {
            status = "error",
            code = "DATABASE_ERROR",
            message = "Unbind failed; no changes were kept. " .. tostring(txn_err or "database error"),
            license_id = key,
        }
    end
    os.execute("logger -t fastfi-ksk 'KSK unbound: live binding cleared; signed KSK retained' >/dev/null 2>&1")
    return { status = "ok", message = "ESP unbound", license_id = key, slots_cleared = true }
end

function M.free(params)
    return {
        status = "error",
        message = "Free License is removed. Each sealed .ksk authorizes one ESP on one router. Unbind before binding a different device requires a new license.",
    }
end

function M.release(params)
    return M.remove(params)
end

return M
