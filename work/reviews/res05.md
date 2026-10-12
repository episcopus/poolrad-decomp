# Review: res05

decompiler: dec-6 (Agent trailer of 6eb63ca) and dec-3 (2e05660); the unit was merged in cefe820
reviewer: rev-4
date: 2026-10-11
commit: 6c92e73

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=res05` (rerun): 18 routines matched (`FreeHeapBlock` 32 bytes, `AllocHeapBlock` 32,
`WriteCharsAt` 197, `WriteTextAt` 112, `FillBlocksAt` 30, `ShowBottomMessage` 90,
`WaitForOverlayDisk` 75 plus 37 pool, `OpenGameFile` 142, `FileExists` 107,
`DeleteAllOccurrences` 207, `MakeDosFileName` 234, `UnpackRle` 188, `OpenDaxFile` 282 plus 2,
`CloseDaxFile` 37, `LoadDaxBlock` 564 plus 10, `SelectTileSet` 19, `RestoreTileSet` 11, `res05_init`
5); `unit: complete, 2413 bytes of code plus 3 of paragraph padding cover the original segment`.
`make readability UNIT=res05` is clean. Packet: `build/packets/res05.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] should-fix FreeHeapBlock: the comment says it "frees a heap block that AllocBlock allocated" (0802:0000); the routine is `AllocHeapBlock`, not `AllocBlock`. Use the declared name.
- [ ] note UnpackRle: `UnpackedSize` is a `var Word` parameter (the caller passes its output `Size`) but the routine stops only at `PackedSize` and never reads it (0802:050F). The comment says "UnpackedSize is not read", so a porter is warned; the signature has to keep the parameter for the call to match.
- [ ] note res05/O+ (spec): the unit is resident (`0802`) and its directive is `{$A-,O+,F+,S-,R-,G-,I+}`; the `O+` is real (WaitForOverlayDisk copies the literal `'game.ovr'` to a stack temporary before calling `FileExists`, 0802:0218, the `O+` form; with `O-` the frame is 2 bytes, not 12). Same spec question as res08: AGENTS.md and SPEC 3 item 6 say only overlay units add `O+`. Already escalated for res08; the spec text needs the human, the source is right.
- [ ] note res05: the routines renamed here (`OpenGameFile` 0802:025D, `WaitForOverlayDisk` 0802:0212, `SelectTileSet` 0802:094A) are still called by their old `res05_fn_XXXX` names in `src/OVL11.PAS` and `src/RES08.PAS`, and `GameDir` (DS:547C) is still `ds547C` in ovl11. Cross-unit naming, Phase 6 (ovl11 is blocked on the matcher issue, res08 on its review).

## What was verified

1. `make match UNIT=res05` rerun: complete, all 18 routines L2. `make readability UNIT=res05` is clean.
2. Names true and specific: the file/text layer (`FreeHeapBlock`, `AllocHeapBlock`, `WriteCharsAt`, `WriteTextAt`, `FillBlocksAt`, `ShowBottomMessage`, `WaitForOverlayDisk`, `OpenGameFile`, `FileExists`), the DOS name cleaning (`DeleteAllOccurrences`, `MakeDosFileName`), the DAX layer (`UnpackRle`, `OpenDaxFile`, `CloseDaxFile`, `LoadDaxBlock`) and the tile set (`SelectTileSet`, `RestoreTileSet`). The constants name the BIOS services (`BiosVideo` $10, `BiosSetCursor` 2, `BiosWriteChar` 9), `SolidBlock` `#$DB`, `PromptRow` 24, `RowWidth` 40, `MaxPackedSize` $8CA0. The globals have `POOLVARS.PAS` comments and `re/dseg.toml` evidence (`ds25D5`, `ds49CE`, `BadNameChars`, `PackedBuf`, `InsertDiskPrompts`, `ds5377`, `ds557C`, `ds547D`, `ds4A1A`/`ds4A1B`).
3. Types fit: `Pause`-style counts and colours are `Byte`, `Code` is `ShortInt` (the `jl`/`jg` arms of UnpackRle), `String40` (limit $28 at 0802:028D, 02A4, 01A3) and `String20` (limit $14 at 0802:0727), `TByteArray`/`PByteArray` for the run-addressed buffers, `file` for the DOS handles, `ds49CE` a `Word` (IOResult), `ds25D5` an `array[0..15] of Byte`.
4. Comments give addresses and meaning; the ones I checked against the packet all hold: `WriteCharsAt`'s BIOS cursor/write pair, the `VideoAdapter` 0 colour map through `ds25D5` (the image at DS:25D5 is `00 00 00 01 02 02 02 03 03 01 01 01 02 02 03 03`, as the comment says) and the `VideoAdapter` 1 repeat on the `ds4A1A` page; `ShowBottomMessage`'s `FillBlocksAt(0,24,0,40)` before and after the key; `WaitForOverlayDisk`'s `game.ovr` copy and `'Please insert overlay disk.'` loop; `MakeDosFileName`'s ten `BadNameChars` (DS:0D1A..0D23 are `20 2E 2A 2C 3F 2F 5C 3A 3B 7C`, the exact ten in the comment) and the `Copy(Name,1,8)` plus `UpCase`; `LoadDaxBlock`'s index walk (id, longint offset, unpacked size, packed size), the `MaxPackedSize` check and the `'tempsize'` message, the two heap blocks and `UnpackRle`.
5. `UnpackRle`'s arms match: `0..$7E` copies `Code+1` literal bytes (0802:053B..056F), `-$7F..-1` (`$81..$FF`) repeats the next byte `-Code` times (0802:0574..), and `$7F`/`$80` match neither (the QUIRK `0802:0574`); `DeleteAllOccurrences`'s stale `LastStart` (QUIRK `0802:03A2`); `ShowBottomMessage`'s stored-and-unread `Key` (QUIRK `0802:01D4`); `LoadDaxBlock`'s unused frame byte (QUIRK `0802:0719`).
6. The `I-`/`I+` block is correct: `{$I-}` sits before `WaitForOverlayDisk` and `{$I+}` after `FileExists`, so exactly the three routines the unit comment names are compiled without the `CheckInOutRes` calls.
7. No `inline`, no `db`, no `assembler`. The heap calls are `GetMem`/`FreeMem` with the `(Size + 7) and $FFF8` round-up.
8. Callers match: `SelectTileSet` from ovl07 and ovl17, `RestoreTileSet` from ovl17, `WaitForOverlayDisk` from `res08_init`, `LoadDaxBlock` from ovl03/ovl07/ovl17/ovl28/ovl29/res06/res07, `OpenGameFile` from `LoadDaxBlock` and `OpenDaxFile`, `ShowBottomMessage` from `OpenGameFile` and `LoadDaxBlock`.
9. Signatures this unit set (`SelectTileSet`, `RestoreTileSet`, ...) are recorded in `re/symbols.toml` and the callers' stubs; the interface declares every routine in address order.
10. Whitepaper 4.1 and 5.15 record what the unit taught (the DAX block layout and RLE, the file layer, the BIOS text writes, `UnpackRle`'s codes); the O+ spec text is the open item.

## Verdict

Passed. Every name, type and comment is true to the bytes; the should-fix is one wrong routine name in a comment and the notes are informational.
