-- watch.lua: MAME autoboot script for the game (step 8.5e). Boots the program disk, types the command, then looks at the
-- screen (physical block 0..3 of the 512 KB, read through the RAM device's save item, whatever the MMU shows) every
-- 0.1 emulated seconds. A screen that stayed the same for two looks and differs from the last one kept is written to
-- <MB_OUT>-sNN.scr4 (32,000 bytes, then the 16 palette registers of the mailbox: the format of poolrad_replay --dump,
-- tools/screens.py hashes them). Stops when the mailbox status is set (the program finished or failed) or MB_LIMIT
-- emulated seconds have passed; writes <MB_OUT>.mbx (the mailbox) and a snapshot.
--   MB_OUT     output prefix        MB_CMD   typed at BASIC (default LOADM"POOL":EXEC)
--   MB_LIMIT   emulated seconds     MB_KEYS  "t:text" pairs separated by ';': type text at emulated second t (\n = Enter)
--   MB_SWAP    "n:file" pairs separated by ';': when the screen count reaches n, mount file in drive 2 (the disk-swap prompts)
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local out = os.getenv("MB_OUT") or "/work/build/run/game"
local cmd = os.getenv("MB_CMD") or 'LOADM"POOL":EXEC'
local limit = tonumber(os.getenv("MB_LIMIT") or "120")
local ram = emu.item(m.devices[":ram"].items["0/m_pointer"])

pcall(function() m.ioport.ports[":screen_config"].fields["Monitor Type"]:set_value(1) end) -- RGB
emu.wait(2)
m.natkeyboard:post(cmd .. "\n")

local keys = {}
for t, txt in string.gmatch(os.getenv("MB_KEYS") or "", "(%d+%.?%d*):([^;]*)") do
  keys[#keys + 1] = {t = tonumber(t), s = (txt:gsub("\\n", "\n")), done = false}
end

local function magic()
  return mem:read_u8(0x1000) == 0x50 and mem:read_u8(0x1001) == 0x52
     and mem:read_u8(0x1002) == 0x41 and mem:read_u8(0x1003) == 0x44
end

local t0 = m.time:as_double()
local hb
local last, prev, nsaved = nil, nil, 0
local lowram
local log
for _ = 1, 50 do                                    -- the shared folder of the VM sometimes refuses the first open
  log = io.open(out .. ".log", "w")
  if log then break end
  emu.wait(0.01)
end
if not log then log = {write = function() end, flush = function() end, close = function() end} end
while m.time:as_double() - t0 < limit do
  emu.wait(0.1)
  local now = m.time:as_double() - t0
  if now >= (hb or 0) then
    hb = now + 10
    local st = m.devices[":maincpu"].state
    log:write(string.format("t=%.0f pc=%04X s=%04X banks=%d\n", now, st["PC"].value, st["S"].value, mem:read_u16(0x1010 + 18)))
    log:flush()
  end
  for _, k in ipairs(keys) do
    if not k.done and now >= k.t then k.done = true; m.natkeyboard:post(k.s) end
  end
  if magic() and mem:read_u16(0x1018) == 0xC0DE then   -- the engine has launched the game (MB_RESULT(4))
    if not lowram then lowram = mem:read_range(0, 0xDFF, 8) end
    local scr = ram:read_block(0, 32000)
    if scr == prev and scr ~= last then
      nsaved = nsaved + 1
      local f = io.open(string.format("%s-s%02d.scr4", out, nsaved), "wb")
      f:write(scr)
      for i = 0, 15 do f:write(string.char(mem:read_u8(0x1050 + i))) end
      f:close()
      log:write(string.format("%d %.2f\n", nsaved, now))
      log:flush()
      last = scr
    end
    prev = scr
    if mem:read_u8(0x1005) ~= 0 then break end
  end
end
log:close()
local f = io.open(out .. ".mbx", "wb")
for i = 0, 0x4F do f:write(string.char(mem:read_u8(0x1000 + i))) end
f:close()
pcall(function() m.screens[":screen"]:snapshot(out .. ".png") end)
local st = m.devices[":maincpu"].state
print(string.format("watch: %d screens, mailbox status %d, pc=%04X s=%04X", nsaved, mem:read_u8(0x1005), st["PC"].value, st["S"].value))
do   -- the paged globals (physical blocks $10..$13) and the native area of the core, for the analysis of data
  local pf = io.open(out .. ".pages", "wb")
  pf:write(ram:read_block(0x10 * 0x2000, 0x8000))
  pf:close()
  local nf = io.open(out .. ".core", "wb")
  nf:write(ram:read_block(0x30 * 0x2000, 0x6000))
  nf:close()
end
do   -- the picture blocks, for the analysis of pictures
  local pf = io.open(out .. ".pics", "wb")
  for _, b in ipairs({8, 9, 10, 11, 12, 13, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x33, 0x34, 0x35, 0x36, 0x37}) do
    pf:write(ram:read_block(b * 0x2000, 0x2000))
  end
  pf:close()
end
do   -- the stack area, for the analysis of an overflow
  local sf = io.open(out .. ".stack", "wb")
  sf:write(mem:read_range(0x1000, 0x1FFF, 8))
  sf:close()
end
do   -- a probe (tools/mkgame.py DEBUG_PATCH): eight words at $0F30, the count at $0F3F
  local t = {}
  for i = 0, 7 do t[#t + 1] = string.format("%04X", mem:read_u16(0x0F30 + 2 * i)) end
  print("probe " .. mem:read_u8(0x0F3F) .. ": " .. table.concat(t, " "))
end
do   -- the engine's event log (src/engine/mailbox.h DBG)
  local n = mem:read_u8(0x0FC0)
  local t = {}
  for i = 0, 63 do
    local v = mem:read_u16(0x0F40 + 2 * ((n + i) % 64))
    if v ~= 0 then t[#t + 1] = string.format("%X:%03X", v >> 12, v & 0xFFF) end
  end
  print("event log (oldest first): " .. table.concat(t, " "))
end
do   -- how deep the stack went: the engine painted $1060..$1E00 with $AA
  local low = 0x1E00
  for a = 0x1060, 0x1DFF do if mem:read_u8(a) ~= 0xAA then low = a; break end end
  print(string.format("stack: lowest touched address %04X (painted from 1060)", low))
end
if lowram then   -- bytes of BASIC's RAM ($0000..$0DFF) that changed since the game started
  local now = mem:read_range(0, 0xDFF, 8)
  local d = {}
  for i = 1, #now do
    if now:byte(i) ~= lowram:byte(i) and #d < 40 then d[#d + 1] = string.format("%04X:%02X>%02X", i - 1, lowram:byte(i), now:byte(i)) end
  end
  print("lowram diff " .. table.concat(d, " "))
end
local tr, tn = tonumber(os.getenv("MB_TRACE") or "0"), tonumber(os.getenv("MB_TRACEN") or "0")
if tr > 0 then
  local n = mem:read_u8(tn)
  local t = {}
  for i = 0, 63 do t[#t + 1] = tostring(mem:read_u8(tr + ((n + i) % 64))) end
  print("engine calls (oldest first) " .. table.concat(t, " "))
end
do
  local t = {}
  for i = 0, 15 do t[#t + 1] = string.format("%02X", mem:read_u8(0xFFA0 + i)) end
  print("mmu " .. table.concat(t, " "))
  local sp = st["S"].value
  local u = {}
  for i = 0, 31 do u[#u + 1] = string.format("%02X", mem:read_u8(sp + i)) end
  print("stack " .. table.concat(u, " "))
  print(string.format("FC_TASK=%d dp8B=%02X", mem:read_u8(0x1009), mem:read_u8(0x8B)))
end
m:exit()
