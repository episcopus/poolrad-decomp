-- mailbox.lua: MAME autoboot script. Types a command at the BASIC prompt, waits for the
-- test program to finish (mailbox at logical $0900, see src/engine/mailbox.inc), dumps the
-- mailbox and a screenshot, then exits. Parameters come from the environment:
--   MB_OUT   output prefix, writes <prefix>.mbx (the 80 mailbox bytes) and <prefix>.png
--   MB_CMD   text typed at BASIC (default LOADM"DEMO":EXEC)
--   MB_SCREENS if set: at every checkpoint dump the screen (the program called mb_hold) to <prefix>-cp<N>.scr4 and release it
--   MB_KEYS, MB_KEYS_CP if set: type MB_KEYS (\n is Enter) into the keyboard when the checkpoint counter reaches MB_KEYS_CP
--   MB_LIMIT emulated seconds to wait in total (default 60)
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local out = os.getenv("MB_OUT") or "/work/build/run/mame"
local cmd = os.getenv("MB_CMD") or 'LOADM"DEMO":EXEC'
local limit = tonumber(os.getenv("MB_LIMIT") or "60")

pcall(function() m.ioport.ports[":screen_config"].fields["Monitor Type"]:set_value(1) end) -- RGB


-- MB_DAC=1: every change of the 6 bit DAC ($FF20 bits 7..2) goes to <out>.dac as `seconds value` (tools/dac2wav.py makes the WAV: step 8.8)
local dac_lines, dac_last, dac_tap = {}, -1, nil
if os.getenv("MB_DAC") then
  dac_tap = mem:install_write_tap(0xFF20, 0xFF20, "dac", function(offset, data, mask)
    local v = data & 0xFC
    if v ~= dac_last and #dac_lines < 4000000 then
      dac_last = v
      dac_lines[#dac_lines + 1] = string.format("%.7f %d", m.time:as_double(), v)
    end
  end)
end
-- MB_WTAP=addr (hex): the time of every write to that byte goes to <out>.wtap (step 8.8: the sound interrupt's counter)
local wtap_lines, wtap_tap = {}, nil
if os.getenv("MB_WTAP") then
  local a = tonumber(os.getenv("MB_WTAP"), 16)
  wtap_tap = mem:install_write_tap(a, a, "wtap", function(offset, data, mask)
    if #wtap_lines < 400000 then wtap_lines[#wtap_lines + 1] = string.format("%.7f %d", m.time:as_double(), data & 0xFF) end
  end)
end
local function dac_save(out)
  if os.getenv("MB_WTAP") then
    local wf = io.open(out .. ".wtap", "w")
    for _, l in ipairs(wtap_lines) do wf:write(l, "\n") end
    wf:close()
  end
  if os.getenv("MB_DAC") then
    local df = io.open(out .. ".dac", "w")
    for _, l in ipairs(dac_lines) do df:write(l, "\n") end
    df:close()
  end
end

-- BASIC needs a moment after reset before it takes keys.
emu.wait(2)
m.natkeyboard:post(cmd .. "\n")

local function magic()
  return mem:read_u8(0x0900) == 0x50 and mem:read_u8(0x0901) == 0x52
     and mem:read_u8(0x0902) == 0x41 and mem:read_u8(0x0903) == 0x44
end

-- Timestamp every change of the checkpoint counter (emulated seconds since the script
-- started): the demo uses them to time call loops. Polling every 0.2 ms of emulated time.
local t0 = m.time:as_double()
local cps, last = {}, 0
while m.time:as_double() - t0 < limit do
  emu.wait(0.0002)
  if magic() then
    local c = mem:read_u8(0x0904)
    if c ~= last then
      last = c
      cps[#cps + 1] = string.format("%d %.6f", c, m.time:as_double() - t0)
      if os.getenv("MB_KEYS") and c == tonumber(os.getenv("MB_KEYS_CP") or "0") then
        m.natkeyboard:post((os.getenv("MB_KEYS"):gsub("\\n", "\n")))   -- the program waits for keys after this checkpoint
      end
      if os.getenv("MB_SCREENS") then
        -- mb_hold has mapped the screen (physical blocks 0..3) at $4000..$BFFF: keep 32,000 bytes and the 16 palette
        -- register values from the mailbox, the format of poolrad_replay --dump (PREFIX-LABEL.scr4)
        local sf = io.open(string.format("%s-cp%d.scr4", out, c), "wb")
        sf:write(mem:read_range(0x4000, 0x4000 + 31999, 8))
        for i = 0, 15 do sf:write(string.char(mem:read_u8(0x0950 + i))) end
        sf:close()
        mem:write_u8(0x0908, 1)
      end
    end
    if mem:read_u8(0x0905) ~= 0 then break end
  end
end
dac_save(out)
local cf = io.open(out .. ".cp", "wb")
for _, l in ipairs(cps) do cf:write(l, "\n") end
cf:close()

local ok = magic() and mem:read_u8(0x0905) ~= 0
local f = io.open(out .. ".mbx", "wb")
for i = 0, 0x4F do f:write(string.char(mem:read_u8(0x0900 + i))) end
f:close()
pcall(function() m.screens[":screen"]:snapshot(out .. ".png") end)
if not ok then   -- a hang: say where the CPU is
  local cpu = m.devices[":maincpu"]
  local st = cpu.state
  print(string.format("mailbox: TIMEOUT pc=%04X cc=%02X s=%04X vectors irq=%04X firq=%04X",
    st["PC"].value, st["CC"].value, st["S"].value, mem:read_u16(0xFFF8), mem:read_u16(0xFFF6)))
else
  print("mailbox: program finished")
end
m:exit()
