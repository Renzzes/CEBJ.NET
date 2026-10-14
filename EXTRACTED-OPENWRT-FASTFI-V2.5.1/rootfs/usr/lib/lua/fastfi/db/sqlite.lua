
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

-- ok, text, err
-- A successful query that returns zero rows is ok=true and text="".
-- Open, prepare, step, and exec failures are ok=false. Callers must not
-- treat that as an empty result.
function M.query_checked(db_path, query)
    if not db_path or db_path == "" or not query or query == "" then
        return false, nil, "missing database path or SQL"
    end

    local function run()
        local db = open_db(db_path)
        if not db then
            return false, nil, "database open failed"
        end

        local is_read = query:match("^%s*[Ss][Ee][Ll][Ee][Cc][Tt]")
            or query:match("^%s*[Pp][Rr][Aa][Gg][Mm][Aa]")
        if is_read then
            local vm = db:prepare(query)
            if not vm then
                local err = db:errmsg() or "prepare failed"
                db:close()
                return false, nil, err
            end
            local result = ""
            local cols = vm:columns()
            local step = vm:step()
            while step == sqlite3.ROW do
                local str_vals = {}
                for i = 0, cols - 1 do
                    table.insert(str_vals, tostring(vm:get_value(i)))
                end
                result = result .. table.concat(str_vals, "|") .. "\n"
                step = vm:step()
            end
            if step ~= sqlite3.DONE then
                local err = db:errmsg() or "query step failed"
                vm:finalize()
                db:close()
                return false, nil, err
            end
            vm:finalize()
            db:close()
            return true, result, nil
        end

        local rc = db:exec(query)
        if rc ~= sqlite3.OK then
            local err = db:errmsg() or "exec failed"
            db:close()
            return false, nil, err
        end
        local changes = tostring(db:changes() or 0)
        db:close()
        return true, changes, nil
    end

    local ok, a, b, c = pcall(run)
    if not ok then
        return false, nil, "sqlite error: " .. tostring(a)
    end
    return a, b, c
end

-- Run fn(exec, query_row) inside one connection with BEGIN IMMEDIATE/COMMIT.
-- On error: ROLLBACK and return false, message. exec(sql) errors on non-OK.
function M.transaction(db_path, fn)
    if not db_path or db_path == "" or type(fn) ~= "function" then
        return false, "missing database path or callback"
    end
    local db = open_db(db_path)
    if not db then
        return false, "database open failed"
    end
    if db:exec("BEGIN IMMEDIATE;") ~= sqlite3.OK then
        local err = db:errmsg() or "BEGIN failed"
        db:close()
        return false, err
    end

    local function exec(sql)
        if db:exec(sql) ~= sqlite3.OK then
            error(db:errmsg() or "exec failed", 0)
        end
    end

    local function query_row(sql)
        local vm = db:prepare(sql)
        if not vm then
            error(db:errmsg() or "prepare failed", 0)
        end
        local row_data = nil
        local step = vm:step()
        if step == sqlite3.ROW then
            row_data = {}
            local cols = vm:columns()
            for i = 0, cols - 1 do
                row_data[i + 1] = vm:get_value(i)
            end
            step = vm:step()
        end
        if step ~= sqlite3.DONE and step ~= sqlite3.ROW then
            local err = db:errmsg() or "query step failed"
            vm:finalize()
            error(err, 0)
        end
        vm:finalize()
        return row_data
    end

    local ok, err = pcall(fn, exec, query_row)
    if not ok then
        pcall(function() db:exec("ROLLBACK;") end)
        db:close()
        return false, tostring(err)
    end
    if db:exec("COMMIT;") ~= sqlite3.OK then
        local cerr = db:errmsg() or "COMMIT failed"
        pcall(function() db:exec("ROLLBACK;") end)
        db:close()
        return false, cerr
    end
    db:close()
    return true
end

return M
