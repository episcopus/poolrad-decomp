-- mailbox.lua: MAME autoboot script. Types a command at the BASIC prompt, waits for the
-- test program to finish (mailbox at logical $0100, see src/engine/mailbox.inc), dumps the
-- mailbox and a screenshot, then exits. Parameters come from the environment:
--   MB_OUT   output prefix, writes <prefix>.mbx (the 80 mailbox bytes) and <prefix>.png
--   MB_CMD   text typed at BASIC (default LOADM"DEMO":EXEC)
--   MB_LIMIT emulated seconds to wait in total (default 60)
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local out = os.getenv("MB_OUT") or "/work/build/run/mame"
local cmd = os.getenv("MB_CMD") or 'LOADM"DEMO":EXEC'
local limit = tonumber(os.getenv("MB_LIMIT") or "60")

pcall(function() m.ioport.ports[":screen_config"].fields["Monitor Type"]:set_value(1) end) -- RGB

-- BASIC needs a moment after reset before it takes keys.
emu.wait(2)
m.natkeyboard:post(cmd .. "\n")

local function magic()
  return mem:read_u8(0x100) == 0x50 and mem:read_u8(0x101) == 0x52
     and mem:read_u8(0x102) == 0x41 and mem:read_u8(0x103) == 0x44
end

-- Timestamp every change of the checkpoint counter (emulated seconds since the script
-- started): the demo uses them to time call loops. Polling every 0.2 ms of emulated time.
local t0 = m.time:as_double()
local cps, last = {}, 0
while m.time:as_double() - t0 < limit do
  emu.wait(0.0002)
  if magic() then
    local c = mem:read_u8(0x104)
    if c ~= last then last = c; cps[#cps + 1] = string.format("%d %.6f", c, m.time:as_double() - t0) end
    if mem:read_u8(0x105) ~= 0 then break end
  end
end
local cf = io.open(out .. ".cp", "wb")
for _, l in ipairs(cps) do cf:write(l, "\n") end
cf:close()

local ok = magic() and mem:read_u8(0x105) ~= 0
local f = io.open(out .. ".mbx", "wb")
for i = 0, 0x4F do f:write(string.char(mem:read_u8(0x100 + i))) end
f:close()
pcall(function() m.screens[":screen"]:snapshot(out .. ".png") end)
print(ok and "mailbox: program finished" or "mailbox: TIMEOUT")
m:exit()
