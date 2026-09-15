#!/usr/bin/env lua
-- Reyee upgrade_crypt_v1 decrypt (stock rg-upgrade-crypto INIT_STATE)
-- Keystream: 6 unique bytes then perpetual 0x7F (verified against B11P313).
-- Usage: oem-reyee-decrypt.lua <encrypted_installer> <rgos.bin>

local MAGIC = "upgrade_crypt_v1!@2021"
-- Precomputed keystream prefix for INIT_STATE {1,0,0,0,1,0,1,0}
local KS6 = {0xe8, 0x74, 0xfa, 0xfd, 0x7e, 0xff}

local function bxor(a, b)
  local r, p = 0, 1
  a = a % 256; b = b % 256
  for _ = 1, 8 do
    if (a % 2) ~= (b % 2) then r = r + p end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    p = p * 2
  end
  return r
end

local inn, outp = arg[1], arg[2]
if not inn or not outp then
  io.stderr:write("usage: oem-reyee-decrypt.lua <in> <out>\n")
  os.exit(2)
end

local f = assert(io.open(inn, "rb"))
local blob = f:read("*a")
f:close()
if not blob or #blob < #MAGIC + 64 then
  io.stderr:write("input too small\n"); os.exit(1)
end
if blob:sub(1, #MAGIC) ~= MAGIC then
  io.stderr:write("missing upgrade_crypt_v1 magic\n"); os.exit(1)
end

local body = blob:sub(#MAGIC + 1)
local n = #body
local o = assert(io.open(outp, "wb"))
local CHUNK = 65536
local i = 1
while i <= n do
  local j = math.min(i + CHUNK - 1, n)
  local piece = body:sub(i, j)
  local buf = {}
  for k = 1, #piece do
    local abs = i + k - 1
    local c = piece:byte(k)
    local key = (abs <= 6) and KS6[abs] or 0x7f
    buf[k] = string.char(bxor(c, key))
  end
  o:write(table.concat(buf))
  i = j + 1
end
o:close()

-- Verify uImage magic
local chk = assert(io.open(outp, "rb"))
local head = chk:read(4)
chk:close()
if head ~= string.char(0x27, 0x05, 0x19, 0x56) then
  io.stderr:write("decrypt produced non-uImage output\n")
  os.remove(outp)
  os.exit(1)
end
print(string.format("ok %d", n))
