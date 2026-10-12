# Review: ovl18

decompiler: dec-4 (AnimateFinalPicture, AnimateAreaDoors; 0a63ab5, 8dfaf62, f30fc4c) and dec-1
(ShowEndingNarrative; 30336ee) from the `Agent:` trailers of the unit's commits.
reviewer: dec-5
date: 2026-10-12
commit: e85368c

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl18` (rerun): `AnimateFinalPicture` 270 bytes plus 6 pool, `ShowEndingNarrative`
1039 plus 400 pool, `AnimateAreaDoors` 579, `ovl18_init` 5; `unit: complete, 2299 bytes of code plus
0 of paragraph padding cover the original segment`. `make readability UNIT=ovl18` is clean. Packet:
`build/packets/ovl18.md`.

Routines: `AnimateFinalPicture` (ovl18:0006), `ShowEndingNarrative` (ovl18:02A4), `AnimateAreaDoors`
(ovl18:06B3), the empty `ovl18_init` (ovl18:08F6).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] should-fix ShowEndingNarrative: the three branch gates `ds49D6^[830] > 1/2/3`
  (ovl18:0407, 0462, 04BE; `es:[di + $67C]`) leave the index 830 bare. The comment for the routine
  says the pictures are conditional but not what the gate is; word 830 is a game variable (TGameVars,
  the DS:49D6 block). Name it (a `Var...` constant in POOLVARS like VarMapX) or say `Purpose unknown:`
  with what is known (it selects how many of the FINAL 4/5/6 pictures are drawn). The three pictures
  themselves (`res07_fn_0111('FINAL' + ds4713, 4/5/6, ...)` at ovl18:044B, 048E, 04D1) are correctly
  documented.
- [ ] note AnimateFinalPicture: `Byte(Sprites.Count)` (ovl18:00E1) is a real faithfulness cast: the
  original compares the `Count` byte with `cmp al, byte [...]` / `jbe`, while `TSpriteList.Count` is
  `ShortInt` (the `for` in FreeSpriteList exits with `jg`, so the type is signed there). The comment and
  whitepaper 5.17 both record it, so a porter is warned; the cast stays.
- [ ] note AnimateAreaDoors: `Pointer(ds5E52)` / `Pointer(ds5E56)` (ovl18:0747 and the like) pass the
  SQRPACI bank pointers to `res07_fn_1E5C`; `ds5E52`/`ds5E56` are typed `PT8x8Bank`, so the `Pointer()`
  cast only matches the stub's `Pointer` parameter. Fine as is; noted so it is not mistaken for a type
  bug if the stub's signature is later sharpened.

## What was verified

1. `make match UNIT=ovl18` rerun as above: complete, all four routines L2. `make readability UNIT=ovl18`
   clean.
2. Names true and specific: `AnimateFinalPicture` animates a FINAL picture, `ShowEndingNarrative` shows
   the ending text, `AnimateAreaDoors` animates the area view doors; `Col`/`Row` the picture position,
   `Bank`/`Cycles` the frame bank and pass count, `Flag` the door on/off switch, `DoorCol`/`DoorRow`
   the table index and animation step, `NowTick`/`StartTick`/`DoneCycles` the frame timing.
3. Types fit: `Col, Row: Word` (the `DrawSprite` and `DrawAreaView` word calls), `Bank, Cycles, Flag:
   Byte`, `NowTick, StartTick: LongInt` (32-bit `res06_fn_0C3F` compares), `Sprites: TSpriteList`,
   `ds470E: Pointer`, the two door tables `array[0..$A]`/`array[0..$11] of Byte` and the 9-step
   `array[0..8] of Word` columns/rows (POOLVARS comments match every use).
4. Comments give addresses and meaning: the unit comment, each routine's comment with its address, the
   `res07_fn_0111('FINAL' + ds4713, N, ...)` picture loads (ovl18:036D, 03E1, 043B, 0496, 04F2) and
   their `res07_fn_0D71` positions (`(0,0)`, `(0,$B)`, `($D,9)`, `(0,9)`), the speech lines checked
   against the literal pool (`'Mortally wounded, the dragon roars!'` loaded at ovl18:02F7,
   `'"No Lord Bane!  I can still rule here!'` at ovl18:061D, ...), the `res06_fn_0DBE` waits, and the
   DS:49F3 save/restore through DS:4712.
5. Quirks: the `Byte(Sprites.Count)` comparison is marked in the comment; `ovl18_init` is the standard
   empty frame and carries a comment with its address. Nothing was "fixed".
6. No raw machine code (`inline`, `db`) and no `assembler` routine; every routine is plain Pascal.
7. Side effects stated: `ShowEndingNarrative` sets and restores the view mode DS:49F3 and shows text and
   pictures; `AnimateAreaDoors` draws or clears the doors and steps the view.
8. Callers: `ShowEndingNarrative` from ovl03:2E10, `AnimateAreaDoors` from ovl03:31B4 and ovl17:1602,
   `AnimateFinalPicture` from ShowEndingNarrative (packet callers), `ShowEndingNarrative` the unit entry.
9. Stub signatures this unit set (`LoadSpriteList` with the FINAL name, `res07_fn_0111`,
   `res07_fn_0D71`, `res07_fn_1E5C`, `res07_fn_1B52`, `DrawSprite`, `FreeSpriteList`, `DrawAreaView`,
   `res06_fn_0626`, `res06_fn_0DD3`, `res06_fn_0DBE`, `res12_fn_27D9`) are recorded in
   `re/symbols.toml` and agree with their other call sites.
10. Whitepaper 5.17 records what the unit taught (the narrative, the door animation, the frame timing and
    the `Byte(Count)` cast) with the one gap: the 830 gate is not mentioned.

## Verdict

Passed with one should-fix: the 830 game-variable gate in ShowEndingNarrative is left bare. The unit is
complete, readable and well documented otherwise.
