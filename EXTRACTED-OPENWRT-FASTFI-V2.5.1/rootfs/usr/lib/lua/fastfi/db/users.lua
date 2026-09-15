local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")
local file_util = require("fastfi.util.file")
local M = {}

local function shell_quote(s)
    return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

local function sha256_hex(s)
    local f = io.popen("printf '%s' " .. shell_quote(s) .. " | sha256sum 2>/dev/null")
    if not f then
        f = io.popen("echo -n " .. shell_quote(s) .. " | openssl dgst -sha256 2>/dev/null")
    end
    if not f then return nil end
    local out = f:read("*a") or ""
    f:close()
    local hex = out:match("([a-fA-F0-9][a-fA-F0-9]+)")
    return hex and hex:lower() or nil
end

function M.hash_password(password)
    local salt = tostring(os.time()) .. tostring(math.random(100000, 999999))
    local digest = sha256_hex(salt .. ":" .. password)
    if not digest then
        -- fallback weak but deterministic for broken environments
        digest = tostring(#password) .. tostring(password:byte(1) or 0)
    end
    return salt .. "$" .. digest
end

function M.verify_hash(password, stored)
    if not stored or stored == "" then return false end
    local salt, digest = stored:match("^([^%$]+)%$(.+)$")
    if not salt then
        -- legacy plaintext compare
        return file_util.trim(password) == file_util.trim(stored)
    end
    local check = sha256_hex(salt .. ":" .. password)
    return check ~= nil and check == digest
end

function M.ensure_default_admin()
    local row = sqlite.query_row(config.CONFIG_DB, "SELECT COUNT(*) FROM admin_users;")
    if tonumber(row and row[1] or 0) > 0 then return true end

    local legacy = file_util.read(config.ADMIN_PASS_FILE)
    legacy = legacy and file_util.trim(legacy) or "admin123"
    local hash = M.hash_password(legacy)
    local now = os.time()
    sqlite.execute(config.CONFIG_DB, string.format(
        "INSERT INTO admin_users (username, password_hash, role, created_at) VALUES ('admin', '%s', 'owner', %d);",
        sqlite.quote(hash), now))
    return true
end

function M.find_by_username(username)
    username = file_util.trim(username or "")
    if username == "" then return nil end
    local row = sqlite.query_row(config.CONFIG_DB, string.format(
        "SELECT id, username, password_hash, role FROM admin_users WHERE username='%s' LIMIT 1;",
        sqlite.quote(username)))
    if not row then return nil end
    return { id = row[1], username = row[2], password_hash = row[3], role = row[4] or "owner" }
end

function M.list_users()
    local rows = sqlite.query_list(config.CONFIG_DB,
        "SELECT id, username, role, created_at FROM admin_users ORDER BY id ASC;") or {}
    local out = {}
    for _, r in ipairs(rows) do
        table.insert(out, { id = r[1], username = r[2], role = r[3], created_at = r[4] })
    end
    return out
end

function M.create_user(username, password, role)
    username = file_util.trim(username or "")
    password = file_util.trim(password or "")
    role = tostring(role or "staff"):lower()
    if role ~= "owner" and role ~= "admin" and role ~= "staff" and role ~= "viewer" then
        role = "staff"
    end
    if username == "" or password == "" then return false, "Missing username or password" end
    if M.find_by_username(username) then return false, "Username already exists" end
    local hash = M.hash_password(password)
    sqlite.execute(config.CONFIG_DB, string.format(
        "INSERT INTO admin_users (username, password_hash, role, created_at) VALUES ('%s', '%s', '%s', %d);",
        sqlite.quote(username), sqlite.quote(hash), role, os.time()))
    return true
end

function M.delete_user(id)
    id = tonumber(id)
    if not id then return false, "Invalid id" end
    local row = sqlite.query_row(config.CONFIG_DB, string.format(
        "SELECT role, username FROM admin_users WHERE id=%d;", id))
    if not row then return false, "User not found" end
    if row[1] == "owner" then
        local owners = sqlite.query_row(config.CONFIG_DB,
            "SELECT COUNT(*) FROM admin_users WHERE role='owner';")
        if tonumber(owners and owners[1] or 0) <= 1 then
            return false, "Cannot delete the last owner"
        end
    end
    sqlite.execute(config.CONFIG_DB, string.format("DELETE FROM admin_users WHERE id=%d;", id))
    return true
end

function M.set_password(username, new_password)
    local u = M.find_by_username(username)
    if not u then return false end
    local hash = M.hash_password(file_util.trim(new_password))
    sqlite.execute(config.CONFIG_DB, string.format(
        "UPDATE admin_users SET password_hash='%s' WHERE id=%d;",
        sqlite.quote(hash), u.id))
    -- keep legacy file in sync for recovery paths when changing default admin
    if u.username == "admin" then
        file_util.write(config.ADMIN_PASS_FILE, file_util.trim(new_password))
    end
    return true
end

function M.audit(username, action, detail)
    sqlite.execute(config.CONFIG_DB, string.format(
        "INSERT INTO audit_log (ts, username, action, detail) VALUES (%d, '%s', '%s', '%s');",
        os.time(), sqlite.quote(username or ""), sqlite.quote(action or ""), sqlite.quote(detail or "")))
end

return M
