-- watch.lua: MAME autoboot script for the game (step 8.5e). Boots the program disk, types the command, then looks at the
-- screen (physical block 0..3 of the 512 KB, read through the RAM device's save item, whatever the MMU shows) every
-- 0.1 emulated seconds. A screen that stayed the same for two looks and differs from the last one kept is written to
-- <MB_OUT>-sNN.scr4 (32,000 bytes, then the 16 palette registers of the mailbox: the format of poolrad_replay --dump,
-- tools/screens.py hashes them). Stops when the mailbox status is set (the program finished or failed) or MB_LIMIT
-- emulated seconds have passed; writes <MB_OUT>.mbx (the mailbox) and a snapshot.
--   MB_OUT     output prefix        MB_CMD   typed at BASIC (default LOADM"POOL":EXEC)
--   MB_LIMIT   emulated seconds     MB_KEYS  "t:text" pairs separated by ';': type text at emulated second t (\n = Enter)
--   MB_SWAP    "n:file" pairs separated by ';': when the screen count reaches n, mount file in drive 2 (the disk-swap prompts)
--   MB_FLOP    the floppy set of step 8.10: a directory of POOLnn.DSK, mounted as the engine asks for them (below)
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]

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

local out = os.getenv("MB_OUT") or "/work/build/run/game"
local cmd = os.getenv("MB_CMD") or 'LOADM"POOL":EXEC'
local limit = tonumber(os.getenv("MB_LIMIT") or "120")
local ram = emu.item(m.devices[":ram"].items["0/m_pointer"])

pcall(function() m.ioport.ports[":screen_config"].fields["Monitor Type"].user_value = 1 end) -- RGB
-- the storage backend of the development build (porting guide D13): a write tap on the doorbell at $0960 serves sector reads and
-- writes between the image file (MB_IMG) and physical RAM at once, the status goes to $0961
last_io = 0                                          -- when the game last used the storage (the session driver waits it out)
local img_path = os.getenv("MB_IMG")
local img, sec_over = nil, {}
if img_path and not os.getenv("MB_NOTAP") then
  local f = assert(io.open(img_path, "rb"))
  img = f:read("a")
  f:close()
  if os.getenv("MB_OVL") then      -- MB_OVL=file: the saved games of a `make play` (build/play/saves.ovl, format of lua/play.lua: "POVL", then records of a save area relative sector number and 256 bytes, the last of a sector wins) are applied first
    local of = io.open(os.getenv("MB_OVL"), "rb")
    if of then
      local d = of:read("a")
      of:close()
      local save_lsn = (img:byte(17) << 24) | (img:byte(18) << 16) | (img:byte(19) << 8) | img:byte(20)
      assert(d:sub(1, 8) == "POVL\0\0\0\1", "MB_OVL: not an overlay of the current format")
      for p = 9, #d - 259, 260 do
        sec_over[save_lsn + ((d:byte(p) << 24) | (d:byte(p + 1) << 16) | (d:byte(p + 2) << 8) | d:byte(p + 3))] = d:sub(p + 4, p + 259)
      end
    end
  end
  -- the tap object must stay referenced: when the collector frees it MAME removes the tap (or crashes)
  secreq_tap = mem:install_write_tap(0x0960, 0x0960, "secreq", function(offset, data, mask)
    local cmd = data & 0xFF
    if cmd == 0 then return end
    last_io = m.time:as_double()
    local lsn = (mem:read_u8(0x0962) << 16) | (mem:read_u8(0x0963) << 8) | mem:read_u8(0x0964)
    local count = (mem:read_u8(0x0965) << 8) | mem:read_u8(0x0966)
    local at = mem:read_u8(0x0967) * 0x2000 + ((mem:read_u8(0x0968) << 8) | mem:read_u8(0x0969))
    local ok = 0
    if os.getenv("MB_SECLOG") then print(string.format("sec cmd=%d lsn=%d count=%d at=%X t=%.3f pc=%04X", cmd, lsn, count, at, m.time:as_double(), m.devices[":maincpu"].state["PC"].value)); io.stdout:flush() end
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
        sec_over[lsn + s] = table.concat(t)
      end
    else
      ok = 2
    end
    mem:write_u8(0x0961, ok)
  end)
end
-- MB_SDC=file: a model of the CoCo SDC's command mode (step 8.10b; there is no SDC in MAME: this is the engine's driver, src/engine/sdc.asm, against what NitrOS-9's
-- driver and the SDC User Guide say of the registers, not against the card). $FF40 = $43 turns command mode on, 0 off; $FF49 and $FF4A:$FF4B the sector
-- (bits 23..16 and 15..0); a command at $FF48 ($80 + drive reads, $A0 + drive writes) makes status bit 1 (ready) rise; then 256 bytes are read from or written to
-- $FF4A/$FF4B one byte at a time in turn; status 0 when done. The file is the SDC image (tools/mkimage.py --sdc): sector 630 is the first of the game's image.
-- Writes go to sec_over (the saves of the run, as with MB_IMG). The FDC under these addresses is told "force interrupt" ($D0) so that it ignores the commands.
if os.getenv("MB_SDC") then
  local f = assert(io.open(os.getenv("MB_SDC"), "rb"))
  local sd = f:read("a")
  f:close()
  local cmdmode, p1, p2, p3, cmd, status = false, 0, 0, 0, 0, 0
  local rbuf, wbuf, pos = nil, nil, 0
  local function lsn() return (p1 << 16) | (p2 << 8) | p3 end
  local function done() rbuf, wbuf, pos, status = nil, nil, 0, 0 end
  sdc_wr40 = mem:install_write_tap(0xFF40, 0xFF40, "sdc40", function(offset, data, mask)
    local v = data & 0xFF
    if v == 0x43 then cmdmode = true; done()
    elseif cmdmode and v == 0 then cmdmode = false end
    return data
  end)
  sdc_wr = mem:install_write_tap(0xFF48, 0xFF4B, "sdc48", function(offset, data, mask)
    if not cmdmode then return data end
    local v = data & 0xFF
    if offset == 0xFF48 then
      cmd = v
      local n = lsn()
      last_io = m.time:as_double()
      if (v & 0xE0) == 0x80 then
        local s = sec_over[n - 630] or sd:sub(n * 256 + 1, n * 256 + 256)
        if #s < 256 then status = 0x80 else rbuf, pos, status = s, 0, 0x02 end
      elseif (v & 0xE0) == 0xA0 then
        wbuf, pos, status = {}, 0, 0x02
      end
      return 0xD0
    elseif offset == 0xFF49 then p1 = v
    elseif wbuf then
      wbuf[#wbuf + 1] = string.char(v)
      if #wbuf == 256 then sec_over[lsn() - 630] = table.concat(wbuf); done() end
    elseif offset == 0xFF4A then p2 = v
    elseif offset == 0xFF4B then p3 = v end
    return data
  end)
  sdc_rd = mem:install_read_tap(0xFF48, 0xFF4B, "sdcrd", function(offset, data, mask)
    if not cmdmode then return data end
    if offset == 0xFF48 then return status end
    if offset == 0xFF49 then return p1 end
    if rbuf then
      local b = rbuf:byte(pos + 1)
      pos = pos + 1
      if pos == 256 then done() end
      return b
    end
    return 0
  end)
end
-- MB_FLOP=dir: the floppy set (step 8.10). The engine (src/engine/flop.c) asks for a disk by writing its number to $090C and the drive to $090D,
-- then waits for ENTER or for $090F: the disk POOLnn.DSK of dir goes into that drive (a second after the old one is out: a person is slower), the
-- prompt is answered. Every swap is printed ("swap t= disk= drive=").
if os.getenv("MB_FLOP") then
  local dir = os.getenv("MB_FLOP")
  local drives = {[0] = m.images[":ext:fdc:wd17xx:0:525dd"], [1] = m.images[":ext:fdc:wd17xx:1:525dd"]}
  local pending
  if os.getenv("MB_DSKLOG") then      -- every DSKCON call (disk.asm writes the operation, drive, track and sector to $EA..$ED): "dsk t op drive track sector"
    dsk_tap = mem:install_write_tap(0x00ED, 0x00ED, "dsklog", function(offset, data, mask)
      print(string.format("dsk %.3f op=%d d=%d t=%d s=%d", m.time:as_double(), mem:read_u8(0xEA), mem:read_u8(0xEB), mem:read_u8(0xEC), data & 0xFF))
      return data
    end)
  end
  flop_frame = emu.add_machine_frame_notifier(function()
    local now = m.time:as_double()
    local req = mem:read_u8(0x090C)
    if req ~= 0 and not pending and mem:read_u8(0x090F) == 0 and now >= (keyed_until or 0) then
      pending = {disk = req, drive = mem:read_u8(0x090D), due = now + (tonumber(os.getenv("MB_SWAP_DELAY") or "1.0"))}
      last_io = now
      if drives[pending.drive] then pcall(function() drives[pending.drive]:unload() end) end
    elseif pending and now >= pending.due then
      if os.getenv("MB_FLOP_WRONG") then pending.drive = pending.drive ~ 1 end     -- (a player who puts the disk in the other drive: the engine looks at every drive)
      local file = string.format("%s/POOL%02d.DSK", dir, pending.disk)
      local ok = drives[pending.drive] and pcall(function() drives[pending.drive]:load(file) end)
      print(string.format("swap t=%.2f disk=%d drive=%d %s", now, pending.disk, pending.drive, ok and "ok" or "FAILED"))
      io.stdout:flush()
      if os.getenv("MB_FLOP_KEY") then m.natkeyboard:post("\n"); keyed_until = now + 3 else mem:write_u8(0x090F, 1) end   -- MB_FLOP_KEY: answer the prompt with ENTER through the emulated keyboard (the engine's own scan), as a player does
      pending = nil
      last_io = now
    end
  end)
end
if os.getenv("MB_WATCH") then      -- MB_WATCH=hexfrom-hexto: log the first writes into that range (pc, s, address, value)
  local lo, hi = os.getenv("MB_WATCH"):match("(%x+)-(%x+)")
  local n = 0
  local il, ih = (os.getenv("MB_WATCH_IGNORE") or ""):match("(%x+)-(%x+)")
  local ignore_lo, ignore_hi = il and tonumber(il, 16), ih and tonumber(ih, 16)
  watch_tap = mem:install_write_tap(tonumber(lo, 16), tonumber(hi, 16), "watch", function(offset, data, mask)
    local st = m.devices[":maincpu"].state
    if ignore_lo and st["PC"].value >= ignore_lo and st["PC"].value < ignore_hi then return end     -- MB_WATCH_IGNORE=from-to: writes by code in that range are not logged (the far-call trampoline)
    if n < tonumber(os.getenv("MB_WATCH_N") or "12") and m.time:as_double() >= tonumber(os.getenv("MB_WATCH_AFTER") or "0") then
      n = n + 1
      local sp, bytes = st["S"].value, {}
      for k = 0, 23 do bytes[#bytes + 1] = string.format("%02X", mem:read_u8(sp + k)) end
      print(string.format("watch write %04X=%02X pc=%04X s=%04X u=%04X x=%04X t=%.1f stack %s", offset, data & 0xFF, st["PC"].value, sp, st["U"].value, st["X"].value, m.time:as_double(), table.concat(bytes, " ")))
    end
  end)
end
if os.getenv("MB_SNAPAT") then      -- MB_SNAPAT=t1,t2,..: a screenshot (OUT-t<t>.png) when the machine's clock passes each of those emulated seconds (the boot splash: step 8.9i)
  local snaps = {}
  for t in string.gmatch(os.getenv("MB_SNAPAT"), "[%d.]+") do snaps[#snaps + 1] = {t = tonumber(t), name = t, done = false} end
  snap_frame = emu.add_machine_frame_notifier(function()
    local now = m.time:as_double()
    for _, sn in ipairs(snaps) do
      if not sn.done and now >= sn.t then
        sn.done = true
        pcall(function() m.screens[":screen"]:snapshot(out .. "-t" .. sn.name .. ".png") end)
      end
    end
  end)
end
if os.getenv("MB_ITRACE") then      -- MB_ITRACE=t: from that emulated second, MAME's debugger writes every instruction to build/run/itrace.txt (needs MB_DEBUGGER=1)
  local t0, itrace_on = tonumber(os.getenv("MB_ITRACE")), false
  itrace_frame = emu.add_machine_frame_notifier(function()
    if not itrace_on and m.time:as_double() >= t0 and m.debugger then
      itrace_on = true
      m.debugger:command("trace /work/build/run/itrace.txt,maincpu,noloop" .. (os.getenv("MB_ITRACE_ACT") and (",{" .. os.getenv("MB_ITRACE_ACT") .. "}") or ""))
    end
  end)
end
if os.getenv("MB_BANKLOG") then      -- MB_BANKLOG=t0-t1: the far call trampoline's writes of FC_CURBANK ($80, the bank the code runs in or returns to) and FC_X ($87, the entry a call goes to) between those emulated seconds, two bytes each (kind 0 = bank, 1 = entry high, 2 = entry low; value), into OUT.banklog; tools/bankpool_sim.py replays it against other pool sizes and policies
  local t0, t1 = os.getenv("MB_BANKLOG"):match("([%d.]+)-([%d.]+)")
  bl_file, bl_buf = io.open(out .. ".banklog", "wb"), {}
  local function bl_log(kind, data)
    local now = m.time:as_double()
    if now >= tonumber(t0) and now <= tonumber(t1) then
      bl_buf[#bl_buf + 1] = string.char(kind, data & 0xFF)
      if #bl_buf >= 4096 then bl_file:write(table.concat(bl_buf)); bl_buf = {} end
    end
  end
  bl_tap = mem:install_write_tap(0x0080, 0x0080, "banklog", function(offset, data, mask) bl_log(0, data); return data end)
  bl_tap2 = mem:install_write_tap(0x0087, 0x0088, "banklog2", function(offset, data, mask) bl_log(offset - 0x0086, data); return data end)
  bl_frame = emu.add_machine_frame_notifier(function() if #bl_buf > 0 then bl_file:write(table.concat(bl_buf)); bl_file:flush(); bl_buf = {} end end)
end
if os.getenv("MB_ENGCOUNT") then      -- MB_ENGCOUNT=t0-t1: how many times the game calls each engine routine between those emulated seconds (a write tap on eng_idx, which __engcall stores at every call), printed at the end as "engcount idx n"
  local t0, t1 = os.getenv("MB_ENGCOUNT"):match("([%d.]+)-([%d.]+)")
  local ei = tonumber((os.getenv("MB_SYMS") or ""):match("eng_idx=(%x+)") or "0", 16)
  ec_n = {}
  ec_tap = mem:install_write_tap(ei, ei, "engcount", function(offset, data, mask)
    local now = m.time:as_double()
    if now >= tonumber(t0) and now <= tonumber(t1) then ec_n[data & 0xFF] = (ec_n[data & 0xFF] or 0) + 1 end
    return data
  end)
  ec_frame = emu.add_machine_frame_notifier(function()
    if m.time:as_double() >= tonumber(t1) and not ec_done then
      ec_done = true
      for k, v in pairs(ec_n) do print(string.format("engcount %d %d", k, v)) end
    end
  end)
end
if os.getenv("MB_PCLOG") then      -- MB_PCLOG=t0-t1: the program counter at every video frame between those emulated seconds
  local t0, t1 = os.getenv("MB_PCLOG"):match("([%d.]+)-([%d.]+)")
  local eng_idx = tonumber((os.getenv("MB_SYMS") or ""):match("eng_idx=(%x+)") or "0", 16)
  pc_frame = emu.add_machine_frame_notifier(function()
    local now = m.time:as_double()
    if now >= tonumber(t0) and now <= tonumber(t1) then
      local st = m.devices[":maincpu"].state
      print(string.format("pc t=%.3f pc=%04X s=%04X task=%d bank=%d polls=%d eng=%d", now, st["PC"].value, st["S"].value, mem:read_u8(0x0909), mem:read_u8(0x0080), mem:read_u16(0x090A), mem:read_u8(eng_idx)))   -- (task: FC_TASK, bank: FC_CURBANK, polls: MB_POLLS, eng: the engine call in progress when task is 1; tools/prof_pc.py turns the samples into a profile)
    end
  end)
end
emu.wait(2)
m.natkeyboard:post(cmd .. "\n")


-- the session driver (MB_SESSION = a tests/sessions/*.keys file, MB_SYMS = "name=hexaddr,..." of the engine's and the core's symbols):
-- the keys go straight into the engine's key queue as the codes the keyboard scan would have produced (the matrix path is
-- tested by itself), one command each time the screen has been still for STILL seconds. `wait` and `shot` are not needed (the
-- screens are kept whenever they settle), `clock` is pinned in the game; `wheel` types the answer of the code wheel question
-- the game picked (wheel_pick) and, once the main menu has settled, puts the random generator where the recorded run had it
-- (WHEEL_SEED, the RandSeed of the original at the main menu: tools/c replay of create-character, read 400000).
local syms = {}
for k, v in string.gmatch(os.getenv("MB_SYMS") or "", "([%w_]+)=(%x+)") do syms[k] = tonumber(v, 16) end
if os.getenv("MB_RLOG") then      -- every Random(range) -> result, from the stores rtl_Random makes to $0A00 and $0A02 (rtl_sys.c, switched on through $090E), into OUT.rlog
  rl_file = io.open(out .. ".rlog", "w")
  rl_on = emu.add_machine_frame_notifier(function() mem:write_u8(0x090E, 1) end)   -- (the game's flag that logs the dice)
  rl_b, rl_n = {0, 0, 0, 0}, 0
  rl_tap = mem:install_write_tap(0x0A00, 0x0A03, "rlog", function(offset, data, mask)
    rl_b[offset - 0x0A00 + 1] = data & 0xFF
    if offset == 0x0A03 then
      rl_n = rl_n + 1
      rl_file:write(string.format("R %d %d %d\n", rl_n, rl_b[1] * 256 + rl_b[2], rl_b[3] * 256 + rl_b[4]))
    end
    return data
  end)
end
local WHEEL_WORDS = {"BEWARE", "ZOMBIE", "NOTNOW", "COPPER", "DRAGON", "EFREET", "FRIEND", "JUNGLE", "KNIGHT", "SAVIOR", "TEMPLE", "VULCAN", "WYVERN"}
local WHEEL_SEED = 0x074494E8
local KEYCODES = {ENTER = 13, ESC = 27, SPACE = 32, TAB = 9, BACKSPACE = 8, UP = 0x81, DOWN = 0x82, LEFT = 0x83, RIGHT = 0x84,
                  F1 = 0x91, F2 = 0x92, HOME = 0xA0, END = 0xA1, PGUP = 0xA2, PGDN = 0xA3}
local STILL = tonumber(os.getenv("MB_STILL") or "2.0")
local script = {}
if os.getenv("MB_SESSION") then
  for line in io.lines(os.getenv("MB_SESSION")) do
    line = line:gsub("#.*", "")
    local cmd, arg = line:match("^%s*(%a+)%s*(.-)%s*$")
    if cmd == "key" or cmd == "press" then
      local code = KEYCODES[arg:upper()] or (#arg == 1 and arg:byte())
      if code then script[#script + 1] = {"keys", {code}, cmd == "press"} else print("session: unknown key " .. arg) end
    elseif cmd == "text" then
      local t = {}
      for c in arg:gmatch(".") do t[#t + 1] = c:byte() end
      script[#script + 1] = {"keys", t}
    elseif cmd == "wheel" then
      script[#script + 1] = {"wheel"}
    end
  end
end
local si, still_since, seed_due = 1, 0, false
local last_press = -10
local inject, inject_at = {}, 0                      -- keys on their way into the queue, one every KEYGAP seconds
local KEYGAP = tonumber(os.getenv("MB_KEYGAP") or "0.4")
local function kq_push(code)
  local tail = mem:read_u8(syms.kq_tail)
  mem:write_u8(syms.kq + tail, code)
  mem:write_u8(syms.kq_tail, (tail + 1) & 15)
end
local function core_phys(a) return 0x30 * 0x2000 + a - 0x2000 end
local last_polls, poll_at, poll_since, last_inject = -1, 0, 0, -10
local function drive(now, changed)
  if changed then still_since = now end
  local polls = mem:read_u16(0x090A)                 -- the game polls the keyboard: it is waiting for a key (or timing a delay)
  if polls ~= last_polls then
    if now - poll_at > 0.3 then poll_since = now end   -- (polling again after a gap: a load, a long animation step)
    last_polls, poll_at = polls, now
  end
  if #inject > 0 then
    if mem:read_u8(0x090C) ~= 0 then inject_at = now + KEYGAP; return end      -- (keys wait while a disk is asked for)
    if now >= inject_at then
      last_inject = now
      kq_push(table.remove(inject, 1))
      inject_at = now + KEYGAP
      still_since = now
    end
    return
  end
  if mem:read_u8(0x090C) ~= 0 then return end        -- the engine asks for a disk (step 8.10): a person does not type at that prompt
  if si > #script or now - poll_at > 0.3 or m.time:as_double() - last_io < 3.0 then return end   -- (a save or a load in progress)
  if os.getenv("MB_FLOP") and (now - poll_since < 3.0 or now - last_inject < 4.0) then return end   -- (on the disks a load takes minutes and the game empties the keyboard when it has done: a key goes in when the game has waited for one for 3 s)
  if now - still_since < STILL and not script[si][3] then return end   -- (`press`: an animated screen never stays still)
  if script[si][3] and now - last_press < 2.0 then return end
  if seed_due then                                  -- the main menu after the wheel has settled: line the generator up
    seed_due = false
    for i = 0, 3 do ram:write(core_phys(syms.rand_seed) + i, (WHEEL_SEED >> (24 - 8 * i)) & 0xFF) end
    print(string.format("session: %.1f s: random seed set to %08X", now, WHEEL_SEED))
  end
  local c = script[si]
  if c[1] == "wheel" then
    local pick = ram:read(core_phys(syms.wheel_pick))
    if pick < 0x80 then return end                   -- the question has not been chosen yet
    local word = WHEEL_WORDS[(pick & 0x7F) + 1]
    print(string.format("session: %.1f s: wheel question %d, answer %s", now, pick & 0x7F, word))
    for ch in word:gmatch(".") do inject[#inject + 1] = ch:byte() end
    inject[#inject + 1] = 13
    seed_due = true
  else
    print(string.format("session: %.1f s: keys %s", now, table.concat(c[2], " ")))
    if c[3] then last_press = now end
    for _, code in ipairs(c[2]) do inject[#inject + 1] = code end
  end
  si = si + 1
  still_since = now
end

local keys = {}
for t, txt in string.gmatch(os.getenv("MB_KEYS") or "", "(%d+%.?%d*):([^;]*)") do
  keys[#keys + 1] = {t = tonumber(t), s = (txt:gsub("\\n", "\n")), done = false}
end

local function magic()
  return mem:read_u8(0x0900) == 0x50 and mem:read_u8(0x0901) == 0x52
     and mem:read_u8(0x0902) == 0x41 and mem:read_u8(0x0903) == 0x44
end

local t0 = m.time:as_double()
local hb, peeked
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
    log:write(string.format("t=%.0f pc=%04X s=%04X banks=%d\n", now, st["PC"].value, st["S"].value, mem:read_u16(0x0910 + 18)))
    log:flush()
  end
  if os.getenv("MB_PEEK") and not peeked and now >= tonumber((os.getenv("MB_PEEK_T") or "0"):match("[%d.]+")) then
    peek_times = peek_times or {}
    for tt in string.gmatch(os.getenv("MB_PEEK_T") or "0", "[%d.]+") do peek_times[#peek_times + 1] = tonumber(tt) end   -- MB_PEEK_T=t1,t2,..: the ranges are read at each of those emulated seconds
    peek_next = 1
    peeked = true
  end
  if peek_times and peek_next <= #peek_times and now >= peek_times[peek_next] then
    peek_next = peek_next + 1
    for lo, hi in string.gmatch(os.getenv("MB_PEEK"), "(%x+)-(%x+)") do
      local t = {}      -- 5 or more digits: a physical address of the 512 KB, else a logical one
      for a = tonumber(lo, 16), tonumber(hi, 16) do t[#t + 1] = string.format("%02X", #lo > 4 and ram:read(a) or mem:read_u8(a)) end
      print(string.format("peek t=%.1f %s-%s: %s", now, lo, hi, table.concat(t, " ")))
    end
  end
  for _, k in ipairs(keys) do
    if not k.done and now >= k.t then k.done = true; m.natkeyboard:post(k.s) end
  end
  if magic() and mem:read_u16(0x0918) == 0xC0DE then   -- the engine has launched the game (MB_RESULT(4))
    if not lowram then lowram = mem:read_range(0, 0xDFF, 8) end
    local scr = ram:read_block(0, 32000)
    drive(now, scr ~= prev)
    if scr == prev and scr ~= last then
      nsaved = nsaved + 1
      local f = io.open(string.format("%s-s%02d.scr4", out, nsaved), "wb")
      f:write(scr)
      for i = 0, 15 do f:write(string.char(mem:read_u8(0x0950 + i))) end
      f:close()
      log:write(string.format("%d %.2f\n", nsaved, now))
      log:flush()
      last = scr
    end
    prev = scr
    if mem:read_u8(0x0905) ~= 0 then break end
  end
end
if os.getenv("MB_DUMPRAM") then                    -- all of the 512 KB, to look for what the screen shows
  local rf = io.open(out .. ".ram", "wb")
  rf:write(ram:read_block(0, 0x80000))
  rf:close()
end
if magic() then                                     -- the screen the run ends with, if it was never still long enough to be kept
  local scr = ram:read_block(0, 32000)
  if scr ~= last then
    nsaved = nsaved + 1
    local f = io.open(string.format("%s-s%02d.scr4", out, nsaved), "wb")
    f:write(scr)
    for i = 0, 15 do f:write(string.char(mem:read_u8(0x0950 + i))) end
    f:close()
    log:write(string.format("%d %.2f (the end)\n", nsaved, m.time:as_double() - t0))
  end
end
log:close()
dac_save(out)
local f = io.open(out .. ".mbx", "wb")
for i = 0, 0x4F do f:write(string.char(mem:read_u8(0x0900 + i))) end
f:close()
pcall(function() m.screens[":screen"]:snapshot(out .. ".png") end)
local st = m.devices[":maincpu"].state
print(string.format("watch: %d screens, mailbox status %d, pc=%04X s=%04X", nsaved, mem:read_u8(0x0905), st["PC"].value, st["S"].value))
do   -- the paged globals (physical blocks $10..$13) and the native area of the core, for the analysis of data
  local pf = io.open(out .. ".pages", "wb")
  pf:write(ram:read_block(0x10 * 0x2000, 0x8000))
  pf:close()
  local lf = io.open(out .. ".low", "wb")                -- slot 0: the shared page (stack, mailbox, bank stack)
  lf:write(ram:read_block(0x38 * 0x2000, 0x2000))
  lf:close()
  local bf = io.open(out .. ".bheap", "wb")              -- the banked heap: eight pages, the physical blocks $14..$17 and $24..$27 (VMBLK_HEAP, VMBLK_HEAP2); a heap
  bf:write(ram:read_block(0x14 * 0x2000, 0x8000))        -- a banked pointer is a handle: the high word 0, the low word page * $2000 + the offset in the page
  bf:write(ram:read_block(0x24 * 0x2000, 0x8000))
  bf:close()
  local nf = io.open(out .. ".core", "wb")
  nf:write(ram:read_block(0x30 * 0x2000, 0x6000))
  nf:close()
end
if syms.pics then   -- the engine's picture table (task 1: slots 1..3 are the blocks $39..$3B, the engine's code and data from $2000)
  local pf = io.open(out .. ".pictab", "wb")
  pf:write(ram:read_block(0x39 * 0x2000 + syms.pics - 0x2000, 128 * 14))
  pf:write(ram:read_block(0x39 * 0x2000 + syms.pic_live - 0x2000, 128))
  pf:close()
end
do   -- DrawBuf (physical blocks 4 and 5)
  local df = io.open(out .. ".drawbuf", "wb")
  df:write(ram:read_block(4 * 0x2000, 0x4000))
  df:close()
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
  sf:write(mem:read_range(0x0900, 0x1FFF, 8))
  sf:close()
end
do   -- a probe (tools/mkgame.py DEBUG_PATCH): eight words at $0F30, the count at $0F3F
  local t = {}
  for i = 0, 7 do t[#t + 1] = string.format("%04X", mem:read_u16(0x0850 + 2 * i)) end
  print("probe " .. mem:read_u8(0x085F) .. ": " .. table.concat(t, " "))
end
do   -- what the game wrote to its console (Output) before it stopped: rtl_file.c, $0970
  local t = {}
  for a = 0x0970, 0x09BD do
    local c = mem:read_u8(a)
    if c == 0 then break end
    t[#t + 1] = string.char(c)
  end
  if #t > 0 then print("console: " .. table.concat(t)) end
end
do   -- the engine's event log (src/engine/mailbox.h DBG)
  local n = mem:read_u8(0x08E0)
  local t = {}
  for i = 0, 63 do
    local v = mem:read_u16(0x0860 + 2 * ((n + i) % 64))
    if v ~= 0 then t[#t + 1] = string.format("%X:%03X", v >> 12, v & 0xFFF) end
  end
  print("event log (oldest first): " .. table.concat(t, " "))
end
do   -- how deep the stack went: the engine painted $0A00..$1E00 with $AA
  local low = 0x1E00
  for a = 0x0A00, 0x1DFF do if mem:read_u8(a) ~= 0xAA then low = a; break end end
  print(string.format("stack: lowest touched address %04X (painted from 0A00)", low))
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
  print(string.format("FC_TASK=%d dp8B=%02X", mem:read_u8(0x0909), mem:read_u8(0x8B)))
end
do   -- the written sectors, for the checks (tools/statecheck.py): lsn (4 bytes), 256 bytes each
  local sf = io.open(out .. ".saves", "wb")
  for l, d in pairs(sec_over) do sf:write(string.pack(">I4", l), d) end
  sf:close()
end
m:exit()
