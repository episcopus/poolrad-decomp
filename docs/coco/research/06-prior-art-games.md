# 06: Prior art games on the CoCo 3, and how 8-bit Gold Box ports fit Pool of Radiance

Scope: what shipped CoCo 3 software (commercial 1986 to 1990 and homebrew 1996 to 2023) proves the machine can do, which CoCo titles are structurally close to Pool of Radiance (PoR), and how SSI fit PoR onto the 64 KB Commodore 64 and 128 KB Apple II. Ends with a capability envelope and per-module implications for the port.

## Key takeaways for the Pool of Radiance port

1. Every high-end CoCo 3 action game of the last 25 years (Joust, Defender, Robotron, Donkey Kong, Pac-Man, Digger III, PopStar Pilot, GunStar, Space Bandits) requires 512K and runs in 320x225 or 320x200 16-colour, written in 6809 assembly, with 8 KB MMU blocks used as a big bank of code, compiled sprites and audio samples. 512K is the normal target, not a luxury; PoR on DOS itself needs 512 KB for EGA (src: https://dosdays.co.uk/topics/Games/game_poolrad.php).
2. The standard CoCo 3 sound recipe is the GIME timer FIRQ feeding 8-bit unsigned PCM (top 6 bits used) into the 6-bit DAC at $FF20, at about 6,000 Hz for samples (Joust: timer $0254, 6005.95 Hz) or 2,000 Hz when CPU is scarce (Space Bandits). That is the model for replacing PoR's 236.7 Hz PSG/speaker driver.
3. A first-person 3D maze at good frame rates is proven: Gloom2 (Sock Master) does about 20 fps full screen at 256x192x16 flat-shaded on a 128K CoCo 3; Gate Crasher (Nick Marentes, 1999) built a full game on Gloom at 128x96x16 double-buffered. PoR's 3D view is a small window of static 8x8 tile walls redrawn only on a move, which is far easier than either.
4. The C64 version of PoR (the original development platform per Filfre; Retro Gamer says Apple II) fit in 64 KB by being "heavily overlaid": one overlay area at $0800 (DUNGEON, COMBAT, CAMP, GEN), each resource kind loaded to a fixed address (ECL script at $9900, portraits at $8C00/$9000, wall sets at $6650 to $6AFF), and a 25-slot "loaded-files cache" table recording which file of each kind is resident (src: https://github.com/malcyon/wish docs/40-memory-map.md, docs/140-loaded-files-cache.md). This is the most directly reusable design for the CoCo port's native memory model.
5. The C64 and Apple II versions each shipped on 4 double-sided disks (8 sides) with constant disk swapping; DOS PoR's compressed data is 1.28 MB, which is about 8 CoCo DECB disk sides of 157.5 KB. Expect either swapping or mass storage (CoCo SDC, DriveWire, hard disk).
6. No SSI or Gold Box game was ever released for any 6809 machine (CoCo, Dragon). CoCo owners had no Gold Box, Bard's Tale or Ultima; the closest commercial CoCo RPG is Paladin's Legacy (1989, solo character, non-tactical combat). A CoCo 3 PoR would be a first.
7. Sierra's King's Quest III and Leisure Suit Larry (1988, OS-9 Level II, 3 disks each, 256K to 512K) are the only proof that a big, disk-heavy, script-driven PC adventure was ported to the CoCo 3 by its publisher; their sound was limited to PC-speaker quality and sound never played during animation.
8. A CMOC-based precedent exists: Space Bandits (Jamie Cho) runs C game objects compiled by CMOC on top of the 6809 assembly DynoSprite engine, built in the same jamieleecho/coco-dev Docker image the port uses. Its split (assembly engine for blits, sound, disk, MMU; C for game logic in 8 KB banked pages) is the pattern to copy.

## Part A: the highly rated titles

### Summary table

| Title | Author(s) | Year | RAM | Video | Method | Sound | Media |
|---|---|---|---|---|---|---|---|
| Donkey Kong | John Kowalski (Sock Master) | 2007 | 512K | 256x225, 16 col | Z80 arcade code hand-translated to 6809, arcade hardware emulated | arcade sound emulated via DAC | 1 disk |
| Donkey Kong Remixed | John Kowalski | 2015 | 512K | as above | new levels on the DK port, smoother frame rate | cleaner | disk |
| Joust | Glen Hewlett | Aug 2021 | 512K | 320x225, 16 col | arcade 6809 code transcoded, software blitter and compiled sprites | 6006 Hz 8-bit samples via timer FIRQ | disk(s), ZX0 compressed |
| Defender | Glen Hewlett | Sep 2021 | 512K | 320x225, 16 col | arcade 6809 code transcoded | sound CPU emulated by timer IRQ + raw samples | 2 disks |
| Robotron | Glen Hewlett | about 2022 (v0.5) | 512K | as Joust | arcade 6809 ROMs converted | samples (incomplete) | disk |
| Pac-Man (tribute) | Nick Marentes | 1997 | 512K | 320x225, 16 col | written from scratch in 6809 asm | two-channel sampled effects | disk |
| Pac-Man (transcode) | Glen Hewlett | 2017 | [unverified] | [unverified] | Z80 disassembly machine-translated to 6809 | [unverified] | disk |
| The Crystal City | Jeremy Spiller (Gosub Software), pub. Sundog | late 1990 | 512K | [unverified mode] | hardware horizontal scrolling, compressed terrain | [unverified] | 2 disks (35 track) |
| Digger III: The Saint's Ascension | Chet Simpson (HyperTech Gaming) | Sep 2020 | 512K | [unverified mode] | 4-way hardware scrolling, parallax | digitised effects and speech | 1 disk, RGB and composite builds |
| Ghost Rush | Paul Shoemaker | Jun 2022 | 32K or 64K (sources differ) | 128x96, 16 col on CoCo 3 | 100% machine language | 4-voice music (Rick Adams routine) | 1 disk |
| Timberman | Paul Thayer, with Simon Jonassen | 2017 | 128K | [unverified] | machine language | [unverified] | SD card / download |
| Asteroids RX | Allan Turvey (Spectrum), CoCo port Pere Serrat | 2023 | 32K, CoCo 1/2/3 | [unverified] | AGD engine port | [unverified] | download |

### Donkey Kong and Donkey Kong Remixed (John Kowalski, "Sock Master")

- Released 31 March 2007, freeware, CoCo 3, 512K, joystick, loaded by RUN"DONKEY" from dk.dsk (src: https://lcurtisboyle.com/nitros9/donkeykong.html). Sock's own page lists the CoCo 3 at "256 x 225" against the arcade's 224 x 256 and says the arcade's 96 hardware sprites and tiled character screen are replaced with bitmapped "work-alike" operations in a 16-colour screen (src: http://www.6809.org.uk/twilight/sock/dk/index.html). The vertical resolution was reduced from 240 to the CoCo 3's maximum of 225 lines (src: https://lcurtisboyle.com/nitros9/donkeykong.html).
- Method: the 3.0 MHz Z80 code was rewritten by hand into 6809 code for the 1.79 MHz CPU; the 6809 emulates the arcade's I/O ports, graphics and sound hardware so the game logic runs as if on the original board; "some accuracy was traded away" (src: http://www.6809.org.uk/twilight/sock/dkremix/index.html). A 6309 is switched into native mode for extra speed but is not required (src: http://www.6809.org.uk/twilight/sock/dk/index.html).
- Remixed (updates dated 23 July, 7 August and 16 August 2015) adds new barrel, spring and rivet stages and gives a smoother frame rate and cleaner sound (src: http://www.6809.org.uk/twilight/sock/dkremix/index.html). Frame rate figures are not published.
- Lesson for PoR: a whole arcade program translated from another CPU, with its graphics hardware emulated in software, runs acceptably on a stock CoCo 3. The decomp's C translation of x86 code is the same idea one level up.

### Joust (Glen Hewlett, 17 August 2021)

Facts from the published source (Joust_CoCo3 on GitHub, files CoCoize27.asm, CoCo3_Memory_Map.txt) and the archive page (src: https://github.com/nowhereman999/Joust_CoCo3 ; https://lcurtisboyle.com/nitros9/joust.html):

- Requires 512K. The original Williams 6809 code (Bill Pfutzenreuter) is reused; Glen emulated the blitter and sound board. The arcade 6809 runs at 1 MHz, the CoCo 3's 68B09E at 1.78 MHz (src: https://lcurtisboyle.com/nitros9/joust.html).
- Video: $FF99 = %01111110, i.e. 320 x 225 x 16 colours, 160 bytes per row, 36,000 bytes ($8CA0) of screen; $FF98 = $80 (graphics, 60 Hz); vertical offset $FF9D/$FF9E = $00F0 (screen starts 12 rows into block 0). The source comment table lists every $FF99 value from 256x192x2 to 640x225x4 with byte sizes, a handy reference (src: CoCoize27.asm in https://github.com/nowhereman999/Joust_CoCo3).
- Single screen, not double-buffered: the VSYNC (vertical border) IRQ and a timer FIRQ are positioned to "emulate where the scanline is", with "no tearing of sprites" at the chosen timing (V0.26 change log). Sprites became compiled sprites (code that writes pixels directly) in V0.16; erasing is done by "blasting rectangles" to imitate the blitter (V0.11, V0.14 which used two banks, $4000 bytes, of rectangle code).
- Memory: of 64 8 KB blocks, blocks $00 to $04 hold graphics, $26 to $37 hold attract-mode code, compiled platform sprites, fake CMOS settings and 15 blocks of compiled font/message routines (one per palette), and $38 to $3F are the 64 KB CPU map (game code from $9600, direct page at $A000, IRQ/FIRQ code at $E000 to $FDFF). Banks are swapped into $C000 to $DFFF (MMU slot 6) to call compiled sprites (src: CoCo3_Memory_Map.txt).
- Sound: GIME timer at $FF94/$FF95 = $0254 with the 279.365 ns (3.58 MHz) timer source gives "6005.95 Hz samples"; FIRQ enabled via $FF93 = $20; IRQ via $FF92 = $08 (VBORD). Samples are unsigned 8-bit PCM written to $FF20 with the PIA set so the low two bits are ignored; conversion command given in the source: `ffmpeg -i in.wav -acodec pcm_u8 -f u8 -ac 1 -ar 6006 -af aresample=6006:filter_size=256:cutoff=1.0 out.raw`. Samples are ZX0 compressed on disk and unpacked during loading (src: CoCoize27.asm; https://lcurtisboyle.com/nitros9/joust.html).
- Tools: MAME debugger and trace logs (`trace output.tr.txt,0,,{tracelog "A=%02X,..."}` in Useful_Info.txt), ZX0 compressor (Einar Saukas) with Doug Masten's 6809 decompressor (src: Joust_CoCo3 README).

### Defender (Glen Hewlett, 25 September 2021)

- 512K, two disk images (DISK1.DSK, DISK2.DSK); with one drive the user swaps during load; a BASIC CONFIG program sets monitor type, keys, lives and drive count; BREAK exits to BASIC and RUN"SAVE" writes scores (src: https://github.com/nowhereman999/Defender_CoCo3 README).
- Same video setup as Joust (320x225x16, $FF99 = %01111110) and the same 6005.95 Hz timer FIRQ audio (src: Defender_CoCo_3_Source.zip in the same repo). The arcade sound CPU is emulated with GIME timer interrupts and raw 8-bit samples; insert-coin and new-game sounds briefly slow down (src: https://lcurtisboyle.com/nitros9/defender.html).
- Development used the original source code and MAME input recording and playback (`mame defender -record defgameplay.ini`) plus debug playback at 5% speed to find crashes (src: https://nowhereman999.wordpress.com/2021/09/25/defender-for-the-tandy-coco-3/). The scrolling method is not documented in prose [unverified]; the arcade redraws objects on a bitmap, and the port appears to do the same.

### Robotron (Glen Hewlett)

- Converted from the original ROMs; hardware "exactly the same as Joust". Released as v0.5 (author says really 0.9) around a CoCoFest: playable with graphic glitches, slowdowns "when there are tons of enemies firing", and unfinished samples; joysticks required (src: https://github.com/nowhereman999/Robotron_CoCo3 README). The author suspects the slowdown is game-logic looping rather than sprite drawing. Lesson: a 1.79 MHz 6809 running an arcade's logic plus software blitting saturates under heavy object counts.

### Pac-Man

Two distinct CoCo 3 versions exist; the human's list does not say which.
- Nick Marentes, "Pacman Tribute", 1997: 6809 assembly, 512K, 320 x 225 ("the tallest vertical resolution" he could achieve), maze full height with scores on the sides, 30 frames per second ("the maximum for a standard TV or the Tandy CM-8"), graphics redrawn on an Amiga from observation, sound effects sampled from a real machine and played by his improved two-channel sound routine from Cosmic Ambush using minimal CPU (src: https://nickmarentes.com/ProjectArchive/pacman.html). The 1997 demo has one level; the full game has all bonus shapes and intermissions (src: https://lcurtisboyle.com/nitros9/pacman.html). It is now free on itch.io, "CoCo3 with 512K" (src: https://nickolasmarentes.itch.io/).
- Glen Hewlett, transcode (2016 to 2017): a utility translates a Z80 disassembly instruction by instruction to 6809, keeping the Z80 line as a comment, data placed at original addresses with ORG, endian swap of word data as an open issue, then hand-tweaked; a custom sprite engine gives a playable frame rate (src: https://nowhereman999.wordpress.com/2016/12/29/zilog-z80-to-motorola-6809-transcode-part-001/ ; https://hackaday.com/2017/09/06/). The disk is in the archive as "Pacman CoCo 3 Transcode (Glen Hewlett)" (src: https://github.com/dougmasten/awesome-coco). His overview post says most arcade games are driven by the VSYNC IRQ, so the conversion sets up a CoCo VSYNC IRQ and emulates the original IRQ routines one at a time (src: https://nowhereman999.wordpress.com/2018/01/20/arcade-machine-conversion-to-the-coco-overview/).

### The Crystal City (1990)

- Jeremy Spiller (Gosub Software), published by Sundog Systems, late 1990; CoCo 3, 512K, joystick, two 35-track disks (program and Levels disk, swapped when prompted); Scramble-like side scroller with "about 30 megabytes" of non-repeating terrain across six levels compressed to fit two disks, destructible terrain, hardware horizontal scrolling; an option adjusts timing on real hardware to reduce garbling of the score and shield line (src: https://lcurtisboyle.com/nitros9/crystalcity.html). The "30 megabytes" figure is the archive page's claim, presumably the uncompressed equivalent [unverified]. Lesson: aggressive compression of level data plus a second disk was the 1990 answer to data volume.

### Digger III: The Saint's Ascension (HyperTech Gaming, 12 September 2020)

- Chet Simpson (code), Paul Thayer (character graphics), sound by Chet Simpson and Eric Crichlow; CoCo 3, 512K, stock 6809; "uses nearly all of the 512K"; 4-way hardware scrolling across multi-screen levels with simulated parallax; digitised sound effects and speech; more than two dozen levels (src: https://www.lcurtisboyle.com/nitros9/diggeriii.html). Separate RGB and composite disk images, about 180 KB each; tools listed as Tiled and GIMP; the loader screen uses a GIME 32x16 attributed text mode, confirmed by the developer (src: https://hypertechgaming.itch.io/digger3). Loaded by LOADM"D3", which then loads all resources (src: https://colorcomputerarchive.com/repo/Documents/Manuals/Games/Digger%20III%20(HyperTech%20Gaming).pdf). Chet Simpson also wrote the KAOS Toolkit for retro multimedia files (src: https://github.com/dougmasten/awesome-coco).

### Ghost Rush (Paul Shoemaker, 2022)

- Released 9 June 2022, v2 19 June, Halloween and Winter editions October and December 2022; CoCo 1/2/3 (holiday editions also Dragon), joystick button only; GR16.BIN is a 16-colour CoCo 3 build, GR.BIN 4-colour, GRVGA.BIN for CoCoVGA; 128x96 graphics; 4-voice music routine by Rick Adams, random number routine by Steve Bjork; "100% machine language" (src: https://pshoemaker70.itch.io/ghost-rush ; https://lcurtisboyle.com/nitros9/ghostrush.html). RAM: itch.io says 64K CoCo 1/2 or CoCo 3, the archive says 32K; sources disagree.
- Lesson: small games at low resolution; relevant mainly for the multi-voice DAC music routine.

### Timberman (Paul Thayer, 2017)

- CoCo 3, 128K, joystick or mouse; Paul Thayer's first all machine-language game, with help from Simon Jonassen; sold on SD cards at CocoFest, Christmas Edition 2019 free (src: https://lcurtisboyle.com/nitros9/timberman.html). No technical write-up found.

### Asteroids RX

- The only "Asteroids RX" found is Allan Turvey's ZX Spectrum game (September 2021), ported to CoCo 1/2/3 and Dragon (32K) by Pere Serrat in April 2023 by converting the AGD engine (src: https://lcurtisboyle.com/nitros9/asteroidsrx.html ; https://www.indieretronews.com/2021/09/asteroids-rx-from-scratch-conversion-of.html). It is not a CoCo 3 specific showcase; if the human meant another title, it was not found.

### Other showcase titles found along the way (relevant numbers)

- PopStar Pilot (Nick Marentes, 2016): 320 x 225 x 16, split-screen smooth scrolling using 1-byte hardware scrolling, raster background effects, flicker-free double buffering, two-channel interrupt-driven sampled effects, 512K, about 80 screens of landscape; tools: Robert Gault's EDTASM6309 on the CoCo 3 itself, Amiga Brilliance for art, Audacity for samples, a level editor written in ROM BASIC (src: https://nickmarentes.com/ProjectArchive/popstar.html).
- GunStar (Nick Marentes, 2020): 128 x 112 x 16, "3-plane" engine, double-buffered, 2-channel sampled sound, 512K and 6309 required (src: https://nickmarentes.com/ProjectArchive/gunstar.html).
- Cosmic Ambush (Nick Marentes, 1992): designed to fit a 32K ROM cartridge, unlimited smooth vertical scrolling, two-channel effects driven by the programmable timer interrupt "without noticeably interrupting graphic animation" (src: https://nickmarentes.com/ProjectArchive/ambush.html).
- Sock Master demos: Demo #1 (about 1989 onward) updates at 60 per second with more than 16 colours on screen; "Moon" does GIME hardware scrolling of four screen areas plus sprites (src: http://www.6809.org.uk/twilight/sock/cocofile/demo.html).
- Space Bandits (Jamie Cho) on DynoSprite: see Part B, raycasters and engines.

## Part B: RPGs, adventures and first-person games close to Pool of Radiance

### What PoR needs, as a checklist

First-person 3D maze view; party of up to six (plus NPCs) with 285-byte records; menus and text windows on 40x25 cells; top-down tactical combat with 24x24 icons; portraits and animated pictures; scripted encounters (ECL bytecode); 1.28 MB of compressed data; saved games. No CoCo title found combines more than two or three of these.

### Summary table

| Title | Year | Who | Machine / RAM | Media | Closest PoR feature |
|---|---|---|---|---|---|
| Dungeons of Daggorath | 1982/83 | DynaMicro (Douglas Morgan, Keith Kiyohara), Tandy | CoCo 1/2, 16K | 8K ROM pack | real-time first-person wireframe dungeon |
| Castle of Tharoggad | 1988 | Scott Cabit, Tandy | CoCo 3, 128K | cartridge | 16-colour first-person sequel [view unverified] |
| Hall of the King I to III | 1985 to 1987 | Glen Dahlgren, Prickly Pear / Sundog | CoCo 1/2/3, 64K | 2 disks each, 6 total | large disk-based graphic adventure |
| Paladin's Legacy | 1989 | Allan Chaney, Sundog | CoCo 1/2/3 (Sundog required CoCo 3 support) | 2 disks (Player, City) | tile RPG, disk swap per city |
| Rogue | 1986 | Epyx authors, Tandy | CoCo 3, 128K (256K graphic font), OS-9 L2 | disk | dungeon RPG, 40/80 col text |
| King's Quest III | 1988 | Sierra (AGI), Tandy | CoCo 3, 512K per Sierra wiki, OS-9 L2 | 3 disks | big scripted interpreter game |
| Leisure Suit Larry | 1988 | Sierra, ported by Chris Iden | CoCo 3, 256K, OS-9 | 3 x 35-track SS disks | same |
| Shanghai | 1987 | Rick Adams (Activision); OS-9 port Bill Nobel | CoCo 3, 128K cart; 256K OS-9 | cartridge, disk | tile graphics, menus |
| Gantelet | 1986 | Dave Dies, Diecom | CoCo 1/2/3, 64K | tape or disk | top-down Gauntlet-style dungeon |
| Kung-Fu Dude | 1987 | Glen Dahlgren, Sundog | CoCo 1/2/3, 64K | disk | none (side-scrolling fighter) |
| Warrior King | 1988 | Glen Dahlgren, Sundog | CoCo 3, 128K | disk | none (Rastan clone, 320x200x16) |
| Gloom / Gloom2 demo | 1996 / 1997 | John Kowalski | CoCo 3, 512K / 128K | disk | first-person 3D engine |
| Gate Crasher | 1999/2000 | Nick Marentes | CoCo 3, 512K | disk | first-person 3D game on Gloom |
| Wolf3D-style demo | 2009 | "remz" on AtariAge | CoCo 3, 128K | [unverified] | first-person 3D |
| Dungeon Crawl v2.0 | 2020s | Paul Shoemaker | CoCo 1/2/3, 64K | 2 disks (Play, Map) | Telengard-style dungeon RPG |

Dropped after checking: "Phantasy" and a Tandy "Dungeon Master" for the CoCo could not be found in Wikipedia's CoCo games list or the archive pages consulted (src: https://en.wikipedia.org/wiki/List_of_TRS-80_Color_Computer_games); FTL's Dungeon Master was never released for the CoCo as far as these sources show. The nearest Tandy first-person dungeon follow-up is Castle of Tharoggad. Kung-Fu Dude and Warrior King are action games, kept only to show they are not RPGs.

### Dungeons of Daggorath (1982/83)

- Designed by Douglas J. Morgan with Keith S. Kiyohara, sounds by Phil Landmeier; developed 1980 to 81, published by Tandy; CoCo and Dragon 32/64; 8 KB ROMpak; first-person 3D maze with wireframe depth; five levels; real time; typed commands like "G L SH"; health shown only by an audible heartbeat; "Fitting the game into the 8 KB cartridge took several months of recoding" (src: https://en.wikipedia.org/wiki/Dungeons_of_Daggorath). 16 KB RAM, 256x192x2 graphics (src: https://www.cocopedia.com/wiki/Dungeons_of_Daggorath). Source code is on GitHub (src: https://github.com/dougmasten/awesome-coco, entry MichaelSpencerJr/DungeonsOfDaggorath).
- Lesson: the iconic CoCo first-person dungeon used line drawing in 2-colour hi-res, not filled tiles. PoR's walls are 8x8 tile mosaics, a different technique, but Daggorath proves the audience accepted a small, fast, simple 3D view.

### Castle of Tharoggad (1988)

- Scott A. Cabit (Computerware), published by Tandy; CoCo 3 only, 128K, cartridge, mouse or joystick; uses the CoCo 3 16-colour mode, criticised as "too cartoony" against Daggorath's wireframe; sold poorly (src: https://www.lcurtisboyle.com/nitros9/castleoftharoggad.html). Whether its view is first-person is not stated on that page [unverified].

### Hall of the King trilogy (1985 to 1987)

- Glen R. Dahlgren, Prickly Pear Software then Sundog Systems; CoCo 1/2/3, 64K, disk; 2 single-sided disks per part, 6 for the trilogy; called "the largest adventure game done on the Coco" at the time (src: https://lcurtisboyle.com/nitros9/halloftheking.html ; https://lcurtisboyle.com/nitros9/hallofthekingiii.html). Interface details (parser plus pictures) are not stated on those pages [unverified]; manuals exist at https://mocagh.org/miscgame/hallking-manual.pdf.
- Lesson: a multi-disk graphic adventure was a normal CoCo product; six disk sides for a trilogy is the high-water mark of CoCo disk volume, comparable to what PoR needs alone.

### Paladin's Legacy (1989): the closest commercial CoCo RPG

- Allan Chaney began it in BASIC as "Quest for the King of Zandor", moved to 6809 assembly with Edtasm+; Sundog (Glen Dahlgren) published it on condition it run on the CoCo 3 while still working on CoCo 1/2, and Dahlgren rewrote the disk I/O in assembly; released just before Christmas 1989; two disks, a Player Disk and a City Disk, swapped when entering and leaving a city; one save slot (src: https://paladinslegacyretro.wordpress.com/).
- The CRPG Addict: 80 x 80 world grid, single hero, single-key commands, combat "no escape, no tactics, and no spells" (1 of 5), graphics "only just adequate", artifact colours on composite; a commenter notes CoCo owners had no Bard's Tale, Ultima or Gold Box games (src: http://crpgaddict.blogspot.com/2018/12/game-311-paladins-legacy-1989.html).
- Lesson: the CoCo commercial market never produced a party-based tactical RPG; the disk-swap-per-area pattern (Player disk vs City disk) mirrors PoR's C64 approach on a smaller scale.

### Rogue (1986)

- Epyx (Mike Leber, Ron Miller, James Long, Ed Rosenzweig), published by Tandy; CoCo 3 only, 128K (256K for the graphic font version); described as the first OS-9 Level II game for the CoCo 3; hardware text mode in 40 or 80 columns; multitasks and can shrink to a 28x12 window (src: https://www.lcurtisboyle.com/nitros9/rogue.html). Lesson: CoCo 3 hardware text modes (40 and 80 columns, with attributes) were good enough for a commercial RPG UI; a PoR text and menu layer could use a GIME text mode for screens with no pictures.

### Sierra AGI on the CoCo 3: King's Quest III and Leisure Suit Larry (1988)

- AGI table: KQ3 and LSL1 released for CoCo 3 in 1988; Donald Duck's Playground (1987) was a non-AGI CoCo 3 release (src: https://en.wikipedia.org/wiki/Adventure_Game_Interpreter). ScummVM notes CoCo 3 "was officially supported by Sierra for KQ3 and LSL1 only"; fan ports of other AGI titles (KQ2, KQ4) with interpreter version 0x2440 exist (src: https://lists.scummvm.org/pipermail/scummvm-git-logs/2022-January/091630.html).
- LSL: ported by Chris Iden, CoCo 3, 256K, OS-9 or NitrOS-9, three 35-track single-sided disks (src: https://www.lcurtisboyle.com/nitros9/leisuresuitlarry.html). KQ3: Sierra's wiki gives 512 KB minimum (src: https://wiki.sierrahelp.com/index.php/King%27s_Quest_III:_To_Heir_is_Human_Technical); the two sources give different RAM for the two games, unresolved.
- Structure (Robert Gault's hard-drive notes): needs VDG interface modules (VDGINT, covdg.io), a VDG screen or window (`xmode /w1 type=1 pag=16` on Level II), the `AGIVIRQDr` driver, data files from three disks with a toc.txt listing which volumes (v0 to v14) are on which disk, processed by `tocgen`, then started with `sierra -r` for RGB (src: https://colorcomputerarchive.com/repo/Documents/Manuals/Games/Running%20KQ3%20from%20hard%20drive.txt).
- Quality: graphics look and run almost identically to the IBM PC versions; music limited to PC-speaker quality by the 6-bit DAC, and the official engine never plays sound during on-screen animation; disks use the 157.5 KiB format (src: https://forums.atariage.com/topic/311559-sierra-agi-ports-to-the-coco-3-any-sound-improvement/).
- Lesson: this is the strongest structural precedent. A PC interpreter (vector pictures, logic scripts, resources split across volume files) was ported to the CoCo 3 by the publisher, under OS-9 Level II, using a disk table of contents for multi-disk resource lookup. PoR's DAX archives plus ECL bytecode map cleanly onto the same shape: an interpreter in RAM, resources fetched by id from whichever disk holds them.

### Shanghai (1987), Thexder (1988)

- Shanghai: Rick Adams (Activision), Tandy cartridge, CoCo 3, 128K, joystick; OS-9 port by Bill Nobel needs 256K and disk (src: https://www.lcurtisboyle.com/nitros9/shanghai.html).
- Thexder: Synergistic/Sierra, Tandy 1988 cartridge, CoCo 3, 128K; Alan Dekok's OS-9 disk version needs 256K and suggests it was first written for OS-9 (src: https://www.lcurtisboyle.com/nitros9/thexder.html).

### Gantelet (1986)

- Dave Dies, Diecom Products; CoCo 1/2/3, 64K, tape or disk; Gauntlet clone, 15 levels of "D&D-style dungeons", up to 3 players; optional Sound/Speech cartridge for speech (src: https://www.lcurtisboyle.com/nitros9/gantelet.html). Lesson: top-down dungeon movement on 64K was routine.

### First-person 3D engines and raycasters

- Gloom (John Kowalski, 1996) and Gloom2 (about 1997): Gloom1 needs 512K, about 13% faster on a 6309 in native mode; Gloom2 is "roughly three times faster", 256 x 192 in 16 colours, about 20 frames per second full-screen, flat-shaded walls (texture mapping ruled out), corrects fish-eye, runs on any 128K CoCo 3 (src: http://www.6809.org.uk/twilight/sock/gloom/gloom.html). The README of the open source release: video set to 256 bytes per line to simplify addressing, drawing only 128 of those bytes; the program scans "a pie slice of the map" in front of the player using precalculated tables of "512 sequences of 96x2 entry subtables" (96 entries of X and Y words), table at $00000 to $2FFFF, map at $60000 to $63FFF, map 128x64 with 2 bytes per square (distance code or $80 for wall, plus colour); graphics simplified into a 256-byte table; only changed screen bytes updated; suggests a second buffer for bitmapped enemies and paging for bigger maps; EDTASM source GLOOM.ASM and a BASIC map editor included (src: https://colorcomputerarchive.com/repo/Programming/Source/Gloom3D/readme.txt).
- Gate Crasher (Nick Marentes, 1999 per archive, 2000 per author, timed for PennFest 2000): built on Gloom; unofficial 128 x 96 x 16 mode; double buffered with about 6K per screen; heavy self-modifying code for frame rate; two-channel interrupt-driven digital sound; five floors with a boss; about 40 copies sold (src: https://nickmarentes.com/ProjectArchive/crasher.html ; https://lcurtisboyle.com/nitros9/gatecrasher.html).
- Wolf3D-style demo by "remz" (AtariAge, 7 December 2009): runs on an unexpanded (128K) CoCo, framerate surprised viewers, but the author says there is "not much hope and clock cycle left" for enemies; the thread discusses a 640-wide 4-grey artifact trick, 160x200x256 or 160x96x256 via scan-line doubling at 16K per page (letting an unexpanded machine double-buffer), and the GIME 50/60 Hz switch (src: https://forums.atariage.com/topic/154556-trs-80-coco-3-wolf-3d-style-demo/). The author's identity, mode and frame rate are not stated [unverified].
- No other CoCo raycaster was found in the awesome-coco list or the itch.io CoCo collections checked (src: https://github.com/dougmasten/awesome-coco ; https://itch.io/c/3339935/coco).

### Modern homebrew RPGs and engines

- Dungeon Crawl v2.0 Freeware Edition (Paul Shoemaker): CoCo 1/2/3, 64K, PMODE 4 without artifact colours, two disks (DCPLAY.DSK, DCMAP.DSK), single created character, real time, game code and play based on Telengard, tiles from the WONDERDOT tileset, monsters modelled on Wizardry (src: https://pshoemaker70.itch.io/dungeon-crawl-v2).
- DynoSprite (Richard Goedeken): object-oriented CoCo 3 engine in 6809 assembly, 512K, 320x200x16, tilemap of 16x16 tiles (max 2000 x 68 tiles), horizontal scroll in 2-pixel and vertical in 1-pixel steps, sprite draw/erase routines compiled to 6809 by a Python sprite compiler, 2-voice audio through the 6-bit DAC or Orchestra-90, variable frame rate, DEFLATE-compressed data loaded via DSKCON (src: https://github.com/richard42/dynosprite doc/DynoSpriteUsage.txt). Its CPU address map dedicates $2000 to $3FFF to globals with the direct page at $2000, $E000 to $FDFF to secondary code, and remaps $0000 to $DFFF per task (tilemap, textures, two screen windows at $6000 and $A000, sprite code at $4000, erase data at $C000) (src: doc/AddressMap.txt). DSKCON calls slow the CPU to 0.89 MHz (`clr $FFD8`) and remap the ROM page (src: engine/system.asm).
- Space Bandits (Jamie Cho): DynoSprite fork; game objects and levels written in C and compiled with CMOC via `scripts/cmoc-wrapper.py`; 512K; double-buffered 320x200x16; 3-voice wavetable music; max 2 simultaneous sounds; audio sample rate set to 2,000 Hz (`AudioSamplingRate EQU 2000`, DynoSprite default 6000); scrolling limited to 4 px horizontal or 4 px vertical per frame; built with `./coco-dev` (Docker jamieleecho/coco-dev) then `make all`, `make test` runs MAME; `CPU=6309`, `RELEASE=1`, `VISUALTIME=1` (frame timing in the border colour) build options (src: https://github.com/jamieleecho/space-bandits README.md, CLAUDE.md, engine/globals.asm).

### Was any SSI or Gold Box game released on a 6809 machine?

- No evidence of any. SSI's history page names only Apple, TRS-80 (Model I era, Computer Bismarck 1980), Commodore 64, MS-DOS and later machines (src: https://en.wikipedia.org/wiki/Strategic_Simulations). The Gold Box engine went to C64, Apple II, MS-DOS, Mac, Amiga, Atari ST (one title), PC-98, NES and Genesis (src: https://en.wikipedia.org/wiki/Gold_Box). Wikipedia's CoCo games list has no SSI entry (src: https://en.wikipedia.org/wiki/List_of_TRS-80_Color_Computer_games). The CRPG Addict's commenters say CoCo owners had no access to Gold Box games (src: http://crpgaddict.blogspot.com/2018/12/game-311-paladins-legacy-1989.html). Dragon 32/64: none found [no source names one].

### The 8-bit Gold Box ports: how PoR fit in 64 KB (C64) and 128 KB (Apple II)

Origins and team:
- The engine was "originally designed for the Commodore 64"; C64 and Apple II versions were "written entirely in 6502 assembly"; most later ports in Pascal, the last ones C/C++ (src: https://en.wikipedia.org/wiki/Gold_Box). The DOS version is Turbo Pascal, as the decomp proves.
- Filfre: "the tool chain was built around the Commodore 64", development began 1987, beginning on the C64 then moving to MS-DOS, Apple II, Mac, Amiga; the module reached SSI in January 1988 and the game shipped August 1988 (src: https://www.filfre.net/2016/03/opening-the-gold-box-part-3-from-tabletop-to-desktop/). A Gold Box map is "exactly 16 by 16 squares", a limit from "the tiny memories of 8-bit machines", with "strict bounds on the amount of custom scripting" per map (src: https://www.filfre.net/2017/03/opening-the-gold-box-part-5-all-that-glitters-is-not-gold/).
- Retro Gamer (2020) differs: developed on the Apple II "with the C64 in mind", converted for other systems with a team-written tool; lead programmer Keith Brors: "You literally had 32KB to work with" and a compiler "would have made the code five or ten times larger than efficiently written assembly"; tavern tales and proclamations moved into the printed journal to save disk space (src: https://www.pressreader.com/uk/retro-gamer/20201001/283643942369917). Sources disagree on Apple II vs C64 first; both agree the 8-bit machines set the engine's limits.
- Wikipedia: about 35 people over a year; Keith Brors and Brad Myers original programmers; C64 "nearly unplayable without SSI's fast loader"; DOS "about twice as fast as the C64 version" (src: https://en.wikipedia.org/wiki/Pool_of_Radiance).

Media and swapping:
- C64: 4 disks, each double-sided (8 sides); two blank disks formatted as save disks; built-in fastloader can be disabled; on a C128 runs in C64 mode; character portraits appear "only in the civilized area" (src: https://www.mocagh.org/ssi/pool-refcard-alt.pdf).
- Apple II: 4 double-sided disks, boot side 1, sample party on side 4, portraits only in the civilised area, Monster Portrait option not used, no Exit to DOS (src: https://141.11.32.100.sslip.io/textfiles.com/apple/DOCUMENTATION/pool.qstart). Box sticker: Apple IIe, IIc or IIGS "with 128k"; the game used only drive 1 (src: https://www.applefritter.com/node/33971).
- DOS for comparison: three 5.25" 360 KB or two 3.5" 720 KB disks, 1.75 MB installed, 384 KB RAM (512 KB EGA, 640 KB Tandy) (src: https://dosdays.co.uk/topics/Games/game_poolrad.php).
- Load time measured on emulated C64 by the wish project: boot to main menu 167.8 s with JiffyDOS, 199.6 s to 238.6 s on a stock KERNAL depending on the fastloader answer (src: https://github.com/malcyon/wish docs/131-fastloader.md).

C64 memory layout (measured in a running game with VICE by the wish project; untrusted third-party notes, but internally cross-checked) (src: https://github.com/malcyon/wish docs/40-memory-map.md and docs/140-loaded-files-cache.md):

| C64 address | Holds |
|---|---|
| $0400 | GEO map (one area), or SQRPACI overland graphics; screen moved to $CC00 |
| $0800 | overlay area: DUNGEON, CAMP, GEN, COMBAT (also POST.COM, COM.PREP, INIT, FINAL) |
| $2B80, $2C48 | LINKER and LIBRARY (resident loader/runtime) |
| $4900 to $64FF | party header and character slots (saved verbatim as SAVEDGAME0, 7,168 bytes) |
| $6500 to $6AFF | SECSET (8x8 multicolour character glyphs for the 3D view) and 3 WALLSET pieces of 400 bytes each at $6650, $67E0, $6970 |
| $6B00 | MON monster record window |
| $6F00 | ITEMNAMES word table |
| $7A00 to $82FF | DUNGEON2, COMBAT3, ITEMS (2,048 bytes) |
| $8300 to $8AFF | roster blocks (SAVEDGAME1) |
| $8400 | SPRITE or ANIMATE (monster/NPC picture, animation) |
| $8C00 | staging buffer: PIC, BODY, SQRDATA, WALLDEF, COMPIC |
| $9000 | HEAD portrait |
| $9900 | ECL script for the area (or CHARPIC icon charset, ITEMFILE) |
| $A700, $AF00 | SPELLE, SPELLN (RAM under BASIC ROM) |
| $B700 | FAST1.O fastloader |
| $BA00 | MDRIVER, SOUNDFX |
| $C000 | GDRIVE movement driver; screen at $CC00 |
| $ED50, $F05C, $F368 | WALLDEF pieces unpacked under the KERNAL (WALLS renderer tables) |

- The 25-slot loaded-files cache at $6E13 to $6E2B (saved at $4BC0 in SAVEDGAME0) holds, per resource kind, the two-hex-digit number of the file currently resident (GEO14, ECL0B and so on); $FF means empty, bit 7 marks "reload" (src: wish docs/140-loaded-files-cache.md).
- The C64 game disk is a normal CBM DOS disk: `DISK A SIDE 1` holds 103 PRG files, one per resource (HEADxx, BODYxx, PICxx, ECLxx, GEOxx), not DAX archives (src: wish docs/10-disk-format.md). DOS packs the same ids into DAX containers; head and body block ids match the C64 file numbers (src: https://wish-goldbox.readthedocs.io/en/latest/api/generated/goldbox.portraits.html).
- The ECL area at $9900 runs up to SPELLE at $A700, i.e. at most $0E00 = 3,584 bytes, against the DOS buffer of $1E00 [inferred from the address table, not measured].
- The C64 character record is 580 bytes, split between a 256-byte save slot, a roster block and an item page; combat icons are 18 screen codes plus 18 colours in a custom character set (src: https://wish-goldbox.readthedocs.io/en/latest/api/generated/goldbox.c64_codec.html). So the C64 3D view and combat icons are character-mode graphics (programmable 8x8 glyphs), not bitmaps [the 3D view inference rests on the SECSET/WALLSET evidence above].

What was cut or reduced on 8-bit: portraits only in civilised areas (both C64 and Apple II); no monster portrait option on Apple II; no Exit to DOS; long loads (src: refcards above). Combat and the full rule set were kept. The paragraph journal, present on all versions, offloaded text (src: Retro Gamer, above).

Lesson: SSI's own 8-bit design is a working blueprint for a native CoCo memory model: a resident runtime, one swappable overlay area, fixed-address buffers per resource type, a table of which resource is loaded, and character-cell graphics for walls and icons. The CoCo 3 with 512K has eight times the C64's RAM and an MMU, so it can keep many of those buffers resident at once and cache recently used resources in spare 8 KB blocks.

## Part C: capability envelope

### Measured or published numbers

| Capability | Best achieved on CoCo 3 (stock 6809, 1.79 MHz) | Source |
|---|---|---|
| CPU budget per 60 Hz field | 29,860 cycles (field 16.683 ms) | DynoSprite doc/Benchmarks.txt |
| Full-screen 16-colour animation | 320x225x16 at 30 fps (Pac-Man tribute); 256x192x16 flat-shaded 3D at about 20 fps (Gloom2); 128x96x16 3D double-buffered (Gate Crasher) | nickmarentes.com pacman, 6809.org.uk gloom, crasher |
| Screen sizes | 320x200x16 = 32,000 bytes; 320x225x16 = 36,000; 256x192x16 = 24,576; 128x96x16 about 6K | Joust source table; crasher page |
| Scrolling | GIME hardware scroll, 1-byte (2-pixel) horizontal steps; split-screen and four-region scroll; DynoSprite max 4 px per frame | popstar page; Sock demo page; Space Bandits CLAUDE.md |
| Sprites | compiled sprites (code per image) are universal; DynoSprite worst case 17,605 of 29,860 cycles for its stationary-objects test on 6809 (14,642 on 6309); Joust/Defender run arcade-level object counts; Robotron slows with many shots | Benchmarks.txt; Robotron README |
| Double buffering | standard in 512K games (PopStar, GunStar, Space Bandits); Joust single buffer raced against the beam | pages above; Joust source |
| Sound | 8-bit samples to 6-bit DAC by timer FIRQ: 6,006 Hz (Joust, Defender, DynoSprite default 6,000), 2,000 Hz (Space Bandits); 2 voices typical, 3-voice wavetable music, 4-voice music routine (Rick Adams) | sources above |
| Disk streaming | DSKCON at 0.89 MHz; DynoSprite level load 14.3 s to 15.0 s from DECB floppy, 5.8 s to 6.4 s HDB-DOS; ZX0 or DEFLATE compression of all data | Benchmarks.txt; Joust/Defender READMEs |
| Disk volume | 2 disks typical (Crystal City, Defender, Paladin's Legacy), 3 disks (KQ3, LSL), 6 disks (Hall of the King trilogy) | pages above |
| RAM | 512K for every modern showcase; Digger III "nearly all of the 512K"; Gloom1 used a 192 KB lookup table | pages above |
| 6309 gain | 10% to 30% (Marentes), 20% to 29% in DynoSprite tests, about 13% Gloom1 | gunstar page; Benchmarks.txt; gloom page |

### Derived estimates (not measured; from 6809 cycle counts) [derived]

- Copying a full 32,000-byte 320x200x16 screen with stack-blast moves costs roughly 3.5 to 4 cycles per byte, about 110,000 to 130,000 cycles, that is about 4 fields (about 15 fps if the CPU did nothing else). A plain LDD/STD loop is about 8 cycles per byte, about 9 fields. A fill is about 2 cycles per byte. So full-screen redraws per frame are not affordable at 60 fps; dirty-rectangle updates or page flipping via $FF9D/$FF9E are the norm.
- A DAC FIRQ at 6,000 Hz costs about 6,000 x (FIRQ entry/exit plus fetch/store, roughly 30 to 40 cycles) = about 180,000 to 240,000 cycles per second, i.e. 10% to 13% of the CPU. At 2,000 Hz it is about 4%.

### Implications for each Pool of Radiance module

| PoR module | DOS behaviour (from brief) | Envelope verdict | Approach suggested by prior art |
|---|---|---|---|
| 3D view | small window built from 8x8 tiles out of WALLDEF wallsets, redrawn when the party moves or turns | Comfortable. Far smaller and less frequent than Gloom2's 20 fps full-screen. | Keep 4bpp tiles as GIME 320x200x16 bytes (2 pixels per byte, high nibble left, same as DAX) so tile blits are byte copies; draw into a back buffer and flip, or draw in place once per keypress. The C64 used a character set for the same job. |
| Combat map | top-down grid, 24x24 icons, animations for attacks and spells, cursor | Comfortable at turn-based speeds; icons are 12 bytes x 24 lines = 288 bytes at 4bpp. | Pre-convert icons to compiled sprites or masked byte blits; dirty-rectangle restore from a background copy in another 8 KB block (DynoSprite's erase-data window pattern). |
| Portraits and animated pictures | 40x88 and 48x88 portraits; frame deltas XOR against frame 0 with per-frame delays | Comfortable: 48x88 at 4bpp is 2,112 bytes; XOR deltas suit byte-wise work. | Keep frames in banked RAM; apply deltas with EOR loops; time with the VBORD IRQ count rather than Delay. |
| Title and full-screen pictures | 320x200x16, 32,000 bytes | Fits exactly one 320x200x16 screen (4 MMU blocks). A full redraw takes about 4 fields, fine for a static picture. | Decompress straight into the off-screen page, then flip with $FF9D; fade palette ($FFB0 to $FFBF) as Marentes and DynoSprite splash code do. |
| Text and menus | 40x25 cells of 8x8 glyphs (177-glyph 1-bit font), windows, keyboard polling | Comfortable. 320 pixels / 8 = 40 columns exactly; 200 / 8 = 25 rows. | Render the 1-bit font into the 16-colour bitmap with a 2-colour expansion table (one byte of font = 4 output bytes); optionally use GIME 40/80-column text modes for pure text screens, as Rogue did. |
| Sound effects | PSG / speaker effects on a 236.7 Hz timer | Comfortable. | Either synthesize square-wave PSG-like tones in a timer FIRQ to the DAC (low rate, cheap), or pre-render each effect to 8-bit PCM at 2,000 to 6,000 Hz with the ffmpeg recipe from Joust and play via FIRQ; follow Sierra's lesson that sound during heavy drawing costs CPU. |
| Data streaming | 113 DAX archives, 1.28 MB compressed, blocks up to about 36 KB | The real constraint. DECB floppy sides are 157.5 KB, so about 8 sides, matching the C64's 8. | Mirror the C64 scheme (fixed buffers per resource kind plus a "resident file" table) but with a larger RAM cache in spare 8 KB blocks; support CoCo SDC/DriveWire/hard disk for a no-swap experience; keep the existing byte RLE (cheap to decode) or recompress with ZX0. |
| Code size | 197 KB of x86 code, 35 overlays, largest 17.5 KB | Plausible with 512K if each overlay fits a few 8 KB blocks; mirrors Joust's 15 blocks of compiled code and Space Bandits' banked C objects. | One overlay window in the CPU map, overlays loaded from disk or from RAM cache; keep the C64 idea of a single overlay area. |

## Implications and recommendations for the port

1. Target 512K CoCo 3, stock 6809, 320x200x16 (not 225 lines; PoR is 200 lines, and 320x200x16 matches EGA pixel-for-pixel). Treat 6309 as an optional speed-up only, as every modern title does except GunStar.
2. Model the memory system on the C64 PoR layout, upgraded with the MMU: a resident runtime and interpreter, one overlay window, fixed slots for GEO, ECL, wall sets, current picture, portrait head and body, monster record, item names, and a "loaded resource" table like the C64's 25-slot cache. Spare 8 KB blocks become a resource cache so revisiting an area does not hit the disk.
3. Copy the DynoSprite/Space Bandits split: assembly for blits, font rendering, DAC FIRQ, disk (DSKCON), decompression and MMU paging; CMOC C for game logic in banked pages. Space Bandits proves CMOC objects in banked pages work in the same Docker toolchain.
4. Use double buffering via $FF9D/$FF9E for the 3D view, title pictures and combat animations; use in-place dirty-rectangle drawing for text windows.
5. Replace the 236.7 Hz PSG driver with a GIME timer FIRQ to the 6-bit DAC. Use Joust's verified register values as the starting point ($FF94/$FF95 countdown, $FF93 = $20, timer source bit in $FF91, DAC at $FF20 with the PIA set so 8-bit values can be written directly).
6. Plan for about 8 floppy sides of data or mass storage. Paladin's Legacy (Player vs City disk), Crystal City (Levels disk) and KQ3 (toc of volumes per disk) show acceptable swap UX; SSI itself shipped 8 sides on C64 and Apple II.
7. Keep everything event-driven: PoR has no vsync dependency and redraws only on input, which is the easiest workload class on this machine. Do not chase 30 to 60 fps; the 3D view needs one redraw per keypress.
8. Use MAME trace logging and input record/playback (as Glen Hewlett did) for regression testing the port against the DOS build.

## Open questions

1. Exact 3D view window size and position in the DOS build (measure from the decomp) to size the back buffer and choose between in-place drawing and flipping.
2. Whether the Apple II version also used character-mode walls and icons, and how its 128K was split (no technical source found).
3. Exact C64 limits for ECL size per area and for wall set sizes compared with DOS (the wish notes give addresses but not the engine's own bounds checks).
4. KQ3 CoCo 3 RAM requirement: 512 KB (Sierra wiki) versus 256K (archive page, for LSL); and whether AGI on the CoCo used RS-DOS or only OS-9 Level II.
5. Crystal City and Digger III graphics modes and scroll implementation (no write-ups found); Defender's scrolling method (source available in the repo, not analysed here).
6. Identity of "remz" and the mode and frame rate of the 2009 Wolf3D-style demo.
7. Glen Hewlett's Pac-Man transcode RAM and video mode (disk in archive, not inspected).
8. Whether to use OS-9 Level II (as Sierra did) or RS-DOS plus custom loaders (as all modern games do); see the storage and runtime research file 03.

## Sources

- https://www.youtube.com/watch?v=JuxXbmcJatg : Mr Lurch "#SepTandy" homebrew video (28 September 2021); description links Nick Marentes and Glen's Defender post.
- https://forums.atariage.com/topic/154556-trs-80-coco-3-wolf-3d-style-demo/ : 2009 Wolf3D-style demo thread; 128K, mode tricks, 256-colour scan-doubling discussion.
- https://www.reddit.com/r/trs80/comments/pxavpw/here_is_another_great_conversion_for_the_coco_3/ : given by the human; fetch blocked.
- https://nowhereman999.wordpress.com/2021/09/25/defender-for-the-tandy-coco-3/ : Defender dev diary, MAME record/playback debugging.
- https://github.com/nowhereman999/Joust_CoCo3 : Joust source; GIME register setup, memory block map, 6006 Hz FIRQ audio, ffmpeg recipe.
- https://github.com/nowhereman999/Defender_CoCo3 : Defender source and README; 2-disk loading, config.
- https://github.com/nowhereman999/Robotron_CoCo3 : Robotron README; slowdown notes.
- https://lcurtisboyle.com/nitros9/joust.html : Joust facts, CPU speed comparison.
- https://lcurtisboyle.com/nitros9/defender.html : Defender facts, sound CPU emulation.
- https://lcurtisboyle.com/nitros9/donkeykong.html : Donkey Kong facts, 512K, 225 lines.
- http://www.6809.org.uk/twilight/sock/dk/index.html : Sock Master's DK page; resolution, 6309 native mode.
- http://www.6809.org.uk/twilight/sock/dkremix/index.html : DK Remixed; Z80 to 6809 rewrite, update dates.
- http://www.6809.org.uk/twilight/sock/cocofile/demo.html : Sock demos; 60 Hz, multi-region scrolling.
- http://www.6809.org.uk/twilight/sock/gloom/gloom.html : Gloom1/Gloom2 resolution, fps, RAM.
- https://colorcomputerarchive.com/repo/Programming/Source/Gloom3D/readme.txt : Gloom source README; algorithm and memory layout.
- https://www.cococommunity.net/?p=156 : DK Remixed announcement.
- https://nowhereman999.wordpress.com/2016/12/29/zilog-z80-to-motorola-6809-transcode-part-001/ : Pac-Man transcode method.
- https://nowhereman999.wordpress.com/2018/01/20/arcade-machine-conversion-to-the-coco-overview/ : arcade conversion process overview.
- https://hackaday.com/2017/09/06/ : Hackaday on the Pac-Man transcode.
- https://nickmarentes.com/ProjectArchive/index.html : Nick Marentes project index.
- https://nickmarentes.com/ProjectArchive/pacman.html : Pac-Man tribute; 320x225, 30 fps, samples.
- https://nickmarentes.com/ProjectArchive/popstar.html : PopStar Pilot; scrolling, double buffer, tools.
- https://nickmarentes.com/ProjectArchive/gunstar.html : GunStar; 128x112, 6309, 512K.
- https://nickmarentes.com/ProjectArchive/ambush.html : Cosmic Ambush; timer-driven 2-channel sound.
- https://nickmarentes.com/ProjectArchive/crasher.html : Gate Crasher; Gloom engine, 128x96x16.
- https://nickmarentes.com/ProjectArchive/256mode.html : rumoured 256-colour GIME mode (unconfirmed).
- https://nickolasmarentes.itch.io/ : current Marentes catalogue and RAM requirements.
- https://lcurtisboyle.com/nitros9/pacman.html : Pac-Man 1997 demo facts.
- https://lcurtisboyle.com/nitros9/gatecrasher.html : Gate Crasher facts.
- https://lcurtisboyle.com/nitros9/crystalcity.html : Crystal City facts.
- https://hypertechgaming.itch.io/digger3 : Digger III release, media, tools.
- https://www.lcurtisboyle.com/nitros9/diggeriii.html : Digger III credits, scrolling, RAM use.
- https://colorcomputerarchive.com/repo/Documents/Manuals/Games/Digger%20III%20(HyperTech%20Gaming).pdf : Digger III manual.
- https://pshoemaker70.itch.io/ghost-rush : Ghost Rush builds and credits.
- https://lcurtisboyle.com/nitros9/ghostrush.html : Ghost Rush dates and requirements.
- https://lcurtisboyle.com/nitros9/timberman.html : Timberman facts.
- https://lcurtisboyle.com/nitros9/asteroidsrx.html : Asteroids RX CoCo port facts.
- https://www.indieretronews.com/2021/09/asteroids-rx-from-scratch-conversion-of.html : Asteroids RX Spectrum original.
- https://itch.io/c/3339935/coco : itch.io CoCo collection (checked for RPGs and raycasters).
- https://en.wikipedia.org/wiki/Dungeons_of_Daggorath : Daggorath history and ROM size.
- https://www.cocopedia.com/wiki/Dungeons_of_Daggorath : Daggorath RAM and mode.
- https://www.lcurtisboyle.com/nitros9/castleoftharoggad.html : Castle of Tharoggad.
- https://lcurtisboyle.com/nitros9/halloftheking.html : Hall of the King I.
- https://lcurtisboyle.com/nitros9/hallofthekingiii.html : Hall of the King III.
- https://paladinslegacyretro.wordpress.com/ : Paladin's Legacy author history, disks, tools.
- http://crpgaddict.blogspot.com/2018/12/game-311-paladins-legacy-1989.html : Paladin's Legacy review; no Gold Box on CoCo.
- https://www.lcurtisboyle.com/nitros9/rogue.html : Rogue CoCo 3, OS-9 Level II, text modes.
- https://en.wikipedia.org/wiki/Adventure_Game_Interpreter : AGI CoCo 3 releases.
- https://lists.scummvm.org/pipermail/scummvm-git-logs/2022-January/091630.html : ScummVM CoCo 3 AGI notes.
- https://www.lcurtisboyle.com/nitros9/leisuresuitlarry.html : LSL CoCo 3 port facts.
- https://wiki.sierrahelp.com/index.php/King%27s_Quest_III:_To_Heir_is_Human_Technical : KQ3 CoCo 3 RAM.
- https://colorcomputerarchive.com/repo/Documents/Manuals/Games/Running%20KQ3%20from%20hard%20drive.txt : KQ3 OS-9 modules and multi-disk toc.
- https://forums.atariage.com/topic/311559-sierra-agi-ports-to-the-coco-3-any-sound-improvement/ : AGI CoCo 3 sound limits, disk format.
- https://www.lcurtisboyle.com/nitros9/shanghai.html : Shanghai facts.
- https://www.lcurtisboyle.com/nitros9/thexder.html : Thexder facts.
- https://www.lcurtisboyle.com/nitros9/gantelet.html : Gantelet facts.
- https://www.lcurtisboyle.com/nitros9/kungfudude.html : Kung-Fu Dude (not an RPG).
- https://www.lcurtisboyle.com/nitros9/warriorking.html : Warrior King (not an RPG).
- https://en.wikipedia.org/wiki/List_of_TRS-80_Color_Computer_games : CoCo games list used to verify titles.
- https://pshoemaker70.itch.io/dungeon-crawl-v2 : Dungeon Crawl homebrew RPG.
- https://github.com/dougmasten/awesome-coco : curated CoCo resource list (engines, ZX0, Gloom, source repos).
- https://github.com/richard42/dynosprite : DynoSprite engine; benchmarks, address map, features.
- https://github.com/jamieleecho/space-bandits : Space Bandits; CMOC on DynoSprite in coco-dev Docker.
- https://en.wikipedia.org/wiki/Strategic_Simulations : SSI platform history (no CoCo).
- https://en.wikipedia.org/wiki/Gold_Box : Gold Box engine origins, 6502 assembly, ports.
- https://en.wikipedia.org/wiki/Pool_of_Radiance : PoR team, platforms, version differences.
- https://www.filfre.net/2016/03/opening-the-gold-box-part-3-from-tabletop-to-desktop/ : C64-centred tool chain, timeline.
- https://www.filfre.net/2016/03/opening-the-gold-box-part-4-pool-of-radiance/ : C64 disk swapping, paragraph book.
- https://www.filfre.net/2017/03/opening-the-gold-box-part-5-all-that-glitters-is-not-gold/ : 16x16 maps and scripting limits from 8-bit memory.
- https://www.pressreader.com/uk/retro-gamer/20201001/283643942369917 : Retro Gamer making-of; Brors "32KB", assembly.
- https://www.mocagh.org/ssi/pool-refcard-alt.pdf : C64 reference card; 4 double-sided disks, fastloader, cuts.
- https://www.c64-wiki.com/wiki/Pool_of_Radiance : C64 credits and 8 sides.
- https://141.11.32.100.sslip.io/textfiles.com/apple/DOCUMENTATION/pool.qstart : Apple II quick start; 4 double-sided disks.
- https://www.applefritter.com/node/33971 : Apple II 128K requirement, drive 1 only.
- https://dosdays.co.uk/topics/Games/game_poolrad.php : DOS disks, RAM, versions.
- https://www.mobygames.com/game/502/pool-of-radiance/specs/ : DOS RAM by video mode.
- https://github.com/malcyon/wish : Wish Gold Box tool; docs/10-disk-format.md, 40-memory-map.md, 131-fastloader.md, 140-loaded-files-cache.md (C64 PoR memory map, file layout, load times).
- https://wish-goldbox.readthedocs.io/en/latest/api/generated/goldbox.c64_codec.html : C64 580-byte record, icon format.
- https://wish-goldbox.readthedocs.io/en/latest/api/generated/goldbox.c64_save.html : C64 save files and addresses.
- https://wish-goldbox.readthedocs.io/en/latest/api/generated/goldbox.portraits.html : portrait ids shared by C64 and DOS DAX.
- https://wish-goldbox.readthedocs.io/en/latest/api/generated/goldbox.d64.html : D64 container details.
