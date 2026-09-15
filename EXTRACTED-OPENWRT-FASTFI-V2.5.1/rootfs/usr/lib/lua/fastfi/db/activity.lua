local config = require("fastfi.config")
local sqlite = require("fastfi.db.sqlite")
local M = {}

function M.add(type_, title, body)
    sqlite.execute(config.CONFIG_DB, string.format(
        "INSERT INTO activity_events (ts, type, title, body) VALUES (%d, '%s', '%s', '%s');",
        os.time(), sqlite.quote(type_ or "info"), sqlite.quote(title or ""), sqlite.quote(body or "")))
    -- keep last 500
    sqlite.execute(config.CONFIG_DB,
        "DELETE FROM activity_events WHERE id NOT IN (SELECT id FROM activity_events ORDER BY id DESC LIMIT 500);")
end

function M.list(limit)
    limit = tonumber(limit) or 50
    local rows = sqlite.query_list(config.CONFIG_DB, string.format(
        "SELECT id, ts, type, title, body FROM activity_events ORDER BY id DESC LIMIT %d;", limit)) or {}
    local out = {}
    for _, r in ipairs(rows) do
        table.insert(out, {
            id = tonumber(r[1]), ts = tonumber(r[2]) or 0, type = r[3], title = r[4], body = r[5]
        })
    end
    return out
end

function M.list_audit(limit)
    limit = tonumber(limit) or 50
    local rows = sqlite.query_list(config.CONFIG_DB, string.format(
        "SELECT id, ts, username, action, detail FROM audit_log ORDER BY id DESC LIMIT %d;", limit)) or {}
    local out = {}
    for _, r in ipairs(rows) do
        table.insert(out, {
            id = tonumber(r[1]), ts = tonumber(r[2]) or 0, username = r[3], action = r[4], detail = r[5]
        })
    end
    return out
end

return M
