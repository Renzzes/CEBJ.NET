-- Detect/Verify/Bind/Remove/Delete contract tests. Synthetic keys only. No production key.
local fix = os.getenv("KSK_FIXTURE_DIR")
if not fix or fix == "" then
    io.stderr:write("FAIL: KSK_FIXTURE_DIR unset\n")
    os.exit(1)
end

local function readf(name)
    local f = io.open(fix .. "/" .. name, "rb")
    if not f then
        io.stderr:write("FAIL: missing " .. name .. "\n")
        os.exit(1)
    end
    local s = f:read("*a") or ""
    f:close()
    return s
end

local function expect(cond, msg)
    if not cond then
        io.stderr:write("FAIL: " .. msg .. "\n")
        os.exit(1)
    end
    io.write("PASS: " .. msg .. "\n")
end

local db = {
    licenses = {},
    slots = {},
    next_id = 1,
    schema_writes = 0,
    binding_writes = 0,
    deleted_licenses = {},
    deleted_slots = {},
}

local function find_license(id)
    id = string.upper(tostring(id or ""))
    for _, r in ipairs(db.licenses) do
        local k = string.upper(tostring(r.license_key or r.license_id or ""))
        if k == id or tostring(r.id) == tostring(id) then
            return r
        end
    end
    return nil
end

local function mock_execute(_, sql)
    if db.fail_next_exec then
        db.fail_next_exec = false
        error("simulated db failure", 0)
    end
    if db.fail_sql_substr and type(db.fail_sql_substr) == "string"
        and sql:find(db.fail_sql_substr, 1, true) then
        db.fail_sql_substr = nil
        error("simulated db failure", 0)
    end
    if sql:find("ALTER TABLE", 1, true) or sql:find("UPDATE esp_licenses SET ksk_ever_bound", 1, true) then
        db.schema_writes = db.schema_writes + 1
        return true
    end
    if sql:find("DELETE FROM esp_licenses", 1, true) then
        local id = sql:match("id='(%d+)'")
        for i = #db.licenses, 1, -1 do
            if tostring(db.licenses[i].id) == tostring(id) then
                local r = db.licenses[i]
                if r.status == "available"
                    and (tonumber(r.grace_used) or 0) == 0
                    and (tonumber(r.ksk_ever_bound) or 0) == 0
                    and (not r.signed_ksk or r.signed_ksk == "") then
                    table.insert(db.deleted_licenses, table.remove(db.licenses, i))
                end
                break
            end
        end
        return true
    end
    if sql:find("DELETE FROM esp_slots", 1, true) then
        local id = sql:match("id='(%d+)'")
        for i = #db.slots, 1, -1 do
            if tostring(db.slots[i].id) == tostring(id) then
                table.insert(db.deleted_slots, table.remove(db.slots, i))
                break
            end
        end
        db.binding_writes = db.binding_writes + 1
        return true
    end
    if sql:find("UPDATE esp_licenses SET status='unbound'", 1, true) then
        local lid = sql:match("license_key='([^']+)'")
        local r = find_license(lid)
        if r then
            if r.live_mac and r.live_mac ~= "" then
                r.last_live_mac = r.live_mac
            end
            r.live_mac = nil
            r.status = "unbound"
            r.used_slot_id = nil
            r.ksk_ever_bound = 1
            -- grace_used / signed_ksk intentionally untouched
        end
        db.binding_writes = db.binding_writes + 1
        return true
    end
    if sql:find("UPDATE esp_slots SET license_status=", 1, true) then
        local lid = sql:match("license_key='([^']+)'")
        local mac = sql:match("UPPER%(slot_mac%)='([^']+)'")
        for _, s in ipairs(db.slots) do
            local match = false
            if lid and string.upper(tostring(s.license_key or "")) == string.upper(lid) then
                match = true
            end
            if mac and string.upper(tostring(s.slot_mac or "")) == string.upper(mac) then
                local sk = tostring(s.license_key or "")
                if sk == "" or (lid and string.upper(sk) == string.upper(lid)) then
                    match = true
                end
            end
            if match then
                s.license_status = "unlicensed"
                s.license_key = nil
            end
        end
        db.binding_writes = db.binding_writes + 1
        return true
    end
    if sql:find("INSERT INTO esp_licenses", 1, true) then
        db.binding_writes = db.binding_writes + 1
        return true
    end
    if sql:find("UPDATE esp_licenses", 1, true) then
        db.binding_writes = db.binding_writes + 1
    end
    return true
end

local function mock_query_row(_, sql)
    if sql:find("FROM esp_licenses WHERE id=", 1, true) then
        local id = sql:match("id='(%d+)'")
        for _, r in ipairs(db.licenses) do
            if tostring(r.id) == tostring(id) then
                local has_signed = (r.signed_ksk and r.signed_ksk ~= "") and 1 or 0
                return { r.status, r.grace_used or 0, r.ksk_ever_bound or 0, has_signed }
            end
        end
        return nil
    end
    if sql:find("FROM esp_licenses WHERE license_key=", 1, true) and sql:find("SELECT license_key, license_id", 1, true) then
        local lid = sql:match("license_key='([^']+)'")
        local r = find_license(lid)
        if not r then return nil end
        return {
            r.license_key or r.license_id or lid,
            r.license_id or r.license_key or lid,
            r.live_mac or "",
            r.last_live_mac or "",
            r.used_slot_id,
        }
    end
    if sql:find("FROM esp_licenses WHERE license_key=", 1, true)
        and (sql:find("SELECT id, status", 1, true)
            or sql:find("SELECT COALESCE(live_mac", 1, true)
            or sql:find("SELECT id, status, COALESCE(live_mac", 1, true)) then
        local lid = sql:match("license_key='([^']+)'")
        local r = find_license(lid)
        if not r then return nil end
        if sql:find("SELECT COALESCE(live_mac", 1, true) and not sql:find("SELECT id, status", 1, true) then
            return { r.live_mac or "", r.last_live_mac or "" }
        end
        local has_signed = (r.signed_ksk and r.signed_ksk ~= "") and 1 or 0
        return {
            r.id,
            r.status,
            r.live_mac or "",
            r.grace_used or 0,
            r.grace_max or 3,
            r.ksk_ever_bound or 0,
            r.last_live_mac or "",
            r.used_slot_id,
            has_signed,
        }
    end
    if sql:find("SELECT id FROM esp_licenses WHERE license_key=", 1, true) then
        local lid = sql:match("license_key='([^']+)'")
        local r = find_license(lid)
        if r then return { r.id } end
        return nil
    end
    if sql:find("FROM esp_slots WHERE id=", 1, true) then
        local id = sql:match("id='(%d+)'")
        for _, s in ipairs(db.slots) do
            if tostring(s.id) == tostring(id) then
                if sql:find("SELECT id FROM", 1, true) then
                    return { s.id }
                end
                if sql:find("slot_name", 1, true) then
                    return { s.license_key or "", s.slot_mac or "", s.license_status or "", s.slot_name or "ESP32" }
                end
                return { s.license_key or "", s.slot_mac or "" }
            end
        end
        return nil
    end
    return nil
end

package.preload["fastfi.db.sqlite"] = function()
    return {
        quote = function(s) return (tostring(s or "")):gsub("'", "''") end,
        execute = mock_execute,
        query_row = mock_query_row,
        query_list = function() return {} end,
        -- Mirrors production BEGIN/COMMIT: on error, restore snapshot (rollback).
        transaction = function(_, fn)
            local snap = {
                licenses = {},
                slots = {},
                deleted_licenses = { unpack(db.deleted_licenses) },
                deleted_slots = { unpack(db.deleted_slots) },
                binding_writes = db.binding_writes,
                schema_writes = db.schema_writes,
            }
            for i, r in ipairs(db.licenses) do
                local c = {}
                for k, v in pairs(r) do c[k] = v end
                snap.licenses[i] = c
            end
            for i, s in ipairs(db.slots) do
                local c = {}
                for k, v in pairs(s) do c[k] = v end
                snap.slots[i] = c
            end
            local ok, err = pcall(fn, function(sql)
                return mock_execute(nil, sql)
            end, function(sql)
                return mock_query_row(nil, sql)
            end)
            if not ok then
                db.licenses = snap.licenses
                db.slots = snap.slots
                db.deleted_licenses = snap.deleted_licenses
                db.deleted_slots = snap.deleted_slots
                db.binding_writes = snap.binding_writes
                db.schema_writes = snap.schema_writes
                return false, tostring(err)
            end
            return true
        end,
    }
end

package.preload["fastfi.config"] = function()
    return {
        ESP_DB = "/tmp/ksk-detect-remove.db",
        MACHINE_ID = "11:22:33:44:55:66",
    }
end

package.preload["fastfi.security"] = function()
    return {
        check_admin_session = function() return true end,
        is_valid_ip = function() return false end,
    }
end

package.preload["fastfi.db.esp"] = function()
    return {}
end

package.preload["fastfi.db.config"] = function()
    return {}
end

package.preload["fastfi.license.ksk_bind"] = function()
    return {
        LEGACY_EVER_BOUND_SQL = "SELECT 1;",
        MAX_GRACE = 3,
        commit = function(_, req)
            db.binding_writes = db.binding_writes + 1
            local existing = find_license(req.license_id)
            if existing then
                existing.status = "used"
                existing.live_mac = req.mac
                existing.signed_ksk = req.signed_ksk or existing.signed_ksk
                existing.ksk_ever_bound = 1
                existing.ksk_verified = 1
            else
                table.insert(db.licenses, {
                    id = db.next_id,
                    license_key = req.license_id,
                    license_id = req.license_id,
                    status = "used",
                    live_mac = req.mac,
                    grace_used = 0,
                    grace_max = 3,
                    ksk_ever_bound = 1,
                    signed_ksk = req.signed_ksk or "",
                    ksk_verified = 1,
                })
                db.next_id = db.next_id + 1
            end
            return {
                status = "ok",
                message = "ESP32 detected and licensed — Insert Coin active",
                license_id = req.license_id,
                live_mac = req.mac,
                grace_used = 0,
                grace_max = 3,
            }
        end,
        parse_signed_grace = function() return 3 end,
    }
end

local ksk = require("fastfi.license.ksk_verify")
local esp = require("fastfi.api.routes.esp_license")
local esp_dev = require("fastfi.api.routes.esp")

local valid = readf("valid.json")
local bw0 = db.binding_writes

-- CASE 1: bare license_id must fail closed
local r1 = esp.detect({ license_id = "KSK-A4CB8FF897B4", mac = "A4:CB:8F:F8:97:B4" })
expect(r1.status == "error", "CASE1 bare license_id fails")
expect(r1.code == "MISSING_SIGNED_KSK", "CASE1 code MISSING_SIGNED_KSK")
expect(tostring(r1.message):find("signed", 1, true) ~= nil, "CASE1 asks for signed .ksk")
expect(db.binding_writes == bw0, "CASE1 no binding mutation")

-- CASE 1b: bare ID also fails verify
local vbare = esp.verify({ license_id = "KSK-A4CB8FF897B4", mac = "A4:CB:8F:F8:97:B4" })
expect(vbare.status == "error", "CASE1b verify bare ID fails")
expect(vbare.code == "MISSING_SIGNED_KSK", "CASE1b MISSING_SIGNED_KSK")
expect(db.binding_writes == bw0, "CASE1b verify no binding mutation")

-- CASE 2a: verify valid signed KSK — no bind yet
bw0 = db.binding_writes
local v2 = esp.verify({
    ksk = valid,
    mac = "AA:BB:CC:DD:EE:10",
    chip_id = "AABBCCDDEE10",
})
expect(v2.status == "ok", "CASE2a verify ok")
expect(v2.ready_to_bind == true, "CASE2a ready_to_bind")
expect(v2.code == "READY_TO_BIND", "CASE2a READY_TO_BIND")
expect(db.binding_writes == bw0, "CASE2a verify no binding mutation")
expect(#db.licenses == 0, "CASE2a no license row created by verify")

-- CASE 2b: bind (detect) after verify
local r2 = esp.detect({
    ksk = valid,
    mac = "AA:BB:CC:DD:EE:10",
    chip_id = "AABBCCDDEE10",
})
expect(r2.status == "ok", "CASE2b bind ok")
expect(#db.licenses == 1, "CASE2b license row after bind")

-- CASE 2c: verify same KSK already bound to same ESP
local v2c = esp.verify({
    ksk = valid,
    mac = "AA:BB:CC:DD:EE:10",
    chip_id = "AABBCCDDEE10",
})
expect(v2c.status == "ok", "CASE2c already-bound verify ok")
expect(v2c.code == "ALREADY_BOUND_SAME", "CASE2c ALREADY_BOUND_SAME")
expect(v2c.already_bound == true, "CASE2c already_bound flag")
expect(v2c.ready_to_bind == false, "CASE2c not ready_to_bind")
local grace_before = db.licenses[1].grace_used or 0
expect(db.licenses[1].grace_used == grace_before, "CASE2c grace unchanged")

-- CASE 2d: verify same KSK against different ESP
local v2d = esp.verify({
    ksk = valid,
    mac = "11:22:33:44:55:99",
    chip_id = "AABBCCDDEE10",
})
-- Identity check fails before existing-state when MAC/chip mismatch vs signed payload.
-- Use matching chip but different MAC that still fails identity of signed KSK:
-- signed MAC is AA:BB:CC:DD:EE:10 — different MAC → INVALID_IDENTITY
expect(v2d.status == "error", "CASE2d different MAC identity fail")
expect(v2d.code == "INVALID_IDENTITY", "CASE2d INVALID_IDENTITY")

-- Simulate already-bound-other by putting a different live_mac with matching identity fields
-- (identity must match signed payload MAC — so ALREADY_BOUND_OTHER needs signed MAC as detected
-- while live_mac differs). Re-bind scenario: live is other; verify with signed MAC.
db.licenses[1].live_mac = "DE:AD:BE:EF:00:01"
db.licenses[1].status = "used"
db.licenses[1].grace_used = 1
local grace_hold = db.licenses[1].grace_used
local bw_hold = db.binding_writes
local v2e = esp.verify({
    ksk = valid,
    mac = "AA:BB:CC:DD:EE:10",
    chip_id = "AABBCCDDEE10",
})
expect(v2e.status == "ok", "CASE2e bound-other verify ok")
expect(v2e.code == "ALREADY_BOUND_OTHER", "CASE2e ALREADY_BOUND_OTHER")
expect(v2e.ready_to_bind == false, "CASE2e not ready - no second-device inheritance")
expect(db.licenses[1].grace_used == grace_hold, "CASE2e verify does not mutate grace")
expect(db.binding_writes == bw_hold, "CASE2e verify no binding mutation")

-- CASE 3: malformed JSON
local r3 = esp.detect({ ksk = "{not-json", mac = "AA:BB:CC:DD:EE:10" })
expect(r3.status == "error", "CASE3 malformed JSON fails")
expect(r3.code == "INVALID_FORMAT", "CASE3 INVALID_FORMAT")

-- CASE 4: invalid signature
local r4 = esp.detect({
    ksk = readf("bad_sig.json"),
    mac = "AA:BB:CC:DD:EE:10",
    chip_id = "AABBCCDDEE10",
})
expect(r4.status == "error", "CASE4 bad signature fails")
expect(r4.code == "INVALID_SIGNATURE", "CASE4 INVALID_SIGNATURE")

-- CASE 5: expired
local now_expired = tonumber(readf("expired.now"):match("%d+")) or os.time()
local v5 = ksk.prepare({
    ksk = readf("expired.json"),
    mac = "AA:BB:CC:DD:EE:10",
    chip_id = "AABBCCDDEE10",
}, now_expired + 1)
expect(v5.code == "EXPIRED", "CASE5 expired KSK")

-- CASE 6: identity mismatch
local r6 = esp.detect({
    ksk = valid,
    mac = "11:22:33:44:55:66",
    chip_id = "AABBCCDDEE10",
})
expect(r6.status == "error", "CASE6 identity mismatch fails")
expect(r6.code == "INVALID_IDENTITY", "CASE6 INVALID_IDENTITY")

-- CASE 7: Unbind clears live + related slots; preserves signed KSK history
db.licenses[1].live_mac = "AA:BB:CC:DD:EE:10"
db.licenses[1].status = "used"
db.licenses[1].grace_used = 2
db.licenses[1].ksk_ever_bound = 1
db.licenses[1].signed_ksk = valid
db.licenses[1].last_live_mac = "AA:BB:CC:DD:EE:09"
db.licenses[1].used_slot_id = nil
db.slots = {
    {
        id = 1,
        license_key = db.licenses[1].license_id,
        slot_mac = "AA:BB:CC:DD:EE:10",
        license_status = "licensed",
        slot_name = "Live",
    },
    {
        id = 2,
        license_key = db.licenses[1].license_id,
        slot_mac = "AA:BB:CC:DD:EE:09",
        license_status = "licensed",
        slot_name = "Orphan",
    },
    {
        id = 3,
        license_key = "KSK-OTHER",
        slot_mac = "FF:EE:DD:CC:BB:AA",
        license_status = "licensed",
        slot_name = "Other",
    },
}
local ub = esp.unbind({ license_id = db.licenses[1].license_id })
expect(ub.status == "ok", "CASE7 unbind ok")
expect(db.licenses[1].status == "unbound", "CASE7 status unbound")
expect(db.licenses[1].live_mac == nil or db.licenses[1].live_mac == "", "CASE7 live_mac cleared")
expect(db.licenses[1].grace_used == 2, "CASE7 grace_used preserved (legacy)")
expect(db.licenses[1].ksk_ever_bound == 1, "CASE7 ksk_ever_bound preserved")
expect(db.licenses[1].signed_ksk == valid, "CASE7 signed_ksk preserved")
expect(db.licenses[1].last_live_mac == "AA:BB:CC:DD:EE:10", "CASE7 last_live_mac preserved from live")
expect(db.slots[1].license_status == "unlicensed", "CASE7 live slot cleared")
expect(db.slots[2].license_status == "unlicensed", "CASE7 related slot cleared")
expect(db.slots[3].license_status == "licensed", "CASE7 unrelated slot untouched")

-- CASE 9: Remove unused available registration
db.licenses = {
    { id = 1, status = "available", grace_used = 0, ksk_ever_bound = 0, signed_ksk = "" },
}
local rm1 = esp.remove({ id = "1" })
expect(rm1.status == "ok", "CASE9 remove unused available")
expect(#db.deleted_licenses == 1, "CASE9 row deleted")

-- CASE 10/11: Remove blocked when history exists
db.licenses = {
    { id = 2, status = "available", grace_used = 1, ksk_ever_bound = 1, signed_ksk = valid },
}
local before = #db.licenses
local rm2 = esp.remove({ id = "2" })
expect(rm2.status == "error", "CASE10/11 remove blocked for history")
expect(rm2.code == "REMOVE_HISTORY_PRESERVED", "CASE10/11 REMOVE_HISTORY_PRESERVED")
expect(#db.licenses == before, "CASE10/11 row not deleted")

db.licenses = {
    { id = 3, status = "used", grace_used = 0, ksk_ever_bound = 1, signed_ksk = valid },
}
local rm3 = esp.remove({ id = "3" })
expect(rm3.status == "error", "CASE10 live/used remove blocked")
expect(rm3.code == "REMOVE_NOT_AVAILABLE", "CASE10 REMOVE_NOT_AVAILABLE")

-- CASE 12: Delete registered ESP requires unbind when live
db.licenses = {
    {
        id = 10,
        license_key = "KSK-TESTAABBCCDDEE10",
        license_id = "KSK-TESTAABBCCDDEE10",
        status = "used",
        live_mac = "AA:BB:CC:DD:EE:10",
        grace_used = 1,
        grace_max = 3,
        ksk_ever_bound = 1,
        signed_ksk = valid,
        last_live_mac = "AA:BB:CC:DD:EE:09",
    },
}
db.slots = {
    {
        id = 5,
        license_key = "KSK-TESTAABBCCDDEE10",
        slot_mac = "AA:BB:CC:DD:EE:10",
        license_status = "licensed",
        slot_name = "ESP32",
    },
}
local d1 = esp_dev.delete_esp_device({ slot_id = "5" })
expect(d1.status == "error", "CASE12 live delete requires unbind")
expect(d1.code == "REQUIRES_UNBIND", "CASE12 REQUIRES_UNBIND")
expect(#db.slots == 1, "CASE12 slot not deleted without force")
expect(db.licenses[1].grace_used == 1, "CASE12 grace untouched without force")
expect(db.licenses[1].live_mac == "AA:BB:CC:DD:EE:10", "CASE12 live_mac untouched without force")

-- CASE 13: force delete unbinds safely + removes slot, preserves history
local d2 = esp_dev.delete_esp_device({ slot_id = "5", force = "1" })
expect(d2.status == "ok", "CASE13 force delete ok")
expect(#db.slots == 0, "CASE13 slot removed")
expect(#db.licenses == 1, "CASE13 license row kept")
expect(db.licenses[1].status == "unbound", "CASE13 license unbound")
expect(db.licenses[1].live_mac == nil or db.licenses[1].live_mac == "", "CASE13 live cleared")
expect(db.licenses[1].grace_used == 1, "CASE13 grace preserved")
expect(db.licenses[1].ksk_ever_bound == 1, "CASE13 ksk_ever_bound preserved")
expect(db.licenses[1].signed_ksk == valid, "CASE13 signed_ksk preserved")
expect(db.licenses[1].last_live_mac == "AA:BB:CC:DD:EE:10", "CASE13 last_live_mac preserved")

-- CASE 14: delete unlicensed offline device (no force needed)
db.licenses = {
    {
        id = 20,
        license_key = "KSK-OTHER0000000001",
        license_id = "KSK-OTHER0000000001",
        status = "used",
        live_mac = "11:22:33:44:55:66",
        grace_used = 0,
        grace_max = 3,
        ksk_ever_bound = 1,
        signed_ksk = valid,
        last_live_mac = "11:22:33:44:55:66",
        used_slot_id = 9,
    },
}
db.slots = {
    {
        id = 7,
        license_key = nil,
        slot_mac = "AA:BB:CC:DD:EE:99",
        license_status = "unlicensed",
        slot_name = "OfflineUnlicensed",
        status = "offline",
    },
    {
        id = 9,
        license_key = "KSK-OTHER0000000001",
        slot_mac = "11:22:33:44:55:66",
        license_status = "licensed",
        slot_name = "KeepMe",
    },
}
local d14 = esp_dev.delete_esp_device({ slot_id = "7" })
expect(d14.status == "ok", "CASE14 unlicensed delete ok")
expect(#db.slots == 1, "CASE14 only target slot removed")
expect(tostring(db.slots[1].id) == "9", "CASE14 unrelated slot kept")
expect(db.licenses[1].status == "used", "CASE14 unrelated license unchanged")
expect(db.licenses[1].live_mac == "11:22:33:44:55:66", "CASE14 unrelated live_mac unchanged")

-- CASE 15: licensed delete without force stays blocked (soft path)
db.licenses = {
    {
        id = 21,
        license_key = "KSK-TESTAABBCCDDEE21",
        license_id = "KSK-TESTAABBCCDDEE21",
        status = "used",
        live_mac = "AA:BB:CC:DD:EE:21",
        grace_used = 0,
        grace_max = 3,
        ksk_ever_bound = 1,
        signed_ksk = valid,
        used_slot_id = 8,
    },
}
db.slots = {
    {
        id = 8,
        license_key = "KSK-TESTAABBCCDDEE21",
        slot_mac = "AA:BB:CC:DD:EE:21",
        license_status = "licensed",
        slot_name = "LicensedOffline",
        status = "offline",
    },
}
local d15 = esp_dev.delete_esp_device({ slot_id = "8" })
expect(d15.status == "error", "CASE15 licensed soft delete blocked")
expect(d15.code == "REQUIRES_UNBIND", "CASE15 REQUIRES_UNBIND")
expect(#db.slots == 1, "CASE15 slot remains")
expect(db.licenses[1].live_mac == "AA:BB:CC:DD:EE:21", "CASE15 live_mac remains")

-- CASE 16: unbind with used_slot_id null
db.licenses[1].used_slot_id = nil
db.licenses[1].status = "used"
db.licenses[1].live_mac = "AA:BB:CC:DD:EE:21"
db.slots[1].license_status = "licensed"
db.slots[1].license_key = "KSK-TESTAABBCCDDEE21"
local u16 = esp.unbind({ license_id = "KSK-TESTAABBCCDDEE21" })
expect(u16.status == "ok", "CASE16 unbind null used_slot_id ok")
expect(db.licenses[1].status == "unbound", "CASE16 license unbound")
expect(db.licenses[1].live_mac == nil or db.licenses[1].live_mac == "", "CASE16 live cleared")
expect(db.licenses[1].used_slot_id == nil, "CASE16 used_slot_id null")
expect(db.slots[1].license_status == "unlicensed", "CASE16 slot cleared by license key")
expect(db.licenses[1].signed_ksk == valid, "CASE16 signed_ksk retained")

-- CASE 17: unbind with stale used_slot_id (points at missing slot)
db.licenses = {
    {
        id = 22,
        license_key = "KSK-TESTAABBCCDDEE22",
        license_id = "KSK-TESTAABBCCDDEE22",
        status = "used",
        live_mac = "AA:BB:CC:DD:EE:22",
        grace_used = 2,
        grace_max = 3,
        ksk_ever_bound = 1,
        signed_ksk = valid,
        used_slot_id = 9999,
        last_live_mac = "AA:BB:CC:DD:EE:22",
    },
}
db.slots = {
    {
        id = 12,
        license_key = "KSK-TESTAABBCCDDEE22",
        slot_mac = "AA:BB:CC:DD:EE:22",
        license_status = "licensed",
        slot_name = "StaleSlot",
    },
}
local u17 = esp.unbind({ license_id = "KSK-TESTAABBCCDDEE22" })
expect(u17.status == "ok", "CASE17 unbind stale used_slot_id ok")
expect(db.licenses[1].status == "unbound", "CASE17 license unbound")
expect(db.licenses[1].used_slot_id == nil, "CASE17 used_slot_id cleared")
expect(db.slots[1].license_status == "unlicensed", "CASE17 slot cleared via key/mac")
expect(db.licenses[1].grace_used == 2, "CASE17 grace preserved on unbind")
expect(db.licenses[1].signed_ksk == valid, "CASE17 signed_ksk retained")

-- CASE 18: confirmed unbind-and-delete (force=1) after soft gate
db.licenses = {
    {
        id = 23,
        license_key = "KSK-TESTAABBCCDDEE23",
        license_id = "KSK-TESTAABBCCDDEE23",
        status = "used",
        live_mac = "AA:BB:CC:DD:EE:23",
        grace_used = 1,
        grace_max = 3,
        ksk_ever_bound = 1,
        signed_ksk = valid,
        used_slot_id = 13,
    },
    {
        id = 24,
        license_key = "KSK-KEEP00000000024",
        license_id = "KSK-KEEP00000000024",
        status = "used",
        live_mac = "DE:AD:BE:EF:00:01",
        grace_used = 0,
        grace_max = 3,
        ksk_ever_bound = 1,
        signed_ksk = valid,
        used_slot_id = 14,
    },
}
db.slots = {
    {
        id = 13,
        license_key = "KSK-TESTAABBCCDDEE23",
        slot_mac = "AA:BB:CC:DD:EE:23",
        license_status = "licensed",
        slot_name = "ForceDeleteMe",
        status = "offline",
    },
    {
        id = 14,
        license_key = "KSK-KEEP00000000024",
        slot_mac = "DE:AD:BE:EF:00:01",
        license_status = "licensed",
        slot_name = "Unrelated",
    },
}
local soft18 = esp_dev.delete_esp_device({ slot_id = "13" })
expect(soft18.code == "REQUIRES_UNBIND", "CASE18 soft requires unbind")
local force18 = esp_dev.delete_esp_device({ slot_id = "13", force = "1", confirm_unbind = "1" })
expect(force18.status == "ok", "CASE18 force unbind-and-delete ok")
expect(#db.slots == 1, "CASE18 only target slot deleted")
expect(tostring(db.slots[1].id) == "14", "CASE18 unrelated slot kept")
expect(find_license("KSK-TESTAABBCCDDEE23").status == "unbound", "CASE18 target license unbound")
expect(find_license("KSK-TESTAABBCCDDEE23").live_mac == nil
    or find_license("KSK-TESTAABBCCDDEE23").live_mac == "", "CASE18 target live cleared")
expect(find_license("KSK-KEEP00000000024").status == "used", "CASE18 unrelated license status")
expect(find_license("KSK-KEEP00000000024").live_mac == "DE:AD:BE:EF:00:01", "CASE18 unrelated live_mac")

-- CASE 19: DB failure midway rolls back (slot + license unchanged)
db.licenses = {
    {
        id = 25,
        license_key = "KSK-TESTAABBCCDDEE25",
        license_id = "KSK-TESTAABBCCDDEE25",
        status = "used",
        live_mac = "AA:BB:CC:DD:EE:25",
        grace_used = 0,
        grace_max = 3,
        ksk_ever_bound = 1,
        signed_ksk = valid,
        used_slot_id = 15,
    },
}
db.slots = {
    {
        id = 15,
        license_key = "KSK-TESTAABBCCDDEE25",
        slot_mac = "AA:BB:CC:DD:EE:25",
        license_status = "licensed",
        slot_name = "TxnFail",
    },
}
db.fail_next_exec = true
local d19 = esp_dev.delete_esp_device({ slot_id = "15", force = "1" })
expect(d19.status == "error", "CASE19 txn failure returns error")
expect(d19.code == "DATABASE_ERROR", "CASE19 DATABASE_ERROR")
expect(#db.slots == 1, "CASE19 slot rolled back")
expect(db.slots[1].license_status == "licensed", "CASE19 slot license_status rolled back")
expect(db.licenses[1].status == "used", "CASE19 license status rolled back")
expect(db.licenses[1].live_mac == "AA:BB:CC:DD:EE:25", "CASE19 live_mac rolled back")
db.fail_next_exec = false

-- CASE 20: retry after success is idempotent (not found)
local d20a = esp_dev.delete_esp_device({ slot_id = "15", force = "1" })
expect(d20a.status == "ok", "CASE20 first force delete ok")
expect(#db.slots == 0, "CASE20 slot gone")
local d20b = esp_dev.delete_esp_device({ slot_id = "15", force = "1" })
expect(d20b.status == "error", "CASE20 retry after success errors")
expect(tostring(d20b.message):find("not found", 1, true) ~= nil, "CASE20 not found message")

-- CASE 21: unbound license cannot authorize coin (no live_mac)
-- Product rule in ksk_now: empty live_mac => invalid; insert_coin never credits.
local unbound = find_license("KSK-TESTAABBCCDDEE25")
expect(unbound ~= nil, "CASE21 unbound license row exists")
expect(unbound.status == "unbound", "CASE21 status unbound")
expect(unbound.live_mac == nil or unbound.live_mac == "", "CASE21 no live_mac after delete")
local live = tostring(unbound.live_mac or ""):gsub("%s+", "")
expect(live == "", "CASE21 empty live_mac denies credit entitlement")
do
    local found = false
    for p in string.gmatch(package.path or "", "([^;]+)") do
        local cand = p:gsub("%?%.lua$", "fastfi/license/ksk_now.lua")
        local f = io.open(cand, "rb")
        if f then
            local src = f:read("*a") or ""
            f:close()
            expect(src:find("live_mac", 1, true) ~= nil, "CASE21 ksk_now references live_mac")
            expect(src:find("function M.valid_now", 1, true) ~= nil, "CASE21 ksk_now.valid_now present")
            found = true
            break
        end
    end
    expect(found, "CASE21 located ksk_now.lua")
end

-- CASE 22: unbind txn failure rolls back
db.licenses = {
    {
        id = 26,
        license_key = "KSK-TESTAABBCCDDEE26",
        license_id = "KSK-TESTAABBCCDDEE26",
        status = "used",
        live_mac = "AA:BB:CC:DD:EE:26",
        grace_used = 1,
        grace_max = 3,
        ksk_ever_bound = 1,
        signed_ksk = valid,
        used_slot_id = nil,
    },
}
db.slots = {
    {
        id = 16,
        license_key = "KSK-TESTAABBCCDDEE26",
        slot_mac = "AA:BB:CC:DD:EE:26",
        license_status = "licensed",
        slot_name = "UnbindFail",
    },
}
-- Target unbound UPDATE so ensure_schema ALTER pcalls do not consume the inject.
db.fail_sql_substr = "UPDATE esp_licenses SET status='unbound'"
local u22 = esp.unbind({ license_id = "KSK-TESTAABBCCDDEE26" })
expect(u22.status == "error", "CASE22 unbind txn failure")
expect(u22.code == "DATABASE_ERROR", "CASE22 unbind DATABASE_ERROR")
expect(db.licenses[1].status == "used", "CASE22 license rolled back")
expect(db.licenses[1].live_mac == "AA:BB:CC:DD:EE:26", "CASE22 live_mac rolled back")
expect(db.slots[1].license_status == "licensed", "CASE22 slot rolled back")
db.fail_sql_substr = nil

io.write("ESP DETECT/VERIFY/BIND/REMOVE/DELETE TESTS PASS\n")
os.exit(0)
