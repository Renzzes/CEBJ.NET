
local M = {}

function M.encode(tbl)
    local function serialize(v)
        if type(v) == "string" then
            v = v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
            return '"' .. v .. '"'
        elseif type(v) == "number" or type(v) == "boolean" then
            return tostring(v)
        elseif type(v) == "table" then
            local is_array = #v > 0
            if next(v) == nil then return "{}" end
            
            local parts = {}
            if is_array then
                for i = 1, #v do
                    table.insert(parts, serialize(v[i]))
                end
                return "[" .. table.concat(parts, ",") .. "]"
            else
                for k, x in pairs(v) do
                    table.insert(parts, '"' .. tostring(k) .. '":' .. serialize(x))
                end
                return "{" .. table.concat(parts, ",") .. "}"
            end
        end
        return '"nil"'
    end
    return serialize(tbl)
end

function M.decode(json_str)
    if not json_str or json_str == "" then return {} end
    
    
    local ok, cjson = pcall(require, "cjson")
    if ok then
        return cjson.decode(json_str)
    end
    
    
    local function parse_value(str, pos)
        pos = pos or 1
        
        
        while pos <= #str and (str:sub(pos, pos) == ' ' or str:sub(pos, pos) == '\t' or str:sub(pos, pos) == '\n' or str:sub(pos, pos) == '\r') do
            pos = pos + 1
        end
        
        if pos > #str then return nil, pos end
        
        local ch = str:sub(pos, pos)
        
        
        if ch == '"' then
            local start = pos + 1
            local escape = false
            for i = start, #str do
                local c = str:sub(i, i)
                if escape then
                    escape = false
                elseif c == '\\' then
                    escape = true
                elseif c == '"' then
                    local val = str:sub(start, i - 1)
                        :gsub('\\"', '"')
                        :gsub('\\\\', '\\')
                        :gsub('\\/', '/')
                        :gsub('\\b', '\b')
                        :gsub('\\f', '\f')
                        :gsub('\\n', '\n')
                        :gsub('\\r', '\r')
                        :gsub('\\t', '\t')
                    return val, i + 1
                end
            end
        end
        
        
        if ch:match('[%d%-]') then
            local num_str = str:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
            if num_str then
                return tonumber(num_str), pos + #num_str
            end
        end
        
        
        if str:sub(pos, pos + 3) == 'true' then
            return true, pos + 4
        end
        if str:sub(pos, pos + 4) == 'false' then
            return false, pos + 5
        end
        if str:sub(pos, pos + 3) == 'null' then
            return nil, pos + 4
        end
        
        
        if ch == '{' then
            local obj = {}
            pos = pos + 1
            
            
            while pos <= #str and str:sub(pos, pos):match('[ \t\n\r]') do pos = pos + 1 end
            
            if str:sub(pos, pos) == '}' then
                return obj, pos + 1
            end
            
            while pos <= #str do
                
                local key, new_pos = parse_value(str, pos)
                pos = new_pos
                
                
                while pos <= #str and str:sub(pos, pos):match('[ \t\n\r]') do pos = pos + 1 end
                if str:sub(pos, pos) == ':' then pos = pos + 1 end
                
                
                local value, val_pos = parse_value(str, pos)
                obj[key] = value
                pos = val_pos
                
                
                while pos <= #str and str:sub(pos, pos):match('[ \t\n\r]') do pos = pos + 1 end
                
                if str:sub(pos, pos) == ',' then
                    pos = pos + 1
                elseif str:sub(pos, pos) == '}' then
                    return obj, pos + 1
                else
                    break
                end
            end
            return obj, pos
        end
        
        
        if ch == '[' then
            local arr = {}
            pos = pos + 1
            
            
            while pos <= #str and str:sub(pos, pos):match('[ \t\n\r]') do pos = pos + 1 end
            
            if str:sub(pos, pos) == ']' then
                return arr, pos + 1
            end
            
            local idx = 1
            while pos <= #str do
                local value, new_pos = parse_value(str, pos)
                arr[idx] = value
                pos = new_pos
                idx = idx + 1
                
                
                while pos <= #str and str:sub(pos, pos):match('[ \t\n\r]') do pos = pos + 1 end
                
                if str:sub(pos, pos) == ',' then
                    pos = pos + 1
                elseif str:sub(pos, pos) == ']' then
                    return arr, pos + 1
                else
                    break
                end
            end
            return arr, pos
        end
        
        return nil, pos
    end
    
    local result, _ = parse_value(json_str, 1)
    return result or {}
end

return M
