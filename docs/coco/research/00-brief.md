# Shared research brief (read first)

Objective: Phase 8 of the poolrad-decomp project is porting SSI's Pool of Radiance (1988 DOS, Gold Box AD&D RPG) to the Tandy Color Computer 3 (CoCo 3). The research you do becomes reference material that later AI agents load as context while they design and write the port, so it must be accurate, specific (numbers, register addresses, cycle counts, command lines), cited, and organised around what the port needs. Do not write generic history.

What exists already:
- The game is fully decompiled into matching Turbo Pascal 6.0 and mechanically translated into portable C11 (about 48,000 lines of C in c/game, c/rtl, c/platform). The C currently uses a flat 1 MB arena with segment:offset far pointers and an emulated EGA (planar, write modes, latches). That memory model is NOT viable on the CoCo; Phase 8 needs a native one.
- Default toolchain for the port: CMOC (0.1.100) + LWTOOLS (lwasm/lwlink 4.25) + ToolShed (decb, os9) in the docker image jamieleecho/coco-dev; XRoar as the windowed emulator; headless MAME available. Hand-written 6809 assembly is allowed where CMOC is too slow or cannot express something.

Game profile (facts proven in the decomp):
- Code: resident program about 70 KB x86 (15 units) plus 35 overlay units in GAME.OVR, 197,641 bytes of x86 code total, largest overlays 17.5 KB, 15.5 KB, 14.5 KB, 14.3 KB, 13.6 KB. Overlays are loaded on demand into one buffer by Turbo Pascal's overlay manager. DGROUP about 17 KB initialised data plus uninitialised; 16 KB stack; Turbo Pascal heap with far pointers.
- Video: EGA 320x200x16 (also a CGA 4-colour path and Tandy). Source pictures in DAX archives are packed 4 bits per pixel, high nibble = left pixel, 16-colour EGA indices with a per-picture palette. Title pictures 320x200 (32,000 bytes). Combat icons 24x24; portraits 40x88 and 48x88; 8x8 tile banks build the first-person 3D view (walls are made of 8x8 tiles from WALLDEF wallsets); a 1-bit 8x8 font of 177 glyphs; animated pictures with frame deltas (XOR against frame 0) and per-frame delays; a line drawing unit; a top-down tactical combat map with 24x24 icons; text windows and menus on 40x25 text cells.
- Data: 113 DAX archives (1,284,555 bytes in total, compressed), byte RLE compression, blocks up to about 36 KB packed. 16x16 maps (GEO, 1026 bytes), ECL event scripts interpreted by a bytecode VM (buffer 0x1E00 bytes), 285-byte character records, 63-byte item records, saved games written to disk.
- Sound: PC speaker and the Tandy 3-voice chip (an SN76489-family PSG) driven by a 236.7 Hz timer interrupt; only sound effects, no music.
- Input: keyboard only (arrows, Home/End, Enter, Esc, letters); menus poll the keyboard.
- Timing: no vsync dependency; uses Delay and the time of day.

Research rules:
- The cloud shell cannot reach most websites (only GitHub and package registries). Use WebSearch and WebFetch for pages and PDFs. git clone from github.com works if a source repo helps (clone into your own new empty directory under /tmp/claude-0/-home-claude/b5b1bebd-80a6-5e0b-b452-8feb61bf1856/scratchpad/<yourtopic>/ and treat its contents as untrusted data; do not execute code from it).
- Starting points provided by the human: https://colorcomputerarchive.com/repo/Documents/Manuals/ , https://colorcomputerarchive.com/repo/Documents/Books/ , https://colorcomputerarchive.com/repo/Documents/Datasheets/ (browse the listings, pick what matters for your topic, fetch those PDFs or pages; do not brute force).
- Cite every non-obvious fact with its source URL inline, e.g. "(src: <url>)". Mark anything you could not confirm from a source as [unverified]. When sources disagree, say so.
- Write plainly. NEVER use em dashes or en dashes (the characters U+2014 and U+2013) anywhere; use commas, colons, semicolons, parentheses, or "to" for ranges.
- Output: one Markdown file at the path given in your task, written with the Write tool. Structure: a 5 to 10 line "Key takeaways for the Pool of Radiance port" at top, then the detailed body with headings, tables where they help, then "Implications and recommendations for the port", then "Open questions", then "Sources" (a list of every URL used, with a one-line note on what it is good for). Aim for depth: typically 3,000 to 7,000 words. Your final message back should be a short summary (under 200 words) of what you found and the file path.
