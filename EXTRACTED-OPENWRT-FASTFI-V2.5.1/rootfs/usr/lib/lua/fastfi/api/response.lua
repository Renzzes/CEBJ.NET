
local json_util = require("fastfi.util.json")
local M = {}




M.ALREADY_SENT = {}

function M.send(response)
    
    if response == M.ALREADY_SENT then return end

    
    print("Content-Type: application/json")
    print("Cache-Control: no-store, no-cache, must-revalidate")
    print("Pragma: no-cache")
    print("Expires: 0")
    
    
    if type(response) == "table" and response._headers then
        for _, header in ipairs(response._headers) do
            print(header)
        end
        
        response._headers = nil
    end
    
    print("")
    
    
    print(json_util.encode(response))
end

function M.success(data, message)
    return {
        status = "ok",
        message = message or "Success",
        data = data
    }
end

function M.error(message, error_code)
    return {
        status = "error",
        message = message or "Unknown error",
        error_code = error_code
    }
end

function M.unauthorized()
    return M.error("Unauthorized access", 401)
end

return M
