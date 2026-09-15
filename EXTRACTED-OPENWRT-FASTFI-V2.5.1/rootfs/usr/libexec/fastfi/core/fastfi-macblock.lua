#!/usr/bin/env lua
-- Apply MAC blocklist via nft/iptables (best-effort on OpenWrt)

local ok_cfg, config = pcall(require, "fastfi.config")
if not ok_cfg then os.exit(0) end
local sqlite = require("fastfi.db.sqlite")

local function sh(cmd)
    os.execute(cmd .. " >/dev/null 2>&1")
end

local action = arg and arg[1] or "apply"

local rows = sqlite.query_list(config.CONFIG_DB, "SELECT mac FROM mac_blocklist;") or {}

-- Prefer nft inet filter forward drop by MAC if possible; fallback iptables
sh("nft list table inet fastfi_macblock >/dev/null 2>&1 || nft add table inet fastfi_macblock")
sh("nft list chain inet fastfi_macblock block >/dev/null 2>&1 || nft add chain inet fastfi_macblock block '{ type filter hook forward priority 0; policy accept; }'")
sh("nft flush chain inet fastfi_macblock block 2>/dev/null")

for _, r in ipairs(rows) do
    local mac = tostring(r[1] or ""):upper()
    if mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        sh(string.format("nft add rule inet fastfi_macblock block ether saddr %s drop", mac))
        sh(string.format("nft add rule inet fastfi_macblock block ether daddr %s drop", mac))
        -- iptables fallback
        sh(string.format("iptables -C FORWARD -m mac --mac-source %s -j DROP 2>/dev/null || iptables -I FORWARD -m mac --mac-source %s -j DROP", mac, mac))
    end
end

if action == "apply" then
    io.write("ok\n")
end
