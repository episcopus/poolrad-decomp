# Review: ovl32

decompiler: dec-3 (Agent trailers of dfbeedf, 8ff9511, e7258c2), dec-1 (92b9735), dec-6 (78cb134)
reviewer: rev-4
date: 2026-10-11
commit: 1911d0d

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl32` (rerun): `Load24x24Set` 207 bytes, `DrawCellPicture` 93, `FreePictureSlot` 98,
`LoadPictureSlot` 820, `DrawIcon` 324, `ovl32_init` 5; `unit: complete, 1605 bytes of code plus 0 of
paragraph padding cover the original segment`. `make readability UNIT=ovl32` is clean. Packet:
`build/packets/ovl32.md`.

Routines: `Load24x24Set` (ovl32:0022), `DrawCellPicture` (ovl32:00F1), `FreePictureSlot` (ovl32:014E),
`LoadPictureSlot` (ovl32:01C8), `DrawIcon` (ovl32:04FC), the empty `ovl32_init` (ovl32:0640).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] should-fix Load24x24Set: the comment says "Callers in ovl03 and ovl10 pass 40, 24 or 5 as Unused" (ovl32:0022). The five call sites pass four different values: ovl03:0D18 and ovl03:1852 push 40, ovl10:1266 pushes 24, ovl10:1282 pushes $21 (33) and ovl10:129C pushes 5 (the `Index, Unused` pair is the last two pushes, `Index` = 0 at all but the last site). 33 is missing. Whitepaper 4.2.3 line 422 repeats "40, 24 or 5". The main claim ("this routine never reads it") is true.
- [ ] should-fix LoadPictureSlot: the comment says "a name ending in T adds $40 to Block and loses that letter" (ovl32:01C8). The `$40` add is conditional on T (ovl32:0242..0246) but the trim of the last character (`SetName := Copy(SetName, 1, Length(SetName)-1)`, ovl32:024A..0271) runs for every `CHEAD`/`CBODY` name, T or not. Say that the branch always drops the last character and only adds `$40` when it was `T`. Whitepaper 4.2.3 line 428 repeats the T-only reading.
- [ ] note Load24x24Set: the copy length is `ItemCount * ByteSize` (ovl32:008C..009A), not one picture; the comment says "copies one picture's bytes". The `ItemCount` is the loaded record's item count, so the two coincide only when it is 1. The copy destination is `Index * ByteSize` into `ds5E52^.Tail`, as the comment says.
- [ ] note Load24x24Set: `res07_fn_2595(Loaded)` at ovl32:0065 frees the loaded picture (`res07_fn_2595` is the picture freer, 0464:2595); the routine comment does not mention the free or the trailing `FlushKeyboard`.
- [ ] note DrawIcon: `res07_fn_0D71(CellCol * CellStep, CellRow * CellStep, NoPicIndex, BlitFlagBit, Dest, DrawBuf)` (ovl32:0AF8 area) passes the cell times 3 and the flag bit 0; the whitepaper leaves what the flags select open, which the comment follows.

## What was verified

1. `make match UNIT=ovl32` rerun: complete, all six routines L2. `make readability UNIT=ovl32` is clean.
2. Names true and specific: the picture-set entry points (`Load24x24Set`, `DrawCellPicture`, `LoadPictureSlot`, `FreePictureSlot`, `DrawIcon`), the table `ds5E5A`/`TPictureSlot` (`FirstPic`/`SecondPic` and the `Pics[0..1]` view), `ds5E52`/`ds5E56`, `DrawBuf`, `TileSet`, `ds0CD2`/`ds0CE2`/`ds0CF2`. The constants name the roles (`PicIndexMask` $7F, `NoBlitFlags`, `IconSetCopyLimit` 3, `OneItem`, `AllocatePixels`, `NoPicIndex`, `BlitFlagBit`, `CellStep` 3, `QuarterAdapter` 1, `AltPictures` $40, `MirrorPictures` $80).
3. Types fit: `PicCol`/`PicRow`/`CellCol`/`CellRow` are `Shortint` (`cwde` before the `Integer` parameters), `Index`/`PicCode`/`Slot`/`Block`/`IconSet`/`Mirror`/`PicIndex`/`Unused` are `Byte`, `SetName` is `string`, `PMemPic`/`TMemPic` match the record the code reads (height +0, width +2, item count +8, byte size +$11, pixels +$13, tail +$17).
4. Comments give addresses and meaning: the index above 127 error and `QuitGame`; `res07_fn_0111` loads; the copy into `ds5E52`; the `DrawCellPicture` source switch on bit 7 (above 127 uses `ds5E56` and clears the bit, else `ds5E52`); `FreePictureSlot`'s two nil-tested frees and stride 8; `LoadPictureSlot`'s `CHEAD`/`CBODY` (prefix compare, T, trim, `$40`), `COMSPR`/`ICON` (as named, recolour ICON from `ds0CD2` to `ds0CF2`), other sets (TileSet suffix, recolour from `ds0CD2` to `ds0CE2`); `DrawIcon`'s nil test, `res07_fn_248E` allocation, the `res07_fn_15C7` copy above 3 versus `Move` of the tail and the quarter-size pixel copy at adapter 1, `res07_fn_0D71`, and the free.
5. The `Unused` parameters are not read (`Unused` in `Load24x24Set` and `DrawCellPicture`), the `UnusedByte`/`UnusedWord` frame bytes are QUIRKs (`ovl32:01CB`, `ovl32:0151`).
6. Quirks kept and marked: `FreePictureSlot`'s `UnusedWord` (`ovl32:0151`) and `LoadPictureSlot`'s `UnusedByte` (`ovl32:01CB`).
7. No `inline`, no `db`, no `assembler`.
8. Behaviour claims match whitepaper 4.2.3 (the picture table, the loading rules, the `DrawIcon` copy) and are tagged [V]; the two caller/trim clauses above are the should-fixes.
9. Signatures this unit set (`res07_fn_0111(S: String; A, B, C: Byte; var P: PT8x8Bank)`, `res07_fn_08D4`, `res07_fn_1951`, `res07_fn_248E`, `res07_fn_15C7`, `res07_fn_0D71`, `res07_fn_1E5C`, `res07_fn_2595(var Pic)`) are recorded in `re/symbols.toml`; `DrawIcon`'s callers (`DrawPartyMarker`, ovl31, ovl16) and `LoadPictureSlot`'s (`StartGame`, ovl03, ovl07, ovl14, ovl16, ovl17) match the packet.
10. Whitepaper 4.2.3 records what the unit taught (the record fields, the loading rules, the table, the copies).

## Verdict

Passed. Every name, type and comment is true to the bytes; the two should-fixes are inexact caller/trim clauses and the notes are informational.
