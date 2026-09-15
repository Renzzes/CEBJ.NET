
local M = {}

function M.read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

function M.write(path, content)
    local f, err = io.open(path, "w")
    if not f then return false, err end
    f:write(content)
    f:close()
    return true
end

function M.trim(s)
    return s and s:match("^%s*(.-)%s*$") or ""
end

function M.exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

function M.execute(cmd)
    local f = io.popen(cmd)
    if not f then return "" end
    local output = f:read("*a")
    f:close()
    return M.trim(output)
end

return M
