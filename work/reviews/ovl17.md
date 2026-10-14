# Review: ovl17

decompiler: dec-17, dec-deepseek-2, dec-mimo, mimo-dec (the `Agent:` trailers of the unit's commits; `integrator` merged them)
reviewer: rev-sonnet
date: 2026-10-13
commit: 080561e (round 2; round 1 reviewed eab0007)

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl17` (rerun): 14 matched (ReadSavedCharacterList, RewriteSavedCharacterList,
CreateSaveDir, MergePictureData, BuildCharacterIcon, SaveCharacter, LoadCharacterFile, LoadMonster,
AddMonsterToParty, AddPartyMember, LoadGame, SaveGame, SaveAndExit, ovl17_init); `unit: complete, 9189
bytes of code plus 0 of paragraph padding cover the original segment`. `make readability UNIT=ovl17` is
clean. Packet: `build/packets/ovl17.md`. No `inline`, no `assembler`, no stub signatures of other units
pending (no `{@stub}` of an ovl17 routine anywhere in `src/`).

Routines: ReadSavedCharacterList (ovl17:0010), RewriteSavedCharacterList (01B8), CreateSaveDir (02AE),
MergePictureData (032F), BuildCharacterIcon (0482), SaveCharacter (069E), LoadCharacterFile (0AEC),
LoadMonster (0EC4), AddMonsterToParty (1262), AddPartyMember (1446), LoadGame (1602), SaveGame (1D58),
SaveAndExit (22D5), the empty ovl17_init (23E0).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [x] must-fix SaveGame (ovl17:1D58, the `for Count := 1 to 3` loop at the start): the comment says it
  "copies the party's map cell into the ECL variable block", and whitepaper 5.11 repeats it ("It first
  copies the party's map cell ..."). `ds6AAEWords[1..3]` is not the party's map cell: it is the table of
  loaded wall sets, one (BlockId, First) pair per slot (`LoadWallSet`, ovl29: "ds6AAEWords[First]
  records (BlockId, First)"; ovl11 sets entries 2 and 3 to $FFFF = empty). LoadGame proves it: it
  copies the same words back and calls `LoadWallSet(.A, .B)` for every entry whose A is not negative.
  The party's cell (PartyMapColumn/PartyMapRow) is written to the file separately, in the 5-byte
  block. Say "the three loaded wall-set slots (block id and slot) into the ECL variable words at
  $4AF9 + I and $4AFC + I", in the routine comment and in the whitepaper, and fix the same wording
  wherever else it appears. (fixed in 7ae850a)
- [x] must-fix LoadGame (ovl17:1602, the tail of the routine, `if AreaViewKind < 2 ... LoadPictureSlot('ICON',
  0, 11) ... for I := 1 to 3`): the comment says "restores TileSet and the 3D map (Load3DMap or, for a
  map view, the wall sets through LoadWallSet)". The code does three things that the comment turns into
  an either/or: `AreaViewKind < 2` runs Load3DMap; independently `AreaViewKind > 1` (a map view)
  runs `LoadPictureSlot('ICON', 0, 11)` and otherwise (the 3D view) the three wall sets are reloaded
  through LoadWallSet. So the 3D view gets Load3DMap AND the wall sets, the map view gets the ICON
  picture and neither of the others; the ICON load is not mentioned anywhere (nor in whitepaper 5.11,
  which has the same either/or and omits the picture). A porter reading the comment would load the wall
  sets for the wrong view kind. Rewrite the sentence from the code, and give the ICON picture its
  meaning if the evidence allows (slot 11 is the same scratch slot BuildCharacterIcon uses). (fixed in 7ae850a)
- [x] must-fix AddMonsterToParty (ovl17:1262, `ds49D6^[PartySize] > 7`): the routine comment says
  "(GameVars^[PartySize] > 7)" but the code, `re/symbols.toml` notes and whitepaper 5.11 (`ds49D6^[830]`)
  read word 830 of the SECOND word block `ds49D6` (the $6B00..$6EFF block), not of `GameVars`. Word 830
  of GameVars is a different variable. AddPartyMember increments the same `ds49D6^[830]`, so the
  comment makes the two routines look as if they used two different counters. Fix the comment (the
  same error was a must-fix in ovl08 CheckMorale). (fixed in 7ae850a)
- [ ] should-fix ReadSavedCharacterList, AddMonsterToParty, SaveCharacter, SaveGame, LoadGame and every
  other routine naming the party list: `ds5D96` is the head of the PARTY list (a chain of TCharacter
  through `Next`), proven by AddPartyMember, LoadGame, SaveGame, ovl05 and ovl07, yet POOLVARS still
  comments it as "head of the TCodeRec list ovl14 walks" and keeps the `dsXXXX` name. The comment in
  the shared file is stale next to the evidence this unit brings. Rename it (`make rename OLD=ds5D96
  NEW=PartyList WHY=...`, keeping its LongInt type) and correct the declaration comment.
- [ ] should-fix AddMonsterToParty (+ TCharacter.B9E in POOLVARS, MonsterBanks): every comment says
  "Who^.B9E" and POOLVARS says its "meaning is not settled", but whitepaper 4.2 states "sex at `0x9E`
  **[V]** on our bytes", the two-row [B9E, roll] tables are exactly a male/female split of head and body
  banks, and ovl16:0A29 sets it from a menu selection minus 1. Name the field `Sex` (or say in the
  comments why the evidence is not enough) so the picture-bank tables read as "head/body bank by sex and
  roll". The two docs disagree today.
- [ ] should-fix LoadMonster (ovl17:0EC4, `ds557C := 1` ... `ds557C := 0`): the comment says only "Sets
  ds557C while the lists are read". `ds557C` is the NoPrompt argument OpenDaxFile passes to
  OpenGameFile (`src/RES05.PAS`, "ds557C is the NoPrompt flag"; ovl07:196 and ovl11:131 also clear it),
  so the point of the assignment is: a MON*SPC / MON*ITM archive that is missing does not raise the
  insert-disk prompt (the lists are optional), while the CHA block above is loaded with the prompt on.
  Say that, and name the global (`DaxNoPrompt` or the like) now that a decompiled unit shows it; the
  POOLVARS comment ("set to 1 while LoadMonster reads ...") has the symptom but not the meaning.
- [ ] should-fix LoadGame (ovl17:1602, `OpenGameFile(..., 'Put save disk in ' + SaveDir, 1, SaveFile)`):
  this is the only place that builds the prompt from the whole `SaveDir` instead of the drive letter plus
  ':' (the other six sites use `SaveDir[1] + ':'`), and it passes NoPrompt = 1, so the prompt is never
  shown (RES05: "while it does not exist and NoPrompt is 0"). Mark it `QUIRK ovl17:16xx:` (dead prompt
  argument) so a port does not "fix" it into a working prompt or copy the odd string; the comment says
  only "opens the slot through OpenGameFile".
- [ ] should-fix SaveGame (ovl17:1D58, `BlockWrite(SaveFile, MemberFiles, $148)`): the file always gets the
  full 8 x 41 bytes of `MemberFiles`, but only the first `Count` names are assigned; the other slots
  are uninitialised stack bytes. That is why `SAVGAMA.DAT` is exactly 13,137 bytes with a garbage tail
  of names, and LoadGame only trusts `MemberCount` of them. A behaviour a port must know (and may not
  copy byte for byte); mark it `QUIRK ovl17:1D58` in the routine. Same for the unexplained
  `VarsAt6B00^[$6E3E] := 0` in LoadGame: say `Purpose unknown:` with what is known (word at VM address
  $6E3E of the ds49D6 block, cleared after the save is read) or name it.
- [ ] should-fix SaveGame: the last sentence of the routine comment, "Called by the heap error handler,
  MakeCamp, the character menu and SaveAndExit (SaveAndExit).", repeats SaveAndExit in a stray
  parenthesis; remove it.
- [ ] should-fix VM address constants in SaveGame/LoadGame: `$49FC` (GameSpeed), `$49FF` (the packed picture
  flags: `ShowMonsterPics * 2 + ShowPortraits`), `$4AF9 + I` / `$4AFC + I` (wall-set pairs), `$6E12`
  (TileSet), `$6E3E` are bare indexes into `VarsAt4900` / `VarsAt6B00`. The comment of SaveGame names
  them in prose, but a constant per word (as POOLVARS does with `VarGeoBlock`, `VarRiverGate`) lets the
  save and the load share one definition and lets the whitepaper cite it.
- [ ] should-fix record and block sizes: `285` (character) appears in SaveCharacter, LoadCharacterFile,
  LoadMonster (`Move`), AddMonsterToParty and LoadGame, `63` (item) and `9` (affect) in four routines
  each, and `$800`, `$400`, `$1E00`, `$148`, `5` in the two game-file routines. The routine comments
  explain them, but a `CharacterBytes = 285` / `ItemBytes = 63` / `AffectBytes = 9` set of constants
  (the unit already has `MenuLineBytes`) would let a reader see that save and load use the same size.
- [ ] should-fix screen and picture numbers: `11` (the scratch head picture slot) is bare in
  MergePictureData (`ds5E5A[11]`), BuildCharacterIcon (`LoadPictureSlot`, two `ds5E5A[11]`,
  `FreePictureSlot(11)`) and LoadGame (`LoadPictureSlot('ICON', 0, 11)`); `ShowMessageLine(15, 'Unable to load monster')` uses a bare 15 while `Yellow = $0E` is a
  constant of this unit; the prompt calls `ReadPromptChoice(..., 13, 10, 15, 0, 0/..., ExtKey)` in
  LoadGame, SaveGame and SaveAndExit and `DrawTextAt(0, $18, $A, ...)` leave the title, word and hot
  colours, the prompt row (24) and colour 10 bare. Same finding as for ovl08/ovl25 (a `MenuColors`
  style constant set).
- [ ] should-fix LoadCharacterFile (ovl17:0AEC): `SavedGame` and `UseSaveDir` are `Byte` parameters tested
  only against 0 (LoadGame passes `1, 1`); they are flags. Make them Boolean if that compiles to the
  same code (a Boolean argument is one pushed byte as well; check with `make tpc`), or say in the
  comment that they are flags and what each value selects (the comment already does the latter, so
  this is a type remark only).
- [ ] should-fix LoadMonster (ovl17:0EC4): the routine comment says "Figure[1..3] and Figure[5..6] are two
  random nibble pairs from RollDice(1, 6)"; the code draws a separate roll for each of the five indexes
  (`Roll + ((Roll + 8) shl 4)` each), so there are five pairs, not two. `Figure[4] = $C4` is a fixed pair
  with no explanation. Also add that a `Race` outside 1..7 leaves `Figure[0]` as loaded from the DAX
  block (the `case` has no `else`).
- [ ] should-fix AddPartyMember (ovl17:1446): the comment says Member's "Next is left nil". The routine never
  writes `Member^.Next`; it relies on the callers (LoadCharacterFile and LoadMonster clear it). Say "must
  arrive with Next nil", so a port does not assume the routine clears it. The `(QUIRK ovl17:1446)`
  mark on `CombatIcon := $FF` says nothing about what the quirk is: the real reason is that the member is
  already linked into the list when the Used[] scan runs, so $FF keeps it out of the scan; write
  that, or drop the QUIRK word if it is not a quirk. Also the first branch's `SelectedCharacter :=
  Member` is overwritten a few lines later (dead store kept for the match): worth a QUIRK line.
- [ ] should-fix MergePictureData (ovl17:032F) and TMemPic: three different names for the same bytes:
  the routine comment calls the tail "the tile ids", TMemPic's `Tail` says "the tile bytes, indexed by
  a byte times ByteSize" and `ByteSize` "bytes per tile", while the routine indexes `Tail[0..ByteSize-1]`
  (so ByteSize is the size of the whole tail/pixel run there, not of one tile), and
  BuildCharacterIcon says "OR the tile bytes". The "mirrored half" in the routine comment (the two
  `FirstPic`/`SecondPic` halves) has no evidence cited. Pick one name for `Tail` and `ByteSize` that
  fits both uses (the probe `tools/re/tp_idioms/ovl17/PIXPRB.PAS` and ovl32's TMemPic show
  the layout) and drop "mirrored" unless it is shown.
- [ ] should-fix unit comment (ovl17, line 2): it describes only the per-character CHRDAT files and the
  directory. The unit also holds the whole-game files `savgam<A..J>.dat` (SaveGame, LoadGame, SaveAndExit,
  the heart of the unit), the saved-character roster `charlist.txt`, the party operations
  (AddPartyMember, AddMonsterToParty, LoadMonster) and the character icon builder (BuildCharacterIcon,
  MergePictureData). R1 passes, but "what the unit is for" is half the unit.
- [ ] should-fix whitepaper 5.11: the introduction still says "Most of its routines are still stubs; the one
  matched so far is how a loaded character joins the party", under a title that says "complete" and
  above 13 matched routines. Remove it. Also the last sentence of Save and exit ("So the 'Save and exit'
  path is the end of the game, when the next area has no ECL script") is an inference tagged [V]; make it
  [I] or cite the evidence.
- [ ] note RewriteSavedCharacterList (ovl17:01B8): `Line^.Text[1] <> '*'` reads the first
  character of the line text; for an empty line (length 0) that byte is whatever the buffer holds. A
  `QUIRK` line would cover it (the menu lines are zero-filled by `FillChar`, so it reads as #0 in practice).
- [ ] note BuildCharacterIcon / SaveCharacter / AddMonsterToParty: the frame spare bytes (`UnusedBytes`,
  `UnusedByte`, `Unused`) carry `QUIRK` marks with the address and say that they are never read or
  written, as the checklist asks; the `Pick: array[1..4]` overflow QUIRK in AddMonsterToParty (writes
  past the array into `Count`, `I`, `Who` for a monster with more than four classes) is the right level
  of warning, but I did not re-derive the frame layout; the byte-exact match covers the code, not the
  claim about which locals are overwritten.
- [ ] note ovl16 routine names in comments (`ovl16_e1`, `ovl16_fn_1EA3`, `ovl16_fn_306D`, `ovl03_fn_2B7E`): the
  "called by" lists use provisional names of units not yet named; they will need `make rename` follow-up
  when those routines are named (the registry rename also updates the comments).
- [ ] note LoadMonster signature: `Who: Pointer` is recorded in `re/symbols.toml`; the routine immediately
  casts it to `PCharacter`. Fine while ovl07 and AddMonsterToParty pass a `Pointer`; sharpen it if
  ovl07's caller is retyped.

- [ ] should-fix LoadGame (ovl17:1602, `LoadPictureSlot('ICON', 0, 11)`; round 2): the new comment and
  whitepaper 5.11 call this "the party marker picture". Slots 9..11 are the marker pictures
  (ovl26 `FirstMarkerPicture = 9`, frame div 2 + 9), but ovl14:0442..0444 loads ICON blocks 0, 1, 2 into
  slots 9, $A, $B, so block 0 belongs in slot 9 there and slot 11 holds block 2. Loading block 0 into
  slot 11 here is not explained by that evidence. State it as observed (ICON block 0 into slot 11 for a
  map view) and tag the "party marker" reading [I], or explain the difference.

## Round 2 (rev-sonnet, HEAD 080561e)

`make match UNIT=ovl17` rerun: 14 matched, `unit: complete`; `make readability UNIT=ovl17` clean. The
three round 1 must-fix findings are ticked and I checked each against the source and whitepaper 5.11:
SaveGame now says "the three loaded wall-set slots (block id and slot)" (source and whitepaper);
LoadGame separates `Load3DMap`, the wall sets (both `AreaViewKind < 2`) and the ICON picture
(`AreaViewKind > 1`) correctly in both places; AddMonsterToParty now names `ds49D6^[PartySize]`, the
same word AddPartyMember counts up. No new must-fix. The should-fix and note findings above are still
open and do not block.

## Verdict

Passed (round 2): the three wrong statements of round 1 are fixed and verified in the source and the
whitepaper, no must-fix is open; the should-fix findings remain for the decompiler.
