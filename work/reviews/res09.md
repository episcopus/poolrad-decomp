# Review: res09

decompiler: dec-2 (Agent trailer of f1214fd; ad573fb touched src/RES09.PAS for ovl27's DrawWindow stub, dec-1)
reviewer: rev-4
date: 2026-10-11
commit: fc43f11

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=res09` (rerun): `DrawWindowFrame` 311 bytes, `ClearWindow` 433, `DrawWindow` 127,
`res09_init` 5; `unit: complete, 876 bytes of code plus 4 of paragraph padding cover the original
segment`. `make readability UNIT=res09` is clean. Packet: `build/packets/res09.md`.

Routines: `DrawWindowFrame` (03F1:0000), `ClearWindow` (03F1:0137), `DrawWindow` (03F1:02E8), the empty
`res09_init` (03F1:0367).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] should-fix res09_init: the empty initialisation at 03F1:0367 (`55 89 E5 5D CB`, then 4 zero bytes of paragraph padding) has no comment and no address, where `res04_init`, `ovl00_init` and `ovl26_init` carry one. It is the routine comment the checklist asks for.
- [ ] should-fix RES09 unit comment: the unit comment cites "(whitepaper 5.9)", but the document has no 5.9 heading and the res09 paragraphs sit under `### 5.8 Keyboard input and menus` (whitepaper line 511, between 5.8 at line 499 and 5.12 at line 532). Either cite 5.8 or move the res09 entry into its own 5.9 section (the section table at whitepaper line 437 reserves 5.9 for graphics).
- [ ] should-fix DrawWindow: "Called from ovl01/02/03/04/05/06 and res12" (03F1:02E8) omits the units that also call it: ovl15:1307, ovl16:0161 and ovl16:382D, ovl19:0FE2 and ovl19:299C, ovl21:0CEB, ovl22:008A, ovl27:0207, ovl28:04F9, res12:272A and res12:2B88. A full caller scan finds 24 callers (the packet caps the list at 12). The `DrawWindowFrame` and `ClearWindow` comments name only DrawWindow; ClearWindow has 28 callers (ovl08, ovl13, ovl14, ovl15, ovl16, ovl19, ovl22, ovl25, res12). Say "the main callers" or list them.
- [ ] should-fix whitepaper 5.8/5.9 caller paragraph: "`DrawWindow` is called for dialogs and screens from ovl01, ovl02 (the code wheel), ovl03, ovl04, ovl05 and ovl06; the frame and clear routines are also called directly from ovl08, ovl13, ovl14, ovl15, ovl16, ovl19 and res12" (whitepaper line 528). DrawWindow is also called from ovl15, ovl16, ovl19, ovl21, ovl22, ovl27, ovl28 and res12 (res12:272A, 27D9, 2B88), so the "also" reads as if those units do not call it. DrawWindowFrame's only callers are ovl15:04A1, ovl19:004A, ovl19:0FE2, DrawWindow and res12:16EC, so ovl08, ovl13, ovl14 and ovl16 do not call it. ClearWindow's list also omits ovl22 and ovl25. Same caller list as the renames.toml `why` and the `re/symbols.toml` note for DrawWindow.
- [ ] note re/symbols.toml DrawWindow: the note says Text is "recorded as the generic string so a skeleton compiles", but the `signature` field holds `Text: String40`. The note is stale; String40 is the right type (the copy limit $28 at 03F1:02EE).
- [ ] note DrawWindowFrame/ovl34_e2: the last two arguments are always 0 (03F1:0032, 0035, and the same pair in the calls at 004C, 0066, 0080). The open blocker `ovl34 needs its caller in res09 to agree (Direct: Boolean vs 0)` is a cross-unit decision for the ovl34 decompiler; the current `src/OVL34.PAS` stub declares `ovl34_e2(A, B: ShortInt; C: Word; D, E: Byte)`, which is what res09 passes.

## What was verified

1. `make match UNIT=res09` rerun: complete, all four routines L2. `make readability UNIT=res09` is clean.
2. Names true and specific: `DrawWindow` clears, frames and titles a window; `ClearWindow` fills the window rectangle with 0; `DrawWindowFrame` draws the tile frame; the constants name what they select (`TilesPerFrameSet`, `FirstFrameTile`, `TileCorner`/`TileVertical`/`TileHorizontal`, `ScanlinesPerTextRow`, `LastTextScanline`, `BytesPerTextColumn`, `GraphRowsPerTextRow`, `LastGraphRow`, `BytesPerGraphColumn`). `VideoAdapter` (DS:4A1E) has a `re/dseg.toml` entry and a `POOLVARS.PAS` comment; `GameVars` is not used here.
3. Types fit: the four coordinates are `ShortInt` (the frame Dec/Inc reaches -1, and the compares are signed); `FrameSet`/`TextColour` are `Byte`; `TopCode`/`BottomCode`/`LeftCode`/`Width` are `Integer` (sign-extended byte math, `idiv` at 03F1:034C) and `Row` is `Word` (the `for` exit test is unsigned `ja`, 03F1:017E and 03F1:0259). `ovl34_e2(A, B: ShortInt; C: Word; D, E: Byte)`, `res06_fn_00B7(A, B, C, D: ShortInt; E, F: Byte)` and `res06_fn_0626(A, Row, Color: Byte; Text: string)` match the pushes; `Text: String40` is proven by the `StrLCopy` limit $28 at 03F1:02EE and the temp at `[bp-$29]`.
4. Comments give addresses and meaning: the four corners and the top/bottom/left/right edges with `TileBase = FrameSet*3 + $114` (03F1:0012..001D, verified); the three `ClearWindow` modes (0: the two text planes `$B800`/`$BA00` with 80-byte rows; 1: `res06_fn_00B7` twice with E=0 then E=1; 2: the four planes `$B800`/`$BA00`/`$BC00`/`$BE00` with 160-byte rows); the centring formula `(LeftCol + RightCol - Length(Text)) div 2` (03F1:0333..034E). Side effects (video memory, screen) are stated.
5. Record types: `TTextPlane` (100x80) and `TGraphPlane` (50x160) fix the compiler's row strides ($50 and $A0) used in the flat addressing; the comment explains the deliberate out-of-range column index.
6. Quirks: none. The planarity and the flat addressing are documented, not fixed (the absolute planes reproduce the FillChar segments).
7. No `inline`, no `db`, no `assembler`. The `absolute $B800:$0000` typed planes are normal Pascal.
8. Claims carry the whitepaper tag where they describe game behaviour; adapter names are left [?].
9. Signatures: `DrawWindow` is recorded in `re/symbols.toml` and declared with the same header in `src/OVL02.PAS`/`src/OVL27.PAS` callers; `DrawWindowFrame`/`ClearWindow` have no decompiled external caller yet, so no stub signature is owed.
10. Whitepaper 5.8 records what the unit taught (the three routines, the parameters, the clear modes, the tile base). The caller paragraph and the unit comment's section number are the two documentation findings above.

## Verdict

Passed. Every name, type and comment is true to the bytes; the findings are documentation completeness (a missing initialisation comment, the caller lists and the whitepaper section number) and do not block.
