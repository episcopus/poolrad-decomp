-- play.lua: MAME autoboot script to PLAY the game (a window, the host's keyboard and speakers; step 8.8b). It boots the program disk, types
-- LOADM"POOL":EXEC and serves the game's storage (porting guide D13: the development backend, a write tap on the doorbell at $0960
-- between the image file and physical RAM, the same as lua/watch.lua) with one addition: what the game writes (saved games, characters)
-- is appended to an overlay file at once and applied again at the next start, so a game saved today is there tomorrow.
--   MB_IMG  the container image (build/game/pool.img)     MB_OVL  the overlay file of what the game wrote (build/play/saves.ovl)
--   MB_CMD  typed at BASIC (default LOADM"POOL":EXEC)
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local ram = emu.item(m.devices[":ram"].items["0/m_pointer"])

local img_path, ovl_path = assert(os.getenv("MB_IMG")), os.getenv("MB_OVL")
local f = assert(io.open(img_path, "rb"))
local img = f:read("a")
f:close()
local sec_over = {}
local ovl
if ovl_path then
  local of = io.open(ovl_path, "rb")
  if of then
    local d = of:read("a")
    of:close()
    local n = 0
    for p = 1, #d - 259, 260 do
      local lsn = (d:byte(p) << 24) | (d:byte(p + 1) << 16) | (d:byte(p + 2) << 8) | d:byte(p + 3)
      sec_over[lsn] = d:sub(p + 4, p + 259)
      n = n + 1
    end
    print(string.format("play: %d saved sectors applied from %s", n, ovl_path))
  end
  ovl = assert(io.open(ovl_path, "ab"))
end

secreq_tap = mem:install_write_tap(0x0960, 0x0960, "secreq", function(offset, data, mask)   -- (kept referenced: the collector would remove the tap)
  local cmd = data & 0xFF
  if cmd == 0 then return end
  local lsn = (mem:read_u8(0x0962) << 16) | (mem:read_u8(0x0963) << 8) | mem:read_u8(0x0964)
  local count = (mem:read_u8(0x0965) << 8) | mem:read_u8(0x0966)
  local at = mem:read_u8(0x0967) * 0x2000 + ((mem:read_u8(0x0968) << 8) | mem:read_u8(0x0969))
  local ok = 0
  if (lsn + count) * 256 > #img then ok = 1 end
  if ok == 0 and cmd == 1 then
    for s = 0, count - 1 do
      local sec = sec_over[lsn + s] or img:sub((lsn + s) * 256 + 1, (lsn + s) * 256 + 256)
      for i = 1, 256 do ram:write(at + s * 256 + i - 1, sec:byte(i)) end
    end
  elseif ok == 0 and cmd == 2 then
    for s = 0, count - 1 do
      local t = {}
      for i = 0, 255 do t[#t + 1] = string.char(ram:read(at + s * 256 + i)) end
      local sec = table.concat(t)
      sec_over[lsn + s] = sec
      if ovl then
        local l = lsn + s
        ovl:write(string.char((l >> 24) & 255, (l >> 16) & 255, (l >> 8) & 255, l & 255), sec)
        ovl:flush()
      end
    end
  else
    ok = 2
  end
  mem:write_u8(0x0961, ok)
end)

pcall(function() m.ioport.ports[":screen_config"].fields["Monitor Type"]:set_value(1) end)   -- RGB
emu.wait(2)                                                    -- BASIC needs a moment after reset before it takes keys
m.natkeyboard:post((os.getenv("MB_CMD") or 'LOADM"POOL":EXEC') .. "\n")
-- (the monitor type is set again a few seconds in: a first run once showed the composite palette, MAME's own settings can come in after the script's)
for _ = 1, 3 do
  emu.wait(4)
  pcall(function() m.ioport.ports[":screen_config"].fields["Monitor Type"]:set_value(1) end)
end

-- The copy protection: the game asks for the code word that goes with a pair of runes of the original's paper code wheel (CheckCodeWheel,
-- ovl02). There are 13 questions, the core keeps the last Random(13) it drew in wheel_pick (bit 7 set), and the words are the game's own table
-- (whitepaper 5.12): the word is printed on the terminal once the question is on the screen. You type it yourself.
local syms = {}
for k, v in string.gmatch(os.getenv("MB_SYMS") or "", "([%w_]+)=(%x+)") do syms[k] = tonumber(v, 16) end
-- MB_KEYLOG=1: print every key the engine's keyboard scan queues (a write tap on kq_tail, the queue's tail index): the code the game will read,
-- with the emulated time, so what the game was given can be told from what was pressed
if os.getenv("MB_KEYLOG") and syms.kq and syms.kq_tail then
  keylog_tap = mem:install_write_tap(syms.kq_tail, syms.kq_tail, "keylog", function(offset, data, mask)
    local tail = data & 15
    local code = mem:read_u8(syms.kq + ((tail - 1) & 15))
    if code == 0 then return end                   -- (the engine clears the queue at start)
    print(string.format("play: t=%.1f key queued: code %d (%s)", m.time:as_double(), code, code >= 32 and code < 127 and string.char(code) or "-"))
    io.stdout:flush()
  end)
end
local WHEEL_WORDS = {"BEWARE", "ZOMBIE", "NOTNOW", "COPPER", "DRAGON", "EFREET", "FRIEND", "JUNGLE", "KNIGHT", "SAVIOR", "TEMPLE", "VULCAN", "WYVERN"}
local function core_phys(a) return 0x30 * 0x2000 + a - 0x2000 end
local function polls() return mem:read_u16(0x090A) end   -- the game polls the keyboard (MB_POLLS) while it waits for a key
local shown
while syms.wheel_pick do
  emu.wait(0.5)
  local pick = ram:read(core_phys(syms.wheel_pick))
  if pick >= 0x80 and pick < 0x80 + #WHEEL_WORDS and polls() > 50 then
    local before = polls()
    emu.wait(2.0)
    if polls() > before + 100 then                    -- (steadily polling: the question is up)
      pick = ram:read(core_phys(syms.wheel_pick))
      local word = WHEEL_WORDS[(pick & 0x7F) + 1]
      if word and pick ~= shown then
        shown = pick
        print("play: code wheel question " .. (pick & 0x7F) .. ": the code word is " .. word)
        io.stdout:flush()
      end
    end
  end
end
