
local M = {}

function M.url_decode(str)
    if not str then return "" end
    str = string.gsub(str, "+", " ")
    str = string.gsub(str, "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    return str
end

function M.parse_query_string(qs)
    local params = {}
    if not qs or qs == "" then return params end
    
    for k, v in qs:gmatch("([^&=]+)=([^&]*)") do
        local dk = M.url_decode(k)
        if params[dk] == nil then
            params[dk] = M.url_decode(v)
        end
    end
    return params
end

function M.read_post_body()
    local method = os.getenv("REQUEST_METHOD") or "GET"
    if method ~= "POST" then return "" end
    
    local cl = tonumber(os.getenv("CONTENT_LENGTH") or "0")
    if cl > 0 then
        return io.read(cl) or ""
    end
    return ""
end

function M.post(url, body, headers)
    
    local tmp_body = "/tmp/fastfi_post_body.json"
    local f = io.open(tmp_body, "w")
    if f then
        f:write(body)
        f:close()
    end
    
    local cmd = "curl -s --connect-timeout 10 --max-time 15 -w '\\n%{http_code}' -X POST "
    if type(headers) == "table" then
        for k, v in pairs(headers) do
            
            local safe_v = tostring(v):gsub("'", "'\\''")
            cmd = cmd .. string.format("-H '%s: %s' ", k, safe_v)
        end
    end
    
    cmd = cmd .. string.format("--data-binary @%s '%s' 2>/dev/null", tmp_body, url:gsub("'", "'\\''"))
    
    local handle = io.popen(cmd)
    if not handle then
        os.remove(tmp_body)
        return { status_code = 500, body = "" }
    end
    
    local output = handle:read("*a")
    handle:close()
    os.remove(tmp_body)
    
    
    local response_body = ""
    local status_code = 500
    
    if output and output ~= "" then
        
        local lines = {}
        for line in output:gmatch("([^\n]*)\n?") do
            if line ~= "" then table.insert(lines, line) end
        end
        
        if #lines > 0 then
            status_code = tonumber(lines[#lines]) or 500
            table.remove(lines, #lines)
            response_body = table.concat(lines, "\n")
        end
    end
    
    return {
        status_code = status_code,
        body = response_body
    }
end

return M
