
local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")
local file_util = require("fastfi.util.file")
local M = {}


local CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"








local CODE_LEN = 6






local MAX_FAILS = 8        
local BLOCK_SECONDS = 600  
local WINDOW_SECONDS = 600 

local function ensure_spam_table()
    sqlite.execute(config.VOUCHER_DB,
        [[CREATE TABLE IF NOT EXISTS voucher_spam (
            client_key TEXT PRIMARY KEY,
            fail_count INTEGER DEFAULT 0,
            last_attempt INTEGER DEFAULT 0,
            blocked_until INTEGER DEFAULT 0
        );]])
end



function M.rate_key(mac)
    local ip = os.getenv("REMOTE_ADDR") or ""
    if ip ~= "" then return ip end
    if mac and mac ~= "" then return tostring(mac):lower() end
    return "unknown"
end


function M.check_rate_limit(key)
    ensure_spam_table()
    local now = os.time()
    local row = sqlite.query_row(config.VOUCHER_DB, string.format(
        "SELECT blocked_until FROM voucher_spam WHERE client_key='%s';", sqlite.quote(key)))
    local blocked_until = tonumber(row and row[1]) or 0
    if blocked_until > now then return blocked_until - now end
    return nil
end

function M.record_failure(key)
    ensure_spam_table()
    local now = os.time()
    local safe = sqlite.quote(key)

    local row = sqlite.query_row(config.VOUCHER_DB, string.format(
        "SELECT fail_count, last_attempt FROM voucher_spam WHERE client_key='%s';", safe))
    local fails = tonumber(row and row[1]) or 0
    local last  = tonumber(row and row[2]) or 0

    
    
    if (now - last) > WINDOW_SECONDS then fails = 0 end
    fails = fails + 1

    local blocked_until = (fails >= MAX_FAILS) and (now + BLOCK_SECONDS) or 0
    if blocked_until > 0 then fails = 0 end

    sqlite.execute(config.VOUCHER_DB, string.format(
        "INSERT INTO voucher_spam (client_key, fail_count, last_attempt, blocked_until) VALUES ('%s', %d, %d, %d) " ..
        "ON CONFLICT(client_key) DO UPDATE SET fail_count=%d, last_attempt=%d, blocked_until=%d;",
        safe, fails, now, blocked_until, fails, now, blocked_until))

    return blocked_until > 0 and BLOCK_SECONDS or nil
end

function M.clear_failures(key)
    ensure_spam_table()
    sqlite.execute(config.VOUCHER_DB, string.format(
        "DELETE FROM voucher_spam WHERE client_key='%s';", sqlite.quote(key)))
end

local function ensure_table()
    sqlite.execute(config.VOUCHER_DB,
        [[CREATE TABLE IF NOT EXISTS vouchers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE NOT NULL,
            minutes INTEGER NOT NULL,
            price INTEGER DEFAULT 10,
            created_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL,
            used_at INTEGER DEFAULT 0,
            used_by TEXT DEFAULT '',
            status TEXT DEFAULT 'active',
            batch TEXT DEFAULT ''
        );]])
end







local function urandom_code()
    local f = io.open("/dev/urandom", "rb")
    if not f then return nil end
    local bytes = f:read(CODE_LEN)
    f:close()
    if not bytes or #bytes < CODE_LEN then return nil end
    local code = ""
    for i = 1, CODE_LEN do
        local idx = (bytes:byte(i) % #CODE_CHARS) + 1
        code = code .. CODE_CHARS:sub(idx, idx)
    end
    return code
end




local function seed_prng()
    local f = io.open("/dev/urandom", "rb")
    if f then
        local b = f:read(4)
        f:close()
        if b and #b == 4 then
            math.randomseed((b:byte(1) * 16777216 + b:byte(2) * 65536 +
                             b:byte(3) * 256 + b:byte(4)) % 1000000000)
            math.random()  
            return
        end
    end
    math.randomseed(os.time() * 1000 + (math.floor(os.clock() * 1000) % 1000))
    math.random()
end






function M.mint_one(minutes, price, expiry_days, batch)
    ensure_table()
    
    
    
    
    minutes = math.min(tonumber(minutes) or 60, 525600)
    price   = math.min(tonumber(price) or 10, 10000)
    expiry_days = tonumber(expiry_days) or 0
    batch = sqlite.quote(tostring(batch or ""))

    local now = os.time()
    local expires_at = (expiry_days > 0) and (now + expiry_days * 86400) or 0

    local fallback_seeded = false
    for _ = 1, 30 do
        
        
        
        
        
        
        
        local code = urandom_code() or ""
        if #code < CODE_LEN then
            local code_cmd = io.popen(string.format(
                "(openssl rand -base64 %d | tr -dc '%s' | fold -w %d | head -n 1) 2>/dev/null",
                CODE_LEN * 4, CODE_CHARS, CODE_LEN))
            if code_cmd then
                code = code_cmd:read("*a") or ""
                code_cmd:close()
            end
            code = code:gsub("%s+", "")
        end
        if #code < CODE_LEN then
            if not fallback_seeded then
                seed_prng()
                fallback_seeded = true
            end
            code = ""
            for _ = 1, CODE_LEN do
                local idx = math.random(1, #CODE_CHARS)
                code = code .. CODE_CHARS:sub(idx, idx)
            end
        end
        
        local exists = sqlite.query_row(config.VOUCHER_DB,
            string.format("SELECT COUNT(*) FROM vouchers WHERE code='%s';", code))
        if tonumber(exists and exists[1]) == 0 then
            sqlite.execute(config.VOUCHER_DB,
                string.format(
                    "INSERT INTO vouchers (code, minutes, price, created_at, expires_at, status, batch) VALUES ('%s', %d, %d, %d, %d, 'active', '%s');",
                    code, minutes, price, now, expires_at, batch))
            return code
        end
    end
    return nil
end

function M.get_voucher(code)
    local safe_code = sqlite.quote((code or ""):upper())
    local row = sqlite.query_row(config.VOUCHER_DB,
        string.format("SELECT code, minutes, price, status, expires_at, used_by, used_at FROM vouchers WHERE code='%s';", safe_code))
    
    if not row then return nil end
    
    return {
        code = row[1],
        minutes = tonumber(row[2]) or 0,
        price = tonumber(row[3]) or 0,
        status = row[4] or "active",
        expires_at = tonumber(row[5]) or 0,
        used_by = row[6] or "",
        used_at = tonumber(row[7]) or 0
    }
end

function M.redeem_voucher(code, mac)
    local safe_code = sqlite.quote((code or ""):upper())
    local safe_mac = sqlite.quote((mac or ""):lower())
    local now = os.time()
    
    
    local result = sqlite.execute(config.VOUCHER_DB,
        string.format("UPDATE vouchers SET status='used', used_at=%d, used_by='%s' WHERE code='%s' AND status='active' AND (expires_at >= %d OR expires_at < 1000000000);",
            now, safe_mac, safe_code, now))
    
    
    if result == "1" then
        return true
    end

    
    local row = sqlite.query_row(config.VOUCHER_DB,
        string.format("SELECT status, used_at, used_by FROM vouchers WHERE code='%s';", safe_code))
    
    
    
    
    
    
    return row and row[1] == "used"
        and tonumber(row[2]) == now
        and row[3] == (mac or ""):lower()
end

return M
