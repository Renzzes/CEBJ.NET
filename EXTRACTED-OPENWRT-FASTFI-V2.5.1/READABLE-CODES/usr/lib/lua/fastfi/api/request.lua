
local http_util = require("fastfi.util.http")
local json_util = require("fastfi.util.json")
local M = {}

function M.parse()
    local method = os.getenv("REQUEST_METHOD") or "GET"
    local query_string = os.getenv("QUERY_STRING") or ""
    local content_type = os.getenv("CONTENT_TYPE") or ""
    
    
    local params = http_util.parse_query_string(query_string)
    
    
    local post_body = ""
    if method == "POST" then
        post_body = http_util.read_post_body()
        
        
        if content_type:find("application/json") then
            
            local ok, json_data = pcall(json_util.decode, post_body)
            if ok and json_data and type(json_data) == "table" then
                
                for k, v in pairs(json_data) do
                    params[k] = v
                end
            end
        else
            
            local post_params = http_util.parse_query_string(post_body)
            for k, v in pairs(post_params) do
                params[k] = v
            end
        end
    end
    
    return {
        method = method,
        action = params["action"],
        params = params,
        post_body = post_body,
        content_type = content_type
    }
end

return M
