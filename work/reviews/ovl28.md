# Review: ovl28

decompiler: dec-4, dec-5, dec-6, dec-7 (Agent trailers of the src/OVL28.PAS commits)
reviewer: rev-5
date: 2026-10-11
commit: a3b6670

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

Round 2. Round 1 (rev-6, commit e8999d0) failed with four must-fix and six should-fix
findings, fixed in 3864765 (ticked in 5c22bb5); dec-7 had completed LoadSpriteList in
a28c0bc before round 1. This round re-runs the checklist on the fixed source.

`make match UNIT=ovl28` (rerun): `unit: complete, 1989 bytes of code plus 0 of paragraph
padding cover the original segment`, 10 matched, 0 stubs. `make readability UNIT=ovl28`:
clean. Packet: `build/packets/ovl28.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

### Resolved in round 1 (rev-6, fixed in 3864765)

- [x] must-fix ShowHeadBodySprites: the parameter `Direct` and the comment misstate the code (every path draws through the staging buffer; [bp+6] only chooses HEAD+BODY or HEAD alone). (fixed in 3864765: `WithBody: Byte`, comment rewritten)
- [x] must-fix LoadHeadBodySprites: the comment says "Flushes the keyboard at the end", but FlushKeyboard does nothing (QUIRK 0899:010A). (fixed in 3864765)
- [x] must-fix LoadSpriteList: unmarked out-of-memory offset quirk and FreeMem size quirk. (fixed in 3864765: QUIRK ovl28:0269 and QUIRK ovl28:046C)
- [x] must-fix FreeSpriteList / whitepaper 5.16: DS:6B1C is set to $FF, not zeroed. (fixed in 3864765)
- [x] should-fix FreeSpriteList: leftover skeleton frame comment. (fixed in 3864765)
- [x] should-fix DrawSprite / whitepaper 5.16: "one pixel up and left" for Col - 1, Row - 1. (fixed in 3864765: "one column and one row")
- [x] should-fix LoadSpriteList: Height/WidthCols vs res07_fn_248E (Cols, Rows). (fixed in 3864765: signature now (Height, Width: Word; ...), whitepaper 5.16 records the variance openly)
- [x] should-fix TSpriteBank naming and missing +$13 pixel pointer. (fixed in 3864765: TSpritePicture with the +$13 note)
- [x] should-fix Show3DSprite: `Bank` param and unexplained res07_fn_00FF. (fixed in 3864765: `Slot`, 00FF explained)
- [x] should-fix ShowHeadBodyWindow: unmarked dead Str() computation. (fixed in 3864765: QUIRK ovl28:056C, ovl28:0593)
- [x] should-fix LoadHeadBodySprites: "the picture number DS:5376" instead of TileSet. (fixed in 3864765)
- [x] should-fix OVL28 unit comment: "(whitepaper 4.x)". (fixed in 3864765: Whitepaper 5.16)
- [x] should-fix bare numbers 3900, 4, 3, $FF, $42. (fixed in 3864765: FreeMemoryFloor, PicBlock1Sprites, Last3DSpriteSlot, NoBank, SizeOf(TSpriteList))
- [x] note LoadSpriteList @List^ code-generation detail. (fixed in 3864765: kept as Note ovl28:00D9)
- [x] note LoadSpriteList TileSet-change no-reload behaviour. (fixed in 3864765: in the comment)

### This cycle (rev-5)

- [ ] should-fix ovl28_init: the empty initialisation at ovl28:07C0 (`55 89 E5 5D CB`) has no comment and no address. Every reviewed unit carries an init comment with the address.
- [ ] should-fix DrawHeadSprite: "Draws the 8x8 sprite Sprite of a bank at column Col and row Row" (ovl28:0050 comment). "of a bank" is a leftover: the parameter is a sprite pointer, nothing bank-related is read here (DrawBodySprite's comment has no such phrase). Rephrase.
- [ ] note DrawHeadSprite/DrawBodySprite: the rename notes in re/symbols.toml still say "called by Show3DSprite (ovl28_e5)". The callers are ShowHeadBodySprites (ovl28:0697); ovl28_e5 is ShowHeadBodySprites and Show3DSprite is ovl28_e7. Notes hygiene for whoever touches those entries next.

Round 2 verification (all checked against the bytes): the WithBody rewrite matches the
three call shapes (ds6B03/ds6B01 and ds6B08/ds6B06 far pointers to DrawHeadSprite/
DrawBodySprite, Direct 0 in the else arm at ovl28:06D6); the QUIRKs match (0269 jumps
to the loop end at 0446 skipping the offset advance; 046C frees with the last Row;
056C/0593 Str_Format results unread; 0899:010A FlushKeyboard); Show3DSprite's X + 3 - 1
is literal in the binary (add 3, dec at ovl28:077C/0788), its range check is 1..3
(ovl28:0721/0727) and the nil slot skips res07_fn_1B52 (ovl28:075F); res07_fn_00FF
really does read DS:4A1C and call res07_fn_00CF (0464:00FF..0107), so the comment's
claim is true; every caller list in the comments agrees with the packet (DrawSprite
from ovl03/ovl07_e8/ovl18/ovl25; LoadSpriteList from ovl03:0856, ovl07_e8, ovl18:0006,
res12_fn_27D9; FreeSpriteList from ovl10/ovl14/ovl18; the HEAD/BODY routines from
ovl07_e7, res12_fn_27D9, ShowHeadBodyWindow, ovl16:33E7, ovl19:031E; Show3DSprite from
ovl07_e8); TSpriteList/TSpriteSlot/TSpritePicture offsets match every use (slots at
+2+8*(I-1) from shl 3 minus 2, FillChar $42 = 66, X/Y at +4/+6, palette 8 at +9,
ByteSize at +$11); all parameterized stub signatures this unit set are recorded in
re/symbols.toml and agree with the other units' stubs (parameterless res07_fn_1B52
correctly records none); whitepaper 5.16 covers the unit and agrees with the fixed
source.

## Verdict

Passed. No open must-fix findings; the unit is complete, readable and true to the bytes.
