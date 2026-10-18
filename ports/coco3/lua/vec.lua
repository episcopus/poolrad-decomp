-- vec.lua: print what the CPU sees at the vector page after BASIC has booted (one-off diagnosis)
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
emu.wait(4)
local t = {}
for a = 0xFEE0, 0xFEFF do t[#t + 1] = string.format("%02X", mem:read_u8(a)) end
print("FEE0..FEFF " .. table.concat(t, " "))
t = {}
for a = 0xFFF0, 0xFFFF do t[#t + 1] = string.format("%02X", mem:read_u8(a)) end
print("FFF0..FFFF " .. table.concat(t, " "))
m:exit()
