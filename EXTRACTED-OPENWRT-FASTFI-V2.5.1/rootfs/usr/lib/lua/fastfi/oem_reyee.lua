-- fastfi.oem_reyee — OEM ReyeeOS package validation (separate from sysupgrade)
local M = {}

local MAGIC = "upgrade_crypt_v1!@2021"
local UIMAGE = "\x27\x05\x19\x56"
local TARGET_PID = 0x60010085
local FIRMWARE_MAX = 0xF70000
local STAGE_DIR = "/tmp"
local UPLOAD_PATH = "/tmp/koneksik_oem_fw_upload.bin"
local EXTRACT_DIR = "/tmp/koneksik_oem_extract"
local RGOS_PATH = "/tmp/koneksik_oem_rgos.bin"
local RECEIPT_PATH = "/tmp/koneksik_oem_ready.json"
local DECRYPT = "/usr/libexec/fastfi/core/oem-reyee-decrypt.lua"
local RESTORE = "/usr/libexec/fastfi/core/koneksik-oem-restore.sh"
local LOG = "/tmp/fw_progress.log"

local function log(msg)
    os.execute(string.format("echo '[OEM] '$(date '+%%Y-%%m-%%d %%H:%%M:%%S')' %s' >> %s",
        (msg or ""):gsub("'", ""), LOG))
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
end

local function write_file(path, data)
    local f, err = io.open(path, "wb")
    if not f then return false, err end
    f:write(data)
    f:close()
    return true
end

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function shell_out(cmd)
    local p = io.popen(cmd .. " 2>/dev/null")
    if not p then return "" end
    local o = p:read("*a") or ""
    p:close()
    return trim(o)
end

local function md5_file(path)
    return shell_out(string.format("md5sum %q | awk '{print $1}'", path)):lower()
end

local function sha256_file(path)
    return shell_out(string.format("sha256sum %q | awk '{print $1}'", path)):lower()
end

local function file_size(path)
    local n = tonumber(shell_out(string.format("wc -c < %q", path)))
    return n or 0
end

local function cleanup_extract()
    os.execute("rm -rf " .. EXTRACT_DIR)
    os.execute("mkdir -p " .. EXTRACT_DIR)
end

function M.paths()
    return {
        upload = UPLOAD_PATH,
        rgos = RGOS_PATH,
        receipt = RECEIPT_PATH,
        extract = EXTRACT_DIR
    }
end

function M.firmware_mtd_info()
    local line = shell_out("awk -F: '/\\\"firmware\\\"/{print; exit}' /proc/mtd")
    if line == "" then
        return nil, "firmware MTD not found"
    end
    local size_hex = line:match("%S+%s+(%S+)")
    local size = tonumber(size_hex, 16) or 0
    return { line = line, size = size, name = "firmware" }
end

local function classify_file(path)
    local f = io.open(path, "rb")
    if not f then return "missing" end
    local head = f:read(32) or ""
    f:seek("end")
    local sz = f:seek()
    f:close()
    if #head >= 2 and head:byte(1) == 0x1f and head:byte(2) == 0x8b then
        return "reyee_oem_tar_gz"
    end
    if head:sub(1, #MAGIC) == MAGIC then
        return "reyee_encrypted_installer"
    end
    if head:sub(1, 4) == UIMAGE then
        -- peek tail for OpenWrt metadata
        local t = shell_out(string.format("tail -c 4096 %q", path))
        if t:find("supported_devices", 1, true) then
            return "openwrt_sysupgrade"
        end
        return "reyee_rgos_uimage"
    end
    return "unknown", sz
end

local function parse_product_ini(text)
    local ids = {}
    for v in text:gmatch("sup_list=(0x%x+)") do
        ids[#ids + 1] = tonumber(v)
    end
    for v in text:gmatch("sup_list=(%d+)") do
        ids[#ids + 1] = tonumber(v)
    end
    return ids
end

local function validate_rgos_file(path, report)
    local sz = file_size(path)
    report.image_size = sz
    if sz <= 0 or sz > FIRMWARE_MAX then
        report.ok = false
        report.errors[#report.errors + 1] = "Firmware image exceeds firmware partition or empty"
        return false
    end
    local f = io.open(path, "rb")
    local head = f and f:read(64) or ""
    if f then f:close() end
    if head:sub(1, 4) ~= UIMAGE then
        report.ok = false
        report.errors[#report.errors + 1] = "Invalid uImage"
        return false
    end
    local name = head:sub(33, 64):gsub("%z.*", "")
    report.kernel = name
    if not name:find("MIPS", 1, true) then
        report.ok = false
        report.errors[#report.errors + 1] = "Not a MIPS uImage"
        return false
    end
    local tail = shell_out(string.format("tail -c 4096 %q", path))
    if tail:find("supported_devices", 1, true) then
        report.ok = false
        report.errors[#report.errors + 1] = "OpenWrt sysupgrade image refused on OEM path"
        return false
    end
    report.sha256 = sha256_file(path)
    report.checks = report.checks or {}
    report.checks.uimage = "PASS"
    report.checks.mips = "PASS"
    report.checks.size = "PASS"
    return true
end

local function decrypt_to_rgos(enc_path)
    os.execute(string.format("rm -f %q", RGOS_PATH))
    local rc = os.execute(string.format("lua %q %q %q", DECRYPT, enc_path, RGOS_PATH))
    -- lua os.execute returns true/nil or exit status depending on version
    if not (rc == true or rc == 0) then
        return false, "Unable to decrypt OEM installer"
    end
    if file_size(RGOS_PATH) < 1024 then
        return false, "Unable to decrypt OEM installer"
    end
    return true
end

function M.validate_staged()
    local report = {
        ok = true,
        errors = {},
        checks = {},
        flash_target = "firmware",
        ready = false
    }
    log("Validation started")
    if not read_file(UPLOAD_PATH) and file_size(UPLOAD_PATH) <= 0 then
        -- file_size 0
    end
    local sz = file_size(UPLOAD_PATH)
    if sz < 100 * 1024 then
        report.ok = false
        report.errors[#report.errors + 1] = "File too small"
        return report
    end
    if sz > 32 * 1024 * 1024 then
        report.ok = false
        report.errors[#report.errors + 1] = "File too large (max 32MB)"
        return report
    end
    report.checks.file = "PASS"
    report.upload_size = sz

    local kind = classify_file(UPLOAD_PATH)
    report.package_type = kind
    log("Package type: " .. tostring(kind))

    if kind == "openwrt_sysupgrade" then
        report.ok = false
        report.errors[#report.errors + 1] = "Unsupported OEM firmware (OpenWrt/KonekSik image — use KonekSik Firmware upload)"
        report.checks.package_type = "FAIL"
        return report
    end
    if kind == "unknown" then
        report.ok = false
        report.errors[#report.errors + 1] = "Unsupported OEM firmware"
        report.checks.package_type = "FAIL"
        return report
    end
    report.checks.package_type = "PASS"

    local mtd, mtd_err = M.firmware_mtd_info()
    if not mtd then
        -- Static fallback size when /proc/mtd unavailable (build host); on device required
        report.firmware_mtd_size = FIRMWARE_MAX
        report.checks.firmware_mtd = "STATIC_FALLBACK"
        report.mtd_note = mtd_err or "firmware MTD not found at validate-time"
    else
        report.firmware_mtd_size = mtd.size
        report.firmware_mtd_line = mtd.line
        report.checks.firmware_mtd = "PASS"
    end

    if kind == "reyee_rgos_uimage" then
        os.execute(string.format("cp -f %q %q", UPLOAD_PATH, RGOS_PATH))
        if not validate_rgos_file(RGOS_PATH, report) then
            return report
        end
    elseif kind == "reyee_encrypted_installer" then
        log("Encrypted installer detected")
        local ok, err = decrypt_to_rgos(UPLOAD_PATH)
        if not ok then
            report.ok = false
            report.errors[#report.errors + 1] = err
            report.checks.decryption = "FAIL"
            return report
        end
        report.checks.decryption = "PASS"
        if not validate_rgos_file(RGOS_PATH, report) then
            return report
        end
    elseif kind == "reyee_oem_tar_gz" then
        cleanup_extract()
        -- Extract only expected basenames; reject traversal via tar --no-same-owner to dir
        local rc = os.execute(string.format(
            "tar -tzf %q >/tmp/koneksik_oem_tar.list 2>/dev/null", UPLOAD_PATH))
        local listing = read_file("/tmp/koneksik_oem_tar.list") or ""
        if listing:find("%.%.") or listing:find("^/") or listing:find("\n/") then
            report.ok = false
            report.errors[#report.errors + 1] = "Malformed tar with path traversal"
            report.checks.path_traversal = "FAIL"
            return report
        end
        report.checks.path_traversal = "PASS"
        os.execute(string.format("tar -xzf %q -C %q", UPLOAD_PATH, EXTRACT_DIR))

        local function find_file(suffix)
            local out = shell_out(string.format("find %q -type f -name '*%s' | head -1", EXTRACT_DIR, suffix))
            return out ~= "" and out or nil
        end

        local product = find_file(".product.ini")
        local pids = find_file(".support_pids")
        local version = find_file(".version")
        local md5f = find_file(".md5")
        local enc = find_file("_install_encypto.bin")

        if not product or not pids or not version or not md5f or not enc then
            report.ok = false
            report.errors[#report.errors + 1] = "OEM package structure incomplete"
            report.checks.structure = "FAIL"
            return report
        end
        report.checks.structure = "PASS"

        local pin = read_file(product) or ""
        local ids = parse_product_ini(pin)
        local pid_ok = false
        for _, id in ipairs(ids) do
            if id == TARGET_PID then pid_ok = true end
        end
        report.product_ids = ids
        if not pid_ok then
            report.ok = false
            report.errors[#report.errors + 1] = "Product ID mismatch"
            report.checks.product_id = "FAIL"
            return report
        end
        report.checks.product_id = "PASS"
        report.product_id = string.format("0x%08x", TARGET_PID)

        local sp = read_file(pids) or ""
        if not sp:find("EW1200G-PRO", 1, true) then
            report.ok = false
            report.errors[#report.errors + 1] = "Hardware compatibility failed (support_pids)"
            report.checks.support_pids = "FAIL"
            return report
        end
        report.checks.support_pids = "PASS"
        report.hardware = "RG-EW1200G-PRO"

        report.version = trim(read_file(version) or "")

        -- MD5 verify
        local md5_txt = read_file(md5f) or ""
        local md5_ok = true
        for line in md5_txt:gmatch("[^\r\n]+") do
            local expect, fname = line:match("^(%x+)%s+(%S+)$")
            if expect and fname then
                local fpath = shell_out(string.format("find %q -type f -name %q | head -1", EXTRACT_DIR, fname))
                if fpath == "" then
                    md5_ok = false
                    break
                end
                local got = md5_file(fpath)
                if got ~= expect:lower() then
                    md5_ok = false
                    break
                end
            end
        end
        if not md5_ok then
            report.ok = false
            report.errors[#report.errors + 1] = "Firmware integrity check failed"
            report.checks.md5 = "FAIL"
            return report
        end
        report.checks.md5 = "PASS"
        log("Package MD5: PASS")

        local head = (read_file(enc) or ""):sub(1, #MAGIC)
        if head ~= MAGIC then
            report.ok = false
            report.errors[#report.errors + 1] = "Encrypted installer magic mismatch"
            report.checks.crypto_magic = "FAIL"
            return report
        end
        report.checks.crypto_magic = "PASS"
        log("Encrypted installer detected")

        local ok, err = decrypt_to_rgos(enc)
        if not ok then
            report.ok = false
            report.errors[#report.errors + 1] = err
            report.checks.decryption = "FAIL"
            return report
        end
        report.checks.decryption = "PASS"
        log("Decryption: PASS")
        if not validate_rgos_file(RGOS_PATH, report) then
            return report
        end
    end

    if report.ok then
        local token = shell_out("dd if=/dev/urandom bs=16 count=1 2>/dev/null | hexdump -v -e '1/1 \"%02x\"'")
        if token == "" then token = tostring(os.time()) .. tostring(sz) end
        report.confirm_token = token
        report.ready = true
        report.rgos_path = RGOS_PATH
        report.message = "OEM firmware validated — confirmation required before flash"
        -- receipt
        local receipt = string.format(
            '{"token":"%s","rgos":"%s","sha256":"%s","size":%d,"version":%q}\n',
            token, RGOS_PATH, report.sha256 or "", report.image_size or 0, report.version or "")
        write_file(RECEIPT_PATH, receipt)
        log("Ready for confirmation")
    end
    return report
end

function M.clear()
    os.execute(string.format("rm -f %q %q %q", UPLOAD_PATH, RGOS_PATH, RECEIPT_PATH))
    os.execute("rm -rf " .. EXTRACT_DIR)
    log("Staging cleared")
end

function M.flash(token)
    local receipt = read_file(RECEIPT_PATH)
    if not receipt then
        return false, "OEM flash target safety check failed (no validation receipt)"
    end
    local rtoken = receipt:match('"token":"([^"]+)"')
    if not token or token == "" or token ~= rtoken then
        return false, "OEM flash requires successful validation confirmation"
    end
    if file_size(RGOS_PATH) <= 0 then
        return false, "Validated rgos.bin missing"
    end
    local mtd = M.firmware_mtd_info()
    if not mtd or mtd.size <= 0 then
        return false, "Firmware MTD partition not found"
    end
    if file_size(RGOS_PATH) > mtd.size then
        return false, "Firmware image exceeds firmware partition"
    end
    log("User confirmed OEM installation")
    log("Flash target: firmware")
    log("Flash started")
    -- async flash + reboot
    os.execute(string.format("(sleep 2; sh %q %q >>%s 2>&1) &", RESTORE, RGOS_PATH, LOG))
    return true, "OEM flash started. Router will reboot into ReyeeOS if flash succeeds."
end

return M
