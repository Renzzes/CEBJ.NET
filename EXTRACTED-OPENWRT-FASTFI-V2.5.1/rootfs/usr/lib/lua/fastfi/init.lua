
local M = {}


setmetatable(M, {
    __index = function(t, key)
        local ok, mod = pcall(require, "fastfi." .. key)
        if ok then
            rawset(t, key, mod)
            return mod
        end
        return nil
    end
})

return M
