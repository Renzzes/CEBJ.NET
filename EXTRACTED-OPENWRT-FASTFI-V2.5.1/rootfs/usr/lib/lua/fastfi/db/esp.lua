
local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")
local M = {}

function M.get_slot_by_mac(mac)
    local safe_mac = sqlite.quote((mac or ""):lower())
    local row = sqlite.query_row(config.ESP_DB,
        string.format("SELECT id, slot_name, slot_mac, status, license_status, license_key, last_seen FROM esp_slots WHERE LOWER(slot_mac)='%s';", safe_mac))
    
    if not row then return nil end
    
    return {
        id = row[1],
        slot_name = row[2],
        slot_mac = row[3],
        status = row[4],
        license_status = row[5],
        license_key = row[6],
        last_seen = tonumber(row[7]) or 0
    }
end

function M.update_slot_last_seen(slot_id)
    local now = os.time()
    sqlite.execute(config.ESP_DB,
        string.format("UPDATE esp_slots SET status='online', last_seen=%d WHERE id='%s';",
            now, sqlite.quote(tostring(slot_id))))
end


function M.increment_credit(slot_mac, pulses)
    pulses = tonumber(pulses) or 1
    if pulses <= 0 then return 0 end

    local slot_info = M.get_slot_by_mac(slot_mac)
    if not slot_info then
        return 0, "slot not found"
    end

    
    M.update_slot_last_seen(slot_info.id)

    
    sqlite.execute(config.ESP_DB,
        string.format("UPDATE esp_slots SET coin_credit = coin_credit + %d WHERE id='%s';",
            pulses, sqlite.quote(tostring(slot_info.id))))

    
    local locked_row = sqlite.query_row(config.ESP_DB,
        string.format("SELECT locked_by FROM esp_slots WHERE id='%s';", sqlite.quote(tostring(slot_info.id))))
    if locked_row and locked_row[1] and locked_row[1] ~= "" then
        sqlite.execute(config.ESP_DB,
            string.format("UPDATE coin_spam SET fail_count=0, blocked_until=0 WHERE client_mac='%s';",
                sqlite.quote(locked_row[1])))
    end

    
    local row = sqlite.query_row(config.ESP_DB,
        string.format("SELECT coin_credit FROM esp_slots WHERE id='%s';", sqlite.quote(tostring(slot_info.id))))
    return tonumber(row and row[1]) or pulses
end

return M
