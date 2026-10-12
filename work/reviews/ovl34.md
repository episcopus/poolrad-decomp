# Review: ovl34

decompiler: dec-4, dec-9 (Agent trailers of 09e1420 and cb57254; 380bdbb re-applied the unit)
reviewer: rev-5
date: 2026-10-12
commit: 027fade

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

Round 2. Round 1 (rev-4, commit 12f1669) failed on the Put8x8Symbol Direct=0 caller
claim, fixed in cb57254 (ticked in c06bf40). This round re-runs the checklist on the
fixed source.

`make match UNIT=ovl34` (rerun): `Load8x8Bank` 255 bytes, `Put8x8Symbol` 336,
`ovl34_init` 5; `unit: complete, 690 bytes of code plus 0 of paragraph padding cover
the original segment`. `make readability UNIT=ovl34` is clean. Packet:
`build/packets/ovl34.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

### Resolved in round 1 (rev-4, fixed in cb57254)

- [x] must-fix Put8x8Symbol: the comment said all callers pass Direct 0, but ovl29's three calls pass 1 (ovl29:010C, 0146, 02FB). (fixed in cb57254: DrawWindowFrame passes 0, the ovl29 calls pass 1)
- [x] should-fix Load8x8Bank: LoadArg2/LoadArg3 named positions, not meaning. (fixed in cb57254: TileLoadB/TileLoadC with Purpose unknown; Count renamed BlockId)
- [x] should-fix OVL34 unit comment: "(whitepaper 4.x)". (fixed in cb57254: whitepaper 4.2.3)
- [ ] note Load8x8Bank: the Unused: Byte local fills the 264-byte frame; honestly commented.
- [ ] note Load8x8Bank: Bank in [0..4] via the 32-byte set-constant pool; above 4 does nothing.

### This cycle (rev-5)

- [ ] should-fix ovl34_init: the empty initialisation at ovl34:02AD (`55 89 E5 5D CB`) has no comment and no address. Every reviewed unit carries an init comment with the address.
- [ ] should-fix Load8x8Bank: "FINAL 1..6 in ovl18" (ovl34:003B comment). ovl18 passes FINAL blocks 1, 3, 4, 5, 6 (src/OVL18.PAS:68,71,75,80,85: no 2), so "1..6" overstates the illustration. Say "FINAL 1, 3..6" or drop the range.

Round 2 verification (all checked against the bytes): the three ovl29 call sites pass
Direct 1 (src/OVL29.PAS:98,101,146) and DrawWindowFrame passes 0, as the comment now
says; the res07_fn_08D4 call pushes XPos, YPos, the Symbol low byte after Dec, Attr,
the TileBanks[Bank] far pointer and DrawBuf, matching its recorded signature; the
staging path Moves Symbol*Stride bytes from +$17 to TileBuf+$17 with size +$11,
matching T8x8Bank; TileBanks indexes by 4 (pointer array) and SymbolBase by 2 (word
array); the Bank set check, the failure epilogue (00FF, WriteLn, ReadGameKey, 00FF,
QuitGame) and the FlushKeyboard path match; the nil-bank skip, the QUIRK ovl34:01C0
(ja past the fatal check) and the case ranges match; Load8x8Bank's callers are
StartGame and LoadWallSet and Put8x8Symbol's are DrawWindowFrame plus the three ovl29
sites, as commented; every stub signature used is recorded in re/symbols.toml;
whitepaper 4.2.3 covers the unit and agrees with the fixed source.

## Verdict

Passed. No open must-fix findings; the unit is complete, readable and true to the bytes.
