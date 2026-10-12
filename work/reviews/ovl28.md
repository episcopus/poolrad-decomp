# Review: ovl28

decompiler: dec-4, dec-5, dec-6, dec-7 (Agent trailers of the src/OVL28.PAS commits)
reviewer: rev-6
date: 2026-10-12
commit: e8999d0

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

First review. `make match UNIT=ovl28`: `unit: complete, 1989 bytes of code plus 0 of paragraph
padding cover the original segment`, 10 matched. `make readability UNIT=ovl28`: clean. Packet:
`build/packets/ovl28.md`.

Routines: DrawSprite (0000), DrawHeadSprite (0050), DrawBodySprite (0070), LoadSpriteList (00A2),
FreeSpriteList (048F), ShowHeadBodyWindow (04F9), LoadHeadBodySprites (05D9), ShowHeadBodySprites
(0697), Show3DSprite (0708), ovl28_init (07C0).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] must-fix ShowHeadBodySprites: the parameter `Direct` and the comment ("when Direct is set it draws the HEAD sprite and the BODY sprite ... over the 3D view, otherwise it draws the HEAD sprite through the staging buffer") misstate the code. Every path draws through the staging buffer: `DrawHeadSprite` and `DrawBodySprite` push 0 as DrawSprite's `Direct` (ovl28:005F, ovl28:0082), and the else arm pushes 0 too (ovl28:06D6). The byte at [bp+6] (ovl28:069A) only chooses HEAD and BODY (nonzero) or HEAD alone (0); nothing goes to DrawBuf through res07_fn_0D71. Rename it (for example `WithBody: Boolean` if it compiles the same, else a Byte with that name), fix the comment, and fix whitepaper 5.16 ("draw the HEAD sprite DS:6B01 and the BODY sprite DS:6B06 over the 3D view"). The first sentence "Shows the 3D sprite" is also wrong for this routine: it shows the HEAD/BODY sprites of the character screen.
- [ ] must-fix LoadHeadBodySprites: the comment says "Flushes the keyboard at the end", but `FlushKeyboard` (0899:0104) does nothing (QUIRK 0899:010A, its first statement is Exit). Same finding as ovl01's round 1; LoadSpriteList's comment in this unit already says it correctly. Say "calls FlushKeyboard, which does nothing (QUIRK 0899:010A)".
- [ ] must-fix LoadSpriteList: a missing QUIRK. When `MaxAvail` is below 3900 (the `jg/jge` at ovl28:0262..0269 jumps to the loop end at ovl28:0446), the routine skips not only the allocation but also the `Inc(Offset, ...)` past the sprite's X, Y, skipped byte, palette and `Row + 1` pixel bytes; so every later sprite of the block is parsed from the wrong offset (its 4 data bytes, height and width read from the middle of the skipped sprite). Also `Count := Loaded` with slots still indexed by `I` leaves a skipped slot as a nil gap below `Count` and a loaded slot above it, and `FreeMem(Prev, Row + 1)` (ovl28:046C..0471) frees with the last picture's `Row`, not the first picture's size it was allocated with (ovl28 `GetMem(Prev, Row + 1)` for I = 1). The comment says only "Sprites skipped for lack of memory are not counted". Mark these `QUIRK ovl28:0269` (and the FreeMem size one at ovl28:046C) with what happens.
- [ ] must-fix FreeSpriteList: whitepaper 5.16 (line 678) says it "zeroes ... the current bank `DS:6B1C`"; the code sets it to $FF (`ds6B1C := $FF`, as the routine's own comment and POOLVARS say). Correct the whitepaper.
- [ ] should-fix FreeSpriteList: the skeleton's frame comment `{ ovl28:048F: retf 4: 4 bytes of parameters; 6 bytes of locals }` was left above the real comment; remove it.
- [ ] should-fix DrawSprite: "blits the sprite one pixel up and left" while the routine and its parameters speak of a column and a row (`Col - 1`, `Row - 1` passed to res07_fn_0D71). Which unit res07_fn_0D71 takes is not shown here (whitepaper 4.2.3 has DrawIcon passing "the cell times 3"); say "one column and one row up and left" or hedge the unit. Same sentence in whitepaper 5.16 line 669.
- [ ] should-fix LoadSpriteList: the data words are named `Height, Width` and passed as `res07_fn_248E(Height, Width, 1, Mode, ...)`, but whitepaper 2.x (line 213, ovl11) names res07_fn_248E's signature `(Cols, Rows: Word; Planes, Flag: Byte; var Buf)`. One of the two readings is wrong; settle which word is the width (for example from res07_fn_2595, which sizes the pixel buffer as byte +8 times word +$11 at 0464:25B9..25C2) and make the names agree.
- [ ] should-fix TSpriteBank: named a "bank" and "One loaded 8x8 sprite bank", but it is one picture as res07_fn_248E allocates it (one per slot; res07_fn_2595 frees its pixel buffer at +$13 and the block of size + $17). `Unknown8` at +8 is the row count res07_fn_2595 multiplies by `Stride` (+$11) to size the buffer (0464:25B9..25C2), and the pixel pointer at +$13 is missing from the record (fine while unused here, but worth a comment). Consider a picture name and record what res07 shows.
- [ ] should-fix Show3DSprite: the parameter `Bank` is a slot index of the list (1..3, `List.Slots[Bank]`), not a DAX bank as in LoadSpriteList's `Bank`; call it `Slot`. The comment also leaves `res07_fn_00FF` (called before the WriteLn on the error path) unexplained.
- [ ] should-fix ShowHeadBodyWindow: the two `Str` calls into `V1`, `V2` whose results are never read are a kept dead computation; the local comment says so, but it is not marked `QUIRK ovl28:<address>:` as ovl04's unused string is (QUIRK ovl04:0250).
- [ ] should-fix LoadHeadBodySprites: the comment says "for the picture number DS:5376"; that global is named `TileSet` (re/dseg.toml) and the code uses the name. Use it (whitepaper 5.16 line 675 too).
- [ ] should-fix OVL28 unit comment: "(whitepaper 4.x)" is not a reference; the unit's section is 5.16 (it is named at the end too). Drop or correct "4.x".
- [ ] should-fix LoadSpriteList, Show3DSprite, LoadHeadBodySprites: meaningful numbers left bare: 3900 (the free-memory floor), 4 (the PIC block 1 sprite limit), 3 (the last legal slot of Show3DSprite), $FF (no HEAD/BODY bank loaded, also in FreeSpriteList), $42 (`SizeOf(TSpriteList)` if it compiles the same). The comments explain them, so this is weak rather than wrong.
- [ ] note LoadSpriteList: "QUIRK ovl28:00D9: FreeSpriteList is passed @List^ (les/push es/push di), not the List value" is a code-generation detail with no effect on behaviour (`@List^` is the same pointer as `List`); it is not a quirk a port must keep. Harmless.
- [ ] note LoadSpriteList: the already-loaded test compares `Name` and `Bank` only, not the `TileSet` digit the file name gets (`Str(TileSet, Digit)` comes after the test), so a TileSet change with the same name and bank does not reload. Faithful; worth a sentence.

## What was verified

1. `make match UNIT=ovl28` rerun: complete, 10 of 10 matched; `make readability UNIT=ovl28` clean.
2. DrawSprite's two paths (res07_fn_0D71 with Col-1, Row-1, mode 0, flag 1, DrawBuf, then res07_fn_1B52; else res07_fn_1951) and DrawHeadSprite/DrawBodySprite (Row and Row + 5, Direct 0) against ovl28:0000..0090.
3. TSpriteList layout ($42 bytes: count +0, flag +1, seven 8-byte slots from +2, pointer at slot +4) against FreeSpriteList's `8*I - 2` and the FillChar of $42; TSpriteBank's X +4, Y +6, palette +9, stride +$11 against LoadSpriteList's Moves.
4. LoadSpriteList's record walk (count byte, PIC block 1 clamp to 4, 4 data bytes, two words, MaxAvail floor, X, Y, one skipped byte, 8 palette bytes, Row from Stride doubled on VideoAdapter 0, xor against the first picture for PIC/FINAL, res07_fn_02A5, res07_fn_1E5C with ds0C6C/ds0C7C on Mode bit 0 and a nonzero adapter, the final FreeMems and FlushKeyboard) against ovl28:00A2..048B.
5. LoadHeadBodySprites (`HEAD`/`BODY` + Str(TileSet), res07_fn_0111 into ds6B01/ds6B06, ds6B00/ds6B05 with $FF) and ShowHeadBodyWindow (both banks nonzero, DrawWindow($1C,1,$26,$B), ds286F/ds287D lookups, ShowHeadBodySprites($1C,1,1)).
6. Show3DSprite: the $42-byte value copy, the 1..3 range check with 'Illegal range in Show3DSprite.' (the routine name comes from the original's literal, ovl28:0737), X + 2 and Y + 2 to res07_fn_0D71, res07_fn_1B52.
7. Callers in comments agree with the packet. Globals used carry POOLVARS comments. No inline, db or assembler.

## Verdict

Not passed. Four must-fix: ShowHeadBodySprites' `Direct` parameter and comment (it selects HEAD+BODY or HEAD only, always through the staging buffer), LoadHeadBodySprites' "flushes the keyboard", LoadSpriteList's unmarked out-of-memory offset quirk, and whitepaper 5.16's DS:6B1C "zeroes" (it is set to $FF).
