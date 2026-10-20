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
-- What the game writes lives in the image's save area, and the image is laid out again at every build (a bank that shrinks moves the save area
-- by a sector or two). The overlay therefore holds sector numbers RELATIVE to the save area (found in the image's header: u32 at byte 16), after the
-- magic "POVL" and a version; an overlay without it (the first format held absolute sector numbers, which a rebuild turned into the wrong sectors:
-- a directory with copies of itself, a character called "CFOO") is put aside and a new one started.
local save_lsn = (img:byte(17) << 24) | (img:byte(18) << 16) | (img:byte(19) << 8) | img:byte(20)
local save_sectors = (img:byte(21) << 8) | img:byte(22)
save_sectors = (save_sectors == 0) and 512 or save_sectors
local OVL_MAGIC = "POVL\0\0\0\1"
if ovl_path then
  local of = io.open(ovl_path, "rb")
  if of then
    local d = of:read("a")
    of:close()
    if #d > 0 and d:sub(1, 8) ~= OVL_MAGIC then
      local old = ovl_path .. ".old-format"
      os.rename(ovl_path, old)
      print(string.format("play: %s is in the old format (absolute sector numbers, wrong after the image changed): kept as %s, starting with empty saves", ovl_path, old))
      d = ""
    end
    local n = 0
    for p = 9, #d - 259, 260 do
      local rel = (d:byte(p) << 24) | (d:byte(p + 1) << 16) | (d:byte(p + 2) << 8) | d:byte(p + 3)
      if rel < save_sectors then
        sec_over[save_lsn + rel] = d:sub(p + 4, p + 259)
        n = n + 1
      end
    end
    if #d > 0 then print(string.format("play: %d saved sectors applied from %s", n, ovl_path)) end
  end
  local fresh = io.open(ovl_path, "rb")
  local empty = (fresh == nil) or (fresh:seek("end") == 0)
  if fresh then fresh:close() end
  ovl = assert(io.open(ovl_path, "ab"))
  if empty then ovl:write(OVL_MAGIC) ovl:flush() end
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
      if ovl and lsn + s >= save_lsn and lsn + s < save_lsn + save_sectors then   -- (only the save area is kept; the game writes nothing else)
        local l = lsn + s - save_lsn
        ovl:write(string.char((l >> 24) & 255, (l >> 16) & 255, (l >> 8) & 255, l & 255), sec)
        ovl:flush()
      end
    end
  else
    ok = 2
  end
  mem:write_u8(0x0961, ok)
end)

local function rgb() pcall(function() m.ioport.ports[":screen_config"].fields["Monitor Type"].user_value = 1 end) end   -- RGB (set_value does nothing on the host)
rgb()
local function boot(settle)
  emu.wait(settle)                                             -- BASIC needs a moment after reset before it takes keys (longer after a reset)
  m.natkeyboard:post((os.getenv("MB_CMD") or 'LOADM"POOL":EXEC') .. "\r")
end
boot(m.time:as_double() > 5 and 6 or 2)           -- (MAME runs this script again after a reset)
-- (the monitor type is set again a few seconds in: a first run once showed the composite palette, MAME's own settings can come in after the script's)
for _ = 1, 3 do
  emu.wait(4)
  rgb()
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
local MB_STATUS = 0x0905
while syms.wheel_pick do
  emu.wait(0.5)
  local status = mem:read_u8(MB_STATUS)
  if status ~= 0 then                       -- the program ended (the original returns to DOS: Halt; a party destroyed does it); BASIC's memory test also writes here while it starts: only a steady value counts
    emu.wait(2)
  end
  if status ~= 0 and mem:read_u8(MB_STATUS) == status then
    print("play: the game ended (status " .. status .. "): starting it again (BASIC starts cold, which takes a while)")
    io.stdout:flush()
    mem:write_u8(MB_STATUS, 0)
    mem:write_u8(0x0071, 0)                 -- (BASIC's warm start flag: a cold start sets up Disk BASIC's variables again, which the game's low RAM has overwritten)
    m:soft_reset()                          -- (the script starts again with the machine: this run is over; the check is for a MAME that does not)
    emu.wait(20)                            -- (reached only when MAME did not start the script again)
    boot(0)
    rgb()
  end
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
