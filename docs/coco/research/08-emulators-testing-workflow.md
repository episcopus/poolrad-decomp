# 08: Emulators, automated testing and deployment workflow for the CoCo 3 port

Scope: how to build, run, verify (golden tests), profile and deploy the Pool of Radiance CoCo 3 port. Covers XRoar, MAME (coco3 driver), VCC/OVCC and trs80gp, then real hardware (CoCo SDC, DriveWire 4) and image tooling (ToolShed decb/os9, LWTOOLS map and listing output). Versions checked on 2026-10-17.

## Key takeaways for the Pool of Radiance port

1. **MAME is the automation emulator; XRoar is the interactive one.** MAME has a Lua engine whose autoboot script runs as a coroutine (so `emu.wait`, `emu.wait_next_frame` work at top level), can read memory, grab the emulated screen as raw pixels, post keystrokes, set breakpoints, save states and exit, all headless with `-video none -sound none -nothrottle` (src: https://raw.githubusercontent.com/mamedev/mame/master/src/frontend/mame/luaengine.h, https://raw.githubusercontent.com/mamedev/mame/master/docs/source/luascript/ref-common.rst). The coco-dev image already ships a headless CoCo 3-only MAME 0.287 (src: https://raw.githubusercontent.com/jamieleecho/coco-dev/master/README.md).
2. **XRoar 1.12.1 (2026-07-27)** has no scripting language, but it has useful batch hooks: `-trap pc=ADDR` with `-trap-snap file` (a `.ram` name gives a raw RAM dump), `-trap-timeout n`, `-timeout n`, `-no-ratelimit`, `-trace`, `-type`, `-run`, and a GDB remote stub on port 65520 (src: https://www.6809.org.uk/xroar/, https://www.6809.org.uk/xroar/doc/xroar.shtml, https://mankier.com/1/xroar).
3. **Do not rely on emulator keyboard injection for golden tests.** Build a replay mode into the port's own input layer (the keyboard poll returns the next recorded key from a buffer loaded from disk) and a checkpoint hook that writes a counter byte to a fixed RAM address. Then the same test runs identically on MAME, XRoar and real hardware, and is as deterministic as the PC and C harness. Emulator-side injection (`-type`, MAME natural keyboard) only works while BASIC owns the keyboard, or at the mercy of key timing.
4. **Compare palette indices, not RGB.** The GIME 320x200x16 mode stores 2 pixels per byte, the same packing as the DAX source pictures; dump the 32,000-byte screen from RAM at each checkpoint and diff it against the C build's 4bpp framebuffer. Use `screen:pixels()` (MAME) or PNG screenshots only as a human-visible secondary artifact, and force the RGB monitor setting so colours are stable.
5. **MAME's GDB stub does not work for the CoCo 3:** it looks up the main CPU's short name and only knows `m6809`; the coco3 driver uses `mc6809e` (and coco3h `hd6309e`), so it would fail with "cpuname not found" (src: https://raw.githubusercontent.com/mamedev/mame/master/src/osd/modules/debugger/debuggdbstub.cpp, https://raw.githubusercontent.com/mamedev/mame/master/src/mame/trs/coco3.cpp). Use XRoar's `-gdb` for source-level remote debugging, and MAME's built-in debugger (`-debug -debugger none -debugscript`) for headless scripted breakpoints.
6. **Profiling:** neither emulator has a per-routine profiler. MAME's debugger exposes `totalcycles` and `lastinstructioncycles`, so `trace file,maincpu,noloop,{tracelog "%d ",totalcycles}` plus an LWTOOLS map file gives an exact flat cycle profile after post-processing (src: https://raw.githubusercontent.com/mamedev/mame/master/src/emu/debug/debugcpu.cpp, https://raw.githubusercontent.com/mamedev/mame/master/docs/source/debugger/execution.rst). Log the current overlay id with each line, because overlays share logical addresses.
7. **Defaults that differ:** MAME coco3 defaults to 512K RAM (options 128K, 2M, 8M) and an FDC cartridge; XRoar's default RAM for coco3 is not stated, so always pass `-ram 512` (src: coco3.cpp above; https://www.6809.org.uk/xroar/doc/xroar.shtml).
8. **Deployment:** ToolShed `decb dskini` and `decb copy -2 -b` build RS-DOS disks; a 35-track disk holds only 68 granules x 2,304 bytes = 156,672 bytes, so the 1.28 MB of DAX data needs either about 9 floppies, larger SDC-compatible DSK geometries, an HDB-DOS multi-drive image, or an OS-9 RBF hard disk image. The CoCo SDC needs FAT16/32 and 8.3 names (src: https://raw.githubusercontent.com/nitros9project/toolshed/master/doc/ToolShed.md; CoCo SDC User Guide v4 p. 5, https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/CoCo%20SDC%20User%20Guide%20v4%20(Darren%20Atkinson).pdf).

## 1. XRoar

### 1.1 Version and machine support

- Current release: **XRoar 1.12.1, 2026-07-27**; 1.12 reworked breakpoints/watchpoints, sends a target description to GDB, added GDB NoAckMode, `-gdb-pseudo-regs`, SDL3 support and `-vo-monochrome` (src: https://www.6809.org.uk/xroar/).
- Machines: Dragon 32/64, Tandy CoCo 1, 2, 3, MC-10 and clones. Built-in CoCo 3 profiles: `coco3` (NTSC) and `coco3p` (PAL); ROM files `coco3.rom` and `coco3p.rom` (src: https://mankier.com/1/xroar).
- RAM: `-ram kbytes` picks the nearest valid size. The manual says the CoCo 3 supports "up to 512K directly", and 1024K or 2048K enable an optional DAT board (src: https://www.6809.org.uk/xroar/doc/xroar.shtml). The default is not stated in the parts read, so pass `-ram 512` explicitly.
- `-ram-init` sets the initial RAM state: `clear`, `set`, `pattern` or `random`; use `clear` (or `pattern`) for deterministic tests (src: same).
- Video: `-tv-type pal|ntsc|pal-m`; `-tv-input cmp|cmp-br|cmp-rb|rgb` (rgb is CoCo 3 only). The NTSC CoCo 3 produces different colours on composite and RGB; the PAL CoCo 3 always uses RGB. CTRL+A cycles cross-colour modes, with a fourth RGB mode on the CoCo 3 (src: same).

### 1.2 Command line options useful for automation

All quoted from the 1.12 manual (src: https://www.6809.org.uk/xroar/doc/xroar.shtml) and the 1.12.1 man page (src: https://mankier.com/1/xroar).

| Option | Meaning |
|---|---|
| `-m coco3` / `-machine coco3` | Select machine profile (`-m help` lists them). |
| `-ram 512` | RAM in KB. |
| `-ram-init clear` | Deterministic initial RAM. |
| `-load file` | Attach a file by extension. |
| `-run file` | As `-load`, then try to autorun. For `.bin` (RS-DOS or DragonDOS binary) XRoar reads the header, loads it into RAM and jumps to the EXEC address; no disk is needed. |
| `-load-fd0 file` .. `-load-fd3 file` | Disk images for drives 0 to 3 (`.dsk`, `.jvc`, `.vdk`, `.os9`, `.dmk`). |
| `-load-hd0 file`, `-load-hd1 file` | Hard disk images (`.ide` with header, `.img` raw 512-byte sectors, `.vhd` 256-byte sectors with no header). NX32 and MOOH cartridges use an SD image given with `-load-hd0`. |
| `-load-text file` | Type a file into BASIC on startup. |
| `-type string` | Intercept ROM calls to type a string into BASIC on startup. Escapes: `\r` ENTER, `\f` CLEAR, `\b` LEFT, `\t` RIGHT, `\n` DOWN, `\nnn` octal; `\e` may map to BREAK. |
| `-timeout s` | Run for s emulated seconds, then quit. |
| `-no-ratelimit` | Run the CPU as fast as possible. (F12 runs at maximum speed while held; SHIFT+F12 toggles.) |
| `-trace` | Start with trace mode on (CTRL+V toggles). |
| `-trap cond` | Trap on `immediate`, `pc=addr`, `read=a-b`, `write=a-b`, `access=a-b` or `tape-motor-off`. A trap fires once unless `-trap-range 1-` is given. |
| `-trap-range m[-n]` | Act only on the mth to nth trigger. |
| `-trap-snap file` | Write a snapshot when the trap fires; a `.ram` extension writes a raw RAM dump (the manual says this is "particularly useful here for analysis"). |
| `-trap-timeout n` | Quit n seconds after the trap fires. |
| `-trap-trace`, `-trap-trace-n n`, `-trap-no-trace` | Start trace at the trap (optionally for n instructions), or stop it. |
| `-snap-motoroff file` | Write a snapshot each time the cassette motor stops. |
| `-gdb`, `-gdb-ip addr`, `-gdb-port port` | Enable the GDB target; defaults 127.0.0.1 and 65520. |
| `-gdb-pseudo-regs` | Report SAM, PIA and GIME state as extra GDB registers. |
| `-debug-gdb flags` | 0x1 connections, 0x2 packet data, 0x4 checksums, 0x8 general queries; -1 enables all. |
| `-becker`, `-becker-ip`, `-becker-port` | Prefer a Becker-enabled DOS cartridge; DriveWire server defaults 127.0.0.1:65504. |
| `-cart name`, `-cart-type`, `-cart-rom`, `-cart-becker`, `-cart-autorun`, `-cart-opt` | Cartridges: types include `gmc`, `orch90`, `ide`, `nx32`, `mooh`, `mpi`. |
| `-mpi-slot n`, `-mpi-load-cart [slot]=name` | Multi-Pak slot selection and loading; only the last DOS cartridge in slot order is properly connected. |
| `-ao-gain db` | Default -3.0 dB; the manual suggests -9.0 for headroom with the Orchestra 90-CC. |
| `-ui module`, `-vo-*`, `-ao module` | UI, video and audio modules (`help` lists those compiled in). |
| `-c file`, `-no-c` | Use another config file (must be first) or none. |
| `-v n`, `-q` | Verbosity. |

Not found in the manual or man page: a Lua or other scripting option, a command-line screenshot option, and an explicit "null" UI. Screenshots are interactive only: CTRL+SHIFT+S saves a PNG (if built with libpng). For headless use, `-ui null` and `-ao null` may exist as compiled-in modules [unverified]; otherwise run under `xvfb-run` with `-ao null` or `SDL_AUDIODRIVER=dummy` [unverified].

### 1.3 Snapshots, traces, GDB

- Snapshots: CTRL+S saves, CTRL+L loads a `.sna`. XRoar 1.x saves most machine state; ROM and disk images are referenced by name and must stay in place; Becker/DriveWire connections and GDB listen settings are not saved (src: https://www.6809.org.uk/xroar/doc/xroar.shtml). The `.sna` format is XRoar specific (format not documented in the parts read). For tests use `.ram` raw dumps; the byte order of a CoCo 3 512K dump (physical order $00000 to $7FFFF is expected) is [unverified]: confirm by dumping a known pattern once.
- Trace: the manual does not describe the trace line format [unverified]; capture a sample before writing a parser.
- GDB: XRoar is a GDB remote target and sends a target description (CPU architecture and registers). A stock host GDB has no 6809 architecture, so either use a 6809-enabled GDB build or write a small Python client for the GDB remote serial protocol (`m addr,len` read, `M` write, `Z0` breakpoint, `c` continue, `g` registers) [inference]. Whether `m` reads logical (CPU-visible) or physical memory is [unverified]; logical is the usual stub behaviour.
- Breakpoints over GDB plus memory writes are a second way to inject input deterministically: break at the port's `kbd_poll`, write the next key into the return register or a mailbox, continue.

## 2. MAME (coco3 driver)

### 2.1 Version and driver facts

- Current MAME documentation is 0.289 (src: https://docs.mamedev.org/commandline/commandline-all.html). Ubuntu 24.04 packages 0.264 (apt-cache, checked 2026-10-17). coco-dev builds MAME 0.287 with `SUBTARGET=coco SOURCES=src/mame/trs/coco3.cpp`, installed as `mame`, headless with `SDL_VIDEODRIVER=dummy` and `SDL_AUDIODRIVER=dummy`, plugins under `/usr/local/share/mame/plugins`; ROMs are not shipped and must be given with `-rompath` (expects `coco3.zip`) (src: https://raw.githubusercontent.com/jamieleecho/coco-dev/master/Dockerfile, https://raw.githubusercontent.com/jamieleecho/coco-dev/master/README.md).
- Systems: `coco3` (NTSC), `coco3p` (PAL), `coco3h` (NTSC with HD6309E, unofficial), `msm3`. CPU MC6809E clocked from the 28.636363 MHz crystal / 32 (0.895 MHz base). RAM default **512K**, extra options 128K, 2M, 8M (`-ramsize 512K`). Screen raw timing 912 x 262 at 14.318 MHz pixel clock, visible 640 x 240. Default cartridge in slot `ext` is `fdc` (src: https://raw.githubusercontent.com/mamedev/mame/master/src/mame/trs/coco3.cpp, https://raw.githubusercontent.com/mamedev/mame/master/src/mame/trs/coco.cpp).
- Config switch "Monitor Type": Composite (0) or RGB (1), port `screen_config` (src: coco3.cpp). Set it to RGB for stable colours.
- Cartridges available in slot `ext` (and in Multi-Pak slots 1 to 3): `banked_16k`, `ccpsg`, `dcmodem`, `gmc`, `ide`, `max`, `midi`, `orch90`, `pak`, `ram`, `rs232`, `ssc`, `ssfm`, `stecomp`, `sym12`, `wpk`, `wpk2`, `wpk2p`, `wpkrs`, `xsid`; FDCs `fdc`, `cd6809_fdc`, `cp450_fdc`, `scii`; and `multi` (Multi-Pak, slot 4 defaults to `fdc`). Example: `-ext multi -ext:multi:slot1 gmc` (src: https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/cococart.cpp, https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_multi.cpp).
- GMC: banked ROM plus SN76489AN written at $FF41 (src: https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_gmc.cpp). Orchestra-90: 8-bit DACs at $FF7A (left) and $FF7B (right) (src: https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_orch90.cpp). Multi-Pak: $FF7F, bits 0 to 1 route SCS, bits 4 to 5 route CTS/CART (src: coco_multi.cpp).
- Becker port: a virtual Becker port device is built in, enabled by a `beckerport` config setting, mapped at $FF41/$FF42, TCP port selectable 65500 to 65509 (default 65504) (src: coco.cpp lines 577 to 594, https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_dwsock.cpp). Note the GMC's PSG also decodes $FF41, so do not enable the Becker port and the GMC together [inference].

### 2.2 Command line options for headless tests

Quoted from the MAME docs source (src: https://raw.githubusercontent.com/mamedev/mame/master/docs/source/commandline/commandline-all.rst):

| Option | Meaning |
|---|---|
| `-rompath dir` | Where `coco3.zip` lives. |
| `-ramsize 512K` | RAM size. |
| `-flop1 file.dsk` .. | Floppy images on the FDC cartridge (coco-dev README example uses `-flop1`/`-flop2`). |
| `-hard1 file.vhd` | Hard disk image (coco3 has two COCO_VHD devices). |
| `-video none` | "Using none displays no windows and does no drawing." |
| `-sound none` | Disables sound output (sound hardware still emulated). |
| `-nothrottle` | Run unthrottled. |
| `-seconds_to_run n` / `-str n` | Stop after n emulated seconds; on exit it writes a screenshot to the snapshot directory named by `-snapname`. |
| `-autoboot_command "text"` | Type a command after boot (natural keyboard); `\n` is ENTER, `"""` a quote. Implemented as `emu.keypost(...)`. |
| `-autoboot_delay n` | Delay in seconds (emulated time) before the autoboot command or script runs. |
| `-autoboot_script file.lua` / `-script` | Lua script run after boot. |
| `-snapshot_directory dir`, `-snapname pattern`, `-snapsize`, `-snapview` | Screenshot location and naming. |
| `-record file.inp`, `-playback file.inp`, `-exit_after_playback` | Record and replay all inputs. |
| `-state slot` | Load a save state on start. |
| `-debug`, `-debugger none|qt|gdbstub|imgui`, `-debugscript file` | Debugger, module and startup command file. |
| `-log`, `-oslog` | error.log output. |
| `-wavwrite`, `-aviwrite`, `-mngwrite` | Audio/video capture. |

The `none` debugger module simply resumes execution whenever the debugger would stop (src: https://raw.githubusercontent.com/mamedev/mame/master/src/osd/modules/debugger/none.cpp), so `-debug -debugger none -debugscript cmds.txt` gives scripted breakpoints, traces and memory saves in a headless run. The coco-dev build sets `USE_QTDEBUG=0`, so no GUI debugger there.

### 2.3 Lua API pieces needed for golden tests

From the Lua reference (src: https://raw.githubusercontent.com/mamedev/mame/master/docs/source/luascript/ref-common.rst, ref-core.rst, ref-input.rst, ref-mem.rst, ref-devices.rst, ref-debugger.rst under https://raw.githubusercontent.com/mamedev/mame/master/docs/source/luascript/):

- Coroutines: `emu.wait(seconds)`, `emu.wait_next_frame()`, `emu.wait_next_update()`. The autoboot script is invoked through `lua_engine::invoke`, which creates a coroutine (src: https://raw.githubusercontent.com/mamedev/mame/master/src/frontend/mame/luaengine.h, https://raw.githubusercontent.com/mamedev/mame/master/src/frontend/mame/mame.cpp), so these can be called directly in the script body.
- Notifiers: `emu.add_machine_frame_notifier(cb)`, `emu.add_machine_stop_notifier(cb)`, reset/pause/save/load notifiers.
- Machine: `manager.machine:exit()`, `machine:save(file)`, `machine:load(file)`, `machine.time`.
- Memory: `manager.machine.devices[":maincpu"].spaces["program"]` with `read_u8`, `read_u16`, `write_u8`, `read_range(start, end, 8)` (binary string), `install_read_tap`/`install_write_tap` (taps are not coroutines). The program space is the CPU's logical (MMU-mapped) view. Avoid reading $FF00 to $FFFF from Lua because I/O reads can have side effects (for example clearing PIA flags) [inference].
- Screen: `manager.machine.screens[":screen"]` with `snapshot([file])` (PNG), `pixel(x,y)`, `pixels()` (packed 32-bit RGB string plus width and height), `frame_number`.
- Input: `manager.machine.natkeyboard:post(text)` / `post_coded("{ENTER}")`, `natkeyboard.empty`, `is_posting`; or per-key `manager.machine.ioport.ports[":row0"].fields[name]:set_value(1)` then `clear_value()`. The coco3 keyboard ports are `row0` to `row6` (src: coco3.cpp); exact field names should be listed once with `natkeyboard:dump()` [unverified].
- Debugger from Lua (only with `-debug`): `manager.machine.debugger:command("...")`, `cpu.debug:bpset(addr, cond, action)`, `cpu.debug:wpset(space, "w", addr, len, cond, action)`.
- Physical RAM: `manager.machine.memory.shares` and `.regions` are enumerable; whether the 512K RAM device appears there is [unverified]. Print `for k,_ in pairs(manager.machine.memory.shares) do print(k) end` once; if absent, read video RAM through the logical map at a checkpoint (see section 5).

### 2.4 Debugger facts relevant to profiling and checkpoints

- `trace {file|off}[,cpu[,noloop|logerror[,action]]]`, `traceover`, `traceflush`; actions like `{tracelog "A=%02X ",a}` add fields to each line (src: https://raw.githubusercontent.com/mamedev/mame/master/docs/source/debugger/execution.rst).
- Symbols `cycles`, `totalcycles`, `lastinstructioncycles` exist for every CPU (src: https://raw.githubusercontent.com/mamedev/mame/master/src/emu/debug/debugcpu.cpp).
- General commands include `history`, `trackpc`, `trackmem`, `pcatmem`, `statesave`, `stateload`, `snap`, `source`, `time`; memory commands `save`, `saver` (memory region), `dump`, `dasm`, `map`, `memdump` (src: https://raw.githubusercontent.com/mamedev/mame/master/docs/source/debugger/general.rst, https://raw.githubusercontent.com/mamedev/mame/master/docs/source/debugger/memory.rst).
- No built-in per-function profiler is documented; build one from trace output (section 6).

## 3. VCC, OVCC, trs80gp

- **VCC** (Windows): latest stable 2.1.9.2 (tag `vcc-2.1.9.2`, "03 Jul", year not shown on the page) with 2.1.9.3 pre-releases. Recent additions: SDC simulator (SDC.dll) and Becker interface moved into FD502.dll (2.1.9.2); Disassembler window with breakpoints and stepping (2.1.9.0); CPU tracking hotkey and Execution Trace export to file (2.1.9.1); Processor window "Set PC" (2.1.8.2); command line auto-paste option (2.1.8.3); 6309 TFM and 6809 TFR/EXG fixes (src: https://github.com/VCCE/VCC/releases). No headless or scripting mode found. Use it as a third opinion on GIME behaviour and for Windows-based contributors.
- **OVCC**: cross-platform port of VCC emulating a stock CoCo 3, requires the agar library, source at https://github.com/WallyZambotti/OVCC (src: https://www.slackbuilds.org/repository/15.0/games/ovcc/). Version not stated. Not needed for the workflow.
- **trs80gp** 2.5.8: lists a "Color Computer" (`-mc`) with Color/Extended/Disk BASIC ROMs and a 6809 debugger, plus generic `-turbo`, `-i` keystroke injection, `-is` screenshots; the page does not mention the CoCo 3 (src: https://48k.ca/trs80gp.html). Not useful for this port.

## 4. Determinism

What makes a CoCo emulator run reproducible:

1. Same ROM files, disk images, machine profile, RAM size and **RAM initial state** (`-ram-init clear` in XRoar; MAME's RAM fill policy for coco3 is [unverified], so the test build should clear the RAM it uses at startup).
2. Inputs timed in **emulated time**, not host time. MAME `-autoboot_delay`, natural keyboard posting and `emu.wait` are all emulated-time based; `-record/-playback` replays port states per frame. XRoar `-type` intercepts ROM calls, so it is exact but only works for BASIC.
3. No host clock leaks. The original game calls Delay and reads the time of day (brief, "Timing"); in replay mode replace the time of day with a frame counter so the RNG seed and any timed waits are identical. DriveWire time services would also leak host time.
4. Throttle on or off does not change emulated results (`-nothrottle`, `-no-ratelimit`) [inference: both emulators schedule purely by emulated cycles].
5. Both emulators are cycle-counted 6809 cores; exact GIME and disk timing fidelity differs between them, so a golden checkpoint must not depend on sub-frame timing (for example, where a disk read completes relative to VSYNC). Driving checkpoints from the game's own logic (checkpoint hook), not from emulated time, removes this issue.

## 5. Golden-test design for the port

The PC and C builds are verified by replaying recorded input sessions and comparing screens and state at checkpoints. Recommended CoCo 3 equivalent:

### 5.1 In-game test hooks (compiled only into the test build)

- `REPLAY` input source: `kbd_poll()` returns the next keycode from a replay buffer (loaded from a `REPLAY.DAT` file on the data disk, or linked in), using the same logical key set as the PC harness (arrows, Home/End, Enter, Esc, letters). When the buffer ends, write checkpoint $FF and spin.
- `cp_hook(n)`: called at the same logical points as in the C harness. It stores `n` in a fixed RAM mailbox (for example logical $0100, in the always-mapped DP/system page), records which physical blocks hold the visible screen and the game state structures in a small table next to it, and optionally waits until the harness writes an ACK byte (MAME) or simply continues (XRoar trap).
- Clock: replace time of day with a frame counter (60 Hz VSYNC IRQ).

### 5.2 Harness on MAME (primary, multi-checkpoint in one run)

```
mame coco3 -rompath /roms -ramsize 512K -flop1 build/test.dsk \
  -video none -sound none -nothrottle -skip_gameinfo \
  -autoboot_delay 2 -autoboot_script tests/golden.lua -seconds_to_run 3600
```

`-skip_gameinfo` is a standard MAME UI option [unverified here]. Do not combine `-autoboot_command` with `-autoboot_script`: MAME then runs only the script (the command branch is an `else`, src: mame.cpp above), so the script posts the LOADM itself:

```lua
-- tests/golden.lua (sketch)
local m    = manager.machine
local cpu  = m.devices[":maincpu"]
local mem  = cpu.spaces["program"]
local scr  = m.screens[":screen"]
m.ioport.ports[":screen_config"].fields["Monitor Type"]:set_value(1) -- RGB
m.natkeyboard:post_coded('LOADM"PRADTEST":EXEC{ENTER}')
local MAILBOX, last = 0x0100, 0
while true do
  emu.wait_next_frame()
  local cp = mem:read_u8(MAILBOX)
  if cp ~= last then
    last = cp
    -- screen: 32,000 bytes of 4bpp packed pixels, mapped by cp_hook at $8000
    local vram = mem:read_range(0x8000, 0x8000 + 31999, 8)
    local f = io.open(string.format("out/cp%03d.scr", cp), "wb"); f:write(vram); f:close()
    local st = mem:read_range(0x2000, 0x3FFF, 8)  -- game state window
    f = io.open(string.format("out/cp%03d.st", cp), "wb"); f:write(st); f:close()
    scr:snapshot(string.format("cp%03d.png", cp))  -- for humans only
    mem:write_u8(MAILBOX + 1, cp)                  -- ACK
    if cp == 0xFF then m:exit() end
  end
end
```

The field name "Monitor Type" and port tag `:screen_config` come from coco3.cpp; the mailbox, window addresses and ACK protocol are the port's own design. A Python script then compares `out/cpNNN.scr` with the C build's 4bpp framebuffer dump at the same checkpoint (convert EGA planes to packed nibbles on the PC side once) and compares selected state structures field by field.

### 5.3 Harness on XRoar (secondary, one checkpoint per run)

Because a trap writes to a fixed file name, run one process per checkpoint (runs are deterministic, so this is valid):

```
xroar -m coco3 -ram 512 -ram-init clear -tv-input rgb -no-ratelimit \
  -load-fd0 build/test.dsk -type 'LOADM"PRADTEST":EXEC\r' \
  -trap write=0x0100-0x0100 -trap-range 7-7 -trap-snap out/cp007.ram \
  -trap-timeout 0 -timeout 3600
```

This snapshots the whole RAM on the 7th write to the mailbox. Extract the screen from the `.ram` dump at the physical block address recorded by `cp_hook` (layout of the dump to be confirmed, section 1.3). `-trap pc=<cp_hook address from the map file>` works the same way.

### 5.4 Real hardware

The same `test.dsk` (with `REPLAY.DAT`) runs on a real CoCo 3 via CoCo SDC; at each checkpoint the test build can write the screen and state to a file on a scratch disk (`CP007.SCR`) for later comparison. This validates real timing and the real FDC path without any emulator.

## 6. Profiling

1. **MAME trace with cycle stamps (exact, offline):** in a debugscript:
   ```
   trace out/prof.tr,maincpu,noloop,{tracelog "%d %02X ",totalcycles,b@0x0102}
   go
   ```
   `b@0x0102` reads a byte the overlay manager updates with the current overlay id (the expression syntax `b@addr` is MAME's memory accessor [unverified exact spelling; check `help expressions`]). Post-process: cycles of each instruction = next totalcycles minus this one; attribute to the symbol containing the PC, using (overlay id, PC) to pick the right map file. Trace files are large; enable trace only around the measured scene with breakpoint actions (`bpset addr,,{trace ...;g}`).
2. **Breakpoint pairs (cheap):** `bpset entry,,{printf "%d E\n",totalcycles;g}` and the same on the return address gives per-call cycle counts for a few hot routines (blit, RLE decode, ECL VM dispatch).
3. **On-target:** change the border colour ($FF9A) at routine entry and exit to see time per frame on screen (works on real hardware and in every emulator), or count VSYNC ticks around a workload.
4. **XRoar:** `-trace` / `-trap-trace-n n` give instruction traces but no cycle profile [unverified: whether trace lines include cycle counts]. VCC's execution trace export is another source.

## 7. Build products, listings and symbols (LWTOOLS)

From the LWASM manual (src: https://www.lwtools.ca/manual/c62.html):

- `--format=decb` (`-b`) for RS-DOS LOADM binaries; other formats `obj`, `os9`, `raw`, `hex`, `srec`, `ihex`.
- `--list[=file]` listing; `--symbols` / `--symbols-nolocals` add the symbol table to the listing; `--symbol-dump[=file]` writes global symbols as assembler source (EQUs).
- `--map=FILE`: "generates a map file which can be used by debuggers and monitors to provide symbol information".
- `--6809` (`-9`) rejects 6309 instructions; `--6309` (`-3`) is the default, so pass `--6809` for the stock target.
- `--pragma=...` and `-I path`.
- Cycle counts in listings: lwasm has listing pragmas for instruction cycle counts and running totals [unverified: names and availability; the pragma section of the manual could not be fetched]. Check `lwasm --help` in the coco-dev image.

Symbol loading: MAME's debugger has no map importer; convert the map to a debugscript of comments or use `symlist`-style Lua `emu.symbol_table` entries [inference]. For XRoar over GDB, a 6809 GDB needs an ELF with symbols, which LWTOOLS does not produce [inference], so a custom RSP client that reads the LWTOOLS map is simpler.

## 8. Deployment

### 8.1 Disk images with ToolShed (2.6.1 in coco-dev)

From the ToolShed manual (src: https://raw.githubusercontent.com/nitros9project/toolshed/master/doc/ToolShed.md):

```
decb dskini build/prad1.dsk            # 35 tracks (default); -4 = 40, -8 = 80 tracks; -h<n> = HDB-DOS drives
decb copy -2 -b -r build/PRAD.BIN build/prad1.dsk,PRAD.BIN   # type 2 = machine language, binary, overwrite
decb copy -1 -b -r data/GEO1.DAX build/prad1.dsk,GEO1.DAX     # type 1 = data
decb dir build/prad1.dsk,
decb free build/prad1.dsk,
os9 format -l<sectors> -e build/prad.vhd    # RBF hard disk image (sector count), full size
os9 copy file build/prad.vhd,PATH          # trailing comma means "on the image"
```

Capacity: 68 granules of 9 x 256 bytes = 156,672 bytes per 35-track single-sided disk (Disk BASIC Unravelled p. 5, https://colorcomputerarchive.com/repo/Documents/Books/Unravelled%20Series/disk-basic-unravelled.pdf). The 113 DAX archives (1,284,555 bytes) need about 9 such disks. Options: (a) larger DSK geometries that the CoCo SDC accepts (geometry table, SDC guide p. 20); (b) an HDB-DOS image with many virtual drives (`decb dskini -h<n>`) on SDC or DriveWire; (c) an OS-9/RBF hard disk image with a custom loader. Decide in the storage design (research file 03).

### 8.2 File naming

RS-DOS directory entries hold 8 name bytes and 3 extension bytes (Disk BASIC Unravelled p. 11), and the CoCo SDC only accepts 8.3 names on its FAT card, with 8.3 path components (SDC guide pp. 5, 25). The original DAX names (for example `GEO1.DAX`, `WALLDEF1.DAX`) already fit 8.3 [inference from the PC file set]; keep names upper case.

### 8.3 CoCo SDC

`DRIVE 0,"PRAD/PRAD1.DSK"` mounts an image; `DRIVE n,"file",k` selects a disk inside an HDB-DOS image; AUTOEXEC.BAS on drive 0 runs at power on unless SHIFT is held; `RUN @n` boots a flash bank (SDC guide pp. 9 to 15). Formats: DSK, JVC, VDK, SDF (pp. 19 to 21). Programs can use the low-level command interface (write $43 to $FF40, commands at $FF48 to $FF4B, p. 34) for fast logical sector reads (p. 31). VCC 2.1.9.2 includes an SDC simulator, useful for testing SDC-specific code paths without hardware (src: https://github.com/VCCE/VCC/releases).

### 8.4 DriveWire 4

DriveWire 4 is a Java server (Java 1.5 or later) that serves disk images to a CoCo over a serial cable; the CoCoPedia guide lists 4.3.3o/4.3.3p as the stable release as of 2013 and boots via HDB-DOS (`DIR` on a mounted image) or NitrOS-9 (`DOS`) (src: https://www.cocopedia.com/wiki/DW4_Installation_Guide). Emulators use a Becker port instead of serial: XRoar `-becker` (127.0.0.1:65504), MAME's built-in Becker port on $FF41/$FF42, VCC's FD502.dll. Becker-enabled HDB-DOS or NitrOS-9 builds are required for emulators (same source). Useful for fast edit-and-run on real hardware: rebuild, the server picks up the new image, reset the CoCo.

## 9. Recommended workflow

1. **Build** (inside coco-dev): `make coco3` produces `build/PRAD.BIN` (CMOC + lwlink, `--format=decb`), per-overlay binaries, `build/*.map` and `build/*.lst` (lwasm `--list --symbols --map`), and `build/prad*.dsk` via `decb dskini` / `decb copy`. A `make coco3-test` variant adds `REPLAY`, `cp_hook` and the frame-counter clock.
2. **Run interactively** (XRoar):
   ```
   xroar -m coco3 -ram 512 -tv-input rgb -load-fd0 build/prad1.dsk -load-fd1 build/prad2.dsk -type 'LOADM"PRAD":EXEC\r'
   ```
   Add `-gdb` for remote debugging and `-trace` when chasing a crash.
3. **Automated golden test** (MAME, headless): section 5.2 command with `tests/golden.lua`, then `python3 tools/compare_cp.py out/ golden/` against the C build's checkpoint dumps. Run the same session on XRoar for a subset of checkpoints (section 5.3) to catch emulator-specific behaviour.
4. **Profile** (MAME): `-debug -debugger none -debugscript tests/prof.cmd` with the trace command of section 6, post-processed with the map files into a per-routine cycle table; spot-check on hardware with the border-colour method.
5. **Deploy**: copy the `.dsk` images to the CoCo SDC card (8.3 names, FAT32), `DRIVE 0,"PRAD1.DSK"`, `LOADM"PRAD":EXEC`; or serve them with DriveWire 4 for quick iteration.

## Implications and recommendations for the port

- Put the replay input source and checkpoint hook in the port's platform layer from day one; they are what makes cross-emulator and hardware verification possible.
- Keep the CoCo 3 screen in the same 4bpp packed format as DAX pictures and dump it raw at checkpoints; compare at palette-index level, and compare palettes separately.
- Standardise the test machine: MAME `coco3`, 512K, FDC in `ext`, RGB monitor, ROM `coco3.zip` from the coco-dev `-rompath`; XRoar `-m coco3 -ram 512 -ram-init clear -tv-input rgb`.
- Use MAME's debugger cycle counters for profiling; do not plan on MAME GDB for this machine.
- If the GMC is chosen for sound, test it in both emulators (`-cart gmc` in XRoar, `-ext gmc` or a Multi-Pak slot in MAME), and keep the Becker port off in that configuration.
- Plan the data layout around 8.3 names and the 156,672-byte RS-DOS disk capacity, or commit early to an SDC/HDB-DOS or RBF hard disk image.

## Open questions

- Does XRoar 1.12 have a `null` UI/video module for fully headless runs, or is `xvfb-run` required?
- Byte layout of XRoar's `.ram` dump for a 512K CoCo 3 (physical order assumed).
- Does XRoar's GDB stub read logical or physical memory, and which GDB build (if any) understands its 6809 target description?
- Is MAME's 512K CoCo 3 RAM reachable through `manager.machine.memory.shares` (physical dump without MMU help)?
- What MAME fills CoCo 3 RAM with at power on, and is it identical across runs and versions?
- Exact lwasm pragma names for cycle counts in listings, and whether CMOC can pass `--map` through to lwlink.
- XRoar trace line format (needed if XRoar traces are to feed the profiler).
- Is MAME's or XRoar's FDC timing close enough that DSKCON-based loading produces identical frame counts? (Matters only if a checkpoint is time based.)

## Sources

- https://www.6809.org.uk/xroar/ : XRoar home, current version 1.12.1 and release notes.
- https://www.6809.org.uk/xroar/doc/xroar.shtml : XRoar 1.12 manual (options, traps, GDB, snapshots, cartridges, keyboard shortcuts).
- https://mankier.com/1/xroar : XRoar 1.12.1 man page (`-no-ratelimit`, `-timeout`, F12, ROM names).
- https://docs.mamedev.org/commandline/commandline-all.html : MAME 0.289 command line docs.
- https://raw.githubusercontent.com/mamedev/mame/master/docs/source/commandline/commandline-all.rst : same docs as source (autoboot, debugger, seconds_to_run text).
- https://raw.githubusercontent.com/mamedev/mame/master/docs/source/luascript/ref-common.rst : emu.wait, notifiers.
- https://raw.githubusercontent.com/mamedev/mame/master/docs/source/luascript/ref-core.rst : machine exit/save/load, video snapshot.
- https://raw.githubusercontent.com/mamedev/mame/master/docs/source/luascript/ref-input.rst : natkeyboard, ioport field set_value.
- https://raw.githubusercontent.com/mamedev/mame/master/docs/source/luascript/ref-mem.rst : address spaces, read_range, taps, shares.
- https://raw.githubusercontent.com/mamedev/mame/master/docs/source/luascript/ref-devices.rst : screen snapshot and pixels.
- https://raw.githubusercontent.com/mamedev/mame/master/docs/source/luascript/ref-debugger.rst : Lua debugger bpset/wpset/command.
- https://raw.githubusercontent.com/mamedev/mame/master/docs/source/debugger/execution.rst : trace commands.
- https://raw.githubusercontent.com/mamedev/mame/master/docs/source/debugger/general.rst : general debugger commands.
- https://raw.githubusercontent.com/mamedev/mame/master/docs/source/debugger/memory.rst : save/dump/map commands.
- https://raw.githubusercontent.com/mamedev/mame/master/src/mame/trs/coco3.cpp : coco3 machine config (RAM, CPU, screen, cartridge default, monitor type, systems).
- https://raw.githubusercontent.com/mamedev/mame/master/src/mame/trs/coco.cpp : cartridge slot tag `ext`, Becker port decode.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/cococart.cpp : cartridge option names.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_multi.cpp : Multi-Pak $FF7F and slots.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_gmc.cpp : GMC SN76489AN at $FF41.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_orch90.cpp : Orchestra-90 DAC addresses.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_dwsock.cpp : virtual Becker port TCP port setting.
- https://raw.githubusercontent.com/mamedev/mame/master/src/osd/modules/debugger/debuggdbstub.cpp : gdbstub CPU list (m6809 only).
- https://raw.githubusercontent.com/mamedev/mame/master/src/osd/modules/debugger/none.cpp : headless "none" debugger behaviour.
- https://raw.githubusercontent.com/mamedev/mame/master/src/emu/debug/debugcpu.cpp : cycles/totalcycles symbols.
- https://raw.githubusercontent.com/mamedev/mame/master/src/frontend/mame/luaengine.h : invoke() runs functions as coroutines.
- https://raw.githubusercontent.com/mamedev/mame/master/src/frontend/mame/mame.cpp : autoboot script vs command precedence.
- https://raw.githubusercontent.com/jamieleecho/coco-dev/master/README.md : coco-dev tool versions and headless MAME usage.
- https://raw.githubusercontent.com/jamieleecho/coco-dev/master/Dockerfile : how the CoCo 3-only MAME is built.
- https://github.com/VCCE/VCC/releases : VCC release history and features.
- https://www.slackbuilds.org/repository/15.0/games/ovcc/ : OVCC description and upstream.
- https://48k.ca/trs80gp.html : trs80gp features and version.
- https://raw.githubusercontent.com/nitros9project/toolshed/master/doc/ToolShed.md : decb/os9 command reference.
- https://www.lwtools.ca/manual/c62.html : lwasm command line options.
- https://www.cocopedia.com/wiki/DW4_Installation_Guide : DriveWire 4 setup.
- https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/CoCo%20SDC%20User%20Guide%20v4%20(Darren%20Atkinson).pdf : CoCo SDC usage, formats, 8.3 rule, command interface.
- https://colorcomputerarchive.com/repo/Documents/Books/Unravelled%20Series/disk-basic-unravelled.pdf : RS-DOS geometry and directory layout.
