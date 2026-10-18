-- mailbox.lua: MAME autoboot script. Types a command at the BASIC prompt, waits for the
-- test program to finish (mailbox at logical $0100, see src/engine/mailbox.inc), dumps the
-- mailbox and a screenshot, then exits. Parameters come from the environment:
--   MB_OUT   output prefix, writes <prefix>.mbx (the 80 mailbox bytes) and <prefix>.png
--   MB_CMD   text typed at BASIC (default LOADM"DEMO":EXEC)
--   MB_SCREENS if set: at every checkpoint dump the screen (the program called mb_hold) to <prefix>-cp<N>.scr4 and release it
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
  return mem:read_u8(0x1000) == 0x50 and mem:read_u8(0x1001) == 0x52
     and mem:read_u8(0x1002) == 0x41 and mem:read_u8(0x1003) == 0x44
end

-- Timestamp every change of the checkpoint counter (emulated seconds since the script
-- started): the demo uses them to time call loops. Polling every 0.2 ms of emulated time.
local t0 = m.time:as_double()
local cps, last = {}, 0
while m.time:as_double() - t0 < limit do
  emu.wait(0.0002)
  if magic() then
    local c = mem:read_u8(0x1004)
    if c ~= last then
      last = c
      cps[#cps + 1] = string.format("%d %.6f", c, m.time:as_double() - t0)
      if os.getenv("MB_SCREENS") then
        -- mb_hold has mapped the screen (physical blocks 0..3) at $4000..$BFFF: keep 32,000 bytes and the 16 palette
        -- register values from the mailbox, the format of poolrad_replay --dump (PREFIX-LABEL.scr4)
        local sf = io.open(string.format("%s-cp%d.scr4", out, c), "wb")
        sf:write(mem:read_range(0x4000, 0x4000 + 31999, 8))
        for i = 0, 15 do sf:write(string.char(mem:read_u8(0x1050 + i))) end
        sf:close()
        mem:write_u8(0x1007, 1)
      end
    end
    if mem:read_u8(0x1005) ~= 0 then break end
  end
end
local cf = io.open(out .. ".cp", "wb")
for _, l in ipairs(cps) do cf:write(l, "\n") end
cf:close()

local ok = magic() and mem:read_u8(0x1005) ~= 0
local f = io.open(out .. ".mbx", "wb")
for i = 0, 0x4F do f:write(string.char(mem:read_u8(0x1000 + i))) end
f:close()
pcall(function() m.screens[":screen"]:snapshot(out .. ".png") end)
print(ok and "mailbox: program finished" or "mailbox: TIMEOUT")
m:exit()
