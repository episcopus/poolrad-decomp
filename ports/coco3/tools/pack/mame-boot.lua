-- mame-boot.lua: starts the game on MAME's CoCo 3 with the Glenside IDE adapter and no Disk BASIC (`-ext ide`): puts POOL.BIN (the engine, a DECB .BIN next to this
-- file) into memory and jumps to its EXEC address, which is what LOADM"POOL":EXEC does on a machine with a disk controller. Also switches the monitor to RGB.
-- Use: mame coco3 -ramsize 512K -ext ide -hard3 POOLIDE.chd -autoboot_script mame-boot.lua   (from the folder that holds POOL.BIN)
local m = manager.machine
pcall(function() m.ioport.ports[":screen_config"].fields["Monitor Type"].user_value = 1 end)
local dir = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "")
emu.wait(2)                                           -- BASIC's start-up
local f = assert(io.open(dir .. "POOL.BIN", "rb"), "POOL.BIN must be next to mame-boot.lua")
local d = f:read("a")
f:close()
local cpu = m.devices[":maincpu"]
local sp = cpu.spaces["program"]
local pos = 1
while true do
  local t, len, addr = d:byte(pos), (d:byte(pos + 1) << 8) | d:byte(pos + 2), (d:byte(pos + 3) << 8) | d:byte(pos + 4)
  pos = pos + 5
  if t == 0 then
    for i = 0, len - 1 do sp:write_u8(addr + i, d:byte(pos + i)) end
    pos = pos + len
  else
    cpu.state["CC"].value = cpu.state["CC"].value | 0x50
    cpu.state["PC"].value = addr
    break
  end
end
