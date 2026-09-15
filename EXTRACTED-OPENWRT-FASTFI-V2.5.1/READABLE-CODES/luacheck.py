# luacheck.py — run as: python luacheck.py <file.lua> [more.lua ...]
# Uses lupa (ships Lua 5.5) to loadfile-check Lua 5.1 source.
# Known false positive: 5.1 `for`-loop var reassignment is flagged in 5.5;
# usr/libexec/fastfi/core/speed-monitor.lua trips this and is NOT broken — ignore it.
import sys, lupa
L = lupa.LuaRuntime(unpack_returned_tuples=False)
chk = L.execute('return function(p) local f,e = loadfile(p); if f then return "OK" else return "FAIL: "..tostring(e) end end')
bad = 0
for p in sys.argv[1:]:
    r = chk(p); print(f"  {r}  {p}")
    if r != "OK": bad += 1
sys.exit(1 if bad else 0)