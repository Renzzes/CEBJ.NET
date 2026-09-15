
local sqlite3 = require("lsqlite3")
local M = {}


local function open_db(db_path)
    local db = sqlite3.open(db_path)
    if db then
        db:busy_timeout(5000)
    end
    return db
end

function M.execute(db_path, query)
    local db = open_db(db_path)
    if not db then return nil end
    
    local result = ""
    
    if query:match("^%s*SELECT") or query:match("^%s*PRAGMA") then
        local vm = db:prepare(query)
        if vm then
            local cols = vm:columns()
            while vm:step() == sqlite3.ROW do
                local str_vals = {}
                for i = 0, cols - 1 do
                    table.insert(str_vals, tostring(vm:get_value(i)))
                end
                result = result .. table.concat(str_vals, "|") .. "\n"
            end
            vm:finalize()
        end
    else
        local rc = db:exec(query)
        if rc == sqlite3.OK then
            result = tostring(db:changes())
        else
            result = "Error: " .. db:errmsg() .. " (code: " .. rc .. ")"
        end
    end
    
    db:close()
    return result
end

function M.quote(str)
    return str and str:gsub("'", "''") or ""
end

function M.query_row(db_path, query)
    local db = open_db(db_path)
    if not db then return nil end
    
    local vm = db:prepare(query)
    if not vm then 
        db:close()
        return nil 
    end
    
    local row_data = nil
    if vm:step() == sqlite3.ROW then
        row_data = {}
        local cols = vm:columns()
        for i = 0, cols - 1 do
            row_data[i + 1] = vm:get_value(i)
        end
    end
    
    vm:finalize()
    db:close()
    return row_data
end

function M.query_list(db_path, query)
    local db = open_db(db_path)
    if not db then return {} end
    
    local vm = db:prepare(query)
    if not vm then 
        db:close()
        return {} 
    end
    
    local rows = {}
    local cols = vm:columns()
    while vm:step() == sqlite3.ROW do
        local row = {}
        for i = 0, cols - 1 do
            row[i + 1] = vm:get_value(i)
        end
        table.insert(rows, row)
    end
    
    vm:finalize()
    db:close()
    return rows
end

return M
